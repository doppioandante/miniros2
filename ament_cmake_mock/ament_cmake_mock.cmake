# Stub implementations of ament_cmake macros for standalone builds.
# Goal: compile .so files, everything else is a no-op.

# Accumulator for ament_export_dependencies calls within current package scope.
# Reset at the start of ament_package().
set(_ament_mock_exported_deps "")

macro(ament_export_dependencies)
  # Collect deps so ament_package can re-export them in the Config
  list(APPEND _ament_mock_exported_deps ${ARGN})
endmacro()

macro(ament_export_include_directories)
endmacro()

# Newer ament_cmake_ros: sets default compiler options / C++ standard.
# A no-op is fine here; the top-level build already sets the standard it needs.
macro(ament_add_default_options)
endmacro()

macro(ament_export_libraries)
endmacro()

macro(ament_export_targets)
endmacro()

macro(ament_export_link_flags)
endmacro()

macro(ament_export_development_version_if_higher_than_manifest)
endmacro()

macro(ament_lint_auto_find_test_dependencies)
endmacro()

macro(ament_cppcheck)
endmacro()

# Resource index: maps resource_type → list of package names.
# Stored as CACHE INTERNAL so it persists across directory scopes.
#
# Also records, per-package, which resource types it registered (plus the
# CONTENT string, if any) so ament_package() can install real ament_index
# marker files (share/ament_index/resource_index/<type>/<pkg>) for runtime
# lookup via ament_index_cpp (needed for RMW runtime implementation selection).
function(ament_index_register_resource _resource_type)
  cmake_parse_arguments(_air "" "CONTENT" "" ${ARGN})

  set(_air_cur "$CACHE{AMENT_INDEX_RESOURCE_${_resource_type}}")
  if(NOT "${PROJECT_NAME}" IN_LIST _air_cur)
    list(APPEND _air_cur "${PROJECT_NAME}")
  endif()
  set(AMENT_INDEX_RESOURCE_${_resource_type} "${_air_cur}" CACHE INTERNAL "" FORCE)

  set(_air_pkg_types "$CACHE{AMENT_INDEX_PKG_RESOURCE_TYPES_${PROJECT_NAME}}")
  if(NOT "${_resource_type}" IN_LIST _air_pkg_types)
    list(APPEND _air_pkg_types "${_resource_type}")
  endif()
  set(AMENT_INDEX_PKG_RESOURCE_TYPES_${PROJECT_NAME} "${_air_pkg_types}" CACHE INTERNAL "" FORCE)
  # Marker-file content is informational only (nothing here parses it back);
  # only its presence matters for ament_index_cpp runtime lookups, so this is
  # a best-effort single-line capture rather than a byte-exact copy.
  string(REPLACE ";" " " _air_content_flat "${_air_CONTENT}")
  string(REPLACE "\n" " " _air_content_flat "${_air_content_flat}")
  set(AMENT_INDEX_PKG_RESOURCE_CONTENT_${PROJECT_NAME}_${_resource_type} "${_air_content_flat}" CACHE INTERNAL "" FORCE)
endfunction()

macro(ament_index_get_resources _out_var _resource_type)
  set(${_out_var} "$CACHE{AMENT_INDEX_RESOURCE_${_resource_type}}")
endmacro()

macro(ament_index_get_resource)
endmacro()

macro(ament_register_extension _ext_point _pkg_name _cmake_file)
  # Store as "pkg_name:cmake_file" in a global list keyed by extension point.
  # Use CACHE INTERNAL so the list persists across directory/function scopes.
  set(_ament_reg_cur "$CACHE{AMENT_EXTENSIONS_${_ext_point}}")
  if(NOT "${_pkg_name}:${_cmake_file}" IN_LIST _ament_reg_cur)
    list(APPEND _ament_reg_cur "${_pkg_name}:${_cmake_file}")
  endif()
  set(AMENT_EXTENSIONS_${_ext_point} "${_ament_reg_cur}" CACHE INTERNAL "" FORCE)
endmacro()

