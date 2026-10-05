#!/usr/bin/env python3
"""Fail a build if its real single-thread Godot export is incomplete."""
import json
import re
import sys
from pathlib import Path

output = Path(sys.argv[1])
required = ["index.html", "index.js", "index.wasm", "index.pck"]
for name in required:
    path = output / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"Missing or empty Web export: {name}")
with (output / "index.wasm").open("rb") as wasm:
    if wasm.read(8) != b"\x00asm\x01\x00\x00\x00":
        raise SystemExit("index.wasm is not a valid WebAssembly v1 binary")
html = (output / "index.html").read_text()
if not re.search(r"const GODOT_THREADS_ENABLED\s*=\s*false\s*;", html):
    raise SystemExit("Expected a verified single-thread Godot HTML shell")
config = re.search(r"const GODOT_CONFIG\s*=\s*(\{[^\n]+\});", html)
if config:
    parsed = json.loads(config.group(1))
    if parsed.get("gdextensionLibs") or parsed.get("threadPoolSize", 0) > 0:
        raise SystemExit("Unexpected threaded/extension build; use the mobile-friendly Web preset")
    if parsed.get("executable") != "index":
        raise SystemExit("Godot engine file names must use the index export base name")
if "index.js" not in html:
    raise SystemExit("The Web page does not reference its Godot JavaScript engine loader")
total = sum(path.stat().st_size for path in output.rglob("*") if path.is_file())
if total > 95 * 1024 * 1024:
    raise SystemExit("Web export exceeds the 95 MiB project safety budget; review growth before deployment")
print(f"Verified real Godot Web export: {total / 1024 / 1024:.1f} MiB, {len(required)} required files present.")
