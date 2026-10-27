#pragma once
#include <windows.h>
#include <gdiplus.h>
#include <algorithm>
#include <cmath>

namespace copykeep::ui {
struct Palette {
    COLORREF background=RGB(244,247,247), surface=RGB(252,253,253);
    COLORREF ink=RGB(32,49,57), muted=RGB(99,117,124), accent=RGB(23,107,99);
    COLORREF selected=RGB(229,242,239), line=RGB(223,231,231), hover=RGB(237,243,242);
    COLORREF accentHover=RGB(19,88,82), accentPressed=RGB(16,74,70);
    COLORREF disabled=RGB(126,141,147), onAccent=RGB(252,253,253);
    bool highContrast=false;
    void system(bool force=false) {
        HIGHCONTRASTW contrast{sizeof(contrast)};
        highContrast=force || (SystemParametersInfoW(SPI_GETHIGHCONTRAST,sizeof(contrast),&contrast,0) && (contrast.dwFlags&HCF_HIGHCONTRASTON));
        if (!highContrast) return;
        background=surface=GetSysColor(COLOR_WINDOW); ink=muted=GetSysColor(COLOR_WINDOWTEXT);
        accent=selected=GetSysColor(COLOR_HIGHLIGHT); onAccent=GetSysColor(COLOR_HIGHLIGHTTEXT);
        accentHover=accentPressed=accent;
        line=GetSysColor(COLOR_WINDOWTEXT); hover=GetSysColor(COLOR_BTNFACE); disabled=GetSysColor(COLOR_GRAYTEXT);
    }
};
inline Gdiplus::Color color(COLORREF value) { return Gdiplus::Color(255,GetRValue(value),GetGValue(value),GetBValue(value)); }
inline void fill(HDC dc,const RECT& rect,COLORREF value) {
    HBRUSH brush=CreateSolidBrush(value); FillRect(dc,&rect,brush); DeleteObject(brush);
}
inline void rounded(HDC dc,const RECT& rect,int radius,COLORREF fillColor,COLORREF strokeColor,bool stroke=true) {
    Gdiplus::Graphics graphics(dc); graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath path; float x=static_cast<float>(rect.left)+0.5f,y=static_cast<float>(rect.top)+0.5f;
    float w=static_cast<float>(rect.right-rect.left)-1,h=static_cast<float>(rect.bottom-rect.top)-1,r=static_cast<float>(radius*2);
    if (w<=0 || h<=0) return;
    r=std::min(r,std::min(w,h));
    path.AddArc(x,y,r,r,180,90); path.AddArc(x+w-r,y,r,r,270,90);
    path.AddArc(x+w-r,y+h-r,r,r,0,90); path.AddArc(x,y+h-r,r,r,90,90); path.CloseFigure();
    Gdiplus::SolidBrush brush(color(fillColor)); graphics.FillPath(&brush,&path);
    if (stroke) { Gdiplus::Pen pen(color(strokeColor),1.0f); graphics.DrawPath(&pen,&path); }
}
enum class Symbol { Document,Picture,Settings,Trash,Clear,Close,Clipboard,Return };
inline void symbol(HDC dc,RECT rect,Symbol type,COLORREF value) {
    Gdiplus::Graphics graphics(dc); graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.TranslateTransform(static_cast<float>(rect.left),static_cast<float>(rect.top));
    graphics.ScaleTransform(static_cast<float>(rect.right-rect.left)/24.0f,static_cast<float>(rect.bottom-rect.top)/24.0f);
    Gdiplus::Pen pen(color(value),1.65f); pen.SetStartCap(Gdiplus::LineCapRound); pen.SetEndCap(Gdiplus::LineCapRound); pen.SetLineJoin(Gdiplus::LineJoinRound);
    auto line=[&](float x,float y,float endX,float endY){graphics.DrawLine(&pen,x,y,endX,endY);};
    switch (type) {
        case Symbol::Document: {
            Gdiplus::Point points[]={{6,3},{14,3},{19,8},{19,21},{6,21},{6,3}};
            graphics.DrawLines(&pen,points,6); line(14,3,14,8); line(14,8,19,8); line(9,12,16,12); line(9,16,15,16); break;
        }
        case Symbol::Picture:
            graphics.DrawRectangle(&pen,3.5f,4.5f,17.0f,15.0f); graphics.DrawEllipse(&pen,7.0f,8.0f,3.0f,3.0f);
            line(4,18,10,13); line(10,13,13,16); line(13,16,17,11); line(17,11,20,15); break;
        case Symbol::Settings:
            line(4,6,20,6); line(4,12,20,12); line(4,18,20,18);
            graphics.DrawEllipse(&pen,7.0f,3.5f,5.0f,5.0f); graphics.DrawEllipse(&pen,14.0f,9.5f,5.0f,5.0f); graphics.DrawEllipse(&pen,5.0f,15.5f,5.0f,5.0f); break;
        case Symbol::Trash:
            line(5,6,19,6); line(9,3,15,3); line(7,6,8,21); line(8,21,16,21); line(16,21,17,6); line(10,10,10,17); line(14,10,14,17); break;
        case Symbol::Clear:
            line(4,6,18,6); line(4,12,14,12); line(4,18,12,18); line(16,15,21,20); line(21,15,16,20); break;
        case Symbol::Close: line(6,6,18,18); line(18,6,6,18); break;
        case Symbol::Clipboard:
            graphics.DrawRectangle(&pen,5.0f,5.0f,14.0f,16.0f); graphics.DrawRectangle(&pen,9.0f,2.5f,6.0f,5.0f);
            line(9,12,15,12); line(9,16,14,16); break;
        case Symbol::Return: line(19,5,19,14); line(19,14,5,14); line(5,14,10,9); line(5,14,10,19); break;
    }
}
}
