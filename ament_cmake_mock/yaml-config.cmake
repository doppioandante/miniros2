# Mock: point yaml find_package at system libyaml
find_library(yaml_LIBRARY NAMES yaml yaml-0 REQUIRED)
find_path(yaml_INCLUDE_DIR NAMES yaml.h REQUIRED)

if(NOT TARGET yaml)
  add_library(yaml SHARED IMPORTED)
  set_target_properties(yaml PROPERTIES
    IMPORTED_LOCATION "${yaml_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${yaml_INCLUDE_DIR}"
  )
endif()

set(yaml_FOUND TRUE)
set(yaml_VERSION "0.2.5")
