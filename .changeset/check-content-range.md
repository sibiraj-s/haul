---
'haul': patch
---

Fix downloads that could finish corrupted when a server sent a different part of the file than asked for: such replies are now retried instead of written, and a reply for a different version of the file stops the download as changed on the server