macro(ament_execute_extensions _ext_point)
  if(DEFINED AMENT_EXTENSIONS_${_ext_point})
    foreach(_ext_entry ${AMENT_EXTENSIONS_${_ext_point}})
      string(REPLACE ":" ";" _ext_list "${_ext_entry}")
      list(GET _ext_list 0 _ext_pkg)
      list(GET _ext_list 1 _ext_file)
      # Resolve cmake file via the package's _DIR (set to cmake/ by ament_package mock)
      if(DEFINED ${_ext_pkg}_DIR AND EXISTS "${${_ext_pkg}_DIR}/${_ext_file}")
        include("${${_ext_pkg}_DIR}/${_ext_file}")
      else()
        message(WARNING "ament_execute_extensions: cannot find ${_ext_file} for package ${_ext_pkg} (${_ext_pkg}_DIR=${${_ext_pkg}_DIR})")
      endif()
    endforeach()
  endif()
endmacro()

macro(stamp)
endmacro()

# Parse package.xml to extract name and group memberships
macro(list_append_unique _list)
  foreach(_item ${ARGN})
    if(NOT _item IN_LIST ${_list})
      list(APPEND ${_list} "${_item}")
    endif()
  endforeach()
endmacro()

macro(ament_package_xml)
  set(_AMENT_PACKAGE_NAME "${PROJECT_NAME}")
  # Parse member_of_group from package.xml
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/package.xml")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/package.xml" _pkg_xml_content)
    string(REGEX MATCHALL "<member_of_group>([^<]+)</member_of_group>"
      _group_matches "${_pkg_xml_content}")
    set(${PROJECT_NAME}_MEMBER_OF_GROUPS "")
    foreach(_match ${_group_matches})
      string(REGEX REPLACE "<member_of_group>([^<]+)</member_of_group>" "\\1"
        _group_name "${_match}")
      list(APPEND ${PROJECT_NAME}_MEMBER_OF_GROUPS "${_group_name}")
    endforeach()
  endif()
endmacro()

