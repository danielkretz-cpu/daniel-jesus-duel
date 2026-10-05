#!/usr/bin/env bash
# Vercel's Amazon Linux build image already supplies these in normal operation.
set -euo pipefail
missing=()
for tool in bash curl unzip sha256sum python3; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
if ((${#missing[@]})); then
  if command -v dnf >/dev/null; then
    dnf install -y curl unzip coreutils python3
  else
    echo "Install these build tools before continuing: ${missing[*]}" >&2
    exit 1
  fi
fi
for tool in bash curl unzip sha256sum python3; do
  command -v "$tool" >/dev/null || { echo "Missing build tool after installation: $tool" >&2; exit 1; }
done
