OnInit("SpellEvent", function() --Lua Spell Event v1.0 by Bribe
    Require "GlobalRemap"                   --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    Require "RegisterAnyPlayerUnitEvent"    --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua
    Require "Event"                         --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Event.lua
    Require "Action"                        --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Action.lua
    Require "PreciseWait"                   --https://github.com/BribeFromTheHive/Lua-Core/blob/main/PreciseWait.lua

    SpellEvent={}

    local _AUTO_ORDER = "spellsteal" --If TriggerRegisterCommandEvent is called and this order is specified,
    --ignore the actual request and instead allow it to be treated as an aiblity to be registered by Spell System.
    --In GUI, this event looks like: Game - Button for ability Animate Dead and order Human Spellbreaker - Spell Steal pressed.
    --If you actually WANT to use this order with this event, you could assign this to a different order (e.g. "battleroar").
    --If you want to be using ALL of these, then I recommend waiting until OnInit.final to register your own TriggerRegisterCommandEvent.

    --[=========================================================================================[
    Required GUI variables:
    
    Events work differently, and it's now allowed to create a spell without being forced into using a separate Config trigger.
        real udg_OnSpellChannel
        real udg_OnSpellCast
        real udg_OnSpellEffect
        real udg_OnSpellFinish

    The below preserve the API from the vJass version:
        unit        udg_Spell__Caster           -> When set, will assign Spell__Index to whatever the last spell this unit cast was.
        player      udg_Spell__CasterOwner
        location    udg_Spell__CastPoint
        location    udg_Spell__TargetPoint
        unit        udg_Spell__Target
        integer     udg_Spell__Index            -> Now is a Lua table behind the scenes. Can alternatively use udg_EventIndex, which is part of Event.
        integer     udg_Spell__Level
        real        udg_Spell__LevelMultiplier
        abilcode    udg_Spell__Ability
        boolean     udg_Spell__Completed
        boolean     udg_Spell__Channeling
        real        udg_Spell__Duration
        real        udg_Spell__Time

    Thanks to Lua, the above variables are read-only, as intended.

    New to Lua:
        real            udg_SleepEvent          -> Inherited from Event. Replaces Spell__Time. Use this instead of a regular wait to preserve event data after the wait.
        integer         udg_Spell__whileChannel -> The loop will continue up until the point where the caster stops channeling the spell.
        string          udg_Spell__abilcode     -> Useful for debugging purposes.

        All of the other variables will be deprecated; possibly at some future point split into separate systems.
    --]=========================================================================================]
    
    local eventSpells = {}
    SpellEvent.__index = function(_,unit) return eventSpells[unit] end
    
    SpellEvent.addProperty = function(name, getter, setter)
        getter = getter or function() return Event.current.data[name] end
        GlobalRemap("udg_Spell__"..name, getter, setter)
    end
    SpellEvent.addProperty("Index", function() return Event.current.data end)
    SpellEvent.addProperty("Caster", nil, Event.sleep)
    SpellEvent.addProperty("Ability")
    SpellEvent.addProperty("Target")
    SpellEvent.addProperty("CasterOwner")
    SpellEvent.addProperty("Completed")
    SpellEvent.addProperty("Channeling")
    do
        local getLevel = function() return Event.current.data.Level end
        SpellEvent.addProperty("Level", getLevel)
        SpellEvent.addProperty("LevelMultiplier", getLevel)
    end
    do
        local castPt, targPt = {},{}
        SpellEvent.addProperty("CastPoint", function()
            local u = Event.current.data.Caster
            castPt[1]=GetUnitX(u)
            castPt[2]=GetUnitY(u)
            return castPt
        end)
        SpellEvent.addProperty("TargetPoint", function()
            local event = Event.current.data
            if event.Target then
                targPt[1]=GetUnitX(event.Target)
                targPt[2]=GetUnitY(event.Target)
            else
                targPt[1]=event.x
                targPt[2]=event.y
            end
            return targPt
        end)
    end
    Action.create("udg_Spell__whileChannel", function(func)
        while Event.current.data.Channeling do
            func()
        end
    end)
    GlobalRemap("udg_Spell__abilcode", function()
        return BlzFourCC2S(Event.current.data.Ability)
    end)

    local coreFunc          = function()
        local caster        = GetTriggerUnit()
        local ability       = GetSpellAbilityId()
        local whichEvent    = GetTriggerEventId()
        local name
        local event         = eventSpells[caster]
        if not event or not event.Channeling then
            event =
            {   Caster      = caster
            ,   Ability     = ability
            ,   Level       = GetUnitAbilityLevel(caster, ability)
            ,   CasterOwner = GetTriggerPlayer()
            ,   Target      = GetSpellTargetUnit()
            ,   x           = GetSpellTargetX()
            ,   y           = GetSpellTargetY()
            ,   Channeling  = true
            }
            eventSpells[caster] = event
            if whichEvent == EVENT_PLAYER_UNIT_SPELL_CHANNEL then
                name = "OnSpellChannel"
            else --whichEvent == EVENT_PLAYER_UNIT_SPELL_EFFECT
                event.Channeling = false
                event.Completed  = true
                name = "OnSpellEffect"          --In the case of Charge Gold and Lumber, only an OnEffect event will run.
            end
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_CAST then
            name = "OnSpellCast"
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_EFFECT then
            name = "OnSpellEffect"
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_FINISH then
            event.Completed = true
            return
        else --whichEvent == EVENT_PLAYER_UNIT_SPELL_ENDCAST
            event.Channeling = false
            name = "OnSpellFinish"
        end
        Event[name].execute(ability, event.Channeling or event.Completed, event)
    end

    local trigAbils = {}

    Event.create "OnSpellChannel"
    Event.create "OnSpellCast"
    Event.create "OnSpellEffect"
    Event.create "OnSpellFinish"

    for _,name in ipairs{"Channel","Cast","Effect","Finish","Endcast"} do
        if name~="Endcast" then

            local event = Event["OnSpell"..name]
            local oldReg = event.register
            event.register = function(func, priority, trig)
                if trig and trigAbils[trig] then
                    for _,abil in ipairs(trigAbils[trig]) do
                        event.await(func, abil, true, priority)
                    end
                    return ---@diagnostic disable-line
                end
                return oldReg(func, priority)
            end
        end
        RegisterAnyPlayerUnitEvent(_G["EVENT_PLAYER_UNIT_SPELL_"..string.upper(name)], coreFunc)
    end

    --Create a hook that expires after the map initialization triggers have run.
    --I could use OnInit.trig, but it would make it harder for people to convert legacy Spell System code, which ran on Map Initialization.
    local h = Hook.add("TriggerRegisterCommandEvent", function(h, whichTrig, whichAbil, whichOrder)
        if whichOrder==_AUTO_ORDER then
            trigAbils[whichTrig] = trigAbils[whichTrig] or {}
            table.insert(trigAbils, whichAbil)
        else
            h.next(whichTrig, whichAbil, whichOrder) --normal use of this event has been requested.
        end
    end)
    OnInit.map(h.remove)
    
    setmetatable(SpellEvent, SpellEvent)
end, Debug and Debug.getLine())