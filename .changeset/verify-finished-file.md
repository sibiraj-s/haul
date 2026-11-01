---
'haul': patch
---

Check a finished download holds every byte of the file before saving it: a download missing parts now fails with a prompt to restart it instead of saving a broken file, and leftover bytes from an earlier attempt are removed
