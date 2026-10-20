# haul

## 1.3.0

### Minor Changes

- 9db8236: Add a `haul` command-line tool: `haul add <link>…` opens the Add panel with the links filled in, and `haul add < links.txt` reads them from a file. Choose Haul → Install Command Line Tool… to put it in ~/.local/bin, no password needed; if your shell doesn't look there yet, Haul shows the line to add and can add it to ~/.zshrc (or your shell's file) for you. The command comes from inside Haul, so it updates with the app, and the same menu item uninstalls it
- b548a95: Choose how downloads connect in Settings → Network → Proxy: System (the default) follows macOS's proxy settings, None connects directly, and Custom sends downloads through an HTTP or SOCKS5 proxy, with an optional username and password kept in the Keychain and a list of hosts that skip the proxy
- 945609b: Extract archives when they finish: tick Extract when finished in the Add panel. Zip, tar (gz, bz2, xz) and 7z archives are unpacked next to the archive, which is kept, and the inspector shows where they went
- 068086e: Send links to Haul from other apps: select links and choose Services → Download with Haul, or open a `haul://add?url=…` link. Either opens the Add panel with the links filled in
- 6560e6f: Pause downloads on Personal Hotspot and Low Data Mode, so they don't use your mobile data. Turn it on or off in Settings → Network. A badge in the toolbar shows when you're on such a network; click it to pause all downloads, or download anyway until you join another network. Android hotspots are detected too
- aed868e: Add keyboard shortcuts for the selected download: ⌘⌫ removes it, ⌘O opens it and ⌘R shows it in Finder. ⇧⌘⌫ clears completed downloads, ⌃⌘S and ⌥⌘I toggle the sidebar and inspector, and ⌘1–⌘5 switch views. Help → Keyboard Shortcuts (⌘/) lists them all
- 8cff6be: Add a Safari extension: right-click a link, or selected text with links, and choose Download with Haul. Turn it on in Settings → General or in Safari's Extensions settings
- b1542f5: Links sent from the Safari extension download as they would in Safari: Haul sends Safari's cookies for the site, its User-Agent and the page as the Referer, so files that need you to be signed in work. Allow the extension on the site in Safari to share its cookies; links from private windows never take them. The cookies are kept only for that download and dropped once it finishes
- 13495f1: Add Haul to the Share menu for web links, which opens them in the Add panel. Turn it on from the Share menu's Edit Extensions, or in System Settings → General → Login Items & Extensions
- 5b13239: Choose what happens when a download is done: open it or show it in Finder, from When done in the Add panel. With Extract when finished, it opens or shows what was extracted

### Patch Changes

- 69a4b23: Update installer design
- 8ac4293: The Dock icon now shows the download percentage badge. Haul asks for permission to badge its icon, which macOS needs before it shows the badge

## 1.2.0

### Minor Changes

- 06a6029: Option to move the file to the Trash when removing a download
  
  - The remove confirmation has an "Also move the file to the Trash" checkbox for finished downloads
  - The checkbox remembers the last choice
  - With "Ask before removing downloads" off, the file is always kept
  - Works for downloads saved to a folder picked in the Add panel
  - If the file can't be moved to the Trash, Haul says so and keeps the download in the list
- 79b1563: Clear finished downloads from the list after a chosen number of days
  
  - "Remove finished downloads from list" now takes any number of days, 90 by default
  - Only the list is cleared; files stay where they were saved
  - The earlier one day, one week and one month choices carry over as 1, 7 and 30 days

### Patch Changes

- 4c95ebb: Turning off "Retry failed downloads" now ends retries already waiting, with the usual failure notification
- e4ed2a9: Sign-in no longer picks the wrong method when the server's realm name mentions "basic"
- 6f5cf52: Replacing an existing file no longer loses it if saving the new one fails
- 4121614: Download fixes
  
  - "Start immediately" now waits for a free slot instead of going past the simultaneous downloads limit
  - Pausing and resuming a download while its size is being checked no longer starts it twice
  - Servers that hide the file size no longer produce a 1-byte download
- fe47e94: Unticking "Start immediately" now adds the download paused, so it doesn't start until you start it
- 74c77b7: Move "Skip web pages" to the Downloads settings

## 1.1.0

### Minor Changes

- 8f72914: Improve handling multiple several links while adding downloads
  
  - The address field stays on one line and shows the start of a pasted link
  - Links can be separated by commas or semicolons, as well as spaces and new lines
  - Real file names are shown when adding several links
  - Warn when the same link is pasted twice, or several links share a file name

### Patch Changes

- ad41b75: Add sponsor links

## 1.0.1

### Patch Changes

- d5523df: Prefer date in build number

## 1.0.0

### Major Changes

- f06ff4e: First release
