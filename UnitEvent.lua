OnInit("UnitEvent", function()

    Require "Timed"         --https://github.com/BribeFromTheHive/Lua/blob/main/Timed.lua
    Require "AddHook"       --https://github.com/BribeFromTheHive/Lua/blob/main/Hook.lua
    Require "GlobalRemap"   --https://github.com/BribeFromTheHive/Lua/blob/main/Global_Variable_Remapper.lua
    Require "Event"         --https://github.com/BribeFromTheHive/Lua/blob/main/Event.lua
    
    local anyUnitEvent = Require "RegisterAnyPlayerUnitEvent"   --https://github.com/BribeFromTheHive/Lua/blob/main/Influa.lua
    
    --needed for GUI coroutine support.
    Require.optionally "PreciseWait"   --https://github.com/BribeFromTheHive/Lua/blob/main/PreciseWait.lua
--[[
Lua Unit Event 1.4.0.0

In addition to the existing benefits enjoyed over the past years, this Lua version supports linked events that allow
your trigger to Wait until another event runs (meaning you can do attachment and cleanup from one trigger).

Variable names have been completely changed from all prior Unit Event incarnations.
> All real variable event names are now prefixed with OnUnit...
> All array references (unit properties) are now prefixed with UnitEvent_
> Lua users can access a unit's properties via UnitEvent[unit].property (e.g. reincarnating/cargo)
> Lua users can easily add a readonly GUI property to a unit via UnitEvent.addProperty("propertyName")
>>> GUI accesses it via UnitEvent_propertyName, the second is readable and writable within Lua via UnitEvent[unit].propertyName
> UnitUserData (custom value of unit) has been completely removed. This is the first unit event/indexer to not use UnitUserData nor hashtables.
>>> UnitEvent_unit is the subject unit of the event.
>>> UnitEvent_index is an integer in GUI, but points to a the unit.
>>> UnitEvent_setKey lets you assign a unit to the key.
>>> UnitEvent_getKey is an integer in GUI, but points to the unit you assigned as the key.
>>>>> Lua doesn't care about array max sizes, nor the type of information used as an index in that array (because it uses tables and not arrays).
>>>>> GUI is over 20 years old and can easily be fooled. As long as the variable is defined with the correct type, it doesn't care what happens to that variable behind the scenes.
--]]
    
    UnitEvent={}

    local _REMOVE_ABIL      = FourCC('A001')
    local _TRANSFORM_ABIL   = FourCC('A002') --be sure to assign these to their respective abilities if you prefer not to initialize via GUI
    
    local unitIndices={} ---@type UnitEventTable[]

    --Backwards-compatibility API (comment-out what you don't need):
    local function InitLegacyAPI()
        --Core functionality:
        ---@overload fun(unit):unit
        GetUnitUserData = function(unit) return unit end
        GlobalRemap("udg_UDex",  function() return Event.current.data.unit end) --fools GUI into thinking unit is an integer
        GlobalRemapArray("udg_UDexUnits", function(unit) return unit end)
        
        --Unit Event properties:
        GlobalRemapArray("IsUnitPreplaced",     function(unit) return unitIndices[unit].preplaced end)
        GlobalRemapArray("SummonerOfUnit",      function(unit) return unitIndices[unit].summoner end)
        GlobalRemapArray("UnitTypeOf",          function(unit) return unitIndices[unit].unitType end)
        GlobalRemapArray("IsUnitReincarnating", function(unit) return unitIndices[unit].reincarnating end)
        GlobalRemapArray("CargoTransportUnit",  function(unit) return unitIndices[unit].transporter end)
        GlobalRemapArray("CargoTransportGroup", function(unit) return unitIndices[unit].cargo end)
        GlobalRemapArray("udg_KillerOfUnit",    GetKillingUnit) --only works from the primary event; no longer persists after that even is over.

        --Unit Events:
        Event.create "UnitIndexEvent"
        .register = function(func, index)
            local --[[index == 2]]      name = "OnUnitRemoval"
            if index == 1 then          name = "OnUnitIndexed"
            elseif index == 1.5 then    name = "OnUnitCreation"
            end
            return Event[name].register(func)
        end

        Event.create "DeathEvent"
        .register = function(func, index)
            local --[[index == 2]]      name = "OnUnitRevival"
            if index == 1 then          name = "OnUnitDeath"
            elseif index == 0.5 then    name = "OnUnitReincarnating"
            end
            return Event[name].register(func)
        end

        Event.create "CargoEvent"
        .register = function(func, index)
            local name = "OnUnitUnloaded" --index == 2
            if index == 1 then
                name = "OnUnitLoaded"
            end
            return Event[name].register(func)
        end
        
        Event.create "UnitTypeEvent"
        .register = Event.OnUnitTransform.register --this one is an easy 1:1

        Event.create "UnitInActionEvent"
        .register = function(func, index)
            local name = "OnUnitPassive" --index == 2
            if index == 1 then
                name = "OnUnitActive"
            end
            return Event[name].register(func)
        end
    end

--[[
    Full list of GUI variables:
    real    udg_OnUnitIndexed
    real    udg_OnUnitCreation
    real    udg_OnUnitRemoval
    real    udg_OnUnitReincarnating
    real    udg_OnUnitRevival
    real    udg_OnUnitLoaded
    real    udg_OnUnitUnloaded
    real    udg_OnUnitTransform
    real    udg_OnUnitDeath
    real    udg_OnUnitActive
    real    udg_OnUnitPassive

    ability udg_DetectRemoveAbility
    ability udg_DetectTransformAbility

    unit    udg_UnitEvent_unit
    integer udg_UnitEvent_index

    unit    udg_UnitEvent_setKey
    integer udg_UnitEvent_getKey

    boolean   array udg_UnitEvent_preplaced
    unit      array udg_UnitEvent_summoner
    unittype  array udg_UnitEvent_unitType
    boolean   array udg_UnitEvent_reincarnating
    unit      array udg_UnitEvent_transporter
    unitgroup array udg_UnitEvent_cargo
--]]

    --The instant a unit starts to exist. Not all of the unit's properties are fully loaded at this point, so it is better to use OnUnitCreation if you need to access those.
    Event.create "OnUnitIndexed"
    --Occurs 0 seconds after a unit is created; more useful than OnUnitIndexed because the unit is fully accessible at this point. Thanks @Spellbound for this event.
    Event.create "OnUnitCreation"
    --The instant a unit is fully removed from the game:
    Event.create "OnUnitRemoval"
    
    --When a unit starts to reincarnate:
    Event.create "OnUnitReincarnating"
    --When a unit finishes reincarnating or is resurrected or temporarily re-animated:
    Event.create "OnUnitRevival"
    
    --When a unit is loaded into a transport unit (Goblin Zeppelin / Orc Burrow / Transport Ship):
    Event.create "OnUnitLoaded"
    --When a unit is unloaded from a transport unit
    Event.create "OnUnitUnloaded"
    
    --When a unit transforms into a nother unit (e.g. Bear Form / Crow Form):
    Event.create "OnUnitTransform"

    --When a unit dies or is created dead (e.g. a ghoul corpse at a Graveyard/meatwagon):
    Event.create "OnUnitDeath"
    
    --When a unit becomes playable (created/summoned, revived or unloaded from a transport):
    Event.create "OnUnitActive"
    --When a unit is unplayable (dead, reincarnating, removed or loaded into a transport):
    Event.create "OnUnitPassive"

    --Used to get the UnitEvent table from the unit to detect UnitEvent-specific properties.
    function UnitEvent.__index(_, unit) return unitIndices[unit] end
    
    ---@param name string
    function UnitEvent.addProperty(name)
        GlobalRemapArray("udg_UnitEvent_"..name, function(unit) return unitIndices[unit][name] end)
    end

    ---@class UnitEventTable : table
    ---@field unit          unit
    ---@field preplaced     boolean
    ---@field summoner      unit
    ---@field transporter   unit
    ---@field cargo         group
    ---@field reincarnating boolean
    ---@field unitType      integer
    ---@field package new boolean
    ---@field package alive boolean
    ---@field package unloading boolean
    
    --The below two variables are intended for GUI typecasting, because you can't use a unit as an array index.
    --What it does is bend the rules of GUI (which is still bound by strict JASS types) by transforming those
    --variables with Global Variable Remapper (which isn't restricted by any types).
    --"setKey" is write-only (assigns the key to a unit)
    --"getKey" is read-only (retrieves the key and tells GUI that it's an integer, allowing it to be used as an array index)
    local lastUnit
    GlobalRemap("udg_UnitEvent_setKey", nil, function(unit)lastUnit=unit end) --assign to a unit to unlock the getKey variable.
    GlobalRemap("udg_UnitEvent_getKey",      function() return lastUnit  end) --type is "integer" in GUI but remains a unit in Lua.

    do
        local function getEventUnit() return Event.current.data.unit end
        GlobalRemap("udg_UnitEvent_unit",  getEventUnit) --the subject unit for the event.
        GlobalRemap("udg_UnitEvent_index", getEventUnit) --fools GUI into thinking unit is an integer
    end
    --add a bunch of read-only arrays to access GUI data. I've removed the "IsUnitAlive" array as the GUI living checks are fixed with the GUI Enhancer Colleciton.
    UnitEvent.addProperty "preplaced"
    UnitEvent.addProperty "unitType"
    UnitEvent.addProperty "reincarnating"
    UnitEvent.addProperty "transporter"
    UnitEvent.addProperty "summoner"
    
    if rawget(_G, "udg_UnitEvent_cargo") then
        UnitEvent.addProperty "cargo"
    end
    
    --Flag a unit as being able to move or attack on its own:
    local function setActive(unitTable)
        if unitTable and not unitTable.active and UnitAlive(unitTable.unit) then --be sure not to run the event when corpses are created/unloaded.
            unitTable.active = true
            Event.OnUnitActive(unitTable)
        end
    end
    ---Flag a unit as NOT being able to move or attack on its own:
    local function setPassive(unitTable)
        if unitTable and unitTable.active then
            unitTable.active = nil
            Event.OnUnitPassive(unitTable)
        end
    end

    Event.OnUnitCreation.register(setActive, 2)
    Event.OnUnitUnloaded.register(setActive, 2)
    Event.OnUnitRevival.register(setActive, 2)
    
    Event.OnUnitLoaded.register(setPassive, 2)
    Event.OnUnitReincarnating.register(setPassive, 2)
    Event.OnUnitDeath.register(setPassive, 2)
    Event.OnUnitRemoval.register(setPassive, 2)
    
    --UnitEvent.onIndex(function(unitTable) print(tostring(unitTable.unit).."/"..GetUnitName(unitTable.unit).." has been indexed.") end)
    
    setmetatable(UnitEvent, UnitEvent)

    InitLegacyAPI()

    --Wait until GUI triggers and events have been initialized. 
    OnInit.trig(function()
        if rawget(_G, "Trig_Unit_Event_Config_Actions") then
            Trig_Unit_Event_Config_Actions()                                ---@diagnostic disable-line: undefined-global
            _REMOVE_ABIL    = udg_DetectRemoveAbility    or _REMOVE_ABIL    ---@diagnostic disable-line: undefined-global
            _TRANSFORM_ABIL = udg_DetectTransformAbility or _TRANSFORM_ABIL ---@diagnostic disable-line: undefined-global
        end
        local function checkAfter(unitTable)
            if not unitTable.checking then
                unitTable.checking              = true
                Timed.call(0, function()
                    unitTable.checking          = nil
                    if unitTable.new then
                        unitTable.new           = nil
                        Event.OnUnitCreation(unitTable) --Credit for this idea to @Spellbound. This event works way better than the OnUnitIndexed event.
                    elseif unitTable.transforming then
                        local unit = unitTable.unit
                        Event.OnUnitTransform(unitTable)
                        unitTable.unitType = GetUnitTypeId(unit) --Set this afterward to give the user extra reference

                        --Reset the transforming flags so that subsequent transformations can be detected.
                        unitTable.transforming  = nil
                        UnitAddAbility(unit, _TRANSFORM_ABIL)
                    elseif unitTable.alive then
                        unitTable.reincarnating = true
                        unitTable.alive         = false
                        Event.OnUnitReincarnating(unitTable)
                    elseif UnitAlive(unitTable.unit) then
                        unitTable.alive = true
                        Event.OnUnitRevival(unitTable)
                        unitTable.reincarnating = false
                    end
                end)
            end
        end
    
        local re = CreateRegion()
        local r = GetWorldBounds()
        local maxX, maxY = GetRectMaxX(r), GetRectMaxY(r)
        RegionAddRect(re, r); RemoveRect(r)
        
        local function unloadUnit(unitTable)
            local unit, transport       = unitTable.unit, unitTable.transporter
            GroupRemoveUnit(unitIndices[transport].cargo, unit)
            unitTable.unloading         = true
            Event.OnUnitUnloaded(unitTable)
            unitTable.unloading         = nil
            if not IsUnitLoaded(unit) or not UnitAlive(transport) or GetUnitTypeId(transport) == 0 then
                unitTable.transporter   = nil
            end
        end
        
        local preplaced = true
        local onEnter = Filter(function()
            local unit = GetFilterUnit()
            local unitTable = unitIndices[unit]
            if not unitTable then
                unitTable = {
                    unit    = unit,
                    new     = true,
                    alive   = true,
                    unitType= GetUnitTypeId(unit)
                }
                UnitAddAbility(unit, _REMOVE_ABIL)
                UnitMakeAbilityPermanent(unit, true, _REMOVE_ABIL)
                UnitAddAbility(unit, _TRANSFORM_ABIL)

                unitIndices[unit] = unitTable

                unitTable.preplaced = preplaced
                Event.OnUnitIndexed(unitTable)
                
                checkAfter(unitTable)
            elseif unitTable.transporter and not IsUnitLoaded(unit) then
                --the unit was dead, but has re-entered the map (e.g. unloaded from meat wagon)
                unloadUnit(unitTable)
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, onEnter)
        
        anyUnitEvent(EVENT_PLAYER_UNIT_LOADED,
            function()
                local unit = GetTriggerUnit()
                local unitTable = unitIndices[unit]
                if unitTable then
                    if unitTable.transporter then
                        unloadUnit(unitTable)
                    end
                    --Loaded corpses do not issue an order when unloaded, therefore must
                    --use the enter-region event method taken from Jesus4Lyf's Transport: https://www.thehelper.net/threads/transport-enter-leave-detection.126051/
                    if not unitTable.alive then
                        SetUnitX(unit, maxX)
                        SetUnitY(unit, maxY)
                    end
                    local transporter = GetTransportUnit()
                    unitTable.transporter = transporter
                    local g = unitIndices[transporter].cargo
                    if not g then
                        g=CreateGroup()
                        unitIndices[transporter].cargo = g
                    end
                    GroupAddUnit(g, unit)
                    
                    Event.OnUnitLoaded(unitTable)
                end
            end
        )
        anyUnitEvent(EVENT_PLAYER_UNIT_DEATH,
            function()
                local unitTable = unitIndices[GetTriggerUnit()]
                if unitTable then
                    unitTable.alive = false
                    Event.OnUnitDeath(unitTable)
                    if unitTable.transporter then
                        unloadUnit(unitTable)
                    end
                end
            end
        )
        anyUnitEvent(EVENT_PLAYER_UNIT_SUMMON,
            function()
                local unitTable = unitIndices[GetTriggerUnit()]
                if unitTable.new then
                    unitTable.summoner = GetSummoningUnit()
                end
            end
        )
        local orderB = Filter(function()
            local unit = GetFilterUnit()
            local unitTable = unitIndices[unit]
            if unitTable then
                if GetUnitAbilityLevel(unit, _REMOVE_ABIL) == 0 then

                    Event.OnUnitRemoval(unitTable)
                    unitIndices[unit] = nil
                    unitTable.cargo = nil
                elseif not unitTable.alive then
                    if UnitAlive(unit) then
                        checkAfter(unitTable)
                    end
                elseif not UnitAlive(unit) then
                    if unitTable.new then
                        --This unit was created as a corpse.
                        unitTable.alive = false
                        Event.OnUnitDeath(unitTable)

                    elseif not unitTable.transporter or not IsUnitType(unit, UNIT_TYPE_HERO) then
                        --The unit may have just started reincarnating.
                        checkAfter(unitTable)
                    end
                elseif GetUnitAbilityLevel(unit, _TRANSFORM_ABIL) == 0 and not unitTable.transforming then
                    unitTable.transforming = true
                    checkAfter(unitTable)
                end
                if unitTable.transporter and not unitTable.unloading and not (IsUnitLoaded(unit) and UnitAlive(unit)) then
                    unloadUnit(unitTable)
                end
            end
        end)
        
        local p
        local order = CreateTrigger()
        for i = 0, bj_MAX_PLAYER_SLOTS - 1 do
            p = Player(i)
            GroupEnumUnitsOfPlayer(bj_lastCreatedGroup, p, onEnter)
            SetPlayerAbilityAvailable(p, _REMOVE_ABIL, false)
            SetPlayerAbilityAvailable(p, _TRANSFORM_ABIL, false)
            TriggerRegisterPlayerUnitEvent(order, p, EVENT_PLAYER_UNIT_ISSUED_ORDER, orderB)
        end
        preplaced = false
    end)
end, Debug and Debug.getLine())