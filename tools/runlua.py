"""Run a Lua file under LuaJIT 2.1 (same VM family as LÖVE and GMod) via lupa.
usage: python3 tools/runlua.py tests/test_core.lua"""
import sys, os
from lupa.luajit21 import LuaRuntime
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('package.path = %r .. "/?.lua;" .. package.path' % root)
src = open(sys.argv[1]).read()
ok = lua.execute(src)
