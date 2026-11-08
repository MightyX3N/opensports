cmake_minimum_required(VERSION 3.20)
project(osble LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded") # static CRT: no extra DLLs to ship
add_library(osble SHARED osble.cpp)
target_compile_options(osble PRIVATE /EHsc /permissive- /W3 /bigobj)
target_link_libraries(osble PRIVATE windowsapp)
