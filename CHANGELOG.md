# haul

## 1.2.0

### Minor Changes

- 529e19a: Option to move the file to the Trash when removing a download
  
  - The remove confirmation has an "Also move the file to the Trash" checkbox for finished downloads
  - The checkbox remembers the last choice
  - With "Ask before removing downloads" off, the file is always kept
  - Works for downloads saved to a folder picked in the Add panel
  - If the file can't be moved to the Trash, Haul says so and keeps the download in the list
- 529e19a: Clear finished downloads from the list after a chosen number of days
  
  - "Remove finished downloads from list" now takes any number of days, 90 by default
  - Only the list is cleared; files stay where they were saved
  - The earlier one day, one week and one month choices carry over as 1, 7 and 30 days

### Patch Changes

- 4c95ebb: Turning off "Retry failed downloads" now ends retries already waiting, with the usual failure notification
- e4ed2a9: Sign-in no longer picks the wrong method when the server's realm name mentions "basic"
- 6f5cf52: Replacing an existing file no longer loses it if saving the new one fails
- 529e19a: Download fixes
  
  - "Start immediately" now waits for a free slot instead of going past the simultaneous downloads limit
  - Pausing and resuming a download while its size is being checked no longer starts it twice
  - Servers that hide the file size no longer produce a 1-byte download
- fe47e94: Unticking "Start immediately" now adds the download paused, so it doesn't start until you start it
- 529e19a: Move "Skip web pages" to the Downloads settings

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
