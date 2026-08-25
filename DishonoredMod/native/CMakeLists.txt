cmake_minimum_required(VERSION 3.16)
project(DishonoredModKit CXX)

# Игра 32-битная (бинарники в Binaries\Win32), поэтому DLL обязана быть x86.
# 64-битная библиотека в 32-битный процесс просто не загрузится, а сообщение
# от загрузчика при этом настолько невнятное, что проверку лучше сделать здесь.
if(CMAKE_SIZEOF_VOID_P GREATER 4)
    message(FATAL_ERROR
        "Нужна 32-битная сборка: игра x86.\n"
        "  MSVC:  cmake -A Win32 -B build\n"
        "  MinGW: cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-i686.cmake")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(DishonoredModKit SHARED
    src/dllmain.cpp
    src/detour.cpp
    src/log.cpp
    src/mode.cpp
    src/modes/bodyswap.cpp
    src/modes/dump.cpp
    src/modes/roleplay.cpp
    src/proxy_dinput8.cpp
    src/sigscan.cpp
    src/ue3detect.cpp
    src/ue3names.cpp
)

# Плагин сам является прокси-библиотекой dinput8: игра честно импортирует её
# (подтверждено diagnose.exe), поэтому сторонний загрузчик не нужен.
# Файл определений даёт неукрашенные имена экспортов.
set_target_properties(DishonoredModKit PROPERTIES
    PREFIX ""
    SUFFIX ".dll"
    OUTPUT_NAME "dinput8"
    LINK_FLAGS "\"${CMAKE_CURRENT_SOURCE_DIR}/dinput8.def\""
)

if(MSVC)
    target_compile_options(DishonoredModKit PRIVATE /W4 /permissive-)
else()
    target_compile_options(DishonoredModKit PRIVATE -Wall -Wextra)
    # Своей C++-рантайм-библиотеки у игры нет, а тащить рядом с модом
    # libstdc++ и libgcc — лишний источник «не найдена DLL» у пользователя.
    target_link_options(DishonoredModKit PRIVATE
        -static-libgcc -static-libstdc++ -static)
endif()
