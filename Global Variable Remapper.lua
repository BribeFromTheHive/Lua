if Debug then Debug.beginFile "Remap" end

GlobalRemap      = nil ---@type fun(var: string, getFunc?: (fun():any),      setFunc?: fun(value))
GlobalRemapArray = nil ---@type fun(var: string, getFunc?: (fun(index):any), setFunc?: fun(index, value))

OnInit(function()

local hook = Require.strict "Hook" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
--[[
--------------------------------------------------------------------------------------
Global Variable Remapper v1.3.2 by Bribe

- Turns normal GUI variable references into function calls that integrate seamlessly
  with a Lua framework.

API:
    GlobalRemap(variableStr[, getterFunc, setterFunc])
    @variableStr is a string such as "udg_MyVariable"
    @getterFunc is a function that takes nothing but returns the expected value when
        "udg_MyVariable" is referenced.
    @setterFunc is a function that takes a single argument (the value that is being
        assigned) and allows you to do what you want when someone uses "Set MyVariable = SomeValue".
        The function doesn't need to do anything nor return anything. Enables read-only
        GUI variables for the first time in WarCraft 3 history.
    
    GlobalRemapArray(variableStr[, getterFunc, setterFunc])
    @variableStr is a string such as "udg_MyVariableArray"
    @getterFunc is a function that takes the index of the array and returns the
        expected value when "MyVariableArray" is referenced.
    @setterFunc is a function that takes two arguments: the index of the array and the
        value the user is trying to assign. The function doesn't return anything.
----------------------------------------------------------------------------------------]]
local getters = {}
hook.add("__index", function(h, g, key)
    if getters[key]~=nil then
        return getters[key]()
    end
    return h.next(g, key)
end, 0, _G, rawget)

local setters = {}
hook.add("__newindex", function(h, g, key, val)
    if setters[key]~=nil then
        setters[key](val)
    else
        h.next(g, key, val)
    end
end, 0, _G, rawset)

local default = DoNothing

---Remap a non-array global variable to call getFunc when referenced or setFunc when assigned:
---
---`GlobalRemap(varName: string [, getFunc: (function -> any), setFunc: (function(value))])`
---@class GlobalRemap
---@overload fun(var: string, getFunc?: (fun():any),      setFunc?: fun(value))
function GlobalRemap(var, getFunc, setFunc)
    if not getters[var] then
        _G[var] = nil --Delete the variable from the global table.
        getters[var] = getFunc or default --Assign a function that returns what should be returned when this variable is referenced.
        setters[var] = setFunc or default --Assign a function that captures the value the variable is attempting to be set to.
    else
        if getFunc then
            hook(var, getFunc, 0, getters)
        end
        if setFunc then
            hook(var, setFunc, 0, setters)
        end
    end
    if getters[var] then
        if getFunc then
            hook(var, getFunc, 0, getters)
        end
    else
        getters[var] = getFunc or default   --Assign a function that returns what should be returned when this variable is referenced.
    end
    setters[var] = setFunc or default   --Assign a function that captures the value the variable is attempting to be set to.
end

---Remap a global variable array to call getFunc when referenced or setFunc when assigned:
---
---`GlobalRemapArray(arrayName: string [, getFunc: (function(index) -> any), setFunc: (function(index, value))])`
---@class GlobalRemapArray
---@overload fun(var: string, getFunc?: (fun(index):any), setFunc?: fun(index, value))
function GlobalRemapArray(var, getFunc, setFunc)
    getFunc = getFunc or default
    setFunc = setFunc or default
    _G[var] = setmetatable({}, {
        __index = function(_, index) return getFunc(index) end,
        __newindex = function(_, index, val) setFunc(index, val) end,
    })
end
end)
if Debug then Debug.endFile() end