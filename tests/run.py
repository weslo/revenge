"""Runs Revenge's offline tests under real Lua 5.1 (via lupa).

Usage:  .venv\\Scripts\\python.exe -I tests\\run.py [name filter]
Setup:  python -m venv .venv  then  .venv\\Scripts\\python.exe -m pip install lupa==2.8
"""

import sys
from pathlib import Path

from lupa import lua51

root = Path(__file__).resolve().parent.parent
runtime = lua51.LuaRuntime(unpack_returned_tuples=True)
runner = runtime.eval(f"assert(loadfile({str(root / 'tests' / 'run.lua').replace(chr(92), '/')!r}))")
failed = runner(str(root).replace('\\', '/'), sys.argv[1] if len(sys.argv) > 1 else '')
sys.exit(1 if failed else 0)
