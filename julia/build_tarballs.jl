# Note: to use the local sources, you must first run (from the repo root):
#   git submodule update --init --recursive
# so that submodule contents are present on disk before DirectorySource
# copies them into the sandbox. Patches are applied inside the build script
# below (see apply_patches), so apply_submodule_patches.sh does not need to
# be run beforehand.

using BinaryBuilder

name = "miniros2"
version = v"0.1.0"

# DirectorySource copies the given local directory into $WORKSPACE/srcdir
# instead of cloning a git repo. This picks up the working tree as-is,
# including uncommitted changes and the already-checked-out submodules —
# there is no need for a sources[] git entry for the miniros2 tree itself.
# (Not Yggdrasil-compatible as-is: a public submission would need this
# replaced with a GitSource/ArchiveSource pinned to a released tag.)
#
# empy/lark are pure-Python build-time deps (rcutils' logging_macros.h and
# rosidl codegen need them at configure/build time — see README.md). The
# sandboxed build step has no network access, but sources are fetched before
# entering the sandbox, so pull pinned sdists from PyPI here rather than
# pip-installing at build time or vendoring the local .venv.
sources = [
    DirectorySource(joinpath(@__DIR__, ".."), target = "miniros2", follow_symlinks = true),
    ArchiveSource(
        "https://files.pythonhosted.org/packages/d1/82/b8b39f837baa80b1bf659beb64c1c8af66f2aa7437169d72a4e1fb0ed3df/empy-4.2.1.tar.gz",
        "b831d642fca95507820b53774c051803142b8441b8c42bf800011da06ba4241b",
    ),
    # The sandbox has no `wheel` package, so pip can't run `setup.py
    # bdist_wheel` for the empy sdist above under --no-build-isolation.
    # Pull a pinned prebuilt wheel and install it first.
    FileSource(
        "https://files.pythonhosted.org/packages/bd/7c/d38a0b30ce22fc26ed7dbc087c6d00851fb3395e9d0dac40bec1f905030c/wheel-0.38.4-py3-none-any.whl",
        "b60533f3f5d530e971d6737ca6d58681ee434818fab630c83a734bb10c083ce8",
    ),
    # lark's sdist is PEP 621 (pyproject.toml-only metadata), which the
    # sandbox's old setuptools can't read — pip silently built an empty
    # "UNKNOWN-0.0.0" wheel from it instead of "lark". It's pure Python, so
    # fetch the prebuilt wheel directly and skip the metadata build entirely.
    FileSource(
        "https://files.pythonhosted.org/packages/82/3d/14ce75ef66813643812f3093ab17e46d3a206942ce7376d31ec2d36229e7/lark-1.3.1-py3-none-any.whl",
        "c629b661023a014c37da873b4ff58a817398d12635d3bbb2c5a03be7fe5d1e12",
    ),
]

