# Mock for ament_cmake_gen_version_h
# ament_generate_version_header(PROJECT_NAME) generates include/<pkg>/version.h
macro(ament_generate_version_header _pkg_name)
  string(TOUPPER "${_pkg_name}" _VER_UPPER)
  string(REPLACE "-" "_" _VER_UPPER "${_VER_UPPER}")
  set(_ver_dir "${CMAKE_CURRENT_BINARY_DIR}/include/${_pkg_name}")
  file(MAKE_DIRECTORY "${_ver_dir}")
  file(WRITE "${_ver_dir}/version.h"
"#pragma once
#define ${_VER_UPPER}_VERSION_MAJOR 0
#define ${_VER_UPPER}_VERSION_MINOR 0
#define ${_VER_UPPER}_VERSION_PATCH 0
#define ${_VER_UPPER}_VERSION \"0.0.0\"
")
  # Make the generated header findable
  if(TARGET ${_pkg_name})
    target_include_directories(${_pkg_name} PUBLIC
      "$<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>")
    # Real ament_cmake defines ROS_PACKAGE_NAME for every target; the logging
    # macros (RCUTILS_LOG_*_NAMED) reference it. Provide it here.
    target_compile_definitions(${_pkg_name} PRIVATE
      "ROS_PACKAGE_NAME=\"${_pkg_name}\"")
  endif()
endmacro()
