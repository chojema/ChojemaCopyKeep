#include "store.h"
#include "image.h"
#include "ids.h"
#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <iostream>
#include <memory>
#include <stdexcept>

using namespace copykeep;
namespace {
constexpr UINT tray_message = WM_APP + 1, paste_message = WM_APP + 2;
constexpr int list_id = 300, settings_id = 301, delete_id = 302, clear_id = 303, close_id = 304;
constexpr UINT capture_timer = 10, paste_timer = 11;
const COLORREF ink = RGB(30, 40, 57), muted = RGB(98, 111, 131), accent = RGB(39, 88, 168);
HINSTANCE instance;
std::wstring text(UINT id, bool english) {
    WORD language = english ? MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US) : MAKELANGID(LANG_KOREAN, SUBLANG_KOREAN);
    auto resource = FindResourceExW(instance, RT_STRING, MAKEINTRESOURCEW(id/16+1), language);
    if (!resource) return L"";
    auto block = LoadResource(instance, resource);
    auto p = static_cast<const WORD*>(LockResource(block));
    for (UINT n = 0; n < id%16; ++n) p += *p + 1;
    return std::wstring(reinterpret_cast<const wchar_t*>(p+1), *p);
}
std::filesystem::path folder_id(REFKNOWNFOLDERID id) {
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(id, KF_FLAG_DEFAULT, nullptr, &value))) throw std::runtime_error("Folder unavailable");
    std::filesystem::path result(value); CoTaskMemFree(value); return result;
}
std::filesystem::path executable() {
    std::wstring value(32768, L'\0'); DWORD n = GetModuleFileNameW(nullptr, value.data(), static_cast<DWORD>(value.size()));
    if (!n || n >= value.size()) throw std::runtime_error("Executable path unavailable");
    value.resize(n); return value;
}
std::filesystem::path startup_path() { return folder_id(FOLDERID_Startup) / L"Chojema CopyKeep.lnk"; }
bool startup_enabled() { return std::filesystem::exists(startup_path()); }
bool set_startup(bool enabled) {
    auto path = startup_path();
    if (!enabled) return !std::filesystem::exists(path) || DeleteFileW(path.c_str());
    IShellLinkW* link = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) return false;
    HRESULT status = link->SetPath(executable().c_str());
    if (SUCCEEDED(status)) status = link->SetWorkingDirectory(executable().parent_path().c_str());
    if (SUCCEEDED(status)) status = link->SetDescription(L"Chojema CopyKeep");
    IPersistFile* file = nullptr;
    if (SUCCEEDED(status)) status = link->QueryInterface(IID_PPV_ARGS(&file));
    if (SUCCEEDED(status)) status = file->Save(path.c_str(), TRUE);
    if (file) file->Release(); link->Release(); return SUCCEEDED(status);
}
HICON make_icon() {
    HDC screen = GetDC(nullptr), dc = CreateCompatibleDC(screen);
    HBITMAP bitmap = CreateCompatibleBitmap(screen, 32, 32), previous = static_cast<HBITMAP>(SelectObject(dc, bitmap));
    HBRUSH blue = CreateSolidBrush(accent); RECT all{0,0,32,32}; FillRect(dc,&all,blue); DeleteObject(blue);
    HPEN pen = CreatePen(PS_SOLID, 2, RGB(255,255,255)); auto oldPen = SelectObject(dc,pen); auto oldBrush=SelectObject(dc,GetStockObject(NULL_BRUSH));
    RoundRect(dc,6,5,23,24,3,3); RoundRect(dc,10,9,27,28,3,3);
    SelectObject(dc,oldPen); SelectObject(dc,oldBrush); DeleteObject(pen); SelectObject(dc,previous);
    HBITMAP mask=CreateBitmap(32,32,1,1,nullptr); HDC maskDC=CreateCompatibleDC(screen); auto oldMask=SelectObject(maskDC,mask); PatBlt(maskDC,0,0,32,32,BLACKNESS); SelectObject(maskDC,oldMask); DeleteDC(maskDC);
    ICONINFO info{TRUE,0,0,mask,bitmap}; HICON result=CreateIconIndirect(&info);
    DeleteObject(mask); DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr,screen); return result;
}
bool set_clipboard_bytes(UINT format, const void* data, size_t size) {
    HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
    if (!memory) return false;
    void* p = GlobalLock(memory);
    if (!p) { GlobalFree(memory); return false; }
    std::memcpy(p, data, size); GlobalUnlock(memory);
    if (!SetClipboardData(format, memory)) { GlobalFree(memory); return false; }
    return true;
}
Bytes clipboard_bytes(UINT format) {
    HGLOBAL memory = static_cast<HGLOBAL>(GetClipboardData(format));
    if (!memory) return {};
    size_t size = GlobalSize(memory);
    if (!size || size > 32u*1024*1024) throw std::runtime_error("Clipboard size exceeds limit");
    const auto* p = static_cast<const unsigned char*>(GlobalLock(memory));
    if (!p) return {};
    Bytes out(p,p+size); GlobalUnlock(memory); return out;
}
int integer(const std::string& s, int fallback) {
    try { size_t end=0; int result=std::stoi(s,&end); return end==s.size()?result:fallback; } catch (...) { return fallback; }
}
class App {
public:
    Store store;
    bool english=false, promote=true, paused=false, testing=false, settingsOpen=false;
    UINT modifiers=MOD_CONTROL|MOD_SHIFT, key='Z';
    HWND host=nullptr, popup=nullptr, list=nullptr, preview=nullptr, buttons[4]{}, target=nullptr;
    HFONT font=nullptr, smallFont=nullptr, titleFont=nullptr;
    HBITMAP previewBitmap=nullptr;
    bool previewExpanded=false, popupAnchorValid=false;
    POINT popupAnchor{};
    HICON icon=nullptr;
    std::vector<Item> items;
    DWORD lastSequence=0;
    int captureAttempts=0, pasteAttempts=0;
    long long pendingId=0;
    UINT pngFormat=RegisterClipboardFormatW(L"PNG"), imagePngFormat=RegisterClipboardFormatW(L"image/png");
    UINT excludeFormat=RegisterClipboardFormatW(L"ExcludeClipboardContentFromMonitorProcessing");
    UINT includeFormat=RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
    UINT taskbarCreated=RegisterWindowMessageW(L"TaskbarCreated");
    bool oldDialogLanguage=false;
    explicit App(const std::filesystem::path& folder, bool test=false):store(folder),testing(test) {
        english=store.setting("language","ko")=="en";
        promote=store.setting("promote","1")!="0";
        modifiers=static_cast<UINT>(integer(store.setting("modifiers","6"),MOD_CONTROL|MOD_SHIFT)) & (MOD_CONTROL|MOD_SHIFT|MOD_ALT);
        key=static_cast<UINT>(integer(store.setting("key","90"),'Z'));
        if (!(modifiers&(MOD_CONTROL|MOD_ALT)) || key<1 || key>254) { modifiers=MOD_CONTROL|MOD_SHIFT; key='Z'; }
        store.limit(integer(store.setting("limit","200"),200));
    }
    ~App() {
        if (previewBitmap) DeleteObject(previewBitmap);
        if (font) DeleteObject(font); if (smallFont) DeleteObject(smallFont); if (titleFont) DeleteObject(titleFont);
        if (icon) DestroyIcon(icon);
    }
    std::wstring t(UINT id) const { return text(id,english); }
    int scale(int value) const { return MulDiv(value, popup?static_cast<int>(GetDpiForWindow(popup)):96,96); }
    void notify(UINT id) {
        if (testing) return;
        NOTIFYICONDATAW data{sizeof(data)}; data.hWnd=host; data.uID=1; data.uFlags=NIF_INFO; data.dwInfoFlags=NIIF_INFO;
        auto body=t(id); wcsncpy_s(data.szInfo,body.c_str(),_TRUNCATE); wcscpy_s(data.szInfoTitle,L"Chojema CopyKeep"); Shell_NotifyIconW(NIM_MODIFY,&data);
    }
    void tray(bool add) {
        NOTIFYICONDATAW data{sizeof(data)}; data.hWnd=host; data.uID=1;
        if (add) {
            data.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP; data.uCallbackMessage=tray_message; data.hIcon=icon; wcscpy_s(data.szTip,L"Chojema CopyKeep");
            Shell_NotifyIconW(NIM_ADD,&data);
        } else Shell_NotifyIconW(NIM_DELETE,&data);
    }
    void initialize() {
        INITCOMMONCONTROLSEX controls{sizeof(controls),ICC_STANDARD_CLASSES|ICC_WIN95_CLASSES}; InitCommonControlsEx(&controls);
        WNDCLASSEXW hostClass{sizeof(hostClass)}; hostClass.hInstance=instance; hostClass.lpszClassName=L"ChojemaCopyKeepHost"; hostClass.lpfnWndProc=host_proc; RegisterClassExW(&hostClass);
        icon=make_icon();
        WNDCLASSEXW popupClass{sizeof(popupClass)}; popupClass.hInstance=instance; popupClass.lpszClassName=L"ChojemaCopyKeepPopup"; popupClass.lpfnWndProc=popup_proc;
        popupClass.hCursor=LoadCursorW(nullptr,IDC_ARROW); popupClass.hIcon=icon; popupClass.hbrBackground=static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)); RegisterClassExW(&popupClass);
        host=CreateWindowExW(WS_EX_TOOLWINDOW,hostClass.lpszClassName,L"Chojema CopyKeep",WS_OVERLAPPED,0,0,0,0,nullptr,nullptr,instance,this);
        popup=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_TOPMOST,popupClass.lpszClassName,L"Chojema CopyKeep",WS_POPUP|WS_CAPTION|WS_SYSMENU,
            40,40,640,460,host,nullptr,instance,this);
        if (!host || !popup) throw std::runtime_error("Window creation failed");
        lastSequence=GetClipboardSequenceNumber();
        if (!testing) {
            if (!AddClipboardFormatListener(host)) throw std::runtime_error("Clipboard listener failed");
            tray(true);
            if (!RegisterHotKey(host,1,modifiers|MOD_NOREPEAT,key)) notify(IDS_HOTKEY_ERROR);
        }
    }
    void fonts() {
        if (font) DeleteObject(font); if (smallFont) DeleteObject(smallFont); if (titleFont) DeleteObject(titleFont);
        auto make=[&](int size,int weight){ return CreateFontW(-scale(size),0,0,0,weight,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI"); };
        font=make(14,FW_NORMAL); smallFont=make(12,FW_NORMAL); titleFont=make(19,FW_SEMIBOLD);
        if (list) { SendMessageW(list,WM_SETFONT,reinterpret_cast<WPARAM>(font),TRUE); SendMessageW(list,LB_SETITEMHEIGHT,0,scale(57)); }
        if (preview) SendMessageW(preview,WM_SETFONT,reinterpret_cast<WPARAM>(font),TRUE);
        for (auto button:buttons) if (button) SendMessageW(button,WM_SETFONT,reinterpret_cast<WPARAM>(font),TRUE);
    }
    void create_controls() {
        list=CreateWindowExW(WS_EX_CLIENTEDGE,L"LISTBOX",L"",WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_TABSTOP|LBS_NOTIFY|LBS_OWNERDRAWFIXED|LBS_HASSTRINGS|LBS_NOINTEGRALHEIGHT,
            0,0,0,0,popup,reinterpret_cast<HMENU>(static_cast<INT_PTR>(list_id)),instance,nullptr);
        SetWindowSubclass(list,list_proc,1,reinterpret_cast<DWORD_PTR>(this));
        preview=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",L"",WS_CHILD|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL|WS_VSCROLL,0,0,0,0,popup,nullptr,instance,nullptr);
        const int ids[]={settings_id,delete_id,clear_id,close_id};
        for (int i=0;i<4;++i) buttons[i]=CreateWindowExW(0,L"BUTTON",L"",WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON,0,0,0,0,popup,reinterpret_cast<HMENU>(static_cast<INT_PTR>(ids[i])),instance,nullptr);
        fonts(); labels(); layout();
    }
    void labels() {
        const UINT ids[]={IDS_SETTINGS,IDS_DELETE,IDS_CLEAR,IDS_CLOSE};
        for (int i=0;i<4;++i) if (buttons[i]) SetWindowTextW(buttons[i],t(ids[i]).c_str());
        if (list) SetWindowTextW(list,t(IDS_APP).c_str());
        if (preview) SetWindowTextW(preview,L"");
        if (popup) InvalidateRect(popup,nullptr,TRUE);
    }
    int compact_list_width() const {
        RECT window{}, client{}; GetWindowRect(popup,&window); GetClientRect(popup,&client);
        MONITORINFO monitor{sizeof(monitor)}; GetMonitorInfoW(MonitorFromWindow(popup,MONITOR_DEFAULTTONEAREST),&monitor);
        int outer=std::min<int>(scale(420),monitor.rcWork.right-monitor.rcWork.left);
        return std::max<int>(scale(80),outer-(window.right-window.left-client.right)-2*scale(16));
    }
    void fit_popup() {
        RECT window{}; GetWindowRect(popup,&window);
        POINT anchor=popupAnchorValid?popupAnchor:POINT{window.left,window.top};
        MONITORINFO monitor{sizeof(monitor)}; GetMonitorInfoW(MonitorFromPoint(anchor,MONITOR_DEFAULTTONEAREST),&monitor);
        int width=std::min<int>(scale(previewExpanded?680:420),monitor.rcWork.right-monitor.rcWork.left);
        int height=std::min<int>(scale(450),monitor.rcWork.bottom-monitor.rcWork.top);
        int x=std::clamp<int>(anchor.x,monitor.rcWork.left,monitor.rcWork.right-width);
        int y=std::clamp<int>(anchor.y,monitor.rcWork.top,monitor.rcWork.bottom-height);
        SetWindowPos(popup,nullptr,x,y,width,height,SWP_NOZORDER|SWP_NOACTIVATE);
        layout();
    }
    void layout() {
        if (!list) return;
        RECT rc{}; GetClientRect(popup,&rc); int margin=scale(16), gap=scale(14), top=scale(72), bottom=scale(66);
        int available=std::max<int>(scale(120),rc.right-2*margin-(previewExpanded?gap:0));
        int left=previewExpanded?std::min<int>(compact_list_width(),available*2/3):available, right=available-left;
        int height=std::max<int>(scale(80),rc.bottom-top-bottom);
        MoveWindow(list,margin,top,left,height,TRUE);
        MoveWindow(preview,margin+left+gap,top,right,height,TRUE);
        int y=rc.bottom-scale(42), width=scale(94);
        MoveWindow(buttons[0],margin,y,width,scale(28),TRUE);
        MoveWindow(buttons[1],margin+width+scale(8),y,scale(76),scale(28),TRUE);
        MoveWindow(buttons[2],margin+width+scale(92),y,width,scale(28),TRUE);
        MoveWindow(buttons[3],rc.right-margin-scale(76),y,scale(76),scale(28),TRUE);
    }
    bool text_needs_preview(const std::wstring& value) const {
        if (value.size()>180 || value.find_first_of(L"\r\n\t")!=std::wstring::npos) return true;
        HDC dc=GetDC(list); auto old=SelectObject(dc,font); RECT bounds{};
        DrawTextW(dc,value.c_str(),static_cast<int>(value.size()),&bounds,DT_SINGLELINE|DT_CALCRECT|DT_NOPREFIX);
        SelectObject(dc,old); ReleaseDC(list,dc);
        RECT client{}, window{}; GetClientRect(list,&client); GetWindowRect(list,&window);
        int rowWidth=compact_list_width()-(window.right-window.left-client.right);
        return bounds.right-bounds.left>rowWidth-scale(20);
    }
    int selected() const { int i=static_cast<int>(SendMessageW(list,LB_GETCURSEL,0,0)); return i>=0 && i<static_cast<int>(items.size())?i:-1; }
    void refresh(int selection=0) {
        items=store.list(); SendMessageW(list,WM_SETREDRAW,FALSE,0); SendMessageW(list,LB_RESETCONTENT,0,0);
        for (const auto& item:items) {
            auto label=item.kind==0?t(IDS_TEXT)+L": "+item.preview:t(IDS_IMAGE)+L" "+std::to_wstring(item.width)+L" × "+std::to_wstring(item.height);
            SendMessageW(list,LB_ADDSTRING,0,reinterpret_cast<LPARAM>(label.c_str()));
        }
        if (!items.empty()) SendMessageW(list,LB_SETCURSEL,std::clamp(selection,0,static_cast<int>(items.size())-1),0);
        SendMessageW(list,WM_SETREDRAW,TRUE,0); InvalidateRect(list,nullptr,TRUE);
        EnableWindow(buttons[1],!items.empty()); EnableWindow(buttons[2],!items.empty()); update_preview();
    }
    void update_preview() {
        if (previewBitmap) { DeleteObject(previewBitmap); previewBitmap=nullptr; }
        int index=selected();
        Bytes data; std::wstring value;
        if (index>=0) {
            const auto& item=items[index]; data=store.payload(item.id);
            if (!item.kind) value=wide(std::string(data.begin(),data.end()));
            previewExpanded=item.kind || text_needs_preview(value);
        } else previewExpanded=false;
        fit_popup();
        SetWindowTextW(preview,L""); ShowWindow(preview,SW_HIDE);
        if (previewExpanded && !items[index].kind) {
            if (value.size()>4000) value=value.substr(0,4000)+L"…";
            SetWindowTextW(preview,value.c_str()); ShowWindow(preview,SW_SHOW);
        } else if (previewExpanded) {
            RECT rect{}; GetWindowRect(preview,&rect);
            previewBitmap=thumbnail(data,std::max<int>(1,rect.right-rect.left-4),std::max<int>(1,rect.bottom-rect.top-4));
            ShowWindow(preview,SW_HIDE);
        }
        InvalidateRect(popup,nullptr,TRUE);
    }
    void show() {
        if (IsWindowVisible(popup)) { ShowWindow(popup,SW_HIDE); return; }
        target=GetForegroundWindow();
        if (target==popup || target==host) target=nullptr;
        POINT point{}; GetCursorPos(&point);
        GUITHREADINFO info{sizeof(info)};
        if (target && GetGUIThreadInfo(GetWindowThreadProcessId(target,nullptr),&info) && info.hwndCaret) {
            POINT caret{info.rcCaret.right,info.rcCaret.bottom};
            if (ClientToScreen(info.hwndCaret,&caret)) point=caret;
        }
        point.x+=scale(12); point.y+=scale(8);
        popupAnchor=point; popupAnchorValid=true;
        refresh();
        SetWindowPos(popup,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
        SetForegroundWindow(popup); SetFocus(list);
    }
    void capture() {
        if (paused || testing) { KillTimer(host,capture_timer); captureAttempts=0; return; }
        DWORD sequence=GetClipboardSequenceNumber();
        if (sequence==lastSequence || GetClipboardOwner()==host) { lastSequence=sequence; KillTimer(host,capture_timer); captureAttempts=0; return; }
        if (!OpenClipboard(host)) { if (++captureAttempts<8) SetTimer(host,capture_timer,50,nullptr); else { KillTimer(host,capture_timer); captureAttempts=0; } return; }
        KillTimer(host,capture_timer); captureAttempts=0; lastSequence=sequence;
        Bytes data; HBITMAP bitmap=nullptr; bool isImage=false;
        try {
            bool excluded=IsClipboardFormatAvailable(excludeFormat)||IsClipboardFormatAvailable(CF_HDROP);
            if (!excluded && IsClipboardFormatAvailable(includeFormat)) {
                auto marker=clipboard_bytes(includeFormat); DWORD include=1;
                if (marker.size()>=sizeof(include)) { std::memcpy(&include,marker.data(),sizeof(include)); excluded=include==0; }
            }
            if (!excluded) {
                if (IsClipboardFormatAvailable(pngFormat)) { data=clipboard_bytes(pngFormat); isImage=true; }
                else if (IsClipboardFormatAvailable(imagePngFormat)) { data=clipboard_bytes(imagePngFormat); isImage=true; }
                else if (IsClipboardFormatAvailable(CF_BITMAP)) {
                    bitmap=static_cast<HBITMAP>(CopyImage(GetClipboardData(CF_BITMAP),IMAGE_BITMAP,0,0,LR_CREATEDIBSECTION)); isImage=true;
                } else if (IsClipboardFormatAvailable(CF_UNICODETEXT)) data=clipboard_bytes(CF_UNICODETEXT);
            }
            CloseClipboard();
        } catch (...) { CloseClipboard(); throw; }
        if (bitmap) {
            try { auto image=from_bitmap(bitmap); DeleteObject(bitmap); bitmap=nullptr; store.put(1,image.png,L"",image.width,image.height); }
            catch (...) { if (bitmap) DeleteObject(bitmap); throw; }
        } else if (!data.empty() && isImage) {
            auto image=from_png(data); store.put(1,image.png,L"",image.width,image.height);
        } else if (!data.empty()) {
            const auto* begin=reinterpret_cast<const wchar_t*>(data.data()); size_t count=data.size()/sizeof(wchar_t);
            const auto* end=std::find(begin,begin+count,L'\0'); std::wstring value(begin,end);
            auto encoded=utf8(value);
            if (!encoded.empty()) {
                auto label=value.substr(0,180); std::replace(label.begin(),label.end(),L'\r',L' '); std::replace(label.begin(),label.end(),L'\n',L' '); std::replace(label.begin(),label.end(),L'\t',L' ');
                store.put(0,Bytes(encoded.begin(),encoded.end()),label);
            }
        }
        if (IsWindowVisible(popup) && !settingsOpen) refresh();
    }
    void begin_paste() {
        int index=selected(); if (index<0 || pendingId) return;
        if (!target || !IsWindow(target)) { notify(IDS_NO_TARGET); return; }
        auto item=items[index]; auto data=store.payload(item.id); if (data.empty()) return;
        Bytes dib; std::wstring value;
        if (item.kind) dib=image_dib(data); else value=wide(std::string(data.begin(),data.end()));
        if (!OpenClipboard(host)) { notify(IDS_PASTE_ERROR); return; }
        bool success=EmptyClipboard()!=FALSE;
        if (success && item.kind) {
            success=set_clipboard_bytes(pngFormat,data.data(),data.size());
            success=set_clipboard_bytes(CF_DIBV5,dib.data(),dib.size())&&success;
        } else if (success) success=set_clipboard_bytes(CF_UNICODETEXT,value.c_str(),(value.size()+1)*sizeof(wchar_t));
        CloseClipboard(); lastSequence=GetClipboardSequenceNumber();
        if (!success) { notify(IDS_PASTE_ERROR); return; }
        pendingId=item.id; pasteAttempts=0; ShowWindow(popup,SW_HIDE);
        SetForegroundWindow(target); SetTimer(host,paste_timer,60,nullptr);
    }
    void finish_paste() {
        if (!pendingId) { KillTimer(host,paste_timer); return; }
        if (!IsWindow(target) || ++pasteAttempts>25) { pendingId=0; KillTimer(host,paste_timer); notify(IDS_PASTE_ERROR); return; }
        const int modifiersToWait[]={VK_CONTROL,VK_SHIFT,VK_MENU,VK_LWIN,VK_RWIN};
        for (int vk:modifiersToWait) if (GetAsyncKeyState(vk)&0x8000) return;
        if (GetForegroundWindow()!=target) { pendingId=0; KillTimer(host,paste_timer); notify(IDS_PASTE_ERROR); return; }
        INPUT input[4]{}; for (auto& i:input) i.type=INPUT_KEYBOARD;
        input[0].ki.wVk=VK_CONTROL; input[1].ki.wVk='V'; input[2].ki.wVk='V'; input[2].ki.dwFlags=KEYEVENTF_KEYUP;
        input[3].ki.wVk=VK_CONTROL; input[3].ki.dwFlags=KEYEVENTF_KEYUP;
        UINT sent=SendInput(4,input,sizeof(INPUT)); KillTimer(host,paste_timer);
        auto used=pendingId; pendingId=0;
        if (sent==4) store.use(used,promote); else {
            INPUT release{}; release.type=INPUT_KEYBOARD; release.ki.wVk=VK_CONTROL; release.ki.dwFlags=KEYEVENTF_KEYUP; SendInput(1,&release,sizeof(INPUT));
            notify(IDS_PASTE_ERROR);
        }
    }
    void remove_selected() { int index=selected(); if (index>=0) { store.erase(items[index].id); refresh(index); SetFocus(list); } }
    void clear_all() {
        if (MessageBoxW(popup,t(IDS_CLEAR_CONFIRM).c_str(),L"Chojema CopyKeep",MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2)==IDYES) { store.clear(); refresh(); }
    }
    void dialog_labels(HWND dialog) {
        SetWindowTextW(dialog,t(IDS_SETTINGS).c_str());
        const std::pair<int,UINT> labels[]={{IDC_LANGUAGE_LABEL,IDS_LANGUAGE},{IDC_PROMOTE,IDS_PROMOTE},{IDC_STARTUP,IDS_STARTUP},{IDC_LIMIT_LABEL,IDS_LIMIT},{IDC_HOTKEY_LABEL,IDS_HOTKEY},{IDOK,IDS_SAVE},{IDCANCEL,IDS_CANCEL}};
        for (auto [control,id]:labels) SetDlgItemTextW(dialog,control,t(id).c_str());
    }
    void settings() {
        oldDialogLanguage=english; settingsOpen=true;
        DialogBoxParamW(instance,MAKEINTRESOURCEW(IDD_SETTINGS),popup,dialog_proc,reinterpret_cast<LPARAM>(this));
        settingsOpen=false; labels(); refresh();
    }
    static INT_PTR CALLBACK dialog_proc(HWND dialog,UINT message,WPARAM w,LPARAM l) {
        auto* self=reinterpret_cast<App*>(GetWindowLongPtrW(dialog,DWLP_USER));
        if (message==WM_INITDIALOG) {
            self=reinterpret_cast<App*>(l); SetWindowLongPtrW(dialog,DWLP_USER,reinterpret_cast<LONG_PTR>(self));
            SendDlgItemMessageW(dialog,IDC_LANGUAGE,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"한국어"));
            SendDlgItemMessageW(dialog,IDC_LANGUAGE,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(L"English"));
            SendDlgItemMessageW(dialog,IDC_LANGUAGE,CB_SETCURSEL,self->english?1:0,0);
            CheckDlgButton(dialog,IDC_PROMOTE,self->promote?BST_CHECKED:BST_UNCHECKED);
            try { CheckDlgButton(dialog,IDC_STARTUP,startup_enabled()?BST_CHECKED:BST_UNCHECKED); } catch (...) {}
            SetDlgItemInt(dialog,IDC_LIMIT,integer(self->store.setting("limit","200"),200),FALSE);
            BYTE mods=0; if (self->modifiers&MOD_CONTROL) mods|=HOTKEYF_CONTROL; if (self->modifiers&MOD_SHIFT) mods|=HOTKEYF_SHIFT; if (self->modifiers&MOD_ALT) mods|=HOTKEYF_ALT;
            SendDlgItemMessageW(dialog,IDC_HOTKEY,HKM_SETHOTKEY,MAKEWORD(self->key,mods),0); self->dialog_labels(dialog); return TRUE;
        }
        if (!self) return FALSE;
        try {
            if (message==WM_COMMAND) {
                if (LOWORD(w)==IDC_LANGUAGE && HIWORD(w)==CBN_SELCHANGE) {
                    self->english=SendDlgItemMessageW(dialog,IDC_LANGUAGE,CB_GETCURSEL,0,0)==1;
                    self->dialog_labels(dialog); self->labels(); self->refresh(); return TRUE;
                }
                if (LOWORD(w)==IDCANCEL) { self->english=self->oldDialogLanguage; EndDialog(dialog,IDCANCEL); return TRUE; }
                if (LOWORD(w)==IDOK) {
                    BOOL valid=FALSE; UINT count=GetDlgItemInt(dialog,IDC_LIMIT,&valid,FALSE);
                    WORD hotkey=static_cast<WORD>(SendDlgItemMessageW(dialog,IDC_HOTKEY,HKM_GETHOTKEY,0,0)); UINT newKey=LOBYTE(hotkey), newMods=0;
                    BYTE flags=HIBYTE(hotkey); if (flags&HOTKEYF_CONTROL) newMods|=MOD_CONTROL; if (flags&HOTKEYF_SHIFT) newMods|=MOD_SHIFT; if (flags&HOTKEYF_ALT) newMods|=MOD_ALT;
                    if (!valid || count<10 || count>1000 || !newKey || !(newMods&(MOD_CONTROL|MOD_ALT))) { MessageBoxW(dialog,self->t(IDS_BAD_SETTINGS).c_str(),L"Chojema CopyKeep",MB_OK|MB_ICONINFORMATION); return TRUE; }
                    if (!self->testing && (newKey!=self->key || newMods!=self->modifiers)) {
                        UnregisterHotKey(self->host,1);
                        if (!RegisterHotKey(self->host,1,newMods|MOD_NOREPEAT,newKey)) {
                            RegisterHotKey(self->host,1,self->modifiers|MOD_NOREPEAT,self->key); MessageBoxW(dialog,self->t(IDS_HOTKEY_ERROR).c_str(),L"Chojema CopyKeep",MB_OK|MB_ICONINFORMATION); return TRUE;
                        }
                    }
                    self->key=newKey; self->modifiers=newMods;
                    bool startup=IsDlgButtonChecked(dialog,IDC_STARTUP)==BST_CHECKED;
                    if (!self->testing && !set_startup(startup)) { MessageBoxW(dialog,self->t(IDS_STARTUP_ERROR).c_str(),L"Chojema CopyKeep",MB_OK|MB_ICONERROR); return TRUE; }
                    self->promote=IsDlgButtonChecked(dialog,IDC_PROMOTE)==BST_CHECKED;
                    self->store.setting("language",std::string(self->english?"en":"ko")); self->store.setting("promote",std::string(self->promote?"1":"0"));
                    self->store.setting("limit",std::to_string(count)); self->store.setting("key",std::to_string(newKey)); self->store.setting("modifiers",std::to_string(newMods)); self->store.limit(count);
                    EndDialog(dialog,IDOK); return TRUE;
                }
            }
            if (message==WM_CLOSE) { self->english=self->oldDialogLanguage; EndDialog(dialog,IDCANCEL); return TRUE; }
        } catch (...) { MessageBoxW(dialog,self->t(IDS_ERROR).c_str(),L"Chojema CopyKeep",MB_OK|MB_ICONERROR); }
        return FALSE;
    }
    void menu() {
        HMENU menu=CreatePopupMenu();
        AppendMenuW(menu,MF_STRING,1,t(IDS_APP).c_str()); AppendMenuW(menu,MF_STRING,2,t(IDS_SETTINGS).c_str());
        AppendMenuW(menu,MF_STRING,3,t(paused?IDS_RESUME:IDS_PAUSE).c_str()); AppendMenuW(menu,MF_STRING,4,t(IDS_ABOUT).c_str()); AppendMenuW(menu,MF_SEPARATOR,0,nullptr); AppendMenuW(menu,MF_STRING,5,t(IDS_QUIT).c_str());
        POINT point{}; GetCursorPos(&point); SetForegroundWindow(host);
        UINT choice=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,point.x,point.y,0,host,nullptr); DestroyMenu(menu);
        if (choice==1) show(); else if (choice==2) settings(); else if (choice==3) paused=!paused;
        else if (choice==4) MessageBoxW(popup,t(IDS_AUTHOR).c_str(),L"Chojema CopyKeep",MB_OK);
        else if (choice==5) DestroyWindow(host);
    }
    void paint_content(HDC dc) {
        RECT rc{}; GetClientRect(popup,&rc);
        HBRUSH brush=CreateSolidBrush(RGB(250,251,253)); FillRect(dc,&rc,brush); DeleteObject(brush);
        SetBkMode(dc,TRANSPARENT); SetTextColor(dc,ink); SelectObject(dc,titleFont);
        RECT title{scale(16),scale(12),rc.right-scale(16),scale(38)}; DrawTextW(dc,L"Chojema CopyKeep",-1,&title,DT_LEFT|DT_SINGLELINE);
        SelectObject(dc,smallFont); SetTextColor(dc,muted);
        RECT subtitle{scale(16),scale(42),rc.right-scale(16),scale(63)}; auto sub=t(IDS_SUBTITLE); DrawTextW(dc,sub.c_str(),-1,&subtitle,DT_SINGLELINE|DT_END_ELLIPSIS);
        RECT help{scale(16),rc.bottom-scale(64),rc.right-scale(16),rc.bottom-scale(44)}; auto hint=t(IDS_HELP); DrawTextW(dc,hint.c_str(),-1,&help,DT_SINGLELINE|DT_END_ELLIPSIS);
        if (previewBitmap) {
            RECT imageRect{}; GetWindowRect(preview,&imageRect); MapWindowPoints(nullptr,popup,reinterpret_cast<POINT*>(&imageRect),2);
            HDC source=CreateCompatibleDC(dc); auto old=SelectObject(source,previewBitmap); BITMAP info{}; GetObjectW(previewBitmap,sizeof(info),&info);
            BitBlt(dc,imageRect.left+2,imageRect.top+2,info.bmWidth,info.bmHeight,source,0,0,SRCCOPY); SelectObject(source,old); DeleteDC(source);
        }
    }
    void paint() { PAINTSTRUCT ps{}; HDC dc=BeginPaint(popup,&ps); paint_content(dc); EndPaint(popup,&ps); }
    void draw_item(DRAWITEMSTRUCT* draw) {
        if (draw->itemID==static_cast<UINT>(-1) || draw->itemID>=items.size()) return;
        const auto& item=items[draw->itemID]; bool chosen=(draw->itemState&ODS_SELECTED)!=0;
        HBRUSH brush=CreateSolidBrush(chosen?RGB(226,237,254):RGB(255,255,255)); FillRect(draw->hDC,&draw->rcItem,brush); DeleteObject(brush);
        SetBkMode(draw->hDC,TRANSPARENT); SetTextColor(draw->hDC,chosen?accent:muted); SelectObject(draw->hDC,smallFont);
        RECT top=draw->rcItem; top.left+=scale(10); top.top+=scale(6); top.bottom=top.top+scale(18);
        auto kind=item.kind?t(IDS_IMAGE)+L"  "+std::to_wstring(item.width)+L" × "+std::to_wstring(item.height):t(IDS_TEXT);
        DrawTextW(draw->hDC,kind.c_str(),-1,&top,DT_SINGLELINE|DT_END_ELLIPSIS);
        RECT label=draw->rcItem; label.left+=scale(10); label.right-=scale(10); label.top+=scale(28); label.bottom-=scale(5);
        SelectObject(draw->hDC,font); SetTextColor(draw->hDC,ink);
        auto summary=item.kind?t(IDS_PASTE_HINT):item.preview; DrawTextW(draw->hDC,summary.c_str(),-1,&label,DT_SINGLELINE|DT_END_ELLIPSIS|DT_NOPREFIX);
    }
    static LRESULT CALLBACK host_proc(HWND window,UINT message,WPARAM w,LPARAM l) {
        auto* self=reinterpret_cast<App*>(GetWindowLongPtrW(window,GWLP_USERDATA));
        if (message==WM_NCCREATE) { self=static_cast<App*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams); SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self)); }
        if (!self) return DefWindowProcW(window,message,w,l);
        try {
            if (message==WM_CLIPBOARDUPDATE) { self->capture(); return 0; }
            if (message==WM_HOTKEY) { self->show(); return 0; }
            if (message==WM_TIMER && w==capture_timer) { self->capture(); return 0; }
            if (message==WM_TIMER && w==paste_timer) { self->finish_paste(); return 0; }
            if (message==tray_message) {
                if (l==WM_LBUTTONUP) self->show(); else if (l==WM_RBUTTONUP || l==WM_CONTEXTMENU) self->menu(); return 0;
            }
            if (message==self->taskbarCreated && !self->testing) { self->tray(true); return 0; }
            if (message==WM_DESTROY) { if (!self->testing) { self->tray(false); RemoveClipboardFormatListener(window); UnregisterHotKey(window,1); } if (self->popup) DestroyWindow(self->popup); PostQuitMessage(0); return 0; }
        } catch (...) { self->notify(message==WM_CLIPBOARDUPDATE?IDS_CAPTURE_ERROR:IDS_ERROR); }
        return DefWindowProcW(window,message,w,l);
    }
    static LRESULT CALLBACK popup_proc(HWND window,UINT message,WPARAM w,LPARAM l) {
        auto* self=reinterpret_cast<App*>(GetWindowLongPtrW(window,GWLP_USERDATA));
        if (message==WM_NCCREATE) { self=static_cast<App*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams); SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self)); self->popup=window; }
        if (!self) return DefWindowProcW(window,message,w,l);
        try {
            if (message==WM_CREATE) { self->create_controls(); return 0; }
            if (message==WM_SIZE) { self->layout(); return 0; }
            if (message==WM_PAINT) { self->paint(); return 0; }
            if (message==WM_PRINTCLIENT) { self->paint_content(reinterpret_cast<HDC>(w)); return 0; }
            if (message==WM_ERASEBKGND) return 1;
            if (message==WM_DRAWITEM) { self->draw_item(reinterpret_cast<DRAWITEMSTRUCT*>(l)); return TRUE; }
            if (message==WM_MEASUREITEM) { reinterpret_cast<MEASUREITEMSTRUCT*>(l)->itemHeight=self->scale(57); return TRUE; }
            if (message==WM_CLOSE) { ShowWindow(window,SW_HIDE); return 0; }
            if (message==WM_ACTIVATE && LOWORD(w)==WA_INACTIVE && !self->settingsOpen && !self->testing) { ShowWindow(window,SW_HIDE); return 0; }
            if (message==WM_DPICHANGED) { auto r=reinterpret_cast<RECT*>(l); SetWindowPos(window,nullptr,r->left,r->top,r->right-r->left,r->bottom-r->top,SWP_NOZORDER|SWP_NOACTIVATE); self->fonts(); self->layout(); self->update_preview(); return 0; }
            if (message==paste_message) { self->begin_paste(); return 0; }
            if (message==WM_COMMAND) {
                switch (LOWORD(w)) {
                    case list_id: if (HIWORD(w)==LBN_SELCHANGE) self->update_preview(); break;
                    case settings_id: self->settings(); break;
                    case delete_id: self->remove_selected(); break;
                    case clear_id: self->clear_all(); break;
                    case close_id: ShowWindow(window,SW_HIDE); break;
                } return 0;
            }
        } catch (...) { self->notify(IDS_ERROR); }
        return DefWindowProcW(window,message,w,l);
    }
    static LRESULT CALLBACK list_proc(HWND window,UINT message,WPARAM w,LPARAM l,UINT_PTR,DWORD_PTR ref) {
        auto* self=reinterpret_cast<App*>(ref);
        if ((message==WM_PAINT || message==WM_PRINTCLIENT) && self->items.empty()) {
            LRESULT result=DefSubclassProc(window,message,w,l);
            HDC dc=message==WM_PAINT?GetDC(window):reinterpret_cast<HDC>(w);
            int saved=SaveDC(dc); RECT bounds{}; GetClientRect(window,&bounds); InflateRect(&bounds,-self->scale(12),-self->scale(12));
            SelectObject(dc,self->font); SetTextColor(dc,muted); SetBkMode(dc,TRANSPARENT);
            auto hint=self->t(IDS_EMPTY); DrawTextW(dc,hint.c_str(),-1,&bounds,DT_WORDBREAK|DT_NOPREFIX);
            RestoreDC(dc,saved); if (message==WM_PAINT) ReleaseDC(window,dc); return result;
        }
        if (message==WM_KEYDOWN) {
            if (w==VK_RETURN) { PostMessageW(self->popup,paste_message,0,0); return 0; }
            if (w==VK_ESCAPE) { ShowWindow(self->popup,SW_HIDE); return 0; }
            if (w==VK_DELETE) { try { self->remove_selected(); } catch (...) { self->notify(IDS_ERROR); } return 0; }
        }
        if (message==WM_LBUTTONUP) {
            LRESULT result=DefSubclassProc(window,message,w,l); DWORD hit=static_cast<DWORD>(SendMessageW(window,LB_ITEMFROMPOINT,0,l));
            if (!HIWORD(hit) && LOWORD(hit)<self->items.size()) PostMessageW(self->popup,paste_message,0,0); return result;
        }
        return DefSubclassProc(window,message,w,l);
    }
};
void require(bool value,const char* message) { if (!value) throw std::runtime_error(message); }
int self_test(const std::filesystem::path& root) {
    auto folder=root/(L"case-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64()));
    int checks=0;
    auto check=[&](bool ok,const char* message){require(ok,message); ++checks;};
    auto a=utf8(L"한글 text\r\n두 번째 줄"); Bytes bytes(a.begin(),a.end());
    long long first=0,second=0;
    {
        Store store(folder); first=store.put(0,bytes,L"한글 text");
        std::string b="second"; second=store.put(0,Bytes(b.begin(),b.end()),L"second");
        check(store.list().front().id==second,"Copy ordering");
        store.use(first,false); check(store.list().front().id==second,"Disabled promotion");
        store.use(first,true); check(store.list().front().id==first,"Enabled promotion");
        check(store.put(0,bytes,L"same")==first && store.list().size()==2,"Duplicate merging");
        check(store.payload(first)==bytes,"Unicode payload round trip");
        store.setting("language",std::string("en")); check(store.setting("language","ko")=="en","Language setting");
        auto image=test_image(); auto decoded=from_png(image.png); check(decoded.width==320 && decoded.height==180,"PNG dimensions");
        auto dib=image_dib(image.png); auto header=reinterpret_cast<const BITMAPV5HEADER*>(dib.data());
        check(header->bV5Width==320 && header->bV5Height==-180 && dib.size()==sizeof(BITMAPV5HEADER)+320*180*4,"Image paste format");
        auto imageId=store.put(1,image.png,L"",image.width,image.height); check(store.payload(imageId)==image.png,"Image persistence");
        HBITMAP preview=thumbnail(image.png,120,80); check(preview!=nullptr,"Image preview"); if (preview) DeleteObject(preview);
        for (UINT id=IDS_APP;id<=IDS_NO_TARGET;++id) { check(!text(id,false).empty(),"Missing Korean resource"); check(!text(id,true).empty(),"Missing English resource"); }
    }
    {
        Store store(folder); check(store.setting("language","ko")=="en" && store.list().size()==3,"Restart persistence");
        check(store.payload(first)==bytes,"Restart payload");
        store.erase(second); check(store.list().size()==2,"Delete selected");
        for (int i=0;i<15;++i) { auto s=std::to_string(i); store.put(0,Bytes(s.begin(),s.end()),wide(s)); }
        store.limit(10); check(store.list().size()==10,"History limit");
        store.clear(); check(store.list().empty(),"Clear history");
        check(store.setting("language","ko")=="en","Clear preserves settings");
    }
    std::filesystem::remove(folder/L"history.db"); std::filesystem::remove(folder/L"history.db-journal"); std::filesystem::remove(folder);
    std::cout<<"PASS: "<<checks<<" storage, localization, and image checks\n"; return 0;
}
int smoke_test(const std::filesystem::path& output,bool english,const std::wstring& scenario) {
    std::filesystem::create_directories(output.parent_path());
    auto folder=output.parent_path()/(L"ui-"+std::to_wstring(GetCurrentProcessId()));
    App app(folder,true); app.english=english;
    app.store.clear();
    auto image=test_image(); app.store.put(1,image.png,L"",image.width,image.height);
    auto add=[&](const std::wstring& value) {
        auto encoded=utf8(value); auto summary=value.substr(0,180);
        std::replace(summary.begin(),summary.end(),L'\r',L' '); std::replace(summary.begin(),summary.end(),L'\n',L' '); std::replace(summary.begin(),summary.end(),L'\t',L' ');
        return app.store.put(0,Bytes(encoded.begin(),encoded.end()),summary);
    };
    auto multilineId=add(english?L"First line\r\nSecond line":L"첫 번째 줄\r\n두 번째 줄");
    auto longId=add(english?L"This is a longer copied passage that does not fit in a single list row. Selecting it automatically shows the preview without another action.":L"목록의 한 줄에 모두 표시할 수 없는 긴 복사 내용입니다. 항목을 선택하면 별도 조작 없이 미리보기가 자동으로 나타나고, 짧은 항목을 선택하면 목록만 표시됩니다.");
    auto shortId=add(english?L"Short copied text":L"짧은 복사 내용");
    auto originalLongPayload=app.store.payload(longId);
    app.initialize(); app.show(); UpdateWindow(app.popup);
    MSG message{}; while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
    wchar_t label[80]{}; GetWindowTextW(app.buttons[0],label,80);
    require(label==app.t(IDS_SETTINGS),"Localized window label");
    int checks=0; auto check=[&](bool ok,const char* why){require(ok,why); ++checks;};
    auto bounds=[](HWND window){RECT rect{}; GetWindowRect(window,&rect); return rect;};
    auto select=[&](int index) {
        SendMessageW(app.list,LB_SETCURSEL,index,0);
        SendMessageW(app.popup,WM_COMMAND,MAKEWPARAM(list_id,LBN_SELCHANGE),reinterpret_cast<LPARAM>(app.list));
    };
    check(app.selected()==0 && app.items.size()==4 && app.items[0].id==shortId,"Popup default selection");
    check(!app.previewExpanded && !IsWindowVisible(app.preview) && !app.previewBitmap,"Short text uses list only");
    auto compact=bounds(app.popup), compactList=bounds(app.list);
    check(!app.text_needs_preview(L"WW") && app.text_needs_preview(std::wstring(80,L'W')),"Preview follows rendered width");
    check(!app.text_needs_preview(std::wstring(80,L'i')),"Narrow text fits without preview");
    check(app.text_needs_preview(L"one\ntwo") && app.text_needs_preview(L"one\ttwo"),"Formatted text needs preview");
    check(app.text_needs_preview(std::wstring(181,L'i')),"Truncated stored summary needs preview");
    SendMessageW(app.list,WM_KEYDOWN,VK_DOWN,0);
    check(app.selected()==1 && app.items[1].id==longId && app.previewExpanded && IsWindowVisible(app.preview),"Arrow selection automatically expands long text");
    auto expanded=bounds(app.popup), expandedList=bounds(app.list);
    check(expanded.right-expanded.left>compact.right-compact.left,"Preview expands popup width");
    check(expandedList.right-expandedList.left==compactList.right-compactList.left,"List width stays stable");
    check(GetFocus()==app.list,"Automatic preview preserves keyboard focus");
    SendMessageW(app.list,WM_KEYDOWN,VK_RETURN,0);
    MSG paste{}; check(PeekMessageW(&paste,app.popup,paste_message,paste_message,PM_REMOVE)!=FALSE && app.selected()==1,"Enter keeps selected paste action");
    SendMessageW(app.list,WM_KEYDOWN,VK_UP,0);
    check(app.selected()==0 && !app.previewExpanded && !IsWindowVisible(app.preview),"Arrow selection collapses short text");
    check(bounds(app.popup).right-bounds(app.popup).left==compact.right-compact.left,"Compact width restored");
    select(2); check(app.items[app.selected()].id==multilineId && app.previewExpanded && IsWindowVisible(app.preview),"Short multiline text expands automatically");
    select(3); check(app.previewExpanded && app.previewBitmap && !IsWindowVisible(app.preview),"Image selection automatically shows thumbnail");
    select(0); check(!app.previewExpanded && !app.previewBitmap,"Short text releases image preview");
    RECT row{}; SendMessageW(app.list,LB_GETITEMRECT,1,reinterpret_cast<LPARAM>(&row));
    LPARAM click=MAKELPARAM(app.scale(20),(row.top+row.bottom)/2);
    SendMessageW(app.list,WM_LBUTTONDOWN,MK_LBUTTON,click);
    SendMessageW(app.list,WM_LBUTTONUP,0,click);
    check(app.selected()==1 && app.previewExpanded,"Mouse selection automatically shows preview");
    check(PeekMessageW(&paste,app.popup,paste_message,paste_message,PM_REMOVE)!=FALSE,"Mouse paste action preserved");
    MONITORINFO monitor{sizeof(monitor)}; GetMonitorInfoW(MonitorFromWindow(app.popup,MONITOR_DEFAULTTONEAREST),&monitor);
    auto originalAnchor=app.popupAnchor;
    app.popupAnchor={monitor.rcWork.right-1,monitor.rcWork.bottom-1};
    select(0); auto edgeCompact=bounds(app.popup);
    select(3); auto edgeExpanded=bounds(app.popup);
    check(edgeCompact.right<=monitor.rcWork.right && edgeExpanded.right<=monitor.rcWork.right && edgeExpanded.bottom<=monitor.rcWork.bottom && edgeExpanded.left>=monitor.rcWork.left,"Expansion stays inside work area");
    select(0); auto edgeAgain=bounds(app.popup);
    check(EqualRect(&edgeCompact,&edgeAgain)!=FALSE,"Repeated expansion does not drift");
    app.popupAnchor=originalAnchor;
    check(app.store.list().front().id==shortId && app.store.payload(longId)==originalLongPayload,"Preview does not modify history order or payload");
    if (scenario==L"empty") { app.store.clear(); app.refresh(); check(!app.previewExpanded && !IsWindowVisible(app.preview) && !app.previewBitmap && !IsWindowEnabled(app.buttons[1]),"Empty history stays compact"); }
    else if (scenario==L"short") select(0);
    else if (scenario==L"long") select(1);
    else if (scenario==L"multiline") select(2);
    else { require(scenario==L"image","Unknown preview scenario"); select(3); }
    UpdateWindow(app.popup);
    RECT rc{}; GetClientRect(app.popup,&rc); HDC screen=GetDC(nullptr), dc=CreateCompatibleDC(screen);
    HBITMAP bitmap=CreateCompatibleBitmap(screen,rc.right,rc.bottom); auto old=SelectObject(dc,bitmap);
    app.paint_content(dc);
    EnumChildWindows(app.popup,[](HWND child,LPARAM context)->BOOL {
        if (!IsWindowVisible(child)) return TRUE;
        HDC canvas=reinterpret_cast<HDC>(context); RECT bounds{}; GetWindowRect(child,&bounds);
        MapWindowPoints(nullptr,GetParent(child),reinterpret_cast<POINT*>(&bounds),2);
        int savedDC=SaveDC(canvas); SetViewportOrgEx(canvas,bounds.left,bounds.top,nullptr);
        IntersectClipRect(canvas,0,0,bounds.right-bounds.left,bounds.bottom-bounds.top);
        SendMessageW(child,WM_PRINT,reinterpret_cast<WPARAM>(canvas),PRF_CLIENT|PRF_ERASEBKGND|PRF_CHILDREN);
        RestoreDC(canvas,savedDC); return TRUE;
    },reinterpret_cast<LPARAM>(dc));
    SelectObject(dc,old);
    bool saved=save_bitmap(bitmap,output); DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(nullptr,screen);
    DestroyWindow(app.host); require(saved,"UI capture failed");
    std::cout<<"PASS: "<<checks<<" popup selection, preview, focus, and work-area checks\n"; return 0;
}
}
int WINAPI wWinMain(HINSTANCE module,HINSTANCE,PWSTR,int) {
    instance=module;
    SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32|LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
    OleInitialize(nullptr);
    Gdiplus::GdiplusStartupInput startup; ULONG_PTR token=0;
    if (Gdiplus::GdiplusStartup(&token,&startup,nullptr)!=Gdiplus::Ok) { OleUninitialize(); return 1; }
    int argc=0; LPWSTR* argv=CommandLineToArgvW(GetCommandLineW(),&argc); int result=0;
    bool commandMode=argc>1 && (std::wstring(argv[1])==L"--self-test" || std::wstring(argv[1])==L"--smoke-test");
    try {
        if (argc>=3 && std::wstring(argv[1])==L"--self-test") result=self_test(argv[2]);
        else if (argc>=4 && std::wstring(argv[1])==L"--smoke-test") result=smoke_test(argv[3],std::wstring(argv[2])==L"en",argc>=5?argv[4]:L"image");
        else {
            HANDLE mutex=CreateMutexW(nullptr,FALSE,L"Local\\ChojemaCopyKeep.SingleInstance");
            if (!mutex) throw std::runtime_error("Single-instance guard failed");
            if (GetLastError()!=ERROR_ALREADY_EXISTS) {
                auto folder=folder_id(FOLDERID_LocalAppData)/L"ChojemaCopyKeep";
                for (int i=1;i+1<argc;++i) if (std::wstring(argv[i])==L"--data-dir") folder=argv[++i];
                { App app(folder); app.initialize(); MSG message{};
                  while (GetMessageW(&message,nullptr,0,0)>0) { if (message.message==WM_KEYDOWN && message.wParam==VK_ESCAPE && GetAncestor(message.hwnd,GA_ROOT)==app.popup) ShowWindow(app.popup,SW_HIDE); else if (!(message.message==WM_KEYDOWN && message.wParam==VK_TAB && IsDialogMessageW(app.popup,&message))) { TranslateMessage(&message); DispatchMessageW(&message); } } }
            }
            CloseHandle(mutex);
        }
    } catch (const std::exception& e) {
        result=1;
        if (commandMode) std::cerr<<"FAIL: "<<e.what()<<"\n";
        else MessageBoxW(nullptr,text(IDS_DATABASE_ERROR,false).c_str(),L"Chojema CopyKeep",MB_OK|MB_ICONERROR);
    }
    if (argv) LocalFree(argv); Gdiplus::GdiplusShutdown(token); OleUninitialize(); return result;
}
