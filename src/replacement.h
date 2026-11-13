#pragma once
#include <string>
#include <vector>

namespace copykeep {
struct ReplacementRule { std::wstring abbreviation, body; };
class ReplacementMatcher {
    std::wstring buffer_;
    static bool word(wchar_t c) { return (c>=L'a' && c<=L'z') || (c>=L'A' && c<=L'Z') || (c>=L'0' && c<=L'9') || c==L'_'; }
public:
    std::vector<ReplacementRule> rules;
    static bool valid(const std::wstring& value) {
        if (value.empty()) return true;
        if (value.size()<2 || value.size()>64) return false;
        for (wchar_t c:value) if (c<33 || c>126) return false;
        return true;
    }
    void reset() { buffer_.clear(); }
    int append(wchar_t c) {
        if (c<33 || c>126) { reset(); return -1; }
        buffer_+=c;
        if (buffer_.size()>65) buffer_.erase(0,buffer_.size()-65);
        for (size_t i=0;i<rules.size();++i) {
            const auto& key=rules[i].abbreviation;
            if (key.empty() || !buffer_.ends_with(key)) continue;
            auto prefix=buffer_.size()-key.size();
            if (word(key.front()) && prefix && word(buffer_[prefix-1])) continue;
            return static_cast<int>(i);
        }
        return -1;
    }
};
}