# Mirrors README.md's "Build Command" section, minus the uv-managed venv:
# empy/lark are unpacked from the pinned sdists above (installed into the
# sandbox's site-packages with pip, offline, from the local sdist directory),
# and the source-tree rosidl Python packages are put on PYTHONPATH instead of
# being registered via a .pth file.
script = raw"""
# Install empy/lark from the sdists fetched above, offline (--no-index), into
# the sandbox's own site-packages so plain `import empy`/`import lark` work.
pip install --no-index --no-deps "$WORKSPACE/srcdir/wheel-0.38.4-py3-none-any.whl"
pip install --no-index --no-deps "$WORKSPACE/srcdir/lark-1.3.1-py3-none-any.whl"
pip install --no-index --no-build-isolation "$WORKSPACE/srcdir/empy-4.2.1"

cd $WORKSPACE/srcdir/miniros2

# Submodules are plain-copied by DirectorySource, so their .git pointers
# (which reference the superproject's .git/modules/) are broken here — use
# `patch` instead of `git apply`, and treat a failed dry-run as "already
# applied" so this step is a no-op on a tree patched before packaging too.
for patch in $WORKSPACE/srcdir/miniros2/patches/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch" .patch)"
    target="$WORKSPACE/srcdir/miniros2/$name"
    if patch -p1 -d "$target" --dry-run -N < "$patch" >/dev/null 2>&1; then
        patch -p1 -d "$target" -N < "$patch"
        echo "applied $name.patch"
    else
        echo "skip $name.patch: already applied (or does not match)"
    fi
done

export PYTHONPATH="$PWD/rosidl/rosidl_adapter:$PWD/rosidl/rosidl_generator_c:$PWD/rosidl/rosidl_generator_type_description:$PWD/rosidl/rosidl_parser:$PWD/rosidl/rosidl_pycommon:$PWD/rosidl/rosidl_generator_cpp:$PWD/rosidl/rosidl_typesupport_introspection_c:$PWD/rosidl/rosidl_typesupport_introspection_cpp:$PWD/rosidl_typesupport/rosidl_typesupport_c:$PWD/rosidl_typesupport/rosidl_typesupport_cpp:${PYTHONPATH:-}"

# ament_cmake_mock/libyaml_vendor-config.cmake expects libyaml to be a
# system-wide install (as if `apt install libyaml-dev` had run), hardcoding
# /usr/lib/x86_64-linux-gnu and /usr/include as search hints. Stage the
# LibYAML_jll files fetched as a dependency into those paths instead of
# patching the mock config.
mkdir -p /usr/lib/x86_64-linux-gnu /usr/include
# LibYAML_jll's files are relative symlinks into the artifact store
# (libyaml.so -> libyaml-0.so.2.0.9 -> ../../artifacts/<hash>/lib/...);
# copying them as symlinks (-a) leaves dangling links once relocated, so
# dereference (-L) to copy the real file contents instead.
cp -avL "$libdir"/libyaml* /usr/lib/x86_64-linux-gnu/
cp -avL "$prefix"/include/yaml.h "$prefix"/include/yaml_version.h /usr/include/ 2>/dev/null || \
  cp -avL "$prefix"/include/yaml.h /usr/include/

# CycloneDDS core, built+installed separately into prefix/ first (README).
# Installed straight into $prefix (BinaryBuilder's destdir) rather than a
# local prefix/ dir, so the main tree's find_package(CycloneDDS) below and
# BinaryBuilder's product audit both see it in the same place.
cmake -B build_cyclonedds -S cyclonedds \
  -DCMAKE_INSTALL_PREFIX="${prefix}" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON \
  -DENABLE_SHM=OFF -DENABLE_SSL=OFF -DENABLE_SECURITY=OFF \
  -DBUILD_IDLC=ON -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
  -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
cmake --build build_cyclonedds -j${nproc} --target install

# Main tree: rcutils through rcl, rosidl codegen, rmw_cyclonedds_cpp, and the
# rmw_implementation dlopen dispatcher.
# __STDC_FORMAT_MACROS: the sandbox's glibc headers still gate PRId8/PRIu16/
# etc. behind this in C++ translation units (pre-C++11 rule some distros keep
# around), and rmw_cyclonedds_cpp's serdes.hpp/rmw_node.cpp use those macros
# without defining it themselves.
cmake -B build -S . \
  -DCMAKE_INSTALL_PREFIX="${prefix}" \
  -DPython3_EXECUTABLE="$(which python3)" \
  -DCMAKE_CXX_FLAGS="-D__STDC_FORMAT_MACROS" \
  -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
cmake --build build -j${nproc}
cmake --install build
"""

platforms = [Platform("x86_64", "linux"; libc = "glibc")]

products = [
    LibraryProduct("librcl", :librcl),
    LibraryProduct("librmw", :librmw),
    LibraryProduct("librmw_implementation", :librmw_implementation),
    LibraryProduct("librmw_cyclonedds_cpp", :librmw_cyclonedds_cpp),
    LibraryProduct("libddsc", :libddsc),
    ExecutableProduct("rcl_pubsub_smoke_test", :rcl_pubsub_smoke_test),
]

dependencies = [
    Dependency("LibYAML_jll"; compat = "=0.2.5"),
]

build_tarballs(
    ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat = "1.6",
    preferred_gcc_version = v"9",
    # No repo-level LICENSE file exists yet (this build isn't set up for
    # Yggdrasil submission — see the DirectorySource note above).
    require_license = false,
)
