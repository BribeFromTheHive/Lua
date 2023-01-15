HealUnit = nil ---@type fun(target: unit, amount: number, source?: unit)

OnInit("Heal Event", function()

Require "Timed"
local remap = Require.optional "GlobalRemap"

local _HEAL_INTERVAL    = 0.05
local _HEAL_THRESHOLD   = 5.00
local _REGEN_INTERVAL   = 1.00
local _REGEN_THRESHOLD  = 5.00
local _STR_BONUS        = 0.05

---@diagnostic disable: undefined-global
do
    local func = rawget(_G, "Trig_Heal_Configuration_Actions")
    if func then
        func()
        _REGEN_INTERVAL = udg_REGEN_EVENT_INTERVAL
        _HEAL_THRESHOLD = udg_HEAL_THRESHOLD
        _HEAL_INTERVAL  = udg_HEAL_CHECK_INTERVAL
        _REGEN_THRESHOLD= udg_REGEN_THRESHOLD
        _STR_BONUS      = udg_REGEN_STRENGTH_VALUE
    end
end

local nextSrc, nextTgt
local inSys = {}

local GetUnitLife   = GetWidgetLife
local SetUnitLife   = SetWidgetLife
local GetUnitState  = GetUnitState
local IsUnitType    = IsUnitType
local GetHeroStr    = GetHeroStr
local _MAX_LIFE     = UNIT_STATE_MAX_LIFE

function HealUnit(target, amount, source)
    nextSrc, nextTgt = nil, nil
    SetUnitLife(target, GetUnitLife(target) + amount)

    Event.OnUnitHealed {target=target, amount=amount, source=source}
end

if remap then
    remap("udg_heal_source", function() return Event.current.data.source end, function(val) nextSrc = val end)
    remap("udg_heal_target", function() return Event.current.data.target end, function(val) nextTgt = val end)
    remap("udg_heal_amount", function() return Event.current.data.amount end, function(val) HealUnit(nextSrc, val, nextTgt) end)
end

Event.create "OnUnitHealed"
Event.create "OnUnitRegen"

--===========================================================================
---Add a unit to the heal checking system
---@param unitTable UnitEventTable
local function addUnitToSys(unitTable)
    local u = unitTable.unit
    if not inSys[unitTable] and not IsUnitType(u, UNIT_TYPE_MECHANICAL) and GetUnitDefaultMoveSpeed(u) ~= 0.00 and GetUnitAbilityLevel(u, FourCC('Aloc')) == 0 then
        local isHero            = IsUnitType(u, UNIT_TYPE_HERO)
        local prevLife          = GetUnitLife(u)
        local prevMax           = GetUnitState(u, _MAX_LIFE)
        local regenTimeLeft     = _REGEN_INTERVAL
        local regen, regenBuildup = 0, 0
        inSys[unitTable]        = Timed.echo(_HEAL_INTERVAL, function()
            local life          = GetUnitLife(u)
            local diff          = life - prevLife
            prevLife            = life
            local heal          = regen > 0 and (diff - regen) or diff
            if GetUnitState(u, _MAX_LIFE) ~= prevMax then
                local max       = GetUnitState(u, _MAX_LIFE)
                max, prevMax    = prevMax - max, max
                if heal >= max then
                    heal        = heal - max --prevent "max life incrase" from triggering a heal.
                end
            end
            if heal >= _HEAL_THRESHOLD then
                Event.OnUnitHealed {target=u, amount=heal}
            else
                regen           = (regen + diff) * 0.5
                regenBuildup    = regenBuildup + diff
                regenTimeLeft   = regenTimeLeft - _HEAL_INTERVAL
                if regenTimeLeft <= 0 then
                    regenTimeLeft = _REGEN_INTERVAL
                    heal        = regenBuildup
                    regenBuildup= 0
                    if isHero then
                        diff    = heal - (GetHeroStr(u, true)*_STR_BONUS)
                    else
                        diff    = heal
                    end
                    if diff >= _REGEN_THRESHOLD then
                        Event.OnUnitRegen {target=u, amount=heal}
                    end
                end
            end
        end)
    end
end

Event.OnUnitCreation.register(addUnitToSys)
Event.OnUnitRevival.register(addUnitToSys)

local function removeUnitFromSys(index)
    if inSys[index] then
        inSys[index]()
        inSys[index] = nil
    end
end

Event.OnUnitRemoval.register(removeUnitFromSys)
Event.OnUnitDeath.register(removeUnitFromSys)
Event.OnUnitReincarnating.register(removeUnitFromSys)

end, Debug and Debug.endFile())