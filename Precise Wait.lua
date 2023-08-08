if Debug then Debug.beginFile 'PreciseWait' end
do
--[[
    Precise Wait v1.6
    This changes the default functionality of TriggerAddAction, PolledWait
    and (because they don't work with manual coroutines) TriggerSleepAction and SyncSelections.

    Requires:
    - Hook: https://github.com/BribeFromTheHive/Lua/blob/master/Hook.lua

    Optionally Requires:
    - Debug Utils:              https://www.hiveworkshop.com/threads/debug-utils-ingame-console-etc.330758/
    - Total Initialization:     https://github.com/BribeFromTheHive/Lua/blob/master/Total%20Initialization.lua
    - Global Variable Remapper: https://github.com/BribeFromTheHive/Lua/blob/master/Global%20Variable%20Remapper.lua
    - Lua-Infused GUI (Influa): https://github.com/BribeFromTheHive/Lua/blob/master/Influa.lua
--]]

local printError = Debug and Debug.throwError or print

---@param name string
---@param error string
local function softErrorHandler(name, error)
    printError('!!!PreciseWait Error!!! "' .. name .. '" ' .. error)
end

local _ACTION_PRIORITY  =  1 --Specify the hook priority for hooking TriggerAddAction (higher numbers run earlier in the sequence).
local _WAIT_PRIORITY    = -2 --The hook priority for TriggerSleepAction/PolledWait

---@param duration number
local function wait(duration)
    local thread = coroutine.running()
    if thread then
        local t = CreateTimer()
        TimerStart(t, duration, false, function()
            DestroyTimer(t)
            coroutine.resume(thread)
        end)
        coroutine.yield()
    else
        softErrorHandler('Wait', 'was called from an invalid thread.')
    end
end

---@param require? {[string]: Requirement}
local function preciseWait(require)
    local remap

    if require then
        require.strict 'Hook'
        remap = require.lazily 'GlobalRemap'
        if remap then
            require.recommends 'GUI'

            --This enables GUI to access WaitIndex as a "local" index for their arrays, which allows
            --the simplest fully-instanciable data attachment in WarCraft 3's GUI history. However,
            --using it as an array index will cause memory leaks over time, unless you also install
            --Lua-Infused GUI.
            remap('udg_WaitIndex', coroutine.running)
        end
    end

    Hook.basic('PolledWait', wait, _WAIT_PRIORITY)
    Hook.basic('TriggerSleepAction', wait, _WAIT_PRIORITY)

    function Hook:SyncSelections()
        local thread = coroutine.running()
        if thread then
            local old = SyncSelections
            function SyncSelections() --this function gets re-declared each time, so calling it via ExecuteFunc will still reference the correct thread.
                SyncSelections = old
                self.next()
                coroutine.resume(thread)
            end
            ExecuteFunc('SyncSelections')
            coroutine.yield(thread)
        else
            self.next()
        end
    end

    ---@param hook Hook.property
    ---@param trig trigger
    ---@param func function
    ---@return triggeraction
    local function addActionFn(hook, trig, func)
        --Return a wrapper as the triggeraction instead. This wraps the actual function in a coroutine.
        return hook.next(trig, function()
            coroutine.wrap(func)()
        end)
    end

    Hook.add('TriggerAddAction', addActionFn, _ACTION_PRIORITY)
end

if OnInit then
    --Get OnInit at: https://github.com/BribeFromTheHive/Lua/blob/master/Total%20Initialization.lua
    OnInit.global('PreciseWait', preciseWait)
else
    local oldInit = InitGlobals
    function InitGlobals()
        oldInit()
        if Hook then
            preciseWait()
        else
            softErrorHandler('Hook', 'is required, and needs to be placed above "PreciseWait" in the Trigger Editor.')
        end
    end
end

end
if Debug then Debug.endFile() end