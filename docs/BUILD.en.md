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

## Distribution

Distribute the executable with both language guides. Exclude databases, personal settings, logs, internal work records, and intermediate build files. Automatic updates and a signed installer are not provided.

Public files are managed through `public-files.txt` and `.gitignore`. Run the public-file audit whenever the list changes.
