cmake_minimum_required(VERSION 3.16)
project(ThirteenCardsCpp LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(thirteen_cards_cpp SHARED
    src/cpp/manager.cpp
    src/cpp/pattern/pattern.cpp
    src/cpp/pattern/searchPattern.cpp
    src/cpp/pattern/dfs.cpp
    src/cpp/players/player.cpp
    src/cpp/players/interaction.cpp
    src/cpp/round/dealer.cpp
    src/cpp/round/evaluate.cpp
    src/cpp/round/closer.cpp
)

target_include_directories(thirteen_cards_cpp
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp/pattern
        ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp/players
        ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp/cards
        ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp/round
)
