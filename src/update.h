#pragma once
#include <array>
#include <optional>
#include <string_view>

namespace copykeep {
using Version = std::array<unsigned,3>;
inline constexpr wchar_t release_page[] = L"https://github.com/chojema/ChojemaCopyKeep/releases/latest";
inline std::optional<Version> parse_version(std::wstring_view value) {
    Version result{};
    for (size_t i=0;i<result.size();++i) {
        auto end=value.find(L'.');
        auto part=value.substr(0,end);
        if (part.empty() || part.size()>5 || (part.size()>1 && part.front()==L'0')) return {};
        for (auto digit:part) {
            if (digit<L'0' || digit>L'9') return {};
            result[i]=result[i]*10+static_cast<unsigned>(digit-L'0');
        }
        if (result[i]>65535 || (i==2)!=(end==value.npos)) return {};
        if (end!=value.npos) value.remove_prefix(end+1);
    }
    return result;
}
inline std::optional<Version> release_version(std::wstring_view location) {
    constexpr std::wstring_view absolute=L"https://github.com/chojema/ChojemaCopyKeep/releases/tag/v";
    constexpr std::wstring_view relative=L"/chojema/ChojemaCopyKeep/releases/tag/v";
    if (location.starts_with(absolute)) location.remove_prefix(absolute.size());
    else if (location.starts_with(relative)) location.remove_prefix(relative.size());
    else return {};
    return parse_version(location);
}
Version check_update();
}
