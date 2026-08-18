#!/usr/bin/env bash
# Create (if needed) the uv-managed venv, install Python deps, and register the
# source-tree rosidl Python packages (rosidl_adapter, rosidl_generator_c, …) as
# importable via a .pth file — they're consumed at cmake configure/build time
# but aren't pip-installable packages in this tree. Idempotent.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

uv venv --allow-existing
uv sync

python_version="$(uv run python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
site_packages="$repo_root/.venv/lib/python${python_version}/site-packages"
pth_file="$site_packages/miniros2_sources.pth"

cat > "$pth_file" <<EOF
$repo_root/rosidl/rosidl_adapter
$repo_root/rosidl/rosidl_generator_c
$repo_root/rosidl/rosidl_generator_type_description
$repo_root/rosidl/rosidl_parser
$repo_root/rosidl/rosidl_pycommon
$repo_root/rosidl/rosidl_generator_cpp
$repo_root/rosidl/rosidl_typesupport_introspection_c
$repo_root/rosidl/rosidl_typesupport_introspection_cpp
$repo_root/rosidl_typesupport/rosidl_typesupport_c
$repo_root/rosidl_typesupport/rosidl_typesupport_cpp
EOF

echo "wrote $pth_file"
