#pragma once
#include <windows.h>
#include <winsqlite/winsqlite3.h>
#include <filesystem>
#include <string>
#include <vector>

namespace copykeep {
using Bytes = std::vector<unsigned char>;
std::string utf8(const std::wstring& value);
std::wstring wide(const std::string& value);
struct Item {
    long long id = 0;
    int kind = 0;
    std::wstring preview;
    int width = 0, height = 0;
    long long size = 0;
};
class Store {
    sqlite3* db_ = nullptr;
    int limit_ = 200;
    void exec(const char* sql);
    void prune();
public:
    explicit Store(const std::filesystem::path& folder);
    ~Store();
    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;
    long long put(int kind, const Bytes& data, const std::wstring& preview, int width = 0, int height = 0);
    std::vector<Item> list();
    Bytes payload(long long id);
    void use(long long id, bool promote);
    void erase(long long id);
    void clear();
    std::string setting(const char* key, const char* fallback);
    void setting(const char* key, const std::string& value);
    void limit(int value);
};
}
