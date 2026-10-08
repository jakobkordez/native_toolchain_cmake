# Included after every project() call (via CMAKE_PROJECT_INCLUDE, CMake 3.15+) when
# CMakeBuilder.staticWhenLinking is set and the build hook runs with linking enabled.
#
# Puts every function and data item into its own section, so the link hook can drop
# unused code at function granularity (--gc-sections, /OPT:REF). Apple's ld64 already
# does this with -dead_strip, so AppleClang is left alone.

foreach(_ntc_lang IN ITEMS C CXX)
  if(NOT CMAKE_${_ntc_lang}_COMPILER_LOADED)
    continue()
  endif()
  if(CMAKE_${_ntc_lang}_COMPILER_ID STREQUAL "MSVC" OR CMAKE_${_ntc_lang}_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    set(_ntc_flags "/Gy /Gw")
  elseif(CMAKE_${_ntc_lang}_COMPILER_ID MATCHES "^(GNU|Clang)$")
    set(_ntc_flags "-ffunction-sections -fdata-sections")
  else()
    continue()
  endif()
  # project() may run several times, e.g. for subprojects; append only once.
  string(FIND " ${CMAKE_${_ntc_lang}_FLAGS} " " ${_ntc_flags} " _ntc_found)
  if(_ntc_found EQUAL -1)
    string(APPEND CMAKE_${_ntc_lang}_FLAGS " ${_ntc_flags}")
  endif()
endforeach()

unset(_ntc_lang)
unset(_ntc_flags)
unset(_ntc_found)
