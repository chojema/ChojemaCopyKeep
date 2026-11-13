#include "replacement_windows.h"
#include <future>
#include <iostream>
#include <stdexcept>

int main() {
    using namespace copykeep;
    HWND window=CreateWindowExW(0,L"STATIC",L"CopyKeep replacement test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,60,60,500,220,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
    HWND edit=CreateWindowExW(WS_EX_CLIENTEDGE,L"EDIT",L"Keep ;;addr",WS_CHILD|WS_VISIBLE|WS_TABSTOP|ES_MULTILINE,20,20,420,120,window,nullptr,GetModuleHandleW(nullptr),nullptr);
    if (!window || !edit) return 1;
    SetForegroundWindow(window); SetFocus(edit); SendMessageW(edit,EM_SETSEL,11,11);
    auto test=std::async(std::launch::async,[=] {
        CoInitializeEx(nullptr,COINIT_MULTITHREADED);
        int checks=0;
        auto check=[&](bool ok) { if (!ok) throw std::runtime_error("Text replacement selection check "+std::to_string(checks+1)+" failed"); ++checks; };
        {
            Microsoft::WRL::ComPtr<IUIAutomation> automation;
            check(SUCCEEDED(CoCreateInstance(CLSID_CUIAutomation,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation))));
            Microsoft::WRL::ComPtr<IUIAutomationElement> expected;
            check(SUCCEEDED(automation->ElementFromHandle(edit,&expected)) && expected);
            check(SUCCEEDED(expected->SetFocus()));
            check(!TextReplacement::select_abbreviation(automation.Get(),L";;wrong"));
            SendMessageW(edit,EM_SETSEL,0,4);
            check(!TextReplacement::select_abbreviation(automation.Get(),L";;addr"));
            SendMessageW(edit,EM_SETSEL,11,11);
            check(TextReplacement::select_abbreviation(automation.Get(),L";;addr"));
            DWORD start=0,end=0; SendMessageW(edit,EM_GETSEL,reinterpret_cast<WPARAM>(&start),reinterpret_cast<LPARAM>(&end));
            check(start==5 && end==11);
            SendMessageW(edit,EM_REPLACESEL,TRUE,reinterpret_cast<LPARAM>(L"서울\r\nSeoul 😀"));
            wchar_t value[128]{}; GetWindowTextW(edit,value,128);
            check(std::wstring(value)==L"Keep 서울\r\nSeoul 😀");
        }
        CoUninitialize(); return checks;
    });
    MSG message{};
    while (test.wait_for(std::chrono::milliseconds(0))!=std::future_status::ready) {
        while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
        MsgWaitForMultipleObjects(0,nullptr,FALSE,10,QS_ALLINPUT);
    }
    int result=0;
    try { int checks=test.get(); std::cout<<"PASS: "<<checks<<" native selection checks\n"; } catch (const std::exception& error) { std::cerr<<error.what()<<"\n"; result=1; }
    DestroyWindow(window); return result;
}
