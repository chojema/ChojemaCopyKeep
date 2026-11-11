Unicode true
RequestExecutionLevel user
ManifestDPIAware true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

!define APP "Chojema CopyKeep"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\ChojemaCopyKeep"
Name "${APP}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\ChojemaCopyKeep"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1042 "ProductName" "${APP}"
VIAddVersionKey /LANG=1042 "CompanyName" "Park Chulwoo"
VIAddVersionKey /LANG=1042 "LegalCopyright" "Park Chulwoo"
VIAddVersionKey /LANG=1042 "FileDescription" "${APP} 설치 프로그램"
VIAddVersionKey /LANG=1042 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${APP}"
VIAddVersionKey /LANG=1033 "CompanyName" "Park Chulwoo"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Park Chulwoo"
VIAddVersionKey /LANG=1033 "FileDescription" "${APP} Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
SetCompressor zlib
ShowInstDetails show
ShowUninstDetails show

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\ChojemaCopyKeep.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_LANGDLL_ALLLANGUAGES
!define MUI_LANGDLL_WINDOWTITLE "Chojema CopyKeep"
!define MUI_LANGDLL_INFO "언어를 선택하세요. / Select a language."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "English"

LangString Running ${LANG_KOREAN} "Chojema CopyKeep이 실행 중이거나 실행 상태를 확인할 수 없습니다. 알림 영역 메뉴에서 앱을 종료한 뒤 다시 시도하세요."
LangString Running ${LANG_ENGLISH} "Chojema CopyKeep is running, or its status could not be checked. Quit the app from the notification area menu, then retry."
LangString Unsupported ${LANG_KOREAN} "이 설치 프로그램은 Windows 10 이상 x64 환경용입니다."
LangString Unsupported ${LANG_ENGLISH} "This installer requires x64 Windows 10 or later."
LangString InstallError ${LANG_KOREAN} "설치를 완료하지 못했습니다. 설치 위치의 쓰기 권한과 사용 중인 파일을 확인하세요."
LangString InstallError ${LANG_ENGLISH} "Installation could not be completed. Check write access and files in use in the installation directory."
LangString DifferentLocation ${LANG_KOREAN} "기존 설치 위치를 선택하세요. 위치를 변경하려면 먼저 기존 설치본을 제거하세요. 기록과 상용구는 유지됩니다."
LangString DifferentLocation ${LANG_ENGLISH} "Choose the existing installation directory. To change locations, uninstall the existing copy first. History and snippets are preserved."

Var StartupTarget
Var SetupMutex

!macro AppFunctions Prefix
Function ${Prefix}EnsureStopped
  Push $0
  Push $1
  retry:
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\ChojemaCopyKeep.SingleInstance") p.r0 ?e'
  Pop $1
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
  ${ElseIf} $1 == 2
    Pop $1
    Pop $0
    Return
  ${EndIf}
  MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "$(Running)" /SD IDCANCEL IDRETRY retry
  SetErrorLevel 2
  Quit
FunctionEnd

!if "${Prefix}" == "un."
Function ${Prefix}ReadStartupTarget
  Push $0
  Push $1
  Push $2
  Push $3
  StrCpy $StartupTarget ""
  System::Call 'ole32::CoCreateInstance(g "{00021401-0000-0000-C000-000000000046}", p 0, i 1, g "{000214F9-0000-0000-C000-000000000046}", *p.r0) i.r3'
  ${If} $3 == 0
    System::Call '$0->0(g "{0000010B-0000-0000-C000-000000000046}", *p.r1) i.r3'
    ${If} $3 == 0
      System::Call '$1->5(w "$SMSTARTUP\Chojema CopyKeep.lnk", i 0) i.r3'
      ${If} $3 == 0
        System::Call '$0->3(w .r2, i ${NSIS_MAX_STRLEN}, p 0, i 0) i.r3'
        ${If} $3 == 0
          StrCpy $StartupTarget $2
        ${EndIf}
      ${EndIf}
      System::Call '$1->2()'
    ${EndIf}
    System::Call '$0->2()'
  ${EndIf}
  Pop $3
  Pop $2
  Pop $1
  Pop $0
