# Haul

[![CI](https://github.com/sibiraj-s/haul/actions/workflows/ci.yml/badge.svg)](https://github.com/sibiraj-s/haul/actions/workflows/ci.yml)

A native download manager for macOS, built with SwiftUI.

![Haul downloading a file over eight connections](./screenshot.png)

## Features

- Multi-connection downloads that pause and resume, including across relaunches
- A queue you can reorder, with a limit on simultaneous downloads
- Speed limit, a nightly download schedule, and pausing on Personal Hotspot
- Automatic retries, and fresh links for expired downloads (Update Link)
- Sorting into folders by kind, duplicate detection, SHA-256 checksums
- Menu bar progress, Dock progress, and notifications
- Links from other apps through Services → Download with Haul, or `haul://add?url=<encoded link>`

## Install

Requires macOS 26 or later on Apple Silicon.

1. Download `Haul-<version>.dmg` from the [latest release](https://github.com/sibiraj-s/haul/releases/latest).
2. Open it and drag Haul to Applications.

Haul checks for updates once a day and installs them from within the app.
