#include "replacement.h"
#include <stdexcept>
#include <iostream>
int main() {
    using namespace copykeep;
    int checks=0;
    auto check=[&](bool value) { if (!value) throw std::runtime_error("Text replacement regression failed"); ++checks; };
    for (auto invalid:{L"a",L"a b",L"한글",L"ab\n"}) check(!ReplacementMatcher::valid(invalid));
    check(ReplacementMatcher::valid(L"")); check(ReplacementMatcher::valid(L";;addr"));
    check(!ReplacementMatcher::valid(std::wstring(65,L'a')));
    ReplacementMatcher matcher; matcher.rules={{L";;addr",L"서울\nSeoul 😀"},{L"sig",L"Signature"}};
    for (wchar_t c:std::wstring(L";;add")) check(matcher.append(c)==-1);
    check(matcher.append(L'r')==0); matcher.reset();
    for (wchar_t c:std::wstring(L"design")) check(matcher.append(c)==-1);
    matcher.reset(); check(matcher.append(L's')==-1); check(matcher.append(L'i')==-1); check(matcher.append(L'g')==1);
    matcher.reset();
    for (wchar_t c:std::wstring(L";;ADDR")) check(matcher.append(c)==-1);
    matcher.append(L';'); matcher.append(L'\b');
    for (wchar_t c:std::wstring(L";addr")) check(matcher.append(c)==-1);
    std::cout<<"PASS: "<<checks<<" text replacement checks\n";
}
