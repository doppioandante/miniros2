# Mock: libyaml is already installed system-wide
find_library(yaml_LIBRARY NAMES yaml yaml-0
  HINTS /usr/lib/x86_64-linux-gnu
  NO_DEFAULT_PATH)
if(NOT yaml_LIBRARY)
  # Fall back to the versioned .so directly
  find_file(yaml_LIBRARY NAMES libyaml-0.so.2
    HINTS /usr/lib/x86_64-linux-gnu)
endif()
if(NOT yaml_LIBRARY)
  message(FATAL_ERROR "Could not find libyaml. Install libyaml-dev: sudo apt install libyaml-dev")
endif()
find_path(yaml_INCLUDE_DIR NAMES yaml.h
  HINTS /usr/include
  NO_DEFAULT_PATH)

if(NOT TARGET yaml)
  add_library(yaml SHARED IMPORTED)
  set_target_properties(yaml PROPERTIES
    IMPORTED_LOCATION "${yaml_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${yaml_INCLUDE_DIR}"
  )
endif()

set(libyaml_vendor_FOUND TRUE)