FunctionEnd
!endif
!macroend
!insertmacro AppFunctions ""
!insertmacro AppFunctions "un."

!macro Initialize
  SetShellVarContext current
  SetRegView 64
  StrCpy $LANGUAGE ${LANG_KOREAN}
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\ChojemaCopyKeep.Setup") p.s ?e'
  Pop $0
  Pop $SetupMutex
  ${If} $SetupMutex == 0
  ${OrIf} $0 == 183
    SetErrorLevel 2
    Quit
  ${EndIf}
!macroend

Function .onInit
  !insertmacro Initialize
  !insertmacro MUI_LANGDLL_DISPLAY
  ${IfNot} ${AtLeastWin10}
  ${OrIfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "$(Unsupported)" /SD IDOK
    SetErrorLevel 1
    Quit
  ${EndIf}
  Call EnsureStopped
FunctionEnd

Section "${APP}"
  Call EnsureStopped
  ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "InstallLocation"
  ${If} $0 != ""
  ${AndIf} $0 != $INSTDIR
    MessageBox MB_OK|MB_ICONSTOP "$(DifferentLocation)" /SD IDOK
    SetErrorLevel 3
    Quit
  ${EndIf}
  SetOutPath "$INSTDIR"
  ClearErrors
  File "${PAYLOAD}\ChojemaCopyKeep.exe"
  File "${PAYLOAD}\README.md"
  File "${PAYLOAD}\README.en.md"
  SetOutPath "$INSTDIR\docs"
  File "${PAYLOAD}\docs\BUILD.ko.md"
  File "${PAYLOAD}\docs\BUILD.en.md"
  File "${PAYLOAD}\docs\PRIVACY.ko.md"
  File "${PAYLOAD}\docs\PRIVACY.en.md"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Chojema CopyKeep"
  CreateShortCut "$SMPROGRAMS\Chojema CopyKeep\Chojema CopyKeep.lnk" "$INSTDIR\ChojemaCopyKeep.exe"
  CreateShortCut "$SMPROGRAMS\Chojema CopyKeep\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  IfFileExists "$SMSTARTUP\Chojema CopyKeep.lnk" 0 +2
    CreateShortCut "$SMSTARTUP\Chojema CopyKeep.lnk" "$INSTDIR\ChojemaCopyKeep.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Park Chulwoo"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\ChojemaCopyKeep.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Language" "$LANGUAGE"
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${If} ${Errors}
    MessageBox MB_OK|MB_ICONSTOP "$(InstallError)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
SectionEnd

Function un.onInit
  !insertmacro Initialize
  ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "Language"
  ${If} $0 != ""
    StrCpy $LANGUAGE $0
  ${EndIf}
  Call un.EnsureStopped
FunctionEnd

Section "Uninstall"
  Call un.EnsureStopped
  Call un.ReadStartupTarget
  ${If} $StartupTarget == "$INSTDIR\ChojemaCopyKeep.exe"
    Delete "$SMSTARTUP\Chojema CopyKeep.lnk"
  ${EndIf}
  Delete "$SMPROGRAMS\Chojema CopyKeep\Chojema CopyKeep.lnk"
  Delete "$SMPROGRAMS\Chojema CopyKeep\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Chojema CopyKeep"
  Delete "$INSTDIR\ChojemaCopyKeep.exe"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\README.en.md"
  Delete "$INSTDIR\docs\BUILD.ko.md"
  Delete "$INSTDIR\docs\BUILD.en.md"
  Delete "$INSTDIR\docs\PRIVACY.ko.md"
  Delete "$INSTDIR\docs\PRIVACY.en.md"
  RMDir "$INSTDIR\docs"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  ReadRegStr $0 HKCU "${UNINSTALL_KEY}" "InstallLocation"
  ${If} $0 == $INSTDIR
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
  ${EndIf}
SectionEnd
