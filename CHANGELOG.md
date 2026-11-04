# haul

## 1.7.0

### Minor Changes

- 430055f: Menu bar mode: Haul can now hide its Dock icon when you close the window and keep running in the menu bar. Turn it on in Settings → General
- c48c52c: Menu bar shortcuts: right-click the icon to open Settings, check for updates or quit Haul

## 1.6.1

### Patch Changes

- a271f12: Smaller downloads: The DMG now uses stronger compression, making the download about a third smaller

## 1.6.0

### Minor Changes

- c15699b: Multi-network downloads: use Wi‑Fi, Ethernet and USB tethering at the same time for faster downloads. Turn it on in Settings → Network

## 1.5.3

### Patch Changes

- 6c48f84: Retry now starts a download over when it can't continue where it left off, and downloads on unstable connections no longer retry forever

## 1.5.2

### Patch Changes

- 9bdf0d5: Fix downloads that could finish corrupted with some servers
- d9f4bae: Long downloads on unreliable networks no longer fail after a few dropped connections
- 0fd4713: Faster downloads from HTTP/2 servers
- 08deb08: Fix downloads that could finish corrupted when a server compresses files
- ca2948a: Incomplete downloads are no longer saved as broken files; Haul asks you to restart them instead

## 1.5.1

### Patch Changes

- ec5a863: Fix download progress freezing while a menu is open or a window is resized

## 1.5.0

### Minor Changes

- 5e26bef: New Chrome and Firefox extension to send downloads and links to Haul. Also works in Brave, Edge, Vivaldi and Arc
- c77c525: New Extensions pane in Settings to set up the Safari, Chrome and Firefox extensions
- f8962be: Remote downloads: add and manage downloads from a web page or the command line. Turn it on in Settings → Remote

## 1.4.0

### Minor Changes

- 2542bc3: Downloads finish sooner: connections that finish early take over the remaining parts

### Patch Changes

- 155f244: Clearer connection details, and downloads no longer stall when a server limits connections

## 1.3.1

### Patch Changes

- e616aec: Fix checking for updates. If you're on an earlier version, download the latest release manually to keep getting updates

## 1.3.0

### Minor Changes

- 9db8236: New `haul` command-line tool to add downloads from Terminal. Install it from Haul → Install Command Line Tool…
- b548a95: Proxy support, in Settings → Network → Proxy
- 945609b: Extract zip, tar and 7z archives automatically when they finish
- 068086e: Send links to Haul from any app with Services → Download with Haul or `haul://` links
- 6560e6f: Pause downloads on Personal Hotspot and Low Data Mode to save mobile data
- aed868e: Keyboard shortcuts for common actions. See Help → Keyboard Shortcuts (⌘/)
- 8cff6be: New Safari extension: right-click a link and choose Download with Haul
- b1542f5: Downloads from Safari now work on sites that need you to be signed in
- 13495f1: Haul is now in the Share menu for web links
- 5b13239: Open a download or show it in Finder automatically when it's done

### Patch Changes

- 69a4b23: Updated installer design
- 8ac4293: The Dock icon shows download progress

## 1.2.0

### Minor Changes

- 06a6029: Option to also move the file to the Trash when removing a download
- 79b1563: Option to clear finished downloads from the list after a number of days you choose

### Patch Changes

- 4c95ebb: Turning off "Retry failed downloads" now stops pending retries
- e4ed2a9: Fix sign-in on some servers
- 6f5cf52: Replacing an existing file no longer loses it if the new one fails to save
- 4121614: Fixes for starting, pausing and resuming downloads
- fe47e94: Unticking "Start immediately" now adds the download paused
- 74c77b7: Moved "Skip web pages" to the Downloads settings

## 1.1.0

### Minor Changes

- 8f72914: Paste several links at once, separated by spaces, commas or new lines, with warnings for duplicates

### Patch Changes

- ad41b75: Add sponsor links

## 1.0.1

### Patch Changes

- d5523df: Prefer date in build number

## 1.0.0

### Major Changes

- f06ff4e: First release
