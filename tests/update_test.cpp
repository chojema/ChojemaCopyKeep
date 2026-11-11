#include "update.h"
#include <iostream>
#include <stdexcept>

int main() {
    using namespace copykeep;
    int checks=0;
    auto check=[&](bool ok) { if (!ok) throw std::runtime_error("Update regression failed"); ++checks; };
    check(parse_version(L"0.2.0")==Version{0,2,0});
    check(parse_version(L"10.20.65535")==Version{10,20,65535});
    check(*parse_version(L"0.10.0")>*parse_version(L"0.9.9"));
    check(*parse_version(L"1.0.0")>*parse_version(L"0.99.99"));
    check(!(*parse_version(L"0.2.0")>*parse_version(L"0.2.0")));
    check(!(*parse_version(L"0.1.9")>*parse_version(L"0.2.0")));
    for (auto invalid:{L"",L"1",L"1.2",L"1.2.3.4",L"1..3",L"-1.2.3",L"1.2.3-beta",L"1.2.3-macos",
        L"1.2.3\n",L" 1.2.3",L"01.2.3",L"65536.0.0",L"9999999999.0.0",L"1.2.x"}) check(!parse_version(invalid));
    check(release_version(L"https://github.com/chojema/ChojemaCopyKeep/releases/tag/v0.3.0")==Version{0,3,0});
    check(release_version(L"/chojema/ChojemaCopyKeep/releases/tag/v0.3.0")==Version{0,3,0});
    for (auto invalid:{L"http://github.com/chojema/ChojemaCopyKeep/releases/tag/v1.0.0",
        L"https://github.com.evil/chojema/ChojemaCopyKeep/releases/tag/v1.0.0",
        L"https://github.com/other/ChojemaCopyKeep/releases/tag/v1.0.0",
        L"https://github.com/chojema/ChojemaCopyKeep/releases/tag/v1.0.0-macos",
        L"https://github.com/chojema/ChojemaCopyKeep/releases/tag/v1.0.0?test",
        L"//evil/releases/tag/v1.0.0"}) check(!release_version(invalid));
    std::cout<<"PASS: "<<checks<<" update checks\n";
}
