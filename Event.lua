if Debug then Debug.beginFile("Event") end

---@class EventTree: { [string]: Event }
---@field create     fun(name?: string): Event
---@field queue      fun(func: function, ...)
---@field freeze     fun(freeze_or_unfreeze: boolean)
---@field instant    fun(callback: fun(...), data)
---@field sleep      async fun(duration?: number, callback?: function, data?: any)
Event = nil

OnInit("Event", function() --https://github.com/BribeFromTheHive/Lua/blob/master/Total_Initialization.lua
--[[
    Event v2.2

    Event is built for GUI support, event linking via coroutines, simple events (e.g. Heal Event),
    binary events (like Unit Indexer) or complex event systems like Spell Event, Damage Engine and Unit Event.
--]]
    local hook        = Require.strict "Hook"            --https://github.com/BribeFromTheHive/Lua/blob/master/Hook.lua
    local remap       = Require.lazily "GlobalRemap"     --https://github.com/BribeFromTheHive/Lua/blob/master/Global_Variable_Remapper.lua
    local sleep       = Require.lazily "PreciseWait"     --https://github.com/BribeFromTheHive/Lua/blob/master/PreciseWait.lua
    local wrapTrigger = Require.lazily "GUI.wrapTrigger" --https://github.com/BribeFromTheHive/Lua/blob/master/Influa.lua
--[[
    API:

    Event.create
    ============
    Create an event that is recursion-proof by default, with easy syntax for GUI support.

    --In its most basic form:
    Event.create "MyEvent"          -> Create your event.
    Event.MyEvent.register(myFunc)  -> Global API for the user to call to register their callback function.
    Event.MyEvent()                 -> call this to execute the event (inherits this functionality from Hook).
    
    --If GUI has a variable by the same name, it hooks it internally (automating the udg_ portion) to allow this to work:
    Game - Value of MyEvent becomes Equal to 0.00

    NOTE - the value that MyEvent compares to is its priority in the event sequence, so events with higher numbers run first.

    --Enhanced event execution:
    Event.MyEvent.execute(extraValue:any, eventSucceeded:boolean, ...)
        - Run the event with special data attached (e.g. Spell Event uses the ability ID, Damage Engine uses limitops)
        - In most cases, eventSucceeded should be "true". However (for example) Attack Engine -> Damage Engine data transmission will use "false" to cover "missed" events.
        - Neither extraValue nor eventSucceeded are propogated as parameters to the callback functions.
    
    --Enhanced event registration:
    Event.SpellEffect.await(function() print "Medivh's Raven Form was used" end), 'Amrf', true)
        - This is an example of how Spell Event uses the ability ID to distinguish a special callback to this function.
        - The second parameter specifies the value that should be matched for the event to run.
        - The third value must be "true" if the event should be static (rather than called only once)
    
    --WaitForEvent functionality:
    Event.OnUnitIndexed.register(function()
        print"Unit Indexed" --runs for any unit.
        Event.OnUnitRemoval.await(function()
            print "Unit Deindexed" --runs only for the specific unit from the OnUnitIndexed event, and then automatically removes this one-off event once it runs.
        end)
    end)

    --SleepEvent:
    Event.sleep(2.5, function() print "this is called after 2.5 seconds" end)
        - In GUI: SleepEvent = 2.50

    --Instantly call a function with the spcified event data. Useful if the eventData was frozen from a previous state and now needs to function with wrappers that depend on Event.current.data.
    Event.instant(callback, eventData)
]]
    local _PRIORITY   = 1000 --The hook priority assigned to the event executor.
    
    local allocate
    local continue ---@type boolean

    ---@class Event.current
    ---@field success boolean
    ---@field funcData Event.funcData
    local currentEvent = {}

    ---@class Event
    ---@overload fun(...) --call Event.MyEventName(...) to execute the event with any number of parameters.
    -- - **Args:** `userFunc: function, priority?: number=0 [, t: trigger, l: limitop]`
    -- - **Desc:** Register a function which is to be executed each time the event runs.
    -- - **Note:** The `trigger` and `limitop` are only used when hooking `TriggerRegisterVariableEvent`
    ---@field register fun(callbackFunc:function, priority?:number, t?:trigger, l?:limitop):Event.funcData
    ---@field await fun(callbackFunc:function, onValue?:any, static?:boolean, priority?:number):Event.funcData --the callback function will listen for a specific value to be executed by the event, and will remove itself once it is called unless "static" is 'true'.
    ---@field execute fun(promiseID:any, successful:boolean, ...) --execute the event, including a unique promiseID that only serves to activate "await" callbacks.
    ---@field destroy function

    ---@class Event.funcData: Hook.property
    ---@field active boolean
    ---@field maxDepth integer

    Event = {}
    Event.current = currentEvent
    function Event.stop() continue = false end

    local cachedName = {} ---@type Event[]

    local function setEventMetaTable()
        ---@deprecated
        ---@return Event default
        function Event.new() end ---@diagnostic disable-line: missing-return

        setmetatable(Event, {
            __newindex = function(self, key, val) if val==nil then self.create(key) else rawset(self, key, val) end end,
            __index = function(_, key) return cachedName[key] end
        })
    end

    local depth = __jarray() ---@type { [Event.funcData]: integer }
    local promisedEvents = {} ---@type { [Event]: Event }
    do
        ---@param name? string
        ---@param event Event
        ---@param func function
        ---@param priority? number
        ---@param hookIndex? any
        ---@return Event.funcData
        local function addFunc(name, event, func, priority, hookIndex)
            assert(type(func)=="function")
            local funcData = hook.add(hookIndex or name,
                function(self, ...)
                    if continue then
                        ---@cast self Event.funcData
                        if self.active then
                            currentEvent.funcData = self
                            depth[self] = 0
                            func(...)
                        end
                        self.next(...)
                    end
                end,
                priority, hookIndex and promisedEvents[event] or event
            )
            ---@cast funcData Event.funcData
            funcData.active = true
            return funcData
        end

        -- Optionally specify a unique name for the event. GUI trigger registration will check if "udg_".."ThisEventName" exists, so do not prefix it with udg_.
        function Event.create(name)
            local event = allocate(name)

            function event.register(userFunc, priority)
                return addFunc(name, event, userFunc, priority)
            end

            ---Calls userFunc when the event is run with the specified index.
            ---@param userFunc      function
            ---@param onValue       any         Defaults to currentEvent.data. This is the value that needs to match when the event runs.
            ---@param static?       boolean     If true, will persists after the first call. If false, will remove itself after being called the first time.
            ---@param priority?     number      defaults to 0
            ---@return Event.funcData
            function event.await(userFunc, onValue, static, priority)
                onValue = onValue or currentEvent.data
                return addFunc(nil, event,
                    function(self, ...)
                        userFunc(...)
                        if not static then
                            self:remove()
                        end
                    end,
                    priority, onValue
                )
            end
            return event --return the event object. Not needed; the user can just access it via Event.MyEventName
        end
    end

    local createHook
    do
        local realID --Needed for GUI support to correctly detect Set WaitForEvent = SomeEvent.
        realID = {
            n = 0,
            name = {},
            create = function(name)
                realID.n = realID.n + 1
                realID.name[realID.n] = name
                return realID.n
            end,
        }

        local function testGlobal(udgName) return globals[udgName] end
        ---@param name string
        function createHook(name)
            local udgName = "udg_"..name
            local isGlobal = pcall(testGlobal, udgName)
            local destroy

            udgName = (isGlobal or _G[udgName]) and udgName
            if udgName then --only proceed with this block if this is a GUI-compatible string.
                if isGlobal then
                    globals[udgName] = realID.create(name) --WC3 will complain if this is assigned to a non-numerical value, hence have to generate one.
                else
                    _G[udgName] = name --do this as a failsafe in case the variable exists but didn't get declared in a GUI Variable Event.
                end
                destroy = select(2, hook.add(
                    "TriggerRegisterVariableEvent", --PreciseWait is needed if triggers use WaitForEvent/SleepEvent.
                    function(h, userTrig, userStr, userOp, priority)
                        if udgName == userStr then
                            Event[name].register(
                                wrapTrigger and wrapTrigger(userTrig) or
                                function()
                                    if IsTriggerEnabled(userTrig) and TriggerEvaluate(userTrig) then
                                        TriggerExecute(userTrig)
                                    end
                                end,
                                priority, userTrig, userOp
                            )
                        else
                            return h.next(userTrig, userStr, userOp, priority)
                        end
                    end
                ))
            end
            return function()
                if destroy then destroy() end
                Event[name] = nil
            end
        end

        ---Call a function after a period of time, with the current event data being preserved for Event.current.data syntax in systems such as SpellEvent.
        ---duration defaults to 0. Callback defaults to yielding an resuming the current coroutine. Data defaults to Event.current.data, but can be used to execute data asynchronously.
        function Event.sleep(duration, callback, data)
            data = data or currentEvent.data
            TimerStart(CreateTimer(), duration or 0, false, function() DestroyTimer(GetExpiredTimer()); Event.instant(callback, data) end)
            if not callback then
                local co = coroutine.running()
                callback = function() coroutine.resume(co) end
                coroutine.yield()
            end
        end

        if remap then
            if sleep then
                remap("udg_WaitForEvent", nil,
                    ---@async
                    function(whichEvent)
                        if type(whichEvent) == "number" then
                            whichEvent = realID.name[whichEvent] --this is a real value (globals.udg_eventName) rather than simply _G.eventName (which stores the string).
                        end
                        assert(whichEvent)
                        local co = coroutine.running()
                        Event[whichEvent].await(function() coroutine.resume(co) end)
                        coroutine.yield()
                    end
                )
                remap("udg_SleepEvent", nil, Event.sleep)
            end
            remap("udg_EventSuccess", function() return currentEvent.success end, function(value) currentEvent.success = value end)
            remap("udg_EventOverride",  nil, Event.stop)
            remap("udg_EventIndex",          function() return currentEvent.data end)
            remap("udg_EventRecursion", nil, function(maxDepth) currentEvent.funcData.maxDepth = maxDepth end)
        end
    end
    
    local createExecutor
    do
        local frozenQ = {} ---@type Event.funcData[]
        local callQueue ---@type { [1]: function, n: integer }[]|nil

        function createExecutor(next, event)
            local promise = promisedEvents[event]
            local function runEvent(promiseID, success, eventID, ...)
                continue = true
                currentEvent.data = eventID
                currentEvent.success = success
                if promiseID then
                    if promise[promiseID] then
                        promise[promiseID](eventID, ...)   --promises are run before normal events.
                        success = currentEvent.success
                    end
                    if promiseID~=eventID and promise[eventID] then --avoid calling duplicate promises. The eventID also counts as a promise, provided they are different.
                        promise[eventID](eventID, ...)
                        success = currentEvent.success
                    end
                end
                if success then
                    next(eventID, ...)
                end
            end
            return function(...)
                Event.queue(runEvent, ...)
            end
        end

        local unfrozen, releasing  = true, false
        local function release()
            if unfrozen and not releasing then
                releasing = true
                while callQueue do --This works similarly to the recursion processing introduced in Damage Engine 5.
                    local tempQ = callQueue
                    callQueue = nil
                    for _,args in ipairs(tempQ) do
                        args[1](table.unpack(args, 2, args.n)) --args[1] points to the "runEvent" function specific to the event that's getting called now.
                    end
                end
                for i=1, #frozenQ do
                    frozenQ[i].active = true
                    frozenQ[i] = nil
                end
                releasing = false
                currentEvent.funcData = nil
            end
        end

        ---If an event is already running, wait until it has finished before calling "func".
        ---Otherwise, call "func" immediately.
        function Event.queue(func, ...)
            local funcData = currentEvent.funcData
            if funcData then --if another event is already running.
                callQueue = callQueue or {}
                table.insert(callQueue, table.pack(func, ...)) --rather than going truly recursive, queue the event to be ran after the already queued event(s).
                depth[funcData] = depth[funcData] + 1
                if depth[funcData] > (funcData.maxDepth or 0) then --max recursion has been reached for this function.
                    funcData.active = false
                    table.insert(frozenQ, funcData) --Pause it and let it be automatically unpaused at the end of the sequence.
                end
            else
                func(...)
                release()
            end
        end

        --Freeze any queued events from running until the queue is unfrozen.
        function Event.freeze(flag)
            unfrozen = not flag
            if not currentEvent.funcData then
                release()
            end
        end
    end

    ---@param name? string
    ---@return Event
    function allocate(name)
        local event = {} ---@type Event
        if name then
            assert(type(name)=="string" or not Event[name])
            cachedName[name] = event
        end
        local this = hook.add(event,
            function(eventIndex, ...)
                event.execute(eventIndex, true, eventIndex, ...) --normal Event("MyEvent",...) function call will have the promise ID matched to the event ID, and "success" as true.
            end,
            _PRIORITY, Event
        )
        promisedEvents[event] = __jarray() --using a jarray allows Lua-Infused GUI to clean up expired promises.
        event.execute = createExecutor(this.next, event)
        event.destroy = name and createHook(name) or DoNothing
        return event
    end
    
    local instant = Event.create()
    function Event.instant(callback, data) --useful to treat non-event sequences as part of an ad hoc event (without re-triggering all of the subsequent events that are part of that chain).
        local r = instant.register(callback)
        instant(data)
        Hook.delete(r)
    end

    setEventMetaTable()
end)
if Debug then Debug.endFile() end

local bob = Event.create()
bob.register(function() end)