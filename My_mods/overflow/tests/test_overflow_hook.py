# -*- coding: utf-8 -*-
"""Tests of the Overflow entry point, hook/lua/ui/game/gamemain.lua.

The hook runs while the game builds its interface: an error outside pcall here
leaves the player without an interface.

Run: python test_overflow_hook.py
"""
import io
import os
import sys

from lupa import luajit21 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(os.path.dirname(HERE), "Overflow", "hook", "lua", "ui", "game",
                    "gamemain.lua")
hook_src = io.open(HOOK, encoding="utf-8").read()

lua = lupa.LuaRuntime(unpack_returned_tuples=True)

STUBS = r'''
msgs = {}
function LOG(m) msgs[table.getn(msgs) + 1] = tostring(m) end
function Said(text) return string.find(table.concat(msgs, ' | '), text, 1, true) ~= nil end

BUILT = 0
function CreateUI(isReplay) BUILT = BUILT + 1 end

-- When a module fails to compile, doscript ends without an error and import returns
-- an empty module. Reading a missing field reaches the strict _G of the game and fails.
function BrokenModule()
    return setmetatable({}, { __index = function(_, key)
        error('access to nonexistent global variable ' .. tostring(key), 2)
    end })
end

MODULE = nil
function import(path) return MODULE end
'''

lua_call = lua.eval("function(name, ...) return _G[name](...) end")
fails = 0


def check(cond, label):
    global fails
    print("  [%s] %s" % ("OK  " if cond else "FAIL", label))
    if not cond:
        fails += 1


def load_hook(module_code):
    """Fresh stubs and a run of the hook file, as the game appends it to gamemain.lua."""
    lua.execute(STUBS)
    lua.execute(module_code)
    try:
        lua.execute(hook_src)
        return True
    except Exception as e:
        print("  hook failed: " + str(e))
        return False


print("=== 1: ui.lua did not compile ===")
check(load_hook("MODULE = BrokenModule()"), "the hook survives a broken module")
lua_call("CreateUI", False)
check(lua.eval("BUILT") == 1, "the game still builds its interface")
check(lua.eval("Said('MODULE FAILED TO LOAD')"), "the failure is in the log")

print("=== 2: ui.lua loaded ===")
check(load_hook("CALLED = 0 MODULE = { OnCreateUI = function() CALLED = CALLED + 1 end }"),
      "the hook loads with a working module")
lua_call("CreateUI", False)
check(lua.eval("BUILT") == 1, "the game builds its interface")
check(lua.eval("CALLED") == 1, "the mod starts after the game interface")

print("=== 3: the mod fails while starting ===")
check(load_hook("MODULE = { OnCreateUI = function() error('boom') end }"),
      "the hook loads with a failing entry point")
lua_call("CreateUI", False)
check(lua.eval("BUILT") == 1, "the game builds its interface")
check(lua.eval("Said('OnCreateUI error')"), "the error is in the log")

print("")
if fails:
    print("failed checks: %d" % fails)
    sys.exit(1)
print("all checks passed")
