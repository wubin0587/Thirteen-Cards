cmake_minimum_required(VERSION 3.16)
project(ThirteenCardsCpp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(thirteen_cards_cpp SHARED
    manager.cpp
    pattern/pattern.cpp
    pattern/searchPattern.cpp
    # DFS 枚举实现（pattern/dfs.cpp）注册到共享库
    pattern/dfs.cpp
    players/player.cpp
    players/interaction.cpp
    round/dealer.cpp
    round/evaluate.cpp
    round/closer.cpp
)

target_include_directories(thirteen_cards_cpp
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/pattern
        ${CMAKE_CURRENT_SOURCE_DIR}/players
        ${CMAKE_CURRENT_SOURCE_DIR}/cards
        ${CMAKE_CURRENT_SOURCE_DIR}/round
)