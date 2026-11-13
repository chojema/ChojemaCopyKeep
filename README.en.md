# Chojema CopyKeep

[한국어](README.md) | [Download](https://github.com/chojema/ChojemaCopyKeep/releases/latest)

A Windows and macOS clipboard manager that saves copied text and images and lets you select and paste them with a keyboard shortcut.

## Download and Run

Windows and macOS packages are available on the same [latest release page](https://github.com/chojema/ChojemaCopyKeep/releases/latest).

The app targets x64 Windows 10 and Windows 11. Choose either option; neither requires administrator privileges.

| Distribution | File | Usage |
| --- | --- | --- |
| Installer | `ChojemaCopyKeep-windows-x64-setup-0.4.0.exe` | Install, then launch from the Start menu. Remove it through Installed apps in Windows Settings. |
| Standalone | `ChojemaCopyKeep-windows-x64-portable-0.4.0.zip` | Extract and run `ChojemaCopyKeep.exe`. No installation or uninstall registration is required. |

The default installation directory is `%LOCALAPPDATA%\Programs\ChojemaCopyKeep`. Quit the running app through its notification area menu before installing, updating, or uninstalling. Also quit the existing app before launching a new standalone version. Only one copy runs at a time; a new executable exits if another copy is already running.

Both distributions use `%LOCALAPPDATA%\ChojemaCopyKeep\history.db` for history, snippets, and settings, preserving data when switching between them. The standalone version also stores data there, rather than beside its executable. Uninstalling or deleting the standalone folder preserves this data. If login startup is already enabled, installation updates its shortcut to the installed location. Installation does not enable login startup by default. Uninstallation removes the startup shortcut only if it points to that installed copy.

`SHA256SUMS-windows.txt` lists SHA-256 checksums for both Windows packages. The original Windows ZIP and checksum remain available. The Windows executable and installer are unsigned. The app icon appears in the notification area.

For macOS 13 or later, download the macOS Universal ZIP from the [latest release](https://github.com/chojema/ChojemaCopyKeep/releases/latest), extract it, and move `Chojema CopyKeep.app` to Applications. It includes Apple Silicon and Intel executables. Use the clipboard icon in the menu bar to check status and open Settings. This distribution is ad hoc signed; it has no Developer ID signature or Apple notarization. If macOS blocks the app, you may need to allow this specific app in System Settings > Privacy & Security.

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

## Checking for Updates

On Windows, right-click the notification area icon; on macOS, click the menu bar icon. Choose `Check for updates`. The check runs in the background and shows the current and latest stable versions. When an update is available, you can open the official release page in your browser. Download and install it manually: quit the app before installing or extracting and running a new ZIP. History and settings stay in their existing storage location.

The app contacts GitHub only when you select this menu item. Connection failures are reported separately and never shown as an up-to-date result. This feature is available in Windows and macOS 0.3.0 or later. On macOS, quit the app, extract the download, and replace the existing app in Applications.

## Text replacement

Windows and macOS 0.4.0 replace a typed abbreviation with registered text automatically. For example, assign a multiline address to `;;addr`; typing the final character and releasing its key inserts the address in another app without opening the popup.

- Open `Text replacements` from the menu or popup, then choose `New text replacement`. Enter a title, abbreviation and content. Content can include multiple lines, Korean and emoji, up to 65,536 UTF-16 units.
- Abbreviations are case-sensitive and contain 2–64 nonspace ASCII letters, digits or symbols. Duplicate abbreviations and abbreviations that prefix one another are rejected. Use a distinctive prefix such as `;;addr` or `;;sig`. Abbreviations starting with a letter or digit do not expand inside another word.
- Type abbreviations with an English input source. Active Korean IME composition is excluded; replacement content can include Korean.
- Existing snippets are preserved. Add an abbreviation to enable automatic replacement, or leave it blank to paste from the list only. Search titles, content or abbreviations; edit, save from history or delete individual entries with confirmation.
- Clearing history and applying its limit do not affect replacements. The pause menu pauses both collection and automatic replacement.
- macOS requires Device Control and Data Access permission (Accessibility on earlier macOS versions). Follow the app's permission prompt, then relaunch it. Password fields and secure input are excluded. If an app does not expose the insertion point and exact abbreviation through accessibility APIs, the original input is left unchanged. Windows input can be restricted in elevated apps.
- Replacement copies the registered content to the system clipboard and pastes it. This changes the previous clipboard content; the replacement itself is not added to clipboard history. Date variables and scripts are not supported.

## Data Storage and Privacy

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`. There is no clipboard content upload, cloud synchronization, account login, or usage collection. Checking for updates contacts GitHub without sending history, snippets, or settings. The app does not encrypt its database.

On macOS the location is `~/Library/Application Support/ChojemaCopyKeep/history.db`. Each operating system keeps its own history.

Sensitive copied content may also be saved. The [privacy guide](docs/PRIVACY.en.md) describes collection exclusions, pause controls, and deletion behavior.

## Support and Limitations

- Text is stored as plain text. HTML, RTF, copied files, and multiple-item clipboard formats are not supported.
- Image collection supports PNG and bitmap on Windows, and PNG and TIFF on macOS. The destination app must also accept image input.
- Pasting sends `Ctrl + V` to the original app. Input restrictions in the destination app can prevent pasting, including in elevated apps and secure input screens.
- Paste compatibility across apps and extended runtime behavior require additional validation.
- On macOS, pasting activates the original app and sends `Command + V`. Secure input or destination app restrictions can prevent pasting. Sending input does not guarantee that the destination accepts the content.
- macOS 0.2.0 was checked with synthetic data and rendered screens on Apple Silicon. Intel builds and executable structure were checked; physical Intel hardware, pasting across external apps, and startup after login remain unverified.

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

The app is generated at `build/macos/Chojema CopyKeep.app`, and the ZIP in `dist/macos-v0.4.0/`. Use the shared `v0.4.0` tag for Windows and macOS 0.4.0 source.

## License

The project uses the [MIT License](LICENSE), permitting commercial use, modification, and redistribution while retaining its copyright and permission notice. The software is provided without warranty. Third-party components retain their own notices.

## Project Information

- Developer and maintainer: Park Chulwoo
- License: [MIT](LICENSE)

Operating system and SQLite components remain subject to their respective rights.
