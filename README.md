# miniros2: standalone build for ROS 2 core libraries

Building `rmw` and `rcl` without a full ROS 2 / ament_cmake installation.

`ament_cmake_mock/` provides stub CMake macros for all `ament_*` functions so
packages can be built with plain CMake. Real source packages are added via
`add_subdirectory()` in dependency order in the top-level `CMakeLists.txt`.

See [`docs/mocking.md`](docs/mocking.md) for details on what's mocked and why.

## Building

Requirements:
- A standard Linux build environment (CMake, a C/C++ compiler, `make`/`ninja`)
- [`uv`](https://docs.astral.sh/uv/) for managing the Python environment

After cloning (with submodules):

```bash
git submodule update --init --recursive
./scripts/setup_venv.sh
```

CycloneDDS core (`cyclonedds/`) must be built and installed into `prefix/`
separately, before the main build:

```bash
cmake -G Ninja -B cyclonedds/build -S cyclonedds \
  -DCMAKE_INSTALL_PREFIX="$PWD/prefix" \
  -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
cmake --build cyclonedds/build --target install
```

Then build the rest:

```bash
mkdir build
uv run cmake -G Ninja -B build
uv run cmake --build build
uv run cmake --build build --target install
```

### Running the smoke test

```bash
AMENT_PREFIX_PATH="$PWD/prefix" LD_LIBRARY_PATH="$PWD/prefix/lib" \
  ./prefix/bin/rcl_pubsub_smoke_test
```

## Supported Middlewares

- **CycloneDDS** — the only middleware supported today. `librcl.so` links
  `librmw_implementation.so` and selects the concrete backend at runtime via
  `RMW_IMPLEMENTATION` / `dlopen`, same as a normal ROS 2 install; only
  `rmw_cyclonedds_cpp` is registered so far.

More middlewares (e.g. FastDDS) will be added in the future.

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
cyclonedds/             # CycloneDDS core (built+installed into prefix/ separately, see Building)
rcpputils/              # C++ utils (needed by rosidl typesupport + rmw)
rosidl_typesupport/     # rosidl_typesupport_c / rosidl_typesupport_cpp
rcl_interfaces/         # message packages: builtin_interfaces, service_msgs, …
rcl_logging/            # rcl_logging_interface + rcl_logging_noop
ros2_tracing/           # tracetools (built with TRACETOOLS_DISABLED=ON)
rcl/                    # rcl + rcl_yaml_param_parser
smoke_test/             # runtime rcl publisher/subscriber smoke test
prefix/                 # install destination
```
