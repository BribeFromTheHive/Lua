OnInit.global("Unit Indexer", function(require)  --https://github.com/BribeFromTheHive/Lua/blob/master/Total_Initialization.lua
    require "GlobalRemap" --https://github.com/BribeFromTheHive/Lua/blob/master/Global_Variable_Remapper.lua
    require "Event"       --https://github.com/BribeFromTheHive/Lua/blob/master/Event.lua

    Event.create "OnUnitIndexed"
    Event.create "OnUnitRemoval"

    ---@diagnostic disable: undefined-global, cast-local-type

    local unitRef = setmetatable({}, {__mode = "k"})
    local eventUnit
    local collector = {__gc = function(unit)
        eventUnit = unit[1]
        unitRef[eventUnit] = nil
        Event.OnUnitRemoval(eventUnit)
    end}

    ---@overload fun(unit):unit
    GetUnitUserData = function(unit) return unit end
    
    GlobalRemap("udg_UDex",  function() return eventUnit end) --fools GUI into thinking unit is an integer
    GlobalRemapArray("udg_UDexUnits", function(unit) return unit end)

    local preplaced = true

    OnInit.trig(function()
        local re, r = CreateRegion(), GetWorldBounds(); RegionAddRect(re, r); RemoveRect(r)
        local b = Filter(
        function()
            local u = GetFilterUnit()
            if not unitRef[u] then
                unitRef[u] = {u}
                setmetatable(unitRef[u], collector)
                if rawget(_G, "udg_IsUnitPreplaced") then
                    udg_IsUnitPreplaced[u] = preplaced
                end
                eventUnit = u
                Event.OnUnitIndexed(u)
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, b)
        for i = 0, bj_MAX_PLAYER_SLOTS -1 do
            GroupEnumUnitsOfPlayer(bj_lastCreatedGroup, Player(i), b)
        end
        preplaced = nil
    end)
end, Debug and Debug.getLine())