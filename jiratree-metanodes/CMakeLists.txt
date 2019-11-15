# CMakeLists.txt
cmake_minimum_required(VERSION 2.8.11)

set(VRTREE_SDK_DIR "" CACHE STRING "Location of the VRTree SDK")

project(jiratree)

include_directories(${VRTREE_SDK_DIR}/include)
link_directories(${VRTREE_SDK_DIR}/lib/x64)

add_library(jiratree SHARED main.cpp)
target_link_libraries(jiratree vrtree-linker)