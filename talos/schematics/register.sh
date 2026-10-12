#!/usr/bin/env bash
# Registers every schematic in this directory with Talos Image Factory and
# prints its schematic ID plus the image URLs for the pinned Talos version.
#
# Registering is idempotent: the ID is a hash of the schematic's content, so
# re-running only yields a new ID when a schematic's extensions change.
#
# Usage: register.sh [schematic.yaml ...]   (defaults to all *.yaml here)
# Env:   TALOS_VERSION  overrides the version (default: talosctl client
#                       version, i.e. the one pinned in mise.toml)
set -euo pipefail

FACTORY=https://factory.talos.dev
cd "$(dirname "$0")"

version=${TALOS_VERSION:-$(talosctl version --client --short | grep -o 'v[0-9][0-9.]*')}

files=("$@")
[[ ${#files[@]} -gt 0 ]] || files=(*.yaml)

for file in "${files[@]}"; do
  id=$(curl -fsS -X POST --data-binary @"$file" "$FACTORY/schematics" |
    sed -E 's/.*"id":"([0-9a-f]+)".*/\1/')

  cat <<OUT
${file%.yaml} (Talos $version)
  schematic:              $id
  iso:                    $FACTORY/image/$id/$version/metal-amd64.iso
  iso (secureboot):       $FACTORY/image/$id/$version/metal-amd64-secureboot.iso
  installer:              factory.talos.dev/metal-installer/$id:$version
  installer (secureboot): factory.talos.dev/metal-installer-secureboot/$id:$version

OUT
done
