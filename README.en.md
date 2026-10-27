# Chojema CopyKeep

[한국어](README.md) | [Download](https://github.com/chojema/ChojemaCopyKeep/releases/latest)

A Windows clipboard manager that saves copied text and images and lets you select and paste them with a keyboard shortcut.

## Download and Run

The app targets x64 Windows 10 and Windows 11. Download the Windows x64 ZIP from the [latest release](https://github.com/chojema/ChojemaCopyKeep/releases/latest), extract it, and run `ChojemaCopyKeep.exe`. The app icon appears in the notification area. Administrator privileges are not required.

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

## Settings and History

- Korean is the default language. Switching to English updates the interface immediately; saving preserves the selection after restart.
- Customize the shortcut using a combination that includes Ctrl or Alt. The default is `Ctrl + Shift + Z`.
- Moving used items to the top is enabled by default.
- Login startup is disabled by default and can be enabled in Settings.
- The default history limit is 200 items, adjustable from 10 to 1000. Duplicate content is merged and moved to the latest position.
- Use Delete or the Delete button to remove the selected item. Clear all requires confirmation.

Storage limits are 32 MiB per item, 16,777,216 pixels per image, and 256 MiB of stored payloads. Database file size and process memory usage may differ from these limits.

## Data Storage and Privacy

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`. There is no cloud synchronization, account login, remote transmission, or usage collection. The app does not encrypt its database.

Sensitive copied content may also be saved. The [privacy guide](docs/PRIVACY.en.md) describes collection exclusions, pause controls, and deletion behavior.

## Support and Limitations

- Text is stored as plain text. HTML, RTF, copied files, and multiple-item clipboard formats are not supported.
- Images support PNG and Windows bitmap formats. The destination app must also accept image input.
- Pasting sends `Ctrl + V` to the original app. Input restrictions in the destination app can prevent pasting, including in elevated apps and secure input screens.
- Paste compatibility across apps and extended runtime behavior require additional validation.
- macOS is not currently supported.

## Build from Source

Visual Studio Desktop development with C++, the Windows SDK, CMake, and Ninja are required. See the [build guide](docs/BUILD.en.md) for setup and checks.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Test
```

The executable is generated at `build/windows/ChojemaCopyKeep.exe`.

## Project Information

- Developer and maintainer: Park Chulwoo
- License: Not designated

Windows and SQLite components remain subject to their respective rights.
