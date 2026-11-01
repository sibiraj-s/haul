---
'haul': patch
---

Fix Retry failing the same way again when a download's saved progress can't be continued, such as when the partial file lost data or the server stopped resuming: Retry now starts it over. Also accept a server sending the whole file compressed, and stop retrying forever on a connection that's cut off after every few bytes
