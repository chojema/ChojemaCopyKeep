#pragma once
#include "replacement.h"
#include <windows.h>
#include <UIAutomation.h>
#include <wrl/client.h>
#include <imm.h>

namespace copykeep {
class TextReplacement {
    inline static TextReplacement* active_=nullptr;
    HHOOK keyboard_=nullptr, mouse_=nullptr;
    HWINEVENTHOOK focus_=nullptr;
    HWND host_=nullptr, target_=nullptr;
    UINT message_=0, candidateKey_=0;
    ULONG_PTR generation_=0;
    int candidate_=-1;
    bool waitingShift_=false;
    ReplacementRule pending_;
    Microsoft::WRL::ComPtr<IUIAutomation> automation_;
    void reset() { matcher.reset(); candidate_=-1; waitingShift_=false; ++generation_; }
    static void CALLBACK focus_event(HWINEVENTHOOK,DWORD,HWND,LONG,LONG,DWORD,DWORD) { if (active_) active_->reset(); }
    static LRESULT CALLBACK mouse_event(int code,WPARAM w,LPARAM l) {
        if (code>=0 && active_ && (w==WM_LBUTTONDOWN || w==WM_RBUTTONDOWN || w==WM_MBUTTONDOWN || w==WM_MOUSEWHEEL)) active_->reset();
        return CallNextHookEx(nullptr,code,w,l);
    }
    static LRESULT CALLBACK key_event(int code,WPARAM w,LPARAM l) {
        if (code<0 || !active_) return CallNextHookEx(nullptr,code,w,l);
        auto& self=*active_; auto& key=*reinterpret_cast<KBDLLHOOKSTRUCT*>(l);
        if (key.flags&LLKHF_INJECTED) return CallNextHookEx(nullptr,code,w,l);
        auto target=GetForegroundWindow(); DWORD process=0, thread=GetWindowThreadProcessId(target,&process);
        if (process==GetCurrentProcessId() || !target) { self.reset(); return CallNextHookEx(nullptr,code,w,l); }
        if (target!=self.target_) { self.reset(); self.target_=target; }
        if (key.vkCode==VK_SHIFT || key.vkCode==VK_LSHIFT || key.vkCode==VK_RSHIFT) {
            if (w==WM_KEYUP && self.waitingShift_) { self.waitingShift_=false; PostMessageW(self.host_,self.message_,self.generation_,0); }
            return CallNextHookEx(nullptr,code,w,l);
        }
        if (GetAsyncKeyState(VK_CONTROL)&0x8000 || GetAsyncKeyState(VK_MENU)&0x8000 ||
            GetAsyncKeyState(VK_LWIN)&0x8000 || GetAsyncKeyState(VK_RWIN)&0x8000) { self.reset(); return CallNextHookEx(nullptr,code,w,l); }
        if (w==WM_KEYUP && self.candidate_>=0 && key.vkCode==self.candidateKey_) {
            self.pending_=self.matcher.rules[self.candidate_]; self.candidate_=-1; self.matcher.reset();
            self.waitingShift_=(GetAsyncKeyState(VK_SHIFT)&0x8000)!=0;
            if (!self.waitingShift_) PostMessageW(self.host_,self.message_,self.generation_,0);
        } else if (w==WM_KEYDOWN) {
            self.waitingShift_=false; ++self.generation_;
            GUITHREADINFO info{sizeof(info)};
            if (!GetGUIThreadInfo(thread,&info)) { self.reset(); return CallNextHookEx(nullptr,code,w,l); }
            HIMC context=ImmGetContext(info.hwndFocus); DWORD conversion=0, sentence=0;
            bool composing=context && ImmGetConversionStatus(context,&conversion,&sentence) && (conversion&IME_CMODE_NATIVE);
            if (context) ImmReleaseContext(info.hwndFocus,context);
            if (composing) { self.reset(); return CallNextHookEx(nullptr,code,w,l); }
            BYTE state[256]{}; GetKeyboardState(state);
            state[VK_SHIFT]=static_cast<BYTE>((GetAsyncKeyState(VK_SHIFT)&0x8000)?0x80:0);
            wchar_t value[4]{};
            int count=ToUnicodeEx(key.vkCode,key.scanCode,state,value,4,4,GetKeyboardLayout(thread));
            self.candidate_=count==1?self.matcher.append(value[0]):-1;
            if (count!=1) self.matcher.reset();
            self.candidateKey_=key.vkCode;
        }
        return CallNextHookEx(nullptr,code,w,l);
    }
public:
    ReplacementMatcher matcher;
    bool start(HWND host,UINT message) {
        stop(); host_=host; message_=message;
        if (matcher.rules.empty()) return true;
        if (FAILED(CoCreateInstance(CLSID_CUIAutomation,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&automation_)))) return false;
        active_=this;
        keyboard_=SetWindowsHookExW(WH_KEYBOARD_LL,key_event,GetModuleHandleW(nullptr),0);
        mouse_=SetWindowsHookExW(WH_MOUSE_LL,mouse_event,GetModuleHandleW(nullptr),0);
        focus_=SetWinEventHook(EVENT_OBJECT_FOCUS,EVENT_OBJECT_FOCUS,nullptr,focus_event,0,0,WINEVENT_OUTOFCONTEXT);
        if (!keyboard_ || !mouse_ || !focus_) { stop(); return false; }
        return true;
    }
    void stop() {
        if (keyboard_) UnhookWindowsHookEx(keyboard_);
        if (mouse_) UnhookWindowsHookEx(mouse_);
        if (focus_) UnhookWinEvent(focus_);
        keyboard_=nullptr; mouse_=nullptr; focus_=nullptr;
        if (active_==this) active_=nullptr;
        automation_.Reset(); reset();
    }
    static bool select_edit(HWND edit,const std::wstring& abbreviation) {
        constexpr UINT timeout=100;
        DWORD_PTR length=0,selection=0,copied=0;
        if (GetWindowLongPtrW(edit,GWL_STYLE)&ES_PASSWORD ||
            !SendMessageTimeoutW(edit,WM_GETTEXTLENGTH,0,0,SMTO_ABORTIFHUNG,timeout,&length) || length>65535 ||
            !SendMessageTimeoutW(edit,EM_GETSEL,0,0,SMTO_ABORTIFHUNG,timeout,&selection)) return false;
        size_t start=LOWORD(selection),end=HIWORD(selection);
        if (start!=end || start<abbreviation.size() || end>length) return false;
        std::wstring value(static_cast<size_t>(length)+1,L'\0');
        if (!SendMessageTimeoutW(edit,WM_GETTEXT,value.size(),reinterpret_cast<LPARAM>(value.data()),SMTO_ABORTIFHUNG,timeout,&copied) ||
            copied!=length || value.compare(start-abbreviation.size(),abbreviation.size(),abbreviation)!=0) return false;
        GUITHREADINFO info{sizeof(info)};
        if (!GetGUIThreadInfo(GetWindowThreadProcessId(GetForegroundWindow(),nullptr),&info) || info.hwndFocus!=edit) return false;
        DWORD_PTR current=0,result=0;
        if (!SendMessageTimeoutW(edit,EM_GETSEL,0,0,SMTO_ABORTIFHUNG,timeout,&current) || current!=selection ||
            !SendMessageTimeoutW(edit,EM_SETSEL,start-abbreviation.size(),end,SMTO_ABORTIFHUNG,timeout,&result)) return false;
        return SendMessageTimeoutW(edit,EM_GETSEL,0,0,SMTO_ABORTIFHUNG,timeout,&current) &&
            LOWORD(current)==start-abbreviation.size() && HIWORD(current)==end;
    }
    static bool select_abbreviation(IUIAutomation* automation,const std::wstring& abbreviation) {
        using Microsoft::WRL::ComPtr;
        ComPtr<IUIAutomationElement> element;
        if (!automation || FAILED(automation->GetFocusedElement(&element)) || !element) return false;
        BOOL password=TRUE;
        if (FAILED(element->get_CurrentIsPassword(&password)) || password) return false;
        UIA_HWND handle=nullptr; wchar_t className[32]{};
        if (SUCCEEDED(element->get_CurrentNativeWindowHandle(&handle)) && handle &&
            GetClassNameW(handle,className,32) && _wcsicmp(className,L"Edit")==0) return select_edit(handle,abbreviation);
        ComPtr<IUIAutomationTextPattern> pattern;
        if (FAILED(element->GetCurrentPatternAs(UIA_TextPatternId,IID_PPV_ARGS(&pattern))) || !pattern) return false;
        ComPtr<IUIAutomationTextRangeArray> ranges; int count=0;
        if (FAILED(pattern->GetSelection(&ranges)) || !ranges || FAILED(ranges->get_Length(&count)) || count!=1) return false;
        ComPtr<IUIAutomationTextRange> range; int comparison=1, moved=0;
        if (FAILED(ranges->GetElement(0,&range)) || !range ||
            FAILED(range->CompareEndpoints(TextPatternRangeEndpoint_Start,range.Get(),TextPatternRangeEndpoint_End,&comparison)) || comparison!=0 ||
            FAILED(range->MoveEndpointByUnit(TextPatternRangeEndpoint_Start,TextUnit_Character,-static_cast<int>(abbreviation.size()),&moved)) ||
            moved!=-static_cast<int>(abbreviation.size())) return false;
        BSTR value=nullptr;
        HRESULT result=range->GetText(static_cast<int>(abbreviation.size()+1),&value);
        bool matches=SUCCEEDED(result) && value && std::wstring(value,SysStringLen(value))==abbreviation;
        SysFreeString(value);
        ComPtr<IUIAutomationElement> current; BOOL same=FALSE;
        return matches && SUCCEEDED(automation->GetFocusedElement(&current)) && current &&
            SUCCEEDED(automation->CompareElements(element.Get(),current.Get(),&same)) && same && SUCCEEDED(range->Select());
    }
    const ReplacementRule* prepare(ULONG_PTR generation) {
        if (generation!=generation_ || target_!=GetForegroundWindow()) return nullptr;
        for (int key:{VK_CONTROL,VK_SHIFT,VK_MENU,VK_LWIN,VK_RWIN}) if (GetAsyncKeyState(key)&0x8000) return nullptr;
        if (!select_abbreviation(automation_.Get(),pending_.abbreviation) || generation!=generation_ || target_!=GetForegroundWindow()) return nullptr;
        return &pending_;
    }
    ~TextReplacement() { stop(); }
};
}
