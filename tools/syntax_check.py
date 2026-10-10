#!/usr/bin/env python3
"""Compile-check every Lua file in the repo with the same Lua runtime family
Valve's bot sandbox targets (LuaJIT / Lua 5.1). Exit code 0 = all files parse."""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["bots", "game", "tools"]
SKIP_FILES = {"--mode_item_generic.lua"}


def get_runtime():
    modules = []
    for name in ("luajit21", "luajit20", "lua51"):
        try:
            modules.append(__import__(f"lupa.{name}", fromlist=["LuaRuntime"]))
            break
        except ImportError:
            continue
    from lupa import LuaRuntime
    mod = modules[0] if modules else None
    rt = mod.LuaRuntime(unpack_returned_tuples=True) if mod else LuaRuntime(unpack_returned_tuples=True)
    return rt, (mod.__name__ if mod else "lupa default")


def read_source(path):
    with open(path, "rb") as f:
        raw = f.read()
    # strip BOM, keep bytes as latin-1 so Lua sees the original bytes
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return raw.decode("latin-1")


def collect_files():
    files = []
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [x for x in dirnames if x not in {".git", "__pycache__"}]
            for fn in filenames:
                if fn.endswith(".lua") and fn not in SKIP_FILES:
                    files.append(os.path.join(dirpath, fn))
    return sorted(files)


def main():
    lua, rtname = get_runtime()
    files = collect_files()
    print(f"[syntax] runtime: {rtname}, files: {len(files)}")
    failures = []
    for path in files:
        src = read_source(path)
        lua.globals().MOCK_SRC = src
        lua.globals().MOCK_CHUNK = "@" + os.path.relpath(path, ROOT).replace("\\", "/")
        ok, err = lua.eval(
            '(function() local f, e = loadstring(MOCK_SRC, MOCK_CHUNK);'
            ' if f then return true, nil else return false, e end end)()'
        )
        if not ok:
            failures.append((path, err))
    if failures:
        print(f"[syntax] FAIL: {len(failures)} file(s)")
        for path, err in failures:
            print(f"  {os.path.relpath(path, ROOT)}\n    {err}")
        return 1
    print("[syntax] PASS: all files compile")
    return 0


if __name__ == "__main__":
    sys.exit(main())
