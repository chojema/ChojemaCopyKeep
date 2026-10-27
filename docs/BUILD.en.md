# Build and Run

[한국어](BUILD.ko.md) / [Home](../README.en.md)

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

The output is `build/windows/ChojemaCopyKeep.exe`. Look for the notification area icon after launch.

## Checks

CTest covers text and image storage, duplicates, promotion settings, deletion, retention limits, settings and restart persistence, previews, and both language resources. It uses temporary data under the supplied build folder and does not collect the actual clipboard.

```powershell
ctest --test-dir build/windows --output-on-failure
python tools/public_audit.py
```

Rendering checks use synthetic samples, disable clipboard collection, and do not register login startup.

```powershell
build/windows/ChojemaCopyKeep.exe --smoke-test ko .local/preview-ko.png
build/windows/ChojemaCopyKeep.exe --smoke-test en .local/preview-en.png
```

Use `--data-dir` during normal execution to select a separate development storage folder. It can contain real copied content and must remain private.

## Distribution

Distribute the executable with both language guides. Exclude databases, personal settings, logs, internal work records, and intermediate build files. Automatic updates and a signed installer are not provided at this stage.

Git operations must use the reviewed files in `public-files.txt`. Do not indiscriminately add the entire folder. Update `.gitignore` and the audit when changing the public-file list.

## Connect and Publish to GitHub

Prepare an empty public repository owned by the user. Run the following in a normal PowerShell session with working Git and GitHub CLI access.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/publish.ps1
```

The default destination is `chojema/ChojemaCopyKeep`. The script verifies the account and public visibility, audits public files, and commits only approved files. It uses Park Chulwoo as the author and committer and derives the no-reply email from the verified GitHub account. It does not replace an unrelated origin or force-push. It confirms that the remote commit matches the local revision before reporting success. Environments that restrict network access or Git writes stop before completion; preparation alone does not mean that publication succeeded.
