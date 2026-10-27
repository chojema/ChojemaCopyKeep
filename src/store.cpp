#include "store.h"
#include <bcrypt.h>
#include <algorithm>
#include <array>
#include <stdexcept>

namespace copykeep {
std::string utf8(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    std::string out(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n, nullptr, nullptr);
    return out;
}
std::wstring wide(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring out(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
    return out;
}
namespace {
class Statement {
public:
    sqlite3_stmt* p = nullptr;
    Statement(sqlite3* db, const char* sql) {
        if (sqlite3_prepare_v2(db, sql, -1, &p, nullptr) != SQLITE_OK) throw std::runtime_error("Database statement failed");
    }
    ~Statement() { sqlite3_finalize(p); }
    void done() { if (sqlite3_step(p) != SQLITE_DONE) throw std::runtime_error("Database update failed"); }
};
std::string digest(int kind, const Bytes& data) {
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    std::array<unsigned char, 32> result{};
    if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) throw std::runtime_error("Hash initialization failed");
    NTSTATUS status = BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0, 0);
    unsigned char type = static_cast<unsigned char>(kind);
    if (status >= 0) status = BCryptHashData(hash, &type, 1, 0);
    if (status >= 0) status = BCryptHashData(hash, const_cast<PUCHAR>(data.data()), static_cast<ULONG>(data.size()), 0);
    if (status >= 0) status = BCryptFinishHash(hash, result.data(), static_cast<ULONG>(result.size()), 0);
    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    if (status < 0) throw std::runtime_error("Hash calculation failed");
    const char* hex = "0123456789abcdef";
    std::string out;
    for (auto b : result) { out += hex[b >> 4]; out += hex[b & 15]; }
    return out;
}
}
void Store::exec(const char* sql) {
    if (sqlite3_exec(db_, sql, nullptr, nullptr, nullptr) != SQLITE_OK) throw std::runtime_error("Database operation failed");
}
Store::Store(const std::filesystem::path& folder) {
    std::filesystem::create_directories(folder);
    auto path = folder / L"history.db";
    if (sqlite3_open16(path.c_str(), &db_) != SQLITE_OK) {
        if (db_) sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error("Database open failed");
    }
    try {
        sqlite3_busy_timeout(db_, 500);
        exec("PRAGMA cache_size=-512; PRAGMA secure_delete=ON; PRAGMA journal_mode=TRUNCATE;"
             "CREATE TABLE IF NOT EXISTS clips(id INTEGER PRIMARY KEY,kind INTEGER NOT NULL,digest TEXT UNIQUE NOT NULL,preview TEXT NOT NULL,payload BLOB NOT NULL,width INTEGER,height INTEGER,rank INTEGER NOT NULL);"
             "CREATE INDEX IF NOT EXISTS clip_rank ON clips(rank DESC);"
             "CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);");
    } catch (...) { sqlite3_close(db_); db_ = nullptr; throw; }
}
Store::~Store() { if (db_) sqlite3_close(db_); }
long long Store::put(int kind, const Bytes& data, const std::wstring& preview, int width, int height) {
    if (data.empty() || data.size() > 32u * 1024u * 1024u) throw std::runtime_error("Clipboard item exceeds limit");
    const auto key = digest(kind, data);
    long long id = 0;
    exec("BEGIN IMMEDIATE");
    try {
        Statement existing(db_, "SELECT id FROM clips WHERE digest=?");
        sqlite3_bind_text(existing.p, 1, key.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(existing.p) == SQLITE_ROW) id = sqlite3_column_int64(existing.p, 0);
        if (id) {
            Statement update(db_, "UPDATE clips SET rank=(SELECT COALESCE(MAX(rank),0)+1 FROM clips) WHERE id=?");
            sqlite3_bind_int64(update.p, 1, id); update.done();
        } else {
            Statement insert(db_, "INSERT INTO clips(kind,digest,preview,payload,width,height,rank) VALUES(?,?,?,?,?,?,(SELECT COALESCE(MAX(rank),0)+1 FROM clips))");
            const auto label = utf8(preview.substr(0, 180));
            sqlite3_bind_int(insert.p, 1, kind);
            sqlite3_bind_text(insert.p, 2, key.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(insert.p, 3, label.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_blob(insert.p, 4, data.data(), static_cast<int>(data.size()), SQLITE_TRANSIENT);
            sqlite3_bind_int(insert.p, 5, width); sqlite3_bind_int(insert.p, 6, height);
            insert.done(); id = sqlite3_last_insert_rowid(db_);
        }
        prune(); exec("COMMIT");
    } catch (...) { sqlite3_exec(db_, "ROLLBACK", nullptr, nullptr, nullptr); throw; }
    return id;
}
void Store::prune() {
    Statement count(db_, "DELETE FROM clips WHERE id NOT IN (SELECT id FROM clips ORDER BY rank DESC LIMIT ?)");
    sqlite3_bind_int(count.p, 1, limit_); count.done();
    for (;;) {
        long long bytes = 0;
        { Statement total(db_, "SELECT COALESCE(SUM(length(payload)),0) FROM clips");
          if (sqlite3_step(total.p) == SQLITE_ROW) bytes = sqlite3_column_int64(total.p, 0); }
        if (bytes <= 256ll * 1024 * 1024) break;
        exec("DELETE FROM clips WHERE id=(SELECT id FROM clips ORDER BY rank LIMIT 1)");
    }
}
std::vector<Item> Store::list() {
    Statement query(db_, "SELECT id,kind,preview,width,height,length(payload) FROM clips ORDER BY rank DESC");
    std::vector<Item> out;
    while (sqlite3_step(query.p) == SQLITE_ROW) {
        Item i; i.id = sqlite3_column_int64(query.p, 0); i.kind = sqlite3_column_int(query.p, 1);
        const auto* text = sqlite3_column_text(query.p, 2);
        i.preview = text ? wide(reinterpret_cast<const char*>(text)) : L"";
        i.width = sqlite3_column_int(query.p, 3); i.height = sqlite3_column_int(query.p, 4);
        i.size = sqlite3_column_int64(query.p, 5); out.push_back(std::move(i));
    }
    return out;
}
Bytes Store::payload(long long id) {
    Statement query(db_, "SELECT payload FROM clips WHERE id=?"); sqlite3_bind_int64(query.p, 1, id);
    if (sqlite3_step(query.p) != SQLITE_ROW) return {};
    const auto* p = static_cast<const unsigned char*>(sqlite3_column_blob(query.p, 0));
    int size = sqlite3_column_bytes(query.p, 0);
    return p && size > 0 ? Bytes(p, p + size) : Bytes{};
}
void Store::use(long long id, bool promote) {
    if (!promote) return;
    Statement update(db_, "UPDATE clips SET rank=(SELECT COALESCE(MAX(rank),0)+1 FROM clips) WHERE id=?");
    sqlite3_bind_int64(update.p, 1, id); update.done();
}
void Store::erase(long long id) {
    Statement remove(db_, "DELETE FROM clips WHERE id=?"); sqlite3_bind_int64(remove.p, 1, id); remove.done();
}
void Store::clear() { exec("DELETE FROM clips; VACUUM;"); }
std::string Store::setting(const char* key, const char* fallback) {
    Statement query(db_, "SELECT value FROM settings WHERE key=?");
    sqlite3_bind_text(query.p, 1, key, -1, SQLITE_TRANSIENT);
    if (sqlite3_step(query.p) != SQLITE_ROW) return fallback;
    const auto* p = sqlite3_column_text(query.p, 0);
    return p ? reinterpret_cast<const char*>(p) : fallback;
}
void Store::setting(const char* key, const std::string& value) {
    Statement update(db_, "INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)");
    sqlite3_bind_text(update.p, 1, key, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(update.p, 2, value.c_str(), -1, SQLITE_TRANSIENT); update.done();
}
void Store::limit(int value) { limit_ = std::clamp(value, 10, 1000); prune(); }
}
