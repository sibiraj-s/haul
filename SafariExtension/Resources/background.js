// Adds "Download with Haul" to the context menu for links and selected text, and sends
// the links to the extension's native handler, which opens them in Haul's Add panel.

const linkPattern = /https?:\/\/[^\s<>"']+/g

// The background page unloads when idle, and Safari doesn't always keep menus created by
// an earlier load, so they're recreated every time it starts.
browser.contextMenus.removeAll().then(() => {
  browser.contextMenus.create({ id: 'download-link', title: 'Download with Haul', contexts: ['link'] })
  browser.contextMenus.create({ id: 'download-selection', title: 'Download Links with Haul', contexts: ['selection'] })
})

// What Safari would send with the links: the page they're on (for the Referer), its User-Agent,
// and the sites' cookies, so downloads that need the user's sign-in work in Haul too. Cookies
// need the extension to be allowed on the site; without that, the links go without them.
// Private windows never share cookies.
async function browserContext(urls, info, tab) {
  const context = { page: info.pageUrl ?? tab?.url, userAgent: navigator.userAgent, cookies: [] }
  if (tab?.incognito) return context
  const seen = new Set()
  for (const url of urls) {
    try {
      for (const c of await browser.cookies.getAll({ url })) {
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

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  const urls =
    info.menuItemId === 'download-link' ? [info.linkUrl] : ((info.selectionText ?? '').match(linkPattern) ?? [])
  if (urls.length === 0) return
  const context = await browserContext(urls, info, tab)
  browser.runtime.sendNativeMessage('application.id', { urls, context }).catch((error) => {
    console.error('Haul: could not send links', error)
  })
})
