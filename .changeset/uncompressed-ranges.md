---
'haul': patch
---

Fix downloads that could finish corrupted when a server compressed its replies: Haul now asks for the file's own bytes, and if a server compresses them anyway, the file is downloaded in one go instead of in parts
