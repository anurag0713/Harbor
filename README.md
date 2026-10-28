# Harbor 🚢

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

## License
MIT License. Copyright © 2026 Anurag Singh.
