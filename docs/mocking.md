# How the ament mock works

ROS 2's build system normally relies on `ament_cmake`: a set of CMake macros
and a package index (`ament_index`) that let each package describe itself —
its include dirs, libraries, and generated files — without knowing where the
other packages in the workspace live. A real ROS 2 install also runs
`colcon`, which builds each package in its own isolated CMake project and
installs it before the next package configures.

`miniros2` doesn't use `colcon` or a real `ament_cmake` install. Instead, all
packages are pulled into a *single* CMake project via `add_subdirectory()`,
in dependency order, and `ament_cmake_mock/` supplies just enough of the real
`ament_*` API surface — as CMake macros and generated `Config.cmake` files —
to make the unmodified package sources build. This document explains what
had to be reimplemented and why.

## Extension points and the resource index

Several ROS 2 packages hook into each other via two mechanisms rather than
direct `find_package` calls:

- **`ament_register_extension(point, package, cmake_file)`** lets a package
  register a CMake file to be run when some other package reaches a named
  extension point, without either package needing to know about the other
  directly. `ament_execute_extensions(point)` runs everything registered for
  that point. The mock implements both with a CMake `CACHE INTERNAL` list
  keyed by extension point, storing `pkg:cmake_file` entries and `include()`-ing
  them when the point fires.

- **`ament_index_register_resource(type, ...)`** / `ament_index_get_resources(type)`
  maintain a resource-type → package-name index at configure time (also via
  `CACHE INTERNAL`). `rosidl_core_generators` uses this to discover which
  packages provide message generators.

`ament_package()` itself calls `ament_execute_extensions("ament_package")` at
the end of processing a package, which is what makes the `rosidl_cmake` hooks
run and populate `${PROJECT_NAME}_IDL_FILES` in that package's generated
`Config.cmake`.

## Generated Config.cmake files

In a real install, `ament_package(CONFIG_EXTRAS foo.cmake.in)` bakes
`foo.cmake.in` into an installed `<pkg>Config.cmake` that downstream packages
pick up via `find_package`. The mock reproduces this at configure time
instead of install time: it runs `configure_file(@ONLY)` on the template
*into the package's own `cmake/` source directory* (so `CMAKE_CURRENT_LIST_DIR`
resolves the way the template expects), then appends a path-fixup block so
that generator/template paths point at the source tree rather than an
`share/` install layout.

A few consequences fall out of building this way:

- **Message packages need two path variables.** A message package's
  generated `Config.cmake` sets `${PKG}_DATADIR` (the adapted-IDL output
  directory, read by `rosidl_find_package_idl`) and `${PKG}_DIR`
  (`type_description_output/cmake`, so `${PKG}_DIR}/..` resolves to the
  type-hash JSON output used by the type description generator).

- **Dependency IDL lookups must go through the DATADIR helper.**
  `rosidl_typesupport_c`/`_cpp` (and `rosidl_generator_c` and the
  introspection typesupports) resolve a dependency package's `.idl` files via
  `rosidl_find_package_idl(_abs_idl_file "${_pkg_name}" "${_idl_file}")`
  rather than a raw path under `share/`, since that install-layout path
  doesn't exist here.

- **Typesupport targets need aggregating.** The rosidl typesupport extras
  only populate per-suffix variables like
  `${PKG}_TARGETS__rosidl_generator_c`, but consumers like `rcl` expect a
  single `${PKG}_TARGETS`. `ament_package` handles a `${PKG}_CONFIG_EXTRAS_POST`
  hook that aggregates the per-typesupport lists into `${PKG}_TARGETS` in the
  generated config.

- **Config.cmake files need a re-entry guard**, since extras files can call
  `find_package(${PKG})` on their own package while it's still being
  processed; without a guard this recurses infinitely.

- **`normalize_path`** is defined in `ament_cmake_core-config.cmake` via
  `get_filename_component(... ABSOLUTE)`, matching the real macro's contract.

- **`ament_cmake_mock.cmake` itself needs an `include_guard(GLOBAL)`.** It's
  re-`include()`d every time a package's mock Config.cmake is loaded via
  `find_package()` — including nested `find_package()` calls a package makes
  on itself while still configuring (e.g. for `rosidl_typesupport_c`). Without
  the guard, the file-scope `set(_ament_mock_exported_deps "")` at its top
  reran on each of those nested includes and wiped out the
  `ament_export_dependencies()` calls already collected for the package
  currently configuring, so packages with message dependencies (like
  `action_msgs` → `unique_identifier_msgs`) silently lost them from their
  generated Config.

- **`${PKG}_RECURSIVE_DEPENDENCIES` is synthesized from that same
  accumulator.** `rosidl_generate_interfaces()` reads this variable on each
  direct dependency to also pull in *that* dependency's own message-package
  dependencies. Upstream `rosidl_cmake` never actually sets this
  variable in its generated Config extras — the mock fills the gap by writing
  it into message packages' `Config.cmake` from `_ament_mock_exported_deps`.

- **Type-description target edges are added by the mock, not a patch.**
  `rosidl_generator_type_description_generate_interfaces.cmake` lists a
  dependency package's type-hash JSON files only as file-level `DEPENDS`, not
  as a build-graph edge to the custom target that produces them — fine when
  `colcon` fully builds and installs each package before the next configures,
  but a race under `-j` in this single-tree build, where dependencies are
  sibling subdirectories built in parallel. `ament_package()` adds the missing
  `add_dependencies()` edge itself, using the
  `rosidl_generate_interfaces_DEPENDENCY_PACKAGE_NAMES` the preceding
  `rosidl_generate_interfaces()` call already computed in the same directory
  scope.

## Runtime package discovery

Because everything here builds as one CMake tree rather than being installed
package-by-package, `rmw` needs another way to discover RMW implementations
at runtime. `ament_cmake_mock.cmake` installs real
`share/ament_index/resource_index/<type>/<pkg>` marker files (using the
vendored `ament_index_cpp` in `ament_index/`, pulled from
`ros2/ament_index@jazzy`) so that runtime lookups work the same way they
would against a real ROS 2 install, rather than relying on CMake
configure-time state that wouldn't exist at runtime.

## Miscellaneous compatibility shims

- **`ROS_PACKAGE_NAME`**: the `ament_generate_version_header` mock (in
  `ament_cmake_mock/ament_cmake_gen_version_h-config.cmake`) adds
  `-DROS_PACKAGE_NAME="${_pkg_name}"` as a compile definition, matching real
  `ament_cmake` behavior — needed by the `RCUTILS_LOG_*_NAMED` logging
  macros. It's included transitively from `ament_cmake_mock.cmake`, so
  packages that use the macro without an explicit
  `find_package(ament_cmake_gen_version_h)` (e.g. `rcpputils`) still
  configure correctly.

- **`ament_add_default_options`** is a no-op macro — a newer
  `ament_cmake_ros` compiler-option helper that some upstream packages (e.g.
  `rmw_dds_common`) call but that doesn't affect whether this tree builds.

- **`pkg::pkg_library` alias**: `ament_package` creates an in-scope `ALIAS`
  for a `${PROJECT_NAME}_library` target in addition to the usual `pkg::pkg`,
  because e.g. `rmw_dds_common` names its library target
  `${PROJECT_NAME}_library` and `rmw_cyclonedds_cpp` links it as
  `rmw_dds_common::rmw_dds_common_library`. This only works because the whole
  tree is one `add_subdirectory` build sharing a single CMake target
  namespace.

## Dirty submodules after build
`rosidl`, `rmw_implementation`, and `rosidl_core` do pick up untracked,
generated `*-extras.cmake` files — produced by the `.cmake.in` CONFIG_EXTRAS
handling described above — that are regenerated on every configure and are
not meant to be committed.
