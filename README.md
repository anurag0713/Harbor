<p align="center">
  <img src="HarborIcon.png" width="128" height="128" alt="Harbor App Icon" style="border-radius: 24px;" />
</p>

# Harbor 🚢

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-black.svg)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)

> A lightweight macOS Menu Bar companion for Xcode Device Hub.
> Bridges the gap between macOS and simulator runtimes with instant drag-and-drop file imports, bidirectional clipboard synchronization, and host keyboard shortcut restoration.

---

## Features

### 1. 📦 Drag & Drop File Routing
- **Media (Images & Videos)**: Drag `.jpg`, `.png`, `.heic`, `.mp4`, `.mov`, etc. onto Harbor (or the floating widget) and it instantly imports them directly into the booted simulator's Photos library via `xcrun simctl addmedia`.
- **Push Notifications (`.apns`)**: Drop an `.apns` JSON payload; Harbor detects the `"Simulator Target Bundle"` and fires a simulated push notification.
- **Documents & Raw Files**: Direct routing into the active app's `Documents` sandbox container.

### 2. 📋 Bidirectional Clipboard Sync
- **Mac → Simulator**: Instantly sends your Mac's pasteboard into the active simulator (`xcrun simctl pbcopy`).
- **Global Hotkey**: Press `Option + Shift + V` (`⌥⇧V`) anywhere on your Mac to sync your clipboard into the simulator without opening any menus.
- **Simulator → Mac**: Pulls text from the simulator's pasteboard back to macOS with one click.

### 3. ⌨️ Host Keyboard Shortcut Fix
- Toggle the `hostKeybindingPolicy` fix to prevent Device Hub from swallowing `⌘H` (Hide), `⌘Tab`, and standard system window shortcuts.
- Writes to `com.apple.dt.DeviceKit` without requiring root privileges.

### 4. 🪟 Always-On-Top Floating Drop Pill
- An optional, borderless, translucent floating widget that stays above Xcode and Device Hub.
- Freely draggable anywhere on screen; remembers its position across restarts.

---

## Requirements & Building

- macOS 14.0+ (Sonoma or later)
- Xcode 16.0+ (supports Xcode 27 Device Hub)
- Built with pure SwiftUI & AppKit — zero external dependencies.

### Generate Xcode Project & Build
```bash
# Generate the .xcodeproj using xcodegen
xcodegen generate

# Build Debug app
xcodebuild -project Harbor.xcodeproj -scheme Harbor build CODE_SIGNING_ALLOWED=NO
```

---

## Contributing 🤝

Contributions are very welcome! Whether it’s reporting a bug, proposing a new feature to fix another Device Hub quirk, or submitting a pull request, your input helps make simulator testing smoother for everyone.

### How to Contribute:
1. **Feature Requests & Ideas**: Have an idea or facing a Device Hub pain point not yet covered? Please [open an issue](https://github.com/anurag0713/Harbor/issues) describing the problem and what workflow it would improve.
2. **Bug Reports**: Found a bug? Open an issue with details about your macOS version, Xcode version, and steps to reproduce.
3. **Pull Requests**:
   - Fork the repository.
   - Create your feature branch (`git checkout -b feature/amazing-feature`).
   - Commit your changes (`git commit -m 'feat: add support for XYZ'`).
   - Push to your branch (`git push origin feature/amazing-feature`).
   - Open a Pull Request.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
