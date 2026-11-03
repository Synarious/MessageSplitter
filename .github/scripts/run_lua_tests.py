"""Run each addon regression test in an isolated Lua 5.1 runtime."""

import os
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
for test in sorted((ROOT / "tests").glob("test_*.lua")):
    print(f"Running {test.name}", flush=True)
    LuaRuntime(unpack_returned_tuples=True).execute(test.read_text(encoding="utf-8-sig"))
