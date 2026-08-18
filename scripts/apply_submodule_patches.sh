#!/usr/bin/env bash
# Apply local source patches to submodules after `git submodule update --init --recursive`.
# Idempotent: skips a patch if it is already applied.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
patch_dir="$repo_root/patches"

for patch in "$patch_dir"/*.patch; do
  [ -e "$patch" ] || continue
  name="$(basename "$patch" .patch)"
  target="$repo_root/$name"
  if [ ! -d "$target" ]; then
    echo "skip $name: directory not found" >&2
    continue
  fi
  if git -C "$target" apply --check "$patch" 2>/dev/null; then
    git -C "$target" apply "$patch"
    echo "applied $name.patch"
  elif git -C "$target" apply --check --reverse "$patch" 2>/dev/null; then
    echo "already applied $name.patch"
  else
    echo "FAILED to apply $name.patch (does not match working tree)" >&2
    exit 1
  fi
done
