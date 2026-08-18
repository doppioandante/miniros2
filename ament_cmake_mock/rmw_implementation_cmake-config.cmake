get_filename_component(_ament_mock_dir "${CMAKE_CURRENT_LIST_FILE}" PATH)
include("${_ament_mock_dir}/ament_cmake_mock.cmake")

# Load the real rmw_implementation_cmake macros
set(_rmw_impl_cmake_src "${CMAKE_CURRENT_LIST_DIR}/../../../rmw/rmw_implementation_cmake")
if(NOT EXISTS "${_rmw_impl_cmake_src}")
  # Try relative to source root
  set(_rmw_impl_cmake_src "${CMAKE_SOURCE_DIR}/rmw/rmw_implementation_cmake")
endif()

if(EXISTS "${_rmw_impl_cmake_src}/cmake")
  list(APPEND CMAKE_MODULE_PATH "${_rmw_impl_cmake_src}/cmake")
  include("${_rmw_impl_cmake_src}/cmake/get_available_rmw_implementations.cmake")
  include("${_rmw_impl_cmake_src}/cmake/get_default_rmw_implementation.cmake")
  include("${_rmw_impl_cmake_src}/cmake/call_for_each_rmw_implementation.cmake")
endif()

# Also load register_rmw_implementation from rmw package
set(_rmw_src "${CMAKE_SOURCE_DIR}/rmw/rmw")
if(EXISTS "${_rmw_src}/cmake/register_rmw_implementation.cmake")
  include("${_rmw_src}/cmake/register_rmw_implementation.cmake")
endif()

# Override the discovery macros to avoid needing a real ament index
macro(get_available_rmw_implementations _out_var)
  if(NOT "${RMW_IMPLEMENTATION}" STREQUAL "")
    set(${_out_var} "${RMW_IMPLEMENTATION}")
  else()
    set(${_out_var} "rmw_implementation")
  endif()
endmacro()

macro(get_default_rmw_implementation _out_var)
  if(NOT "${RMW_IMPLEMENTATION}" STREQUAL "")
    set(${_out_var} "${RMW_IMPLEMENTATION}")
  else()
    set(${_out_var} "rmw_implementation")
  endif()
endmacro()

set(rmw_implementation_cmake_FOUND TRUE)
