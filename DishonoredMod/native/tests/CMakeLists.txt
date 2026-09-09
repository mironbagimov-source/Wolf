cmake_minimum_required(VERSION 3.16)
project(DishonoredModKitTests CXX)

# Тесты собираются под хост, а не под Windows: проверяемая логика не трогает
# windows.h ровно ради этого. Гонять их можно на любой машине, включая ту, где
# игры нет.
#
#     cmake -B build tests && cmake --build build && ./build/test_bytepattern

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(test_bytepattern test_bytepattern.cpp)
target_include_directories(test_bytepattern PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_compile_options(test_bytepattern PRIVATE -Wall -Wextra)

add_executable(test_ue3detect test_ue3detect.cpp)
target_include_directories(test_ue3detect PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_compile_options(test_ue3detect PRIVATE -Wall -Wextra)

add_executable(test_ue3patch test_ue3patch.cpp)
target_include_directories(test_ue3patch PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_compile_options(test_ue3patch PRIVATE -Wall -Wextra)

add_executable(test_roles test_roles.cpp)
target_include_directories(test_roles PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../src)
target_compile_options(test_roles PRIVATE -Wall -Wextra)

enable_testing()
add_test(NAME bytepattern COMMAND test_bytepattern)
add_test(NAME ue3detect COMMAND test_ue3detect)
add_test(NAME ue3patch COMMAND test_ue3patch)
add_test(NAME roles COMMAND test_roles)
