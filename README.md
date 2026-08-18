# uros2 Standalone Build

Building `rmw` and `rcl` without a full ROS 2 / ament_cmake installation.

## Strategy

`ament_cmake_mock/` provides stub CMake macros for all `ament_*` functions so
packages can be built with plain CMake. Real source packages are added via
`add_subdirectory()` in dependency order in the top-level `CMakeLists.txt`.

## Setup

After cloning (with submodules), apply the local patches to the affected
submodules:

```bash
git submodule update --init --recursive
./scripts/apply_submodule_patches.sh
```

See "Per-Repository Source Edits" below for what each patch does.

## Build Command

```bash
uv run cmake -B build -S . -DPython3_EXECUTABLE="$(pwd)/.venv/bin/python"
cmake --build build -j$(nproc)
```

CycloneDDS core is built and installed separately into `prefix/` first:

```bash
cmake -B build_cyclonedds -S cyclonedds \
  -DCMAKE_INSTALL_PREFIX="$(pwd)/prefix" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON \
  -DENABLE_SHM=OFF -DENABLE_SSL=OFF -DENABLE_SECURITY=OFF \
  -DBUILD_IDLC=ON -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF
cmake --build build_cyclonedds -j$(nproc) --target install
```

Python (with `empy`, `lark`) is needed because:
- `rcutils` generates `logging_macros.h` from a `.em` template at build time
- `rosidl_adapter` converts `.msg/.srv` to `.idl` at cmake configure time
- `rosidl_generator_c` and `rosidl_generator_type_description` run Python generators at build time

Source-tree Python packages (`rosidl_adapter`, `rosidl_generator_c`,
`rosidl_generator_type_description`, `rosidl_parser`, `rosidl_pycommon`) are
made importable via `.venv/lib/python3.x/site-packages/uros2_sources.pth`.

## Current Status

The full tree — `rcutils` through `rcl`, all rosidl codegen packages, message
packages (`builtin_interfaces`, `service_msgs`, `type_description_interfaces`,
`rcl_interfaces`), `rmw`, `rmw_cyclonedds_cpp` against a standalone CycloneDDS
core, and the `rmw_implementation` dlopen dispatcher — configures, compiles,
and links with a single `cmake --build build`.

The dispatcher is wired for **runtime** RMW selection: `librcl.so` links
`librmw_implementation.so` rather than a concrete `rmw_*` backend, and the
middleware is chosen at runtime via `RMW_IMPLEMENTATION` / `dlopen`, same as a
normal ROS 2 install. Only `rmw_cyclonedds_cpp` is registered today, so this
proves the mechanism rather than an actual choice between middlewares; adding
a second `rmw_*` package is the natural next step.

`smoke_test/rcl_pubsub_smoke_test.c` publishes and subscribes a
`builtin_interfaces/msg/Time` message in-process via `rcl` and confirms the
round-trip, exercising rcl → rmw_implementation → rmw_cyclonedds_cpp →
CycloneDDS end-to-end. It passes with both the default and an explicit
`RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`:

```bash
cmake --install build
export AMENT_PREFIX_PATH="$(pwd)/prefix"
export LD_LIBRARY_PATH="$(pwd)/prefix/lib"
./build/rcl_pubsub_smoke_test
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ./build/rcl_pubsub_smoke_test
```

Its `CMakeLists.txt` target links `rcl_interfaces__rosidl_typesupport_c` and
`type_description_interfaces__rosidl_typesupport_c` explicitly — `librcl.so`
has unresolved typesupport symbols that are tolerated when it's built as a
`.so` alone but must be resolved once something actually links `rcl` into an
executable.

The `iceoryx_binding_c` shared-memory dependency is not needed since
CycloneDDS core is built with `ENABLE_SHM=OFF`; revisit if shared-memory
transport is wanted.

## Implemented Mock Mechanisms

The following ament mechanisms are implemented in `ament_cmake_mock/`:

- **`ament_register_extension` / `ament_execute_extensions`**: Uses a CMake
  `CACHE INTERNAL` list to store `extension_point → [pkg:cmake_file, ...]`
  mappings. Extensions are executed (included) when the extension point fires.

- **`ament_index_register_resource` / `ament_index_get_resources`**: Uses
  `CACHE INTERNAL` to maintain a resource-type → package-name index.
  Required for `rosidl_core_generators` to discover generator packages.

