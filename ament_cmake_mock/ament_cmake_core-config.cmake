get_filename_component(_ament_mock_dir "${CMAKE_CURRENT_LIST_FILE}" PATH)
include("${_ament_mock_dir}/ament_cmake_mock.cmake")

# normalize_path(OUTPUT_VAR input_path): resolves . and .. in a path
macro(normalize_path _out_var _in_path)
  get_filename_component(${_out_var} "${_in_path}" ABSOLUTE)
endmacro()
