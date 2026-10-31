---@meta
-- Types LuaLS cannot see on its own. The "deprecated" diagnostic is off in .luarc.json
-- because Lua 5.1 marks table.getn as deprecated, and in the game it is the only way.

UMT = {
    Options = import("/mods/UMT/modules/Options.lua"),
}

---@class SyncTable
---@field Reclaim? table<EntityId, table|false>

---@type SyncTable
Sync = {}
