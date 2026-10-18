---
"haul": patch
---

Download fixes

- "Start immediately" now waits for a free slot instead of going past the simultaneous downloads limit
- Pausing and resuming a download while its size is being checked no longer starts it twice
- Servers that hide the file size no longer produce a 1-byte download
