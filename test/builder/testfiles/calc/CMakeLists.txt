cmake_minimum_required(VERSION 3.15)
project(test_calc VERSION 1.0 LANGUAGES C)

# No SHARED or STATIC, BUILD_SHARED_LIBS decides.
add_library(calc src/calc.c src/calc.h)
if(ANDROID)
    target_link_options(calc PRIVATE "-Wl,-z,max-page-size=16384")
endif()

# Lets tests check the flags added by CMakeBuilder.staticWhenLinking.
file(WRITE "${CMAKE_BINARY_DIR}/c_flags.txt" "${CMAKE_C_FLAGS}")

install(TARGETS calc DESTINATION lib)
