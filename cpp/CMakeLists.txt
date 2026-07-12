cmake_minimum_required(VERSION 3.16)
project(ThirteenCardsCpp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(thirteen_cards_cpp SHARED
    manager.cpp
    pattern/pattern.cpp
    pattern/searchPattern.cpp
    pattern/names.cpp
    pattern/dfs.cpp
    players/player.cpp
    players/interaction.cpp
    round/dealer.cpp
    round/evaluate.cpp
    round/closer.cpp
    game/game.cpp
)

set_target_properties(thirteen_cards_cpp PROPERTIES
    PREFIX ""
    OUTPUT_NAME "libthirteen_cards_cpp"
)

target_include_directories(thirteen_cards_cpp
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/pattern
        ${CMAKE_CURRENT_SOURCE_DIR}/players
        ${CMAKE_CURRENT_SOURCE_DIR}/cards
        ${CMAKE_CURRENT_SOURCE_DIR}/round
)

if(MSVC)
    target_compile_options(thirteen_cards_cpp PRIVATE /utf-8)
    target_compile_definitions(thirteen_cards_cpp PRIVATE _CRT_SECURE_NO_WARNINGS)
    set_target_properties(thirteen_cards_cpp PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

# ---- ONNX Runtime wrapper (独立库，链接 onnxruntime) ----
# ONNX Runtime — 查找头文件和库
set(ONNXRT_BASE "${CMAKE_CURRENT_SOURCE_DIR}/../flutter/android/onnxruntime")
if(EXISTS "${ONNXRT_BASE}/include/onnxruntime_c_api.h")
    set(ONNXRT_INCLUDE_DIR "${ONNXRT_BASE}/include")
    message(STATUS "ONNXRT headers: ${ONNXRT_INCLUDE_DIR}")
elseif(DEFINED ONNXRT_HOME AND EXISTS "${ONNXRT_HOME}/include/onnxruntime_c_api.h")
    set(ONNXRT_INCLUDE_DIR "${ONNXRT_HOME}/include")
    message(STATUS "ONNXRT headers: ${ONNXRT_INCLUDE_DIR} (from ONNXRT_HOME)")
else()
    message(STATUS "ONNXRT headers NOT found")
endif()

if(ONNXRT_INCLUDE_DIR)
    find_library(ONNXRT_LIBRARY onnxruntime
        HINTS
            "${CMAKE_CURRENT_SOURCE_DIR}/../flutter/android/app/src/main/jniLibs/arm64-v8a"
            "${ONNXRT_BASE}/lib"
    )
    if(ONNXRT_LIBRARY)
        message(STATUS "ONNXRT library: ${ONNXRT_LIBRARY}")
    else()
        message(STATUS "ONNXRT library NOT found — only libthirteen_cards_cpp will be built")
    endif()
endif()

if(ONNXRT_INCLUDE_DIR AND ONNXRT_LIBRARY)
    add_library(onnx_thirteen SHARED onnx_thirteen.c)
    target_include_directories(onnx_thirteen PRIVATE ${ONNXRT_INCLUDE_DIR})
    target_link_libraries(onnx_thirteen PRIVATE ${ONNXRT_LIBRARY})
    target_compile_options(onnx_thirteen PRIVATE -fvisibility=default)
    set_target_properties(onnx_thirteen PROPERTIES
        PREFIX ""
        OUTPUT_NAME "libonnx_thirteen"
    )
    message(STATUS "ONNX Runtime found: ${ONNXRT_LIBRARY}")
else()
    message(STATUS "ONNX Runtime NOT found — onnx_thirteen will not be built")
endif()

include(CTest)
if(BUILD_TESTING)
    add_executable(thirteen_game_flow_test tests/game_flow_test.cpp)
    target_link_libraries(thirteen_game_flow_test PRIVATE thirteen_cards_cpp)
    target_include_directories(thirteen_game_flow_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    if(MSVC)
        target_compile_options(thirteen_game_flow_test PRIVATE /utf-8)
    endif()
    add_custom_command(TARGET thirteen_game_flow_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                $<TARGET_FILE:thirteen_cards_cpp>
                $<TARGET_FILE_DIR:thirteen_game_flow_test>)
    add_test(NAME thirteen_game_flow COMMAND thirteen_game_flow_test)
endif()
