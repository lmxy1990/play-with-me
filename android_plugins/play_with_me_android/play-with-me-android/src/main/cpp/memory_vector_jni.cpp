#include <jni.h>

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iterator>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <android/log.h>

#include "sqlite3.h"
#include "hnswlib/hnswlib.h"

namespace {

constexpr const char *TAG = "MemoryVectorNative";
constexpr int EMBEDDING_DIMENSION = 128;

class JniString {
public:
    JniString(JNIEnv *env, jstring value) : env_(env), value_(value) {
        if (value_ == nullptr) {
            return;
        }
        chars_ = env_->GetStringUTFChars(value_, nullptr);
        if (chars_ == nullptr) {
            throw std::runtime_error("Unable to read Java string");
        }
    }

    ~JniString() {
        if (chars_ != nullptr) {
            env_->ReleaseStringUTFChars(value_, chars_);
        }
    }

    std::string str() const {
        return chars_ == nullptr ? std::string() : std::string(chars_);
    }

private:
    JNIEnv *env_;
    jstring value_;
    const char *chars_ = nullptr;
};

struct VectorItem {
    std::string memory_id;
    std::string memory_type;
    std::vector<float> vector;
};

struct HnswScopeIndex {
    int dimension = EMBEDDING_DIMENSION;
    std::unique_ptr<hnswlib::InnerProductSpace> space;
    std::unique_ptr<hnswlib::HierarchicalNSW<float>> index;
    std::vector<std::string> ids;
    std::vector<std::string> types;
};

struct SearchItem {
    std::string memory_id;
    std::string memory_type;
    std::string retrieval_source;
    std::string backend;
    float distance = 0.0f;
    float score = 0.0f;
};

std::mutex g_hnsw_mutex;
std::unordered_map<std::string, std::shared_ptr<HnswScopeIndex>> g_hnsw_indexes;

std::string json_escape(const std::string &value) {
    std::ostringstream out;
    for (char ch : value) {
        switch (ch) {
            case '\\':
                out << "\\\\";
                break;
            case '"':
                out << "\\\"";
                break;
            case '\b':
                out << "\\b";
                break;
            case '\f':
                out << "\\f";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                if (static_cast<unsigned char>(ch) < 0x20) {
                    out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(ch));
                } else {
                    out << ch;
                }
        }
    }
    return out.str();
}

std::string json_string(const std::string &value) {
    return "\"" + json_escape(value) + "\"";
}

std::string json_bool(bool value) {
    return value ? "true" : "false";
}

std::string vector_json(const std::vector<float> &vector) {
    std::ostringstream out;
    out << "[";
    for (size_t i = 0; i < vector.size(); ++i) {
        if (i > 0) {
            out << ",";
        }
        out << std::setprecision(9) << vector[i];
    }
    out << "]";
    return out.str();
}

jstring to_jstring(JNIEnv *env, const std::string &value) {
    return env->NewStringUTF(value.c_str());
}

std::string join_path(const std::string &dir, const std::string &name) {
    if (dir.empty()) {
        return name;
    }
    if (dir.back() == '/') {
        return dir + name;
    }
    return dir + "/" + name;
}

bool exec_sql(sqlite3 *db, const std::string &sql, std::string *error) {
    char *message = nullptr;
    const int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &message);
    if (rc == SQLITE_OK) {
        return true;
    }
    if (error != nullptr) {
        *error = message != nullptr ? std::string(message) : sqlite3_errmsg(db);
    }
    if (message != nullptr) {
        sqlite3_free(message);
    }
    return false;
}

class SqliteHandle {
public:
    explicit SqliteHandle(sqlite3 *db) : db_(db) {}
    ~SqliteHandle() {
        if (db_ != nullptr) {
            sqlite3_close(db_);
        }
    }

    sqlite3 *get() const {
        return db_;
    }

private:
    sqlite3 *db_;
};

class Statement {
public:
    Statement(sqlite3 *db, const std::string &sql) : db_(db) {
        const int rc = sqlite3_prepare_v2(db_, sql.c_str(), -1, &statement_, nullptr);
        if (rc != SQLITE_OK) {
            throw std::runtime_error(sqlite3_errmsg(db_));
        }
    }

    ~Statement() {
        if (statement_ != nullptr) {
            sqlite3_finalize(statement_);
        }
    }

    sqlite3_stmt *get() const {
        return statement_;
    }

private:
    sqlite3 *db_;
    sqlite3_stmt *statement_ = nullptr;
};

