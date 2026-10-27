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

```powershell
ctest --test-dir build/windows --output-on-failure
python tools/public_audit.py
```

화면 렌더링 확인용 명령은 합성 샘플만 사용하고 실제 클립보드 수집과 자동 실행 등록을 하지 않습니다.

```powershell
build/windows/ChojemaCopyKeep.exe --smoke-test ko .local/preview-ko.png
build/windows/ChojemaCopyKeep.exe --smoke-test en .local/preview-en.png
```

개발용 저장 위치는 `--data-dir`로 지정할 수 있습니다. 일반 실행에서는 이 폴더에 실제 복사 내용이 저장되므로 공개 대상에서 제외해야 합니다.

## 배포

실행 파일과 두 언어 안내를 함께 배포합니다. 데이터베이스, 개인 설정, 로그, 내부 작업 기록과 빌드 중간 파일을 포함하지 않습니다. 자동 업데이트와 서명된 설치 프로그램은 제공하지 않습니다.

공개 대상 파일은 `public-files.txt`와 `.gitignore`로 관리합니다. 목록을 변경할 때는 공개 파일 검사도 함께 실행합니다.
