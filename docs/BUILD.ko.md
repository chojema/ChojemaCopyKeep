# 빌드와 실행

[English](BUILD.en.md) | [README](../README.md)

## 준비

- Windows x64 환경
- Visual Studio 또는 Build Tools의 C++ 데스크톱 개발 도구와 Windows SDK
- CMake 3.24 이상, Ninja
- 공개 파일 검사용 Python 3.11 이상

SQLite는 Windows SDK의 `winsqlite/winsqlite3.h`와 `winsqlite3.lib`로 빌드하고 운영체제의 `winsqlite3.dll`을 사용합니다. 빌드 중 외부 패키지를 다운로드하지 않습니다.

## 빌드

프로젝트 폴더에서 실행합니다. 빌드 스크립트는 설치된 Visual Studio를 검색하고 해당 프로세스 안에서 C++ 환경을 구성합니다. 시스템 환경 변수와 전역 실행 정책은 바꾸지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Test
```

빌드 결과는 `build/windows/ChojemaCopyKeep.exe`에 생성됩니다. 실행하면 알림 영역에 아이콘이 표시됩니다.

## 검사

CTest는 텍스트와 이미지 저장, 중복 처리, 순서 이동 옵션, 삭제, 보관 한도, 설정과 재실행 후 복원, 이미지 미리보기 및 두 언어 리소스를 검사합니다. 테스트는 전달된 빌드 폴더의 임시 데이터만 사용하고 실제 클립보드 내용을 수집하지 않습니다.

두 언어의 팝업 검사에서는 항목 선택에 따른 미리보기 자동 표시와 숨김, 마우스 호버 미리보기, 키보드와 마우스 선택, 붙여넣기 명령 유지 및 화면 가장자리 배치를 확인합니다. 합성 데이터만 사용하고 실제 붙여넣기 입력은 전송하지 않습니다.

```powershell
ctest --test-dir build/windows --output-on-failure
python tools/public_audit.py
```

화면 렌더링 확인용 명령은 합성 샘플만 사용하고 실제 클립보드 수집과 자동 실행 등록을 하지 않습니다.

```powershell
build/windows/ChojemaCopyKeep.exe --smoke-test ko .local/preview-ko.png
build/windows/ChojemaCopyKeep.exe --smoke-test en .local/preview-en.png
```

마지막 인수로 `short`, `long`, `multiline`, `hover`, `image`, `empty`, `many`, `settings`, `contrast`를 지정하면 해당 상태를 렌더링합니다. 생략하면 이미지 상태를 사용합니다. `contrast`는 합성 화면에 시스템 고대비 색상을 적용하며 운영체제 설정은 바꾸지 않습니다. 설정창 검사도 기본 검사에 포함됩니다. Windows는 `snippets`, `snippet-editor` 시나리오도 지원하며 상용구 목록과 편집창의 두 언어 검사를 기본 검사에 포함합니다. 상용구 저장·검색·수정·취소·재실행 복원과 기록 삭제로부터의 분리도 검사합니다.

개발용 저장 위치는 `--data-dir`로 지정할 수 있습니다. 일반 실행에서는 이 폴더에 실제 복사 내용이 저장되므로 공개 대상에서 제외해야 합니다.

## 배포

실행 파일과 두 언어 안내를 함께 배포합니다. 데이터베이스, 개인 설정, 로그, 내부 작업 기록과 빌드 중간 파일을 포함하지 않습니다. 자동 업데이트와 서명된 설치 프로그램은 제공하지 않습니다.

공개 대상 파일은 `public-files.txt`와 `.gitignore`로 관리합니다. 목록을 변경할 때는 공개 파일 검사도 함께 실행합니다.

## macOS

macOS 13 이상, Xcode Command Line Tools의 Swift 6.0 이상과 Python 3.11 이상을 사용합니다. Swift Package Manager와 AppKit, Carbon 단축키, 운영체제 SQLite를 사용하며 외부 패키지를 다운로드하지 않습니다.

```bash
bash tools/build-macos.sh test
bash tools/build-macos.sh universal
python3 tools/public_audit.py
bash tools/package-macos.sh
```

`universal`은 arm64와 x86_64 Release 실행 파일을 합칩니다. `native`는 현재 Mac 아키텍처만 빌드합니다. 결과는 `build/macos/Chojema CopyKeep.app`입니다. `bash script/build_and_run.sh`로 현재 아키텍처 빌드와 실행을 함께 할 수 있습니다. `--verify`, `--debug`, `--logs` 옵션을 지원합니다. 실제 실행은 앱 실행 이후의 클립보드를 수집합니다.

검사는 임시 데이터베이스와 이름 있는 시험용 페이스트보드만 사용합니다. 저장 및 복원, 중복, 순서, 삭제, 보관 한도, 언어 키, 단축키 검증, 화면 영역 배치, PNG 변환과 수집 제외를 검사합니다. 화면 확인은 실제 클립보드와 로그인 항목, 손쉬운 사용 권한을 변경하지 않습니다.

```bash
open -n -W 'build/macos/Chojema CopyKeep.app' --args --smoke-test ko /tmp/copykeep-ko.png hover
open -n -W 'build/macos/Chojema CopyKeep.app' --args --smoke-test en /tmp/copykeep-en.png settings
```

화면 시나리오는 `short`, `long`, `multiline`, `image`, `hover`, `empty`, `settings`, `interactions`입니다. PNG와 같은 이름의 JSON에 선택 및 미리보기 상태를 저장합니다. 일반 실행의 개발용 저장 위치는 `--data-dir`로 지정합니다.

`tools/package-macos.sh`는 Universal 앱과 두 언어 안내만 ZIP에 넣고 `SHA256SUMS-macos.txt`를 생성합니다. 기본 빌드는 임시 서명(ad hoc)만 적용하며 Apple 공증과 Developer ID 서명은 포함하지 않습니다. Windows 릴리스와 태그는 보존하고 macOS 소스는 `v0.2.0-macos` 태그로 구분합니다.

macOS 상용구 합성 검사 시나리오는 `snippets`, `snippet-editor`, `snippet-interactions`입니다. 시험용 데이터베이스에서 생성·편집·취소·검색·키보드 이동·붙여넣기 명령과 기록 삭제 후 보존·재실행 복원을 확인하며 실제 클립보드와 사용자 설정은 변경하지 않습니다.