SqliteHandle open_database(const std::string &database_path) {
    sqlite3 *db = nullptr;
    const int rc = sqlite3_open_v2(
        database_path.c_str(),
        &db,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nullptr);
    if (rc != SQLITE_OK) {
        const std::string message = db != nullptr ? sqlite3_errmsg(db) : "sqlite open failed";
        if (db != nullptr) {
            sqlite3_close(db);
        }
        throw std::runtime_error(message);
    }
    sqlite3_busy_timeout(db, 300);
    return SqliteHandle(db);
}

bool load_sqlite_vec(sqlite3 *db, const std::string &native_library_dir, std::string *error) {
    sqlite3_enable_load_extension(db, 1);
    const std::vector<std::string> paths = {
        join_path(native_library_dir, "libvec0.so"),
        "libvec0.so",
    };
    const std::vector<const char *> entries = {nullptr, "sqlite3_vec_init"};
    std::string last_error;
    for (const std::string &path : paths) {
        for (const char *entry : entries) {
            char *message = nullptr;
            const int rc = sqlite3_load_extension(db, path.c_str(), entry, &message);
            if (rc == SQLITE_OK) {
                sqlite3_enable_load_extension(db, 0);
                return true;
            }
            last_error = message != nullptr ? std::string(message) : sqlite3_errmsg(db);
            if (message != nullptr) {
                sqlite3_free(message);
            }
        }
    }
    sqlite3_enable_load_extension(db, 0);
    if (error != nullptr) {
        *error = last_error.empty() ? "sqlite-vec extension load failed" : last_error;
    }
    return false;
}

bool create_vec_table(sqlite3 *db, std::string *error) {
    if (!exec_sql(db, "DROP TABLE IF EXISTS memory_episodic_vec", error)) {
        return false;
    }
    const std::vector<std::string> candidates = {
        "CREATE VIRTUAL TABLE memory_episodic_vec USING vec0("
        "memory_rowid integer primary key, "
        "scope_key text partition key, "
        "memory_id text, "
        "embedding float[128])",
        "CREATE VIRTUAL TABLE memory_episodic_vec USING vec0("
        "memory_rowid integer primary key, "
        "scope_key text, "
        "memory_id text, "
        "embedding float[128])",
    };
    std::string last_error;
    for (const std::string &sql : candidates) {
        if (exec_sql(db, sql, &last_error)) {
            return true;
        }
    }
    if (error != nullptr) {
        *error = last_error;
    }
    return false;
}

bool probe_sqlite_vec(const std::string &native_library_dir, std::string *error) {
    sqlite3 *raw = nullptr;
    const int rc = sqlite3_open_v2(
        ":memory:",
        &raw,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
        nullptr);
    if (rc != SQLITE_OK) {
        if (error != nullptr) {
            *error = raw != nullptr ? sqlite3_errmsg(raw) : "sqlite probe open failed";
        }
        if (raw != nullptr) {
            sqlite3_close(raw);
        }
        return false;
    }
    SqliteHandle db(raw);
    if (!load_sqlite_vec(db.get(), native_library_dir, error)) {
        return false;
    }
    std::string create_error;
    if (!exec_sql(db.get(), "CREATE VIRTUAL TABLE vec_probe USING vec0(embedding float[1])", &create_error)) {
        if (error != nullptr) {
            *error = create_error;
        }
        return false;
    }
    return true;
}

std::vector<std::string> jstring_array(JNIEnv *env, jobjectArray values) {
    std::vector<std::string> result;
    if (values == nullptr) {
        return result;
    }
    const jsize count = env->GetArrayLength(values);
    result.reserve(static_cast<size_t>(count));
    for (jsize i = 0; i < count; ++i) {
        auto item = static_cast<jstring>(env->GetObjectArrayElement(values, i));
        result.push_back(JniString(env, item).str());
        env->DeleteLocalRef(item);
    }
    return result;
}

std::vector<std::vector<float>> jfloat_array_array(JNIEnv *env, jobjectArray values) {
    std::vector<std::vector<float>> result;
    if (values == nullptr) {
        return result;
    }
    const jsize count = env->GetArrayLength(values);
    result.reserve(static_cast<size_t>(count));
    for (jsize i = 0; i < count; ++i) {
        auto item = static_cast<jfloatArray>(env->GetObjectArrayElement(values, i));
        if (item == nullptr) {
            result.emplace_back();
            continue;
        }
        const jsize length = env->GetArrayLength(item);
        std::vector<float> vector(static_cast<size_t>(length));
        if (length > 0) {
            env->GetFloatArrayRegion(item, 0, length, vector.data());
        }
        result.push_back(std::move(vector));
        env->DeleteLocalRef(item);
    }
    return result;
}

