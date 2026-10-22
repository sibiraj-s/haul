// The Chrome and Firefox extension. It hands the browser's downloads to Haul instead of
// downloading them itself, and adds "Download with Haul" to the menu for links and selected
// text. Links go to Haul's Add panel through the `haul` tool inside Haul.app, which Haul
// registers with the browser as a native messaging host when it launches (BrowserHosts in
// the app). Clicking the toolbar button turns capturing downloads off and on.

const api = globalThis.browser ?? globalThis.chrome
const host = 'dev.sibiraj.haul'
const linkPattern = /https?:\/\/[^\s<>"']+/g

// Service workers and event pages unload when idle, so menus are recreated every time
// the script starts rather than only when the extension is installed.
api.contextMenus.removeAll().then(() => {
  api.contextMenus.create({ id: 'download-link', title: 'Download with Haul', contexts: ['link'] })
  api.contextMenus.create({ id: 'download-selection', title: 'Download Links with Haul', contexts: ['selection'] })
})

async function captureEnabled() {
  const { capture = true } = await api.storage.local.get('capture')
  return capture
}

async function showCaptureState() {
  const capture = await captureEnabled()
  await api.action.setTitle({
    title: capture
      ? 'Haul is capturing downloads. Click to turn off.'
      : 'Haul isn’t capturing downloads. Click to turn on.',
  })
  await api.action.setBadgeText({ text: capture ? '' : 'off' })
}

showCaptureState()

api.action.onClicked.addListener(async () => {
  await api.storage.local.set({ capture: !(await captureEnabled()) })
  await showCaptureState()
})

// What the browser would send with the links: the page they're on (for the Referer), its
// User-Agent, and the sites' cookies, so downloads that need the user's sign-in work in Haul
// too. Private windows never share cookies.
async function browserContext(urls, page, incognito) {
  const context = { page, userAgent: navigator.userAgent, cookies: [] }
  if (incognito) return context
  const seen = new Set()
  for (const url of urls) {
    try {
      for (const c of await api.cookies.getAll({ url })) {
        const key = `${c.domain}\t${c.path}\t${c.name}`
        if (seen.has(key)) continue
        seen.add(key)
        context.cookies.push({
          name: c.name,
          value: c.value,
          domain: c.domain,
          path: c.path,
          secure: c.secure,
          hostOnly: c.hostOnly,
          expires: c.expirationDate,
        })
      }
    } catch (error) {
      console.warn('Haul: could not read cookies for', url, error)
    }
  }
  return context
}

// Opens the links in Haul's Add panel; throws when Haul isn't installed or didn't take them.
async function sendToHaul(urls, page, incognito) {
  const reply = await api.runtime.sendNativeMessage(host, {
    urls,
    context: await browserContext(urls, page, incognito),
  })
  if (!reply?.ok) throw new Error(reply?.error ?? 'Haul did not accept the links')
}

api.contextMenus.onClicked.addListener(async (info, tab) => {
  const urls =
    info.menuItemId === 'download-link' ? [info.linkUrl] : ((info.selectionText ?? '').match(linkPattern) ?? [])
  if (urls.length === 0) return
  sendToHaul(urls, info.pageUrl ?? tab?.url, tab?.incognito).catch((error) => {
    console.error('Haul: could not send links', error)
  })
})

// Hands an http(s) download to Haul and removes it from the browser's list; returns whether
// Haul took it. If Haul can't be reached, the browser carries on downloading it instead.
async function capture(item) {
  const url = item.finalUrl || item.url
  if (item.state !== 'in_progress' || !/^https?:/i.test(url) || !(await captureEnabled())) return false
  try {
    await sendToHaul([url], item.referrer || undefined, item.incognito)
  } catch (error) {
    console.warn('Haul: left the download to the browser', error)
    return false
  }
  await api.downloads.cancel(item.id).catch(() => {})
  await api.downloads.erase({ id: item.id }).catch(() => {})
  return true
}

if (api.downloads.onDeterminingFilename) {
  // Chromium waits for this before it picks the file name, so a download Haul takes is cancelled
  // before the browser asks where to save it. Returning true answers later; `suggest` lets the
  // browser go on as usual.
  api.downloads.onDeterminingFilename.addListener((item, suggest) => {
    capture(item).then((taken) => taken || suggest())
    return true
  })
} else {
  // Firefox has no such step: it asks what to do with a file before it creates the download.
  // So Haul takes downloads as their response arrives, before Firefox sees them; cancelling the
  // request leaves the page as it was.
  api.webRequest.onHeadersReceived.addListener(
    async (details) => {
      if (!isDownload(details) || !(await captureEnabled())) return {}
      try {
        await sendToHaul([details.url], details.originUrl, details.incognito)
      } catch (error) {
        console.warn('Haul: left the download to the browser', error)
        return {}
      }
      return { cancel: true }
    },
    { urls: ['http://*/*', 'https://*/*'], types: ['main_frame', 'sub_frame'] },
    ['blocking', 'responseHeaders'],
  )

  // Downloads that don't come from a page load, like those started from the Library window.
  // Pause each one while Haul takes it.
  api.downloads.onCreated.addListener(async (item) => {
    await api.downloads.pause(item.id).catch(() => {})
    if (!(await capture(item))) await api.downloads.resume(item.id).catch(() => {})
  })
}

// Types Firefox shows in the tab itself rather than downloading.
const displayed =
  /^(text\/|image\/|audio\/|video\/|multipart\/|application\/(pdf|json|xml|xhtml\+xml|rss\+xml|atom\+xml|[\w.+-]*\+json|javascript|ecmascript)$)/

// Whether a page or frame load is a file to download: the server says so, or Firefox couldn't
// show it. Only plain GETs, since Haul fetches the link again.
function isDownload(details) {
  if (details.method !== 'GET' || details.statusCode !== 200) return false
  const header = (name) => details.responseHeaders?.find((h) => h.name.toLowerCase() === name)?.value ?? ''
  if (/^\s*attachment/i.test(header('content-disposition'))) return true
  const type = header('content-type').split(';')[0].trim().toLowerCase()
  return type !== '' && !displayed.test(type)
}
