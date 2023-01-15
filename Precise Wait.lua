OnInit.global("PreciseWait", function(require) --https://github.com/BribeFromTheHive/Lua/blob/master/Total_Initialization.lua

    local hook  = require.strict "Hook"        --https://github.com/BribeFromTheHive/Lua/blob/master/Hook.lua
    local remap = require.lazily "GlobalRemap" --https://github.com/BribeFromTheHive/Lua/blob/master/Global_Variable_Remapper.lua
    if remap then
        require.recommends "GUI"               --https://github.com/BribeFromTheHive/Lua/blob/master/Influa.lua
    end
    
    --Precise Wait v1.5.3.0
    --This changes the default functionality of TriggerAddAction, PolledWait
    --and (because they don't work with manual coroutines) TriggerSleepAction and SyncSelections.
    
    local _ACTION_PRIORITY  =  1 --Specify the hook priority for hooking TriggerAddAction (higher numbers run earlier in the sequence).
    local _WAIT_PRIORITY    = -2 --The hook priority for TriggerSleepAction/PolledWait

    local function wait(duration)
        local thread = coroutine.running()
        if thread then
            local t = CreateTimer()
            TimerStart(t, duration, false, function()
                DestroyTimer(t)
                coroutine.resume(thread)
            end)
            coroutine.yield(thread)
        end
    end

    if remap then
        --This enables GUI to access WaitIndex as a "local" index for their arrays, which allows
        --the simplest fully-instanciable data attachment in WarCraft 3's GUI history. However,
        --using it as an array index will cause memory leaks over time, unless you also install
        --Lua-Infused GUI.
        remap("udg_WaitIndex", coroutine.running)
    end
    
    hook.basic("PolledWait", wait, _WAIT_PRIORITY)
    hook.basic("TriggerSleepAction", wait, _WAIT_PRIORITY)
    
    function Hook:SyncSelections()
        local thread = coroutine.running()
        if thread then
            local old = SyncSelections
            SyncSelections = function() --this function gets re-declared each time, so calling it via ExecuteFunc will still reference the correct thread.
                SyncSelections = old
                self.next()
                coroutine.resume(thread)
            end
            ExecuteFunc("SyncSelections")
            coroutine.yield(thread)
        end
    end

    hook.add("TriggerAddAction", function(h, trig, func)
        --Return a function that will actually be added as the triggeraction, which itself wraps the actual function in a coroutine.
        return h.next(trig, function() coroutine.wrap(func)() end)
    end, _ACTION_PRIORITY)
end, Debug and Debug.getLine())