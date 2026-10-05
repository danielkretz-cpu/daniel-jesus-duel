#!/usr/bin/env bash
# Pinned, project-local installation for Linux x86_64 CI/build machines.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="4.6.3"
ARCHIVE="Godot_v${VERSION}-stable_linux.x86_64.zip"
EDITOR_SHA256="d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3"
TEMPLATE_ARCHIVE="Godot_v${VERSION}-stable_export_templates.tpz"
TEMPLATE_ARCHIVE_SHA256="3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"
RELEASE_SHA256="1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9"
DEBUG_SHA256="4a8a8ef7519637f7898fad25f09d3e466965e99c04e441682e1bc2d97a548922"
CACHE="$ROOT/.cache/godot-$VERSION"
TEMPLATES="$ROOT/tooling/$VERSION.stable"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "This automated build requires Linux x86_64. Open the project in Godot $VERSION on other systems." >&2
  exit 1
fi
for command in curl unzip sha256sum; do
  command -v "$command" >/dev/null || { echo "Missing required build tool: $command" >&2; exit 1; }
done

mkdir -p "$CACHE"
verify() { printf '%s  %s\n' "$1" "$2" | sha256sum --check --status; }
if [[ ! -f "$CACHE/$ARCHIVE" ]] || ! verify "$EDITOR_SHA256" "$CACHE/$ARCHIVE"; then
  echo "Downloading official Godot $VERSION editor..." >&2
  temporary="$(mktemp "$CACHE/editor.XXXXXX")"
  trap 'rm -f "${temporary:-}"' EXIT
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 \
    "https://github.com/godotengine/godot-builds/releases/download/$VERSION-stable/$ARCHIVE" \
    --output "$temporary" >&2
  verify "$EDITOR_SHA256" "$temporary" || { echo "Godot editor checksum mismatch; refusing to run it." >&2; exit 1; }
  mv "$temporary" "$CACHE/$ARCHIVE"
  trap - EXIT
fi

# Cache only the two extracted Web templates. A cold build downloads the official
# all-platform archive, verifies its published digest, and discards that archive.
# Existing verified local templates still work without downloading it.
if ! { [[ -f "$TEMPLATES/web_nothreads_release.zip" && -f "$TEMPLATES/web_nothreads_debug.zip" ]] \
  && verify "$RELEASE_SHA256" "$TEMPLATES/web_nothreads_release.zip" \
  && verify "$DEBUG_SHA256" "$TEMPLATES/web_nothreads_debug.zip"; }; then
  echo "Downloading official Godot $VERSION export templates (1.26 GB on a cold build)..." >&2
  temporary="$(mktemp "$CACHE/templates.XXXXXX")"
  trap 'rm -f "${temporary:-}"' EXIT
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 \
    "https://github.com/godotengine/godot-builds/releases/download/$VERSION-stable/$TEMPLATE_ARCHIVE" \
    --output "$temporary" >&2
  verify "$TEMPLATE_ARCHIVE_SHA256" "$temporary" || {
    echo "Godot template archive checksum mismatch; refusing to use it." >&2; exit 1;
  }
  mkdir -p "$TEMPLATES"
  unzip -oqj "$temporary" templates/web_nothreads_release.zip templates/web_nothreads_debug.zip -d "$TEMPLATES"
  verify "$RELEASE_SHA256" "$TEMPLATES/web_nothreads_release.zip" \
    && verify "$DEBUG_SHA256" "$TEMPLATES/web_nothreads_debug.zip" || {
      echo "Godot extracted template checksum mismatch; refusing to use it." >&2; exit 1;
    }
  rm -f "$temporary"
  trap - EXIT
fi

# Re-extract from the checked archive, so an old local executable is never trusted.
unzip -oq "$CACHE/$ARCHIVE" "Godot_v${VERSION}-stable_linux.x86_64" -d "$CACHE"
chmod u+x "$CACHE/Godot_v${VERSION}-stable_linux.x86_64"
printf '%s\n' "$CACHE/Godot_v${VERSION}-stable_linux.x86_64"
