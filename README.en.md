# Chojema CopyKeep

[한국어](README.md) | [Download](https://github.com/chojema/ChojemaCopyKeep/releases/latest)

A Windows and macOS clipboard manager that saves copied text and images and lets you select and paste them with a keyboard shortcut.

## Download and Run

The app targets x64 Windows 10 and Windows 11. Download the Windows x64 ZIP from the [latest release](https://github.com/chojema/ChojemaCopyKeep/releases/latest), extract it, and run `ChojemaCopyKeep.exe`. The app icon appears in the notification area. Administrator privileges are not required.

For macOS 13 or later, download the Universal ZIP from the [macOS 0.1.4 release](https://github.com/chojema/ChojemaCopyKeep/releases/tag/v0.1.4-macos), extract it, and move `Chojema CopyKeep.app` to Applications. It includes Apple Silicon and Intel executables. Use the clipboard icon in the menu bar to check status and open Settings. This distribution is ad hoc signed; it has no Developer ID signature or Apple notarization. If macOS blocks the app, you may need to allow this specific app in System Settings > Privacy & Security.

## Usage

1. Copy text or an image in another app.
2. Place the insertion point in the destination and press `Ctrl + Shift + Z`.
3. Press `Enter` to paste the first item, or choose another item with the arrow keys or mouse.
4. Press `Esc` to close the list.

The list appears near the right side of the text insertion point. When that position is unavailable, it appears near the mouse pointer. History starts with content copied after the app launches.

Short text uses the list alone. Selecting text that does not fit on one list row, multiline text, or an image automatically shows a preview on the right. Selecting a short item returns to the list alone. No separate action is needed to open the preview.

Resting the mouse pointer on an item briefly shows its preview without changing the selection. Moving the pointer off the list returns to the preview of the selected item. Clicking an item pastes it immediately.

Each list row shows a document or picture icon followed by its content. The selected item has a highlighted background and outline. Keyboard hints, Settings, and deletion controls appear below the list.

Right-click the notification area icon to open Settings, pause collection, or quit.

The default macOS shortcut is also `Control + Shift + Z`. Click the menu bar icon for Settings, pause, and quit. To paste into the original app, allow Chojema CopyKeep in System Settings > Privacy & Security > Accessibility. Without this permission the app displays guidance and does not send paste input.

## Settings and History

- Korean is the default language. Switching to English updates the interface immediately; saving preserves the selection after restart.
- Customize the shortcut using a combination that includes Ctrl or Alt. The default is `Ctrl + Shift + Z`.
- On macOS, combine Control, Option, or Command with a letter or digit, optionally adding Shift. Shortcut letters refer to physical US keyboard positions.
- Moving used items to the top is enabled by default.
- Login startup is disabled by default and can be enabled in Settings.
- The default history limit is 200 items, adjustable from 10 to 1000. Duplicate content is merged and moved to the latest position.
- Use Delete or the Delete button to remove the selected item. Clear all requires confirmation.

Storage limits are 32 MiB per item, 16,777,216 pixels per image, and 256 MiB of stored payloads. Database file size and process memory usage may differ from these limits.

## Data Storage and Privacy

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`. There is no cloud synchronization, account login, remote transmission, or usage collection. The app does not encrypt its database.

On macOS the location is `~/Library/Application Support/ChojemaCopyKeep/history.db`. Each operating system keeps its own history.

Sensitive copied content may also be saved. The [privacy guide](docs/PRIVACY.en.md) describes collection exclusions, pause controls, and deletion behavior.

## Support and Limitations

- Text is stored as plain text. HTML, RTF, copied files, and multiple-item clipboard formats are not supported.
- Image collection supports PNG and bitmap on Windows, and PNG and TIFF on macOS. The destination app must also accept image input.
- Pasting sends `Ctrl + V` to the original app. Input restrictions in the destination app can prevent pasting, including in elevated apps and secure input screens.
- Paste compatibility across apps and extended runtime behavior require additional validation.
- On macOS, pasting activates the original app and sends `Command + V`. Secure input or destination app restrictions can prevent pasting. Sending input does not guarantee that the destination accepts the content.
- macOS 0.1.4 was checked with synthetic data and rendered screens on Apple Silicon. Intel builds and executable structure were checked; physical Intel hardware, pasting across external apps, and startup after login remain unverified.

## Build from Source

Visual Studio Desktop development with C++, the Windows SDK, CMake, and Ninja are required. See the [build guide](docs/BUILD.en.md) for setup and checks.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Test
```

The executable is generated at `build/windows/ChojemaCopyKeep.exe`.

On macOS, use Swift 6.0 or later from Xcode Command Line Tools. No external packages are required.

```bash
bash tools/build-macos.sh test
bash tools/build-macos.sh universal
bash tools/package-macos.sh
```

The app is generated at `build/macos/Chojema CopyKeep.app`, and the ZIP in `dist/macos-v0.1.4/`. Use the `v0.1.4-macos` tag for macOS 0.1.4 source. The original `v0.1.3` tag contains Windows source.

## Project Information

- Developer and maintainer: Park Chulwoo
- License: Not designated

Operating system and SQLite components remain subject to their respective rights.