- **`.cmake.in` CONFIG_EXTRAS**: `ament_package(CONFIG_EXTRAS foo.cmake.in)`
  processes the template via `configure_file(@ONLY)` into the package's
  `cmake/` source directory (so `CMAKE_CURRENT_LIST_DIR` resolves correctly),
  then appends a path-fixup block for source-tree BIN/GENERATOR_FILES/TEMPLATE_DIR.

- **`ament_package` extension hooks**: `ament_package()` calls
  `ament_execute_extensions("ament_package")` so the `rosidl_cmake` hooks
  run and set `${PROJECT_NAME}_IDL_FILES` in the generated Config.cmake.

- **`DATADIR` + `_DIR` for message packages**: Config.cmake for rosidl message
  packages sets:
  - `${PKG}_DATADIR` → adapted IDL output dir (used by `rosidl_find_package_idl`)
  - `${PKG}_DIR` → `type_description_output/cmake` so `_DIR/..` resolves to
    the type-hash JSON output dir (used by the type description generator)

- **`normalize_path`**: defined in `ament_cmake_core-config.cmake` via
  `get_filename_component(... ABSOLUTE)`.

- **Re-entry guard**: Config.cmake files include a loading guard that prevents
  infinite recursion when extras cmake files call `find_package(${PKG})`.

- **`${PKG}_TARGETS` aggregation**: The rosidl typesupport extras only
  populate per-suffix variables like `${PKG}_TARGETS__rosidl_generator_c`,
  while consumers (rcl) link against the aggregate `${PKG}_TARGETS`.
  `ament_package` handles `${PKG}_CONFIG_EXTRAS_POST` and aggregates the
  per-typesupport target lists into `${PKG}_TARGETS` in the generated
  Config.cmake.

- **`ROS_PACKAGE_NAME`**: `ament_generate_version_header` mock in
  `ament_cmake_mock/ament_cmake_gen_version_h-config.cmake` adds
  `-DROS_PACKAGE_NAME="${_pkg_name}"` as a compile definition on the target,
  matching real ament_cmake behaviour (needed by the `RCUTILS_LOG_*_NAMED`
  logging macros). Included transitively from `ament_cmake_mock.cmake`, so
  packages that call it without an explicit
  `find_package(ament_cmake_gen_version_h)` (e.g. `rcpputils`) configure.

- **`ament_add_default_options`**: no-op macro (newer `ament_cmake_ros`
  compiler-option helper that upstream packages like `rmw_dds_common` call).

- **`pkg::pkg_library` alias**: `ament_package` creates an in-scope ALIAS for
  a `${PROJECT_NAME}_library` target in addition to `pkg::pkg`, needed because
  e.g. `rmw_dds_common` names its library target `${PROJECT_NAME}_library`
  and `rmw_cyclonedds_cpp` links it as `rmw_dds_common::rmw_dds_common_library`
  (sufficient because the whole tree is one `add_subdirectory` build).

- **Dependency-IDL resolution in typesupport**: `rosidl_typesupport_c` /
  `_cpp` resolve the IDL files of dependency packages via
  `rosidl_find_package_idl(_abs_idl_file "${_pkg_name}" "${_idl_file}")`
  (the DATADIR-aware helper `rosidl_generator_c` and the introspection
  typesupports also use), rather than a raw install-layout path that doesn't
  exist in this standalone tree.

- **Ament index resource markers**: `ament_cmake_mock.cmake` installs real
  `share/ament_index/resource_index/<type>/<pkg>` marker files (vendored
  `ament_index_cpp` in `ament_index/`, from `ros2/ament_index@jazzy`), needed
  for runtime RMW discovery — resource registration previously only lived in
  CMake's configure-time cache.

## Per-Repository Source Edits

Each subfolder that is its own git checkout was inspected with `git diff` /
`git status`. Only `rosidl` carries a tracked local change; the rest are
pristine (`ament_index`, `cyclonedds`, `libyaml_vendor`, `rcl`,
`rcl_interfaces`, `rcl_logging`, `rcpputils`, `rcutils`, `rmw`,
`rmw_cyclonedds`, `rmw_dds_common`, `ros2_tracing`, `rosidl_defaults`,
`rosidl_dynamic_typesupport`, `rosidl_typesupport`) — `rmw_implementation`
and `rosidl_core` only carry generated, untracked config-extras files (see
below).

