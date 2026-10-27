# Chojema CopyKeep

[한국어](README.md)

A Windows clipboard history app for storing text and images and selecting an item to paste with a keyboard shortcut. Developed by Park Chulwoo.

## Run

The current target is x64 Windows 10 or Windows 11. Run `ChojemaCopyKeep.exe` to add its icon to the notification area. Administrator privileges are not required.

1. Copy text or an image in another app.
2. Place the insertion point in the destination and press `Ctrl + Shift + Z`.
3. Press `Enter` to paste the first item, or choose another item with the arrow keys or mouse.
4. Press `Esc` to close the list. Right-click the notification area icon to pause collection or quit.

The list appears near the text insertion point, falling back to the mouse pointer when that location is unavailable. Collection starts with copies made after the app starts.

## Settings

- Korean is the initial language. Switching to English updates the interface immediately; saving preserves the selection after restart.
- Customize the shortcut using a combination that includes Ctrl or Alt. The default is `Ctrl + Shift + Z`.
- Moving used items to the top is enabled by default.
- Login startup is disabled by default and can be enabled in Settings.
- The default history limit is 200 items, adjustable from 10 to 1000. Duplicate content is merged and moved to the latest position.
- Limits are 32 MiB per item, 16,777,216 pixels per image, and 256 MiB of stored payloads. These are not limits on the full database file or process memory.
- Use Delete or the Delete button to remove the selected item. Clear all requires confirmation.

## Storage and Privacy

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`. The app loads history metadata rather than keeping every payload in memory. It creates image previews on selection. There is no cloud synchronization, account login, remote content transmission, or usage collection. The app does not encrypt its database.

Copied sensitive content may be recorded. Use Pause and deletion controls when appropriate. Items marked for exclusion by their source apps are skipped, but the app cannot automatically identify sensitive content from every app. See the [privacy guide](docs/PRIVACY.en.md).

## Supported Scope

- Text is stored as plain text. HTML, RTF, copied files, and multiple-item clipboard packages are outside the current scope.
- Images support PNG and Windows bitmap formats. The destination must accept image pastes.
- Pasting sends Ctrl + V to the original app. Elevated apps and secure input screens may restrict this. Successful input transmission does not prove that the destination accepted the paste.
- The macOS version has not been implemented. Development and builds will be handled separately.

## Build and Check

See the [English build guide](docs/BUILD.en.md). Visual Studio Desktop development with C++, the Windows SDK, CMake, and Ninja are required.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Test
```

The executable is `build/windows/ChojemaCopyKeep.exe`. Version 0.1.0 is under development. Real-world paste compatibility and extended runtime behavior require additional validation.

## Developer and License

Park Chulwoo. A project distribution license has not been designated. Reuse terms will be documented separately from repository visibility. Windows and SQLite components remain subject to their respective rights.
