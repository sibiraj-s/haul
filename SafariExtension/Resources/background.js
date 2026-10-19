// Adds "Download with Haul" to the context menu for links and selected text, and sends
// the links to the extension's native handler, which opens them in Haul's Add panel.

const linkPattern = /https?:\/\/[^\s<>"']+/g

// The background page unloads when idle, and Safari doesn't always keep menus created by
// an earlier load, so they're recreated every time it starts.
browser.contextMenus.removeAll().then(() => {
  browser.contextMenus.create({ id: 'download-link', title: 'Download with Haul', contexts: ['link'] })
  browser.contextMenus.create({ id: 'download-selection', title: 'Download Links with Haul', contexts: ['selection'] })
})

browser.contextMenus.onClicked.addListener((info) => {
  const urls =
    info.menuItemId === 'download-link' ? [info.linkUrl] : ((info.selectionText ?? '').match(linkPattern) ?? [])
  if (urls.length === 0) return
  browser.runtime.sendNativeMessage('application.id', { urls }).catch((error) => {
    console.error('Haul: could not send links', error)
  })
})