std::vector<float> jfloat_vector(JNIEnv *env, jfloatArray values) {
    if (values == nullptr) {
        return {};
    }
    const jsize length = env->GetArrayLength(values);
    std::vector<float> vector(static_cast<size_t>(length));
    if (length > 0) {
        env->GetFloatArrayRegion(values, 0, length, vector.data());
    }
    return vector;
}

std::vector<VectorItem> vector_items(
    const std::vector<std::string> &ids,
    const std::vector<std::string> &types,
    const std::vector<std::vector<float>> &vectors,
    const std::string &fallback_type) {
    std::vector<VectorItem> result;
    const size_t count = std::min(ids.size(), vectors.size());
    result.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        if (ids[i].empty() || vectors[i].size() != EMBEDDING_DIMENSION) {
            continue;
        }
        VectorItem item;
        item.memory_id = ids[i];
        item.memory_type = i < types.size() && !types[i].empty() ? types[i] : fallback_type;
        item.vector = vectors[i];
        result.push_back(std::move(item));
    }
    return result;
}

bool rebuild_sqlite_vec(
    const std::string &database_path,
    const std::string &native_library_dir,
    const std::string &scope_key,
    const std::vector<VectorItem> &events,
    std::string *error) {
    SqliteHandle db = open_database(database_path);
    if (!load_sqlite_vec(db.get(), native_library_dir, error)) {
        return false;
    }
    if (!exec_sql(db.get(), "BEGIN IMMEDIATE", error)) {
        return false;
    }
    bool ok = false;
    try {
        if (!create_vec_table(db.get(), error)) {
            throw std::runtime_error(error != nullptr ? *error : "sqlite-vec table create failed");
        }
        Statement insert(
            db.get(),
            "INSERT INTO memory_episodic_vec(memory_rowid, scope_key, memory_id, embedding) "
            "VALUES (?, ?, ?, vec_f32(?))");
        int rowid = 1;
        for (const VectorItem &item : events) {
            sqlite3_reset(insert.get());
            sqlite3_clear_bindings(insert.get());
            const std::string encoded = vector_json(item.vector);
            sqlite3_bind_int(insert.get(), 1, rowid++);
            sqlite3_bind_text(insert.get(), 2, scope_key.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(insert.get(), 3, item.memory_id.c_str(), -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(insert.get(), 4, encoded.c_str(), -1, SQLITE_TRANSIENT);
            const int rc = sqlite3_step(insert.get());
            if (rc != SQLITE_DONE) {
                throw std::runtime_error(sqlite3_errmsg(db.get()));
            }
        }
        if (!exec_sql(db.get(), "COMMIT", error)) {
            return false;
        }
        ok = true;
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = exception.what();
        }
    }
    if (!ok) {
        std::string ignored;
        exec_sql(db.get(), "ROLLBACK", &ignored);
    }
    return ok;
}

std::shared_ptr<HnswScopeIndex> build_hnsw_index(const std::vector<VectorItem> &items) {
    if (items.empty()) {
        return nullptr;
    }
    auto result = std::make_shared<HnswScopeIndex>();
    result->dimension = EMBEDDING_DIMENSION;
    result->space = std::make_unique<hnswlib::InnerProductSpace>(EMBEDDING_DIMENSION);
    result->index = std::make_unique<hnswlib::HierarchicalNSW<float>>(
        result->space.get(),
        std::max<size_t>(1, items.size()),
        16,
        200);
    result->ids.reserve(items.size());
    result->types.reserve(items.size());
    for (size_t i = 0; i < items.size(); ++i) {
        result->ids.push_back(items[i].memory_id);
        result->types.push_back(items[i].memory_type);
        result->index->addPoint(items[i].vector.data(), static_cast<hnswlib::labeltype>(i));
    }
    result->index->setEf(64);
    return result;
}

void store_hnsw_index(const std::string &scope_key, const std::shared_ptr<HnswScopeIndex> &index) {
    std::lock_guard<std::mutex> lock(g_hnsw_mutex);
    if (index == nullptr) {
        g_hnsw_indexes.erase(scope_key);
    } else {
        g_hnsw_indexes[scope_key] = index;
    }
}

std::shared_ptr<HnswScopeIndex> hnsw_index_for_scope(const std::string &scope_key) {
    std::lock_guard<std::mutex> lock(g_hnsw_mutex);
    auto found = g_hnsw_indexes.find(scope_key);
    if (found == g_hnsw_indexes.end()) {
        return nullptr;
    }
    return found->second;
}

float score_from_distance(float distance) {
    if (!std::isfinite(distance)) {
        return 0.0f;
    }
    const float score = 1.0f - distance;
    return std::max(0.0f, std::min(1.0f, score));
}

std::vector<SearchItem> search_sqlite_vec(
    const std::string &database_path,
    const std::string &native_library_dir,
    const std::string &scope_key,
    const std::vector<float> &query,
    int top_k,
    bool *searched,
    std::string *error) {
    std::vector<SearchItem> result;
    if (top_k <= 0 || query.size() != EMBEDDING_DIMENSION) {
        return result;
    }
    SqliteHandle db = open_database(database_path);
    if (!load_sqlite_vec(db.get(), native_library_dir, error)) {
        return result;
    }
    try {
        Statement statement(
            db.get(),
            "SELECT memory_id, distance FROM memory_episodic_vec "
            "WHERE embedding MATCH vec_f32(?) AND k = ? AND scope_key = ? "
            "ORDER BY distance");
        const std::string encoded = vector_json(query);
        sqlite3_bind_text(statement.get(), 1, encoded.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(statement.get(), 2, top_k);
        sqlite3_bind_text(statement.get(), 3, scope_key.c_str(), -1, SQLITE_TRANSIENT);
        if (searched != nullptr) {
            *searched = true;
        }
        while (true) {
            const int rc = sqlite3_step(statement.get());
            if (rc == SQLITE_DONE) {
                break;
            }
            if (rc != SQLITE_ROW) {
                throw std::runtime_error(sqlite3_errmsg(db.get()));
            }
            const unsigned char *memory_id_text = sqlite3_column_text(statement.get(), 0);
            const float distance = static_cast<float>(sqlite3_column_double(statement.get(), 1));
            SearchItem item;
            item.memory_id = memory_id_text != nullptr
                ? reinterpret_cast<const char *>(memory_id_text)
                : "";
            item.memory_type = "episodic";
            item.retrieval_source = "sqlite_vec_event";
            item.backend = "sqlite-vec";
            item.distance = distance;
            item.score = score_from_distance(distance);
            if (!item.memory_id.empty()) {
                result.push_back(std::move(item));
            }
        }
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = exception.what();
        }
    }
    return result;
}

std::vector<SearchItem> search_hnsw(
    const std::string &scope_key,
    const std::vector<float> &query,
    int top_k,
    bool *searched,
    std::string *error) {
    std::vector<SearchItem> result;
    if (top_k <= 0 || query.size() != EMBEDDING_DIMENSION) {
        return result;
    }
    const auto index = hnsw_index_for_scope(scope_key);
    if (index == nullptr || index->index == nullptr || index->ids.empty()) {
        return result;
    }
    try {
        const size_t limit = std::min<size_t>(static_cast<size_t>(top_k), index->ids.size());
        const auto nearest = index->index->searchKnnCloserFirst(query.data(), limit);
        if (searched != nullptr) {
            *searched = true;
        }
        result.reserve(nearest.size());
        for (const auto &entry : nearest) {
            const size_t label = static_cast<size_t>(entry.second);
            if (label >= index->ids.size()) {
                continue;
            }
            SearchItem item;
            item.memory_id = index->ids[label];
            item.memory_type = label < index->types.size() ? index->types[label] : "semantic";
            item.retrieval_source = "hnsw_semantic";
            item.backend = "hnswlib";
            item.distance = entry.first;
            item.score = score_from_distance(entry.first);
            result.push_back(std::move(item));
        }
    } catch (const std::exception &exception) {
        if (error != nullptr) {
            *error = exception.what();
        }
    }
    return result;
}

void append_warnings(std::ostringstream &out, const std::vector<std::string> &warnings) {
    out << "\"warnings\":[";
    for (size_t i = 0; i < warnings.size(); ++i) {
        if (i > 0) {
            out << ",";
        }
        out << json_string(warnings[i]);
    }
    out << "]";
}

void append_items(std::ostringstream &out, const std::vector<SearchItem> &items) {
    out << "\"items\":[";
    for (size_t i = 0; i < items.size(); ++i) {
        const SearchItem &item = items[i];
        if (i > 0) {
            out << ",";
        }
        out << "{"
            << "\"memory_id\":" << json_string(item.memory_id) << ","
            << "\"memory_type\":" << json_string(item.memory_type) << ","
            << "\"retrieval_source\":" << json_string(item.retrieval_source) << ","
            << "\"backend\":" << json_string(item.backend) << ","
            << "\"distance\":" << std::setprecision(9) << item.distance << ","
            << "\"score\":" << std::setprecision(9) << item.score
            << "}";
    }
    out << "]";
}

std::string status_json(
    bool sqlite_available,
    const std::string &sqlite_error,
    const std::string &native_library_dir) {
    std::vector<std::string> warnings;
    if (!sqlite_available) {
        warnings.push_back("native_sqlite_vec_unavailable");
    }
    std::ostringstream out;
    out << "{"
        << "\"ok\":" << json_bool(sqlite_available) << ","
        << "\"sqlite_vec_available\":" << json_bool(sqlite_available) << ","
        << "\"hnswlib_available\":true,"
        << "\"native_sqlite_vec_enabled\":false,"
        << "\"native_hnswlib_enabled\":false,"
        << "\"sqlite_vec_event_enabled\":false,"
        << "\"hnsw_semantic_enabled\":false,"
        << "\"native_vector_backend\":\"sqlite-vec+hnswlib\","
        << "\"sqlite_version\":" << json_string(sqlite3_libversion()) << ","
        << "\"native_library_dir\":" << json_string(native_library_dir) << ",";
    if (!sqlite_error.empty()) {
        out << "\"sqlite_vec_error\":" << json_string(sqlite_error) << ",";
    }
    append_warnings(out, warnings);
    out << "}";
    return out.str();
}

std::string rebuild_json(
    bool sqlite_ok,
    bool hnsw_ok,
    int event_count,
    int semantic_count,
    const std::string &sqlite_error,
    const std::string &hnsw_error) {
    std::vector<std::string> warnings;
    if (!sqlite_ok) {
        warnings.push_back("native_sqlite_vec_rebuild_failed");
    }
    if (!hnsw_ok && semantic_count > 0) {
        warnings.push_back("native_hnswlib_rebuild_failed");
    }
    std::ostringstream out;
    out << "{"
        << "\"ok\":" << json_bool(sqlite_ok && hnsw_ok) << ","
        << "\"sqlite_vec_available\":" << json_bool(sqlite_ok) << ","
        << "\"hnswlib_available\":" << json_bool(hnsw_ok) << ","
        << "\"native_sqlite_vec_enabled\":" << json_bool(sqlite_ok && event_count > 0) << ","
        << "\"native_hnswlib_enabled\":" << json_bool(hnsw_ok && semantic_count > 0) << ","
        << "\"sqlite_vec_event_enabled\":" << json_bool(sqlite_ok && event_count > 0) << ","
        << "\"hnsw_semantic_enabled\":" << json_bool(hnsw_ok && semantic_count > 0) << ","
        << "\"native_vector_backend\":\"sqlite-vec+hnswlib\","
        << "\"event_vector_count\":" << event_count << ","
        << "\"semantic_vector_count\":" << semantic_count << ",";
    if (!sqlite_error.empty()) {
        out << "\"sqlite_vec_error\":" << json_string(sqlite_error) << ",";
    }
    if (!hnsw_error.empty()) {
        out << "\"hnswlib_error\":" << json_string(hnsw_error) << ",";
    }
    append_warnings(out, warnings);
    out << "}";
    return out.str();
}

std::string search_json(
    bool sqlite_searched,
    bool hnsw_searched,
    const std::vector<SearchItem> &items,
    const std::string &sqlite_error,
    const std::string &hnsw_error) {
    std::vector<std::string> warnings;
    if (!sqlite_error.empty()) {
        warnings.push_back("native_sqlite_vec_search_failed");
    }
    if (!hnsw_error.empty()) {
        warnings.push_back("native_hnswlib_search_failed");
    }
    std::ostringstream out;
    out << "{"
        << "\"ok\":true,"
        << "\"native_sqlite_vec_enabled\":" << json_bool(sqlite_searched) << ","
        << "\"native_hnswlib_enabled\":" << json_bool(hnsw_searched) << ","
        << "\"sqlite_vec_event_enabled\":" << json_bool(sqlite_searched) << ","
        << "\"hnsw_semantic_enabled\":" << json_bool(hnsw_searched) << ","
        << "\"native_vector_backend\":\"sqlite-vec+hnswlib\","
        << "\"item_count\":" << items.size() << ",";
    if (!sqlite_error.empty()) {
        out << "\"sqlite_vec_error\":" << json_string(sqlite_error) << ",";
    }
    if (!hnsw_error.empty()) {
        out << "\"hnswlib_error\":" << json_string(hnsw_error) << ",";
    }
    append_items(out, items);
    out << ",";
    append_warnings(out, warnings);
    out << "}";
    return out.str();
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_playwithme_godot_MemoryNative_nativeStatus(
    JNIEnv *env,
    jclass,
    jstring,
    jstring native_library_dir) {
    try {
        const std::string lib_dir = JniString(env, native_library_dir).str();
        std::string error;
        const bool sqlite_available = probe_sqlite_vec(lib_dir, &error);
        return to_jstring(env, status_json(sqlite_available, error, lib_dir));
    } catch (const std::exception &exception) {
        return to_jstring(
            env,
            std::string("{\"ok\":false,\"sqlite_vec_available\":false,")
                + "\"hnswlib_available\":true,\"error\":"
                + json_string(exception.what())
                + ",\"warnings\":[\"native_status_failed\"]}");
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_playwithme_godot_MemoryNative_nativeRebuild(
    JNIEnv *env,
    jclass,
    jstring database_path,
    jstring native_library_dir,
    jstring scope_key,
    jobjectArray event_ids,
    jobjectArray event_vectors,
    jobjectArray semantic_ids,
    jobjectArray semantic_types,
    jobjectArray semantic_vectors) {
    try {
        const std::string db_path = JniString(env, database_path).str();
        const std::string lib_dir = JniString(env, native_library_dir).str();
        const std::string scope = JniString(env, scope_key).str();
        const auto event_items = vector_items(
            jstring_array(env, event_ids),
            {},
            jfloat_array_array(env, event_vectors),
            "episodic");
        const auto semantic_items = vector_items(
            jstring_array(env, semantic_ids),
            jstring_array(env, semantic_types),
            jfloat_array_array(env, semantic_vectors),
            "semantic");

        std::string sqlite_error;
        std::string hnsw_error;
        const bool sqlite_ok = rebuild_sqlite_vec(db_path, lib_dir, scope, event_items, &sqlite_error);
        bool hnsw_ok = true;
        try {
            store_hnsw_index(scope, build_hnsw_index(semantic_items));
        } catch (const std::exception &exception) {
            hnsw_ok = false;
            hnsw_error = exception.what();
            store_hnsw_index(scope, nullptr);
        }
        return to_jstring(
            env,
            rebuild_json(
                sqlite_ok,
                hnsw_ok,
                static_cast<int>(event_items.size()),
                static_cast<int>(semantic_items.size()),
                sqlite_error,
                hnsw_error));
    } catch (const std::exception &exception) {
        return to_jstring(
            env,
            std::string("{\"ok\":false,\"error\":")
                + json_string(exception.what())
                + ",\"warnings\":[\"native_rebuild_failed\"]}");
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_playwithme_godot_MemoryNative_nativeSearch(
    JNIEnv *env,
    jclass,
    jstring database_path,
    jstring native_library_dir,
    jstring scope_key,
    jfloatArray query_vector,
    jint event_top_k,
    jint semantic_top_k) {
    try {
        const std::string db_path = JniString(env, database_path).str();
        const std::string lib_dir = JniString(env, native_library_dir).str();
        const std::string scope = JniString(env, scope_key).str();
        const auto query = jfloat_vector(env, query_vector);
        bool sqlite_searched = false;
        bool hnsw_searched = false;
        std::string sqlite_error;
        std::string hnsw_error;
        std::vector<SearchItem> items = search_sqlite_vec(
            db_path,
            lib_dir,
            scope,
            query,
            static_cast<int>(event_top_k),
            &sqlite_searched,
            &sqlite_error);
        auto hnsw_items = search_hnsw(
            scope,
            query,
            static_cast<int>(semantic_top_k),
            &hnsw_searched,
            &hnsw_error);
        items.insert(
            items.end(),
            std::make_move_iterator(hnsw_items.begin()),
            std::make_move_iterator(hnsw_items.end()));
        return to_jstring(env, search_json(sqlite_searched, hnsw_searched, items, sqlite_error, hnsw_error));
    } catch (const std::exception &exception) {
        return to_jstring(
            env,
            std::string("{\"ok\":false,\"error\":")
                + json_string(exception.what())
                + ",\"items\":[],\"warnings\":[\"native_search_failed\"]}");
    }
}