# Write config into the build tree so sibling subdirs can find this package.
macro(ament_package)
  cmake_parse_arguments(_ap "" "" "CONFIG_EXTRAS" ${ARGN})

  # Run ament_package hooks (e.g. rosidl_cmake_package_hook sets ${PROJECT_NAME}_IDL_FILES
  # in a generated cmake extra file and appends it to ${PROJECT_NAME}_CONFIG_EXTRAS).
  ament_execute_extensions("ament_package")
  # Collect any extras that hooks appended to ${PROJECT_NAME}_CONFIG_EXTRAS
  list(APPEND _ap_CONFIG_EXTRAS ${${PROJECT_NAME}_CONFIG_EXTRAS})
  # CONFIG_EXTRAS_POST run after the main extras (e.g. the rosidl aggregate
  # target hook, which needs ${PROJECT_NAME}_TARGETS already populated).
  set(_ap_CONFIG_EXTRAS_POST ${${PROJECT_NAME}_CONFIG_EXTRAS_POST})

  set(_build_cfg_dir "${CMAKE_BINARY_DIR}/ament_mock_configs/${PROJECT_NAME}")
  file(MAKE_DIRECTORY "${_build_cfg_dir}")

  set(_src_dir "${CMAKE_CURRENT_SOURCE_DIR}")

  # Create namespace alias/target for usage as pkg::pkg in current scope
  if(TARGET ${PROJECT_NAME})
    get_target_property(_target_type ${PROJECT_NAME} TYPE)
    get_target_property(_target_imported ${PROJECT_NAME} IMPORTED)
    if(NOT _target_imported AND NOT TARGET ${PROJECT_NAME}::${PROJECT_NAME})
      if(_target_type STREQUAL "STATIC_LIBRARY" OR
         _target_type STREQUAL "SHARED_LIBRARY" OR
         _target_type STREQUAL "MODULE_LIBRARY" OR
         _target_type STREQUAL "INTERFACE_LIBRARY")
        add_library(${PROJECT_NAME}::${PROJECT_NAME} ALIAS ${PROJECT_NAME})
      endif()
      # UTILITY targets (custom targets from rosidl) cannot be aliased
    endif()
  endif()

  # Some packages (e.g. rmw_dds_common) name their library target
  # ${PROJECT_NAME}_library and consumers link it as pkg::pkg_library.
  # Since everything is built in one add_subdirectory tree, an in-scope ALIAS
  # is enough for downstream find_package()/target_link_libraries to resolve.
  if(TARGET ${PROJECT_NAME}_library AND
     NOT TARGET ${PROJECT_NAME}::${PROJECT_NAME}_library)
    get_target_property(_lib_imported ${PROJECT_NAME}_library IMPORTED)
    if(NOT _lib_imported)
      add_library(${PROJECT_NAME}::${PROJECT_NAME}_library ALIAS ${PROJECT_NAME}_library)
    endif()
  endif()
  # Only create fallback INTERFACE target if package has no CONFIG_EXTRAS.
  # Packages with CONFIG_EXTRAS create their own :: target from the extras cmake.
  if(NOT _ap_CONFIG_EXTRAS AND NOT TARGET ${PROJECT_NAME}::${PROJECT_NAME})
    add_library(${PROJECT_NAME}::${PROJECT_NAME} INTERFACE IMPORTED GLOBAL)
    if(EXISTS "${_src_dir}/include")
      target_include_directories(${PROJECT_NAME}::${PROJECT_NAME}
        INTERFACE "${_src_dir}/include")
    endif()
  endif()

  # --- Build the Config.cmake content ---
  set(_cfg_content "# Build-tree config generated by ament_cmake_mock
# Re-entry guard: prevent infinite recursion when extras call find_package(${PROJECT_NAME})
if(_ament_mock_${PROJECT_NAME}_loading)
  return()
endif()
set(_ament_mock_${PROJECT_NAME}_loading TRUE)
set(${PROJECT_NAME}_FOUND TRUE)
set(${PROJECT_NAME}_INCLUDE_DIRS \"${_src_dir}/include\")
set(${PROJECT_NAME}_LIBRARIES ${PROJECT_NAME})
set(${PROJECT_NAME}_DIR \"${_build_cfg_dir}\")
")

  # For rosidl message packages, set DATADIR and also redirect _DIR so that
  # ${pkg}_DIR/.. resolves to the type_description output dir (used by downstream
  # rosidl_generator_type_description to locate dependency JSON files).
  # The type description generator outputs to:
  #   ${CMAKE_CURRENT_BINARY_DIR}/rosidl_generator_type_description/${PROJECT_NAME}/
  # IDL adapter outputs to:
  #   ${CMAKE_CURRENT_BINARY_DIR}/rosidl_adapter/${PROJECT_NAME}/
  set(_type_desc_dir "${CMAKE_CURRENT_BINARY_DIR}/rosidl_generator_type_description/${PROJECT_NAME}")
  set(_adapted_idl_dir "${CMAKE_CURRENT_BINARY_DIR}/rosidl_adapter/${PROJECT_NAME}")
  if(_rosidl_cmake_IDL_FILES OR _rosidl_cmake_INTERFACE_FILES)
    # This is a rosidl message package. Set two path variables for downstream generators:
    #
    # DATADIR: rosidl_find_package_idl() uses this first to locate .idl files.
    #   Points to the rosidl_adapter output dir where the adapted .idl files live.
    string(APPEND _cfg_content "set(${PROJECT_NAME}_DATADIR \"${_adapted_idl_dir}\")\n")
    #
    # rosidl_typesupport_c/_cpp (upstream, unpatched) resolves *dependency* IDL
    # files with the raw install-layout expression `${${pkg}_DIR}/../${idl_file}`
    # instead of the DATADIR-aware helper. To keep that working without patching
    # rosidl_typesupport, mirror each adapted .idl file into the type_description
    # output tree (which _DIR/.. already points at, see below), so both the raw
    # path expression and rosidl_generator_type_description's INCLUDE_PATHS
    # resolve against the same directory.
    foreach(_idl_rel ${_rosidl_cmake_IDL_FILES})
      get_filename_component(_idl_rel_dir "${_idl_rel}" DIRECTORY)
      file(MAKE_DIRECTORY "${_type_desc_dir}/${_idl_rel_dir}")
      file(COPY "${_adapted_idl_dir}/${_idl_rel}" DESTINATION "${_type_desc_dir}/${_idl_rel_dir}")
    endforeach()
    #
    # _DIR/.. : rosidl_generator_type_description_generate_interfaces.cmake uses this
    #   to build include paths for finding dependency .json type-hash files.
    #   By pointing _DIR one level inside the type_description output, _DIR/.. resolves
    #   to the type_description output dir containing the msg/*.json files.
    string(APPEND _cfg_content "set(${PROJECT_NAME}_DIR \"${_type_desc_dir}/cmake\")\n")
  endif()

  # Re-export dependencies: find_package them so their macros are available
  foreach(_dep ${_ament_mock_exported_deps})
    string(APPEND _cfg_content "find_package(${_dep} QUIET)\n")
  endforeach()

  # Set _DIR to the cmake/ subdirectory (real ament does this so extras can use ${PKG_DIR}/foo.cmake)
  if(EXISTS "${_src_dir}/cmake")
    string(APPEND _cfg_content "set(${PROJECT_NAME}_DIR \"${_src_dir}/cmake\")\n")
    string(APPEND _cfg_content "list(APPEND CMAKE_MODULE_PATH \"${_src_dir}/cmake\")\n")
  endif()

  # For packages without CONFIG_EXTRAS, ensure a :: target exists in the Config.cmake.
  # Packages with CONFIG_EXTRAS typically create the :: target themselves in their extras cmake.
  if(NOT _ap_CONFIG_EXTRAS)
    string(APPEND _cfg_content "if(NOT TARGET ${PROJECT_NAME}::${PROJECT_NAME})
  add_library(${PROJECT_NAME}::${PROJECT_NAME} INTERFACE IMPORTED GLOBAL)
  if(EXISTS \"${_src_dir}/include\")
    target_include_directories(${PROJECT_NAME}::${PROJECT_NAME}
      INTERFACE \"${_src_dir}/include\")
  endif()
endif()
")
  endif()

  # Include CONFIG_EXTRAS (.cmake included directly; .cmake.in processed via configure_file)
  foreach(_extra ${_ap_CONFIG_EXTRAS})
    if(_extra MATCHES "\\.cmake\\.in$")
      # Write the processed file into the source cmake/ dir so that CMAKE_CURRENT_LIST_DIR
      # resolves correctly when the file is included (e.g. for relative include() calls inside it).
      get_filename_component(_in_name "${_extra}" NAME)
      string(REGEX REPLACE "\\.in$" "" _out_name "${_in_name}")
      set(_in_path "${_src_dir}/${_extra}")
      set(_out_path "${_src_dir}/cmake/${_out_name}")
      file(MAKE_DIRECTORY "${_src_dir}/cmake")
      configure_file("${_in_path}" "${_out_path}" @ONLY)
      # Append source-tree path fixup after the template-generated calls.
      # The template uses ${PKG_DIR}/../../../lib/PKG/PKG for BIN, which assumes install layout.
      # We patch the known variables to point at the actual source-tree locations.
      if(EXISTS "${_src_dir}/bin/${PROJECT_NAME}")
        file(APPEND "${_out_path}"
          "\n# Standalone build: override paths to use source tree locations\n"
          "if(NOT EXISTS \"\${${PROJECT_NAME}_BIN}\")\n"
          "  set(${PROJECT_NAME}_BIN \"\${CMAKE_CURRENT_LIST_DIR}/../bin/${PROJECT_NAME}\")\n"
          "endif()\n"
          "if(NOT EXISTS \"\${${PROJECT_NAME}_GENERATOR_FILES}\")\n"
          "  set(${PROJECT_NAME}_GENERATOR_FILES \"\${CMAKE_CURRENT_LIST_DIR}/../${PROJECT_NAME}/__init__.py\")\n"
          "endif()\n"
          "if(NOT EXISTS \"\${${PROJECT_NAME}_TEMPLATE_DIR}\")\n"
          "  set(${PROJECT_NAME}_TEMPLATE_DIR \"\${CMAKE_CURRENT_LIST_DIR}/../resource\")\n"
          "endif()\n"
        )
      endif()
      string(APPEND _cfg_content "include(\"${_out_path}\" OPTIONAL)\n")
    elseif(IS_ABSOLUTE "${_extra}")
      string(APPEND _cfg_content "include(\"${_extra}\" OPTIONAL)\n")
    else()
      string(APPEND _cfg_content "include(\"${_src_dir}/${_extra}\" OPTIONAL)\n")
    endif()
  endforeach()

  # Aggregate the per-typesupport target lists (e.g. ${PKG}_TARGETS__rosidl_generator_c,
  # populated by the rosidl typesupport-targets extras above) into the single
  # convenience variable ${PKG}_TARGETS that downstream packages (e.g. rcl) link against.
  # This must happen after the CONFIG_EXTRAS includes but before CONFIG_EXTRAS_POST,
  # since the aggregate-target hook reads ${PKG}_TARGETS.
  string(APPEND _cfg_content
"if(NOT DEFINED ${PROJECT_NAME}_TARGETS)
  set(${PROJECT_NAME}_TARGETS \"\")
  foreach(_ts_suffix __rosidl_generator_c __rosidl_typesupport_c __rosidl_typesupport_introspection_c __rosidl_generator_cpp __rosidl_typesupport_cpp __rosidl_typesupport_introspection_cpp)
    if(DEFINED ${PROJECT_NAME}_TARGETS\${_ts_suffix})
      list(APPEND ${PROJECT_NAME}_TARGETS \${${PROJECT_NAME}_TARGETS\${_ts_suffix}})
    endif()
  endforeach()
endif()
")

  # Include CONFIG_EXTRAS_POST (after main extras and after _TARGETS aggregation).
  foreach(_extra ${_ap_CONFIG_EXTRAS_POST})
    string(APPEND _cfg_content "include(\"${_extra}\" OPTIONAL)\n")
  endforeach()

  # Unset the re-entry guard at the very end so future find_package() calls can re-enter.
  string(APPEND _cfg_content "unset(_ament_mock_${PROJECT_NAME}_loading)\n")

  file(WRITE "${_build_cfg_dir}/${PROJECT_NAME}Config.cmake" "${_cfg_content}")

  # Register in CMAKE_PREFIX_PATH so sibling subdirs find this package
  list(APPEND CMAKE_PREFIX_PATH "${_build_cfg_dir}")
  set(CMAKE_PREFIX_PATH "${CMAKE_PREFIX_PATH}" PARENT_SCOPE)

  # Reset exported deps accumulator
  set(_ament_mock_exported_deps "")

  # Install real ament_index resource_index marker files for this package, so
  # that runtime lookups via ament_index_cpp (e.g. RMW runtime implementation
  # selection) can find it under AMENT_PREFIX_PATH/share/ament_index/resource_index/<type>/<pkg>.
  foreach(_air_type ${AMENT_INDEX_PKG_RESOURCE_TYPES_${PROJECT_NAME}})
    set(_air_marker_dir "${CMAKE_BINARY_DIR}/ament_index_markers/${_air_type}")
    file(MAKE_DIRECTORY "${_air_marker_dir}")
    set(_air_marker_file "${_air_marker_dir}/${PROJECT_NAME}")
    file(WRITE "${_air_marker_file}" "${AMENT_INDEX_PKG_RESOURCE_CONTENT_${PROJECT_NAME}_${_air_type}}")
    install(FILES "${_air_marker_file}"
      DESTINATION "share/ament_index/resource_index/${_air_type}")
  endforeach()

  # Install rules (only for real installable library/executable targets, no EXPORT to avoid
  # issues with IMPORTED transitive deps)
  if(TARGET ${PROJECT_NAME})
    get_target_property(_ap_target_type ${PROJECT_NAME} TYPE)
    get_target_property(_ap_imported ${PROJECT_NAME} IMPORTED)
    if(NOT _ap_imported AND
       (_ap_target_type STREQUAL "STATIC_LIBRARY" OR
        _ap_target_type STREQUAL "SHARED_LIBRARY" OR
        _ap_target_type STREQUAL "MODULE_LIBRARY" OR
        _ap_target_type STREQUAL "EXECUTABLE"))
      install(TARGETS ${PROJECT_NAME}
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
      )
    endif()
  endif()
endmacro()

# Real ament_cmake makes ament_generate_version_header available transitively
# via find_package(ament_cmake). Mirror that by including the mock here so a
# package (e.g. rcpputils) that calls it without an explicit find_package works.
include("${CMAKE_CURRENT_LIST_DIR}/ament_cmake_gen_version_h-config.cmake")
