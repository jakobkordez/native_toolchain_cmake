cmake_minimum_required(VERSION 3.15)
project(add_link VERSION 1.0 LANGUAGES C)

# No SHARED or STATIC, CMakeBuilder.staticWhenLinking sets BUILD_SHARED_LIBS.
add_library(add_link src/add_link.c)
if(ANDROID)
    target_link_options(add_link PRIVATE "-Wl,-z,max-page-size=16384")
endif()

install(TARGETS add_link DESTINATION lib)
