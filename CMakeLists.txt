cmake_minimum_required(VERSION 3.15)
project(uros2_standalone)

list(PREPEND CMAKE_PREFIX_PATH
  "${CMAKE_CURRENT_SOURCE_DIR}/ament_cmake_mock"
  "${CMAKE_CURRENT_SOURCE_DIR}/prefix"
)

set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_SOURCE_DIR}/prefix" CACHE PATH "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
# Build shared libraries (.so). ROS 2 packages use bare add_library() so they
# honor BUILD_SHARED_LIBS; position-independent code is required for linking
# the resulting shared objects.
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE)
set(RMW_IMPLEMENTATION "rmw_cyclonedds_cpp" CACHE STRING "" FORCE)
set(RMW_IMPLEMENTATION_DISABLE_RUNTIME_SELECTION OFF CACHE BOOL "" FORCE)
set(TRACETOOLS_DISABLED ON CACHE BOOL "" FORCE)
set(RCL_LOGGING_IMPLEMENTATION "rcl_logging_noop" CACHE STRING "" FORCE)

# Core utils
add_subdirectory(rcutils)
add_subdirectory(rcpputils)

# rosidl runtime (no generation needed)
add_subdirectory(rosidl/rosidl_typesupport_interface)
add_subdirectory(rosidl/rosidl_runtime_c)
add_subdirectory(rosidl/rosidl_runtime_cpp)

# rosidl generation pipeline
add_subdirectory(rosidl/rosidl_cmake)
add_subdirectory(rosidl_core/rosidl_core_generators)
add_subdirectory(rosidl_defaults/rosidl_default_generators)
add_subdirectory(rosidl/rosidl_adapter)
add_subdirectory(rosidl/rosidl_generator_type_description)
add_subdirectory(rosidl/rosidl_generator_c)

# C++ message generation + typesupport (needed by rmw_cyclonedds)
add_subdirectory(rosidl/rosidl_generator_cpp)
add_subdirectory(rosidl/rosidl_typesupport_introspection_c)
add_subdirectory(rosidl/rosidl_typesupport_introspection_cpp)
add_subdirectory(rosidl_typesupport/rosidl_typesupport_c)
add_subdirectory(rosidl_typesupport/rosidl_typesupport_cpp)

# Message packages (order: dependencies first)
add_subdirectory(rcl_interfaces/builtin_interfaces)
add_subdirectory(rcl_interfaces/service_msgs)
add_subdirectory(rcl_interfaces/type_description_interfaces)
add_subdirectory(rcl_interfaces/rcl_interfaces)

# rmw
add_subdirectory(rosidl_dynamic_typesupport)
add_subdirectory(rmw/rmw)
add_subdirectory(ament_index/ament_index_cpp)

add_subdirectory(ros2_tracing/tracetools)

# Cyclone DDS rmw implementation must register itself (register_rmw_implementation)
# before rmw_implementation configures, since get_default_rmw_implementation()
# validates RMW_IMPLEMENTATION against the set of already-registered implementations.
#   CycloneDDS core is built+installed separately into prefix/ (see README).
add_subdirectory(rmw_dds_common/rmw_dds_common)
add_subdirectory(rmw_cyclonedds/rmw_cyclonedds_cpp)

add_subdirectory(rmw_implementation/rmw_implementation)

# rcl deps
add_subdirectory(rcl_logging/rcl_logging_interface)
add_subdirectory(rcl_logging/rcl_logging_noop)
add_subdirectory(rcl/rcl_yaml_param_parser)

# rcl
add_subdirectory(rcl/rcl)

# Runtime smoke test: rcl publisher/subscriber round trip over the compiled-in RMW.
add_executable(rcl_pubsub_smoke_test smoke_test/rcl_pubsub_smoke_test.c)
target_link_libraries(rcl_pubsub_smoke_test
  rcl::rcl
  builtin_interfaces__rosidl_generator_c
  builtin_interfaces__rosidl_typesupport_c
  rcl_interfaces__rosidl_typesupport_c
  type_description_interfaces__rosidl_typesupport_c)
