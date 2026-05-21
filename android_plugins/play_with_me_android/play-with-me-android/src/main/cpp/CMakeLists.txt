cmake_minimum_required(VERSION 3.22.1)

project(playwithme_native)

add_library(sqlite3_amalgamation STATIC third_party/sqlite/sqlite3.c)
target_compile_definitions(
    sqlite3_amalgamation
    PRIVATE
    SQLITE_THREADSAFE=1
    SQLITE_ENABLE_LOAD_EXTENSION
    SQLITE_ENABLE_FTS5
)
target_include_directories(
    sqlite3_amalgamation
    PUBLIC
    "${CMAKE_CURRENT_LIST_DIR}/third_party/sqlite"
)

add_library(sherpa_onnx_c_api SHARED IMPORTED)
set_target_properties(
    sherpa_onnx_c_api
    PROPERTIES
    IMPORTED_LOCATION
    "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libsherpa-onnx-c-api.so"
)

add_library(playwithme_kokoro_jni SHARED kokoro_jni.cpp)

target_link_libraries(
    playwithme_kokoro_jni
    sherpa_onnx_c_api
    log
)

add_library(playwithme_memory_jni SHARED memory_vector_jni.cpp)

target_include_directories(
    playwithme_memory_jni
    PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/third_party/sqlite"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/hnswlib"
)

target_link_libraries(
    playwithme_memory_jni
    sqlite3_amalgamation
    log
    dl
)
