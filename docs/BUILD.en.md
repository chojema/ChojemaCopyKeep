# Build and Run

[한국어](BUILD.ko.md) | [README](../README.en.md)

## Prerequisites

- x64 Windows
- Visual Studio or Build Tools with Desktop development with C++ and the Windows SDK
- CMake 3.24 or later and Ninja
- Python 3.11 or later for the public-file audit

SQLite is built against `winsqlite/winsqlite3.h` and `winsqlite3.lib` from the Windows SDK and uses the operating system's `winsqlite3.dll`. The build does not download external packages.

## Build

Run from the project folder. The script discovers Visual Studio and sets up the C++ environment within its own process. It does not change system environment variables or the global execution policy.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Test
```

The executable is generated at `build/windows/ChojemaCopyKeep.exe`. Launching it adds an icon to the notification area.

## Checks

CTest covers text and image storage, duplicates, promotion settings, deletion, retention limits, settings and restart persistence, previews, and both language resources. It uses temporary data under the supplied build folder and does not collect the actual clipboard.

Popup checks in both languages cover automatic preview expansion and collapse, mouse hover previews, keyboard and mouse selection, preservation of the paste command, and placement at screen edges. They use synthetic data and do not send actual paste input.

```powershell
ctest --test-dir build/windows --output-on-failure
python tools/public_audit.py
```

Rendering checks use synthetic samples, disable clipboard collection, and do not register login startup.

```powershell
build/windows/ChojemaCopyKeep.exe --smoke-test ko .local/preview-ko.png
build/windows/ChojemaCopyKeep.exe --smoke-test en .local/preview-en.png
```

Append `short`, `long`, `multiline`, `hover`, `image`, `empty`, `many`, `settings`, or `contrast` to render that state. The default is `image`. The `contrast` case uses system high-contrast colors in the synthetic window without changing operating system settings. Settings checks are included in the standard test run.

Use `--data-dir` during normal execution to select a separate development storage folder. It can contain real copied content and must remain private.

Windows also supports the `snippets` and `snippet-editor` smoke scenarios. CTest includes both languages for the snippet list and editor. Checks cover snippet storage, search, editing, cancellation, restart persistence, and separation from history deletion and retention limits.

## Distribution

Distribute the executable with both language guides. Exclude databases, personal settings, logs, internal work records, and intermediate build files. Automatic updates and a signed installer are not provided.

Public files are managed through `public-files.txt` and `.gitignore`. Run the public-file audit whenever the list changes.
## macOS build

Use macOS 13 or later, Swift 6.0 or later from Xcode Command Line Tools, and Python 3.11 or later. The Swift package uses AppKit, Carbon hotkeys, and system SQLite without downloading external packages.

```bash
bash tools/build-macos.sh test
bash tools/build-macos.sh universal
python3 tools/public_audit.py
bash tools/package-macos.sh
```

`universal` combines arm64 and x86_64 Release executables. `native` builds only the current Mac architecture. Output: `build/macos/Chojema CopyKeep.app`. Run `bash script/build_and_run.sh` to build and launch the native app; optional flags include `--verify`, `--debug`, and `--logs`. Normal launch collects clipboard changes made after startup.

Tests use temporary databases and a named test pasteboard. They cover persistence, deduplication, ordering, deletion, limits, localization keys, shortcut validation, screen bounds, PNG conversion, and collection exclusions. Screen rendering does not change the general clipboard, login items, or Accessibility permission.

```bash
open -n -W 'build/macos/Chojema CopyKeep.app' --args --smoke-test ko /tmp/copykeep-ko.png hover
open -n -W 'build/macos/Chojema CopyKeep.app' --args --smoke-test en /tmp/copykeep-en.png settings
```

Scenarios: `short`, `long`, `multiline`, `image`, `hover`, `empty`, `settings`, `interactions`. A JSON file alongside each PNG records selection and preview state. Normal launches accept `--data-dir` for an alternate development data directory.

`tools/package-macos.sh` packages the Universal app and bilingual guides, and creates `SHA256SUMS-macos.txt`. Default builds use ad hoc signing, with no Developer ID signature or Apple notarization. Existing Windows releases and tags are preserved. macOS source uses the `v0.2.0-macos` tag.

The macOS snippet smoke scenarios are `snippets`, `snippet-editor`, and `snippet-interactions`. They use temporary databases to check creation, editing, cancellation, search, keyboard navigation, paste commands, separation from history deletion, and restart persistence. They do not change the real clipboard or user settings.
