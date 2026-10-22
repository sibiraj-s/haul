---
'haul': minor
---

Finish downloads sooner: when a connection finishes its part, it takes over half of the part with the most left, so every connection keeps downloading until the end instead of waiting on the slowest one. Parts with less than 8 MB left aren't split, and downloads never use more connections than you set
