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
    DirectorySource("../", target = "miniros2", follow_symlinks = true),
    ArchiveSource(
        "https://files.pythonhosted.org/packages/d1/82/b8b39f837baa80b1bf659beb64c1c8af66f2aa7437169d72a4e1fb0ed3df/empy-4.2.1.tar.gz",
        "b831d642fca95507820b53774c051803142b8441b8c42bf800011da06ba4241b",
    ),
    ArchiveSource(
        "https://files.pythonhosted.org/packages/da/34/28fff3ab31ccff1fd4f6c7c7b0ceb2b6968d8ea4950663eadcb5720591a0/lark-1.3.1.tar.gz",
        "b426a7a6d6d53189d318f2b6236ab5d6429eaf09259f1ca33eb716eed10d2905",
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
pip install --no-index --no-build-isolation \
  "$WORKSPACE/srcdir/empy-4.2.1" "$WORKSPACE/srcdir/lark-1.3.1"

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

# CycloneDDS core, built+installed separately into prefix/ first (README).
cmake -B build_cyclonedds -S cyclonedds \
  -DCMAKE_INSTALL_PREFIX="$PWD/prefix" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=ON \
  -DENABLE_SHM=OFF -DENABLE_SSL=OFF -DENABLE_SECURITY=OFF \
  -DBUILD_IDLC=ON -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF \
  -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
cmake --build build_cyclonedds -j${nproc} --target install

# Main tree: rcutils through rcl, rosidl codegen, rmw_cyclonedds_cpp, and the
# rmw_implementation dlopen dispatcher.
cmake -B build -S . \
  -DPython3_EXECUTABLE="$(which python3)" \
  -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TARGET_TOOLCHAIN}"
cmake --build build -j${nproc}
cmake --install build

install_license LICENSE 2>/dev/null || true
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

dependencies = Dependency[]

build_tarballs(
    ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat = "1.6",
    preferred_gcc_version = v"9",
)
