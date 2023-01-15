OnInit.global("Action", function(uses)
    uses "GlobalRemap" --(https://www.hiveworkshop.com/threads/global-variable-remapper.339308)
    uses "PreciseWait" --https://www.hiveworkshop.com/threads/precise-wait-gui-friendly.316960/
--[[
    Action v1.3.0.0 by Bribe

    What it does:
        1) Allows GUI to declare its own functions to be passed to a Lua system.
        2) Automatic variable localization and cleanup for effects.
        3) Automatic variable localization for units, reals, integers, groups and locations.
        4) Recursive local tracking (as long as array indices are not shadowed).

    Why it can benefit:
        1) Allows you to have all of your functions in one GUI trigger
        2) Each trigger and each sub-action within the trigger has access to each others' data.
        3) No need to create the same variables for each new trigger if you use the variables provided here.

    How it works:
        1) In some cases replaces ForForce, allowing you to manipulate the callback function instead.
        2) Attaches data via coroutines, allowing all locals powered by this system to be local to the running instance of the trigger, regardless of how many times it waits.
        3) To destroy (for example) a unit group: Set DestroyGroup = TempGroup1
--]]
    ---@class Action
    ---@field create fun(whichVar:string, onForForce:fun(callback:fun(), arrayIndex?:any), isArray?:boolean)
    ---@field wait fun(duration:number)
    Action={}

    local systemPrefix="udg_Action_"
    local actions={}
    local cleanTracker
    local topIndex=__jarray()
    local lastIndex

    function Hook:ForForce(whichForce, whichFunc)
        if actions[whichForce] then
            local index=lastIndex
            lastIndex=nil
            actions[whichForce](whichFunc, index)
        else
            self.next(whichForce, whichFunc)
        end
    end

    ---@param whichVar      string                                  --The name of the user-defined global. It will add the udg_ prefix if you don't feel like adding it yourself.
    ---@param onForForce    fun(callback:fun(), arrayIndex?:any)    --Takes the GUI function passed to ForForce and allows you to do whatever you want with it instead.
    ---@param isArray?      boolean                                 --If true, will pass the array index to the onForForce callback.
    function Action.create(whichVar, onForForce, isArray)
        if whichVar:sub(1,4)~="udg_" then
            whichVar="udg_"..whichVar
        end
        local force = _G[whichVar]
        if isArray then
            if force then
                GlobalRemapArray(whichVar, function(index)
                    lastIndex=index
                    return whichVar
                end)
            end
        else
            if force then
                GlobalRemap(whichVar, function()
                    lastIndex=nil
                    return whichVar
                end)
            end
        end
        actions[whichVar]=onForForce
    end
    local durations=__jarray()
    local getCoroutine=coroutine.running
    Action.create(systemPrefix.."forDuration", function(func)
        local co = getCoroutine()
        if durations[co] then
            while durations[co] > 0 do
                func()
            end
        end
    end)

    GlobalRemap(systemPrefix.."duration", function() return durations[getCoroutine()] end, function(val) durations[getCoroutine()] = val end)
    
    --Look at this: Every time a trigger runs, it can have its own fully-fledged, perfectly MUI hashtable, without having to initialize or destroy it manually.
    local hash = __jarray()
    GlobalRemap(systemPrefix.."hash", function()
        local parent = topIndex[getCoroutine()]
        hash[parent] = hash[parent] or __jarray()
        return hash[parent]
    end)

    ---Nearly the same as Precise PolledWait, with the exception that it tracks the duration.
    ---@param duration number
    function Action.wait(duration)
        local co = getCoroutine()
        if co then
            local t = CreateTimer()
            TimerStart(t, duration, false, function()
                DestroyTimer(t)
                if durations[co] then
                    durations[co] = durations[co] - duration
                end
                coroutine.resume(co)
            end)
            coroutine.yield(co)
        end
    end
    GlobalRemap(systemPrefix.."wait", nil, Action.wait)

    local function cleanup(co)
        if cleanTracker[co] then
            for _,obj in ipairs(cleanTracker[co]) do
                DestroyEffect(obj)
            end
        end
    end

    ---Allows the function to be run as a coroutine a certain number of times (determined by the array index)
    ---Most importantly, the calling function does not wait for these coroutines to complete (just like in GUI when you execute a trigger from another trigger).
    Action.create(systemPrefix.."loop",
        ---@param func function
        ---@param count number
        function(func, count)
            local top = getCoroutine()
            for _=1,count do
                local co
                co = coroutine.create(function()
                    func()
                    cleanup(co)
                end)
                topIndex[co]=top
                coroutine.resume(co)
            end
        end
    , true)
    Hook.add("TriggerAddAction", function(h, trig, func)
        return h.next(trig, function()
            local co = getCoroutine()
            topIndex[co]=co
            func()
            cleanup(co)
        end)
    end, 2)

    GlobalRemap(systemPrefix.."index", function() return topIndex[getCoroutine()] end)

    for _,name in ipairs {
        "point",
        "group",
        "effect",
        "integer",
        "real",
        "unit"
    } do
        local tracker=__jarray()
        local varName=systemPrefix..name
        if name=="effect" then
            cleanTracker=tracker
        end
        GlobalRemapArray(varName, function(index)
            local co = getCoroutine()
            ::start::
            local result = rawget(tracker[co], index) --check if the value is already assigned at the level of the current coroutine
            if not result and topIndex[co]~=co then
                --If not, hunt around and try to find if any calling coroutines have the index assigned.
                co = topIndex[co]
                goto start
            end
            return result
        end,
        function(index, val)
            local tb = tracker[getCoroutine()]
            if not tb then
                tb={}
                tracker[getCoroutine()]=tb
            elseif name=="effect" and tb[index] then
                DestroyEffect(tb[index])
            end
            tb[index]=val
        end)
    end
end, Debug and Debug.getLine())