### `rosidl/`
- **Tracked edit** — `rosidl_generator_type_description/cmake/rosidl_generator_type_description_generate_interfaces.cmake`:
  adds an explicit build-graph dependency on each dependency package's
  `…__rosidl_generator_type_description` target. In a single-tree standalone
  build the dependency packages are sibling subdirectories, so this prevents a
  parallel-build race where a dependency's type-hash JSON is read before it has
  been generated.
- **Untracked** — generated `*-extras.cmake` files written into the package
  `cmake/` source dirs (by the `ament_cmake_mock` CONFIG_EXTRAS processing),
  each with a source-tree path-fixup block (`BIN`/`GENERATOR_FILES`/`TEMPLATE_DIR`
  fall back to `CMAKE_CURRENT_LIST_DIR/..` when the install-layout path is
  absent):
  - `rosidl_generator_c/cmake/rosidl_generator_c-extras.cmake`
  - `rosidl_generator_cpp/cmake/rosidl_generator_cpp-extras.cmake`
  - `rosidl_generator_type_description/cmake/rosidl_generator_type_description-extras.cmake`
  - `rosidl_typesupport_introspection_c/cmake/rosidl_typesupport_introspection_c-extras.cmake`
  - `rosidl_typesupport_introspection_cpp/cmake/rosidl_typesupport_introspection_cpp-extras.cmake`

### `rmw_implementation/`
- **Untracked** — `rmw_implementation/cmake/rmw_implementation-extras.cmake`,
  the generated config-extras hard-wiring `rmw_implementation` as the single RMW
  implementation (matches the `RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION=ON`
  build) and creating the `rmw_implementation::rmw_implementation` interface
  target.

### `rosidl_core/`
- **Untracked** — `rosidl_core_generators/cmake/rosidl_core_generators-extras.cmake`,
  the generated config-extras that discovers the registered typesupport /
  generator packages via `ament_index_get_resources` and re-exports their
  definitions/includes/libraries.

> Note: the untracked `*-extras.cmake` files are produced into the source trees
> by the mock's `.cmake.in` CONFIG_EXTRAS handling (see "Implemented Mock
> Mechanisms"); they are regenerated on configure and are not meant to be
> committed to the upstream repos.

The tracked edit above (`rosidl/`) is stored as a diff in `patches/` and
applied to the git-submodule checkout by `scripts/apply_submodule_patches.sh`
(see "Setup" above).

### Known harmless warnings
Configure prints `message(WARNING ...)` lines like `Package 'builtin_interfaces'
exports the typesupport target '...' which doesn't exist` for a few message
packages. These come from upstream's
`rosidl_cmake_export_typesupport_targets-extras.cmake` template running before
that package's own `rosidl_typesupport_c`/`_cpp` target is registered — an
extension-execution-order gap in the mock's `ament_execute_extensions`, not a
missing target. The aggregated `${PKG}_TARGETS` list is still populated
correctly afterward, so the build is unaffected; fixing the ordering is left
for later.

## Package Layout

```
ament_cmake_mock/       # Stub + implemented CMake macros
rcutils/                # rcutils source
rosidl/                 # rosidl monorepo (adapter, runtime_c, generator_c,
                        #   generator_type_description, cmake, parser, pycommon, …)
rosidl_core/            # rosidl_core_generators meta package
rosidl_defaults/        # rosidl_default_generators meta package
rosidl_dynamic_typesupport/
rmw/                    # rmw + rmw_implementation_cmake
rmw_implementation/     # rmw_implementation dispatcher
rmw_cyclonedds/         # rmw_cyclonedds_cpp
rmw_dds_common/         # rmw_dds_common (msgs + cpp lib, needed by rmw_cyclonedds)
cyclonedds/             # CycloneDDS core (built+installed into prefix/)
rcpputils/              # C++ utils (needed by rosidl typesupport + rmw)
rosidl_typesupport/     # rosidl_typesupport_c / rosidl_typesupport_cpp
rcl_interfaces/         # message packages: builtin_interfaces, service_msgs, …
rcl_logging/            # rcl_logging_interface + rcl_logging_noop
ros2_tracing/           # tracetools (built with TRACETOOLS_DISABLED=ON)
rcl/                    # rcl + rcl_yaml_param_parser
smoke_test/             # runtime rcl publisher/subscriber smoke test
prefix/                 # install destination
```
