OnInit("Damage Engine", function() --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua
--Lua Version 3
--Author: Bribe
local Event = Require.strict "Event" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Event.lua

local onEvent = Require "RegisterAnyPlayerUnitEvent"  --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua
local remap   = Require.lazily "GlobalRemap"          --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua

--Configurables:
local _USE_GUI           = remap    --GUI only works if Global Variable Remapper is included.
local _USE_ROOT_TRACKING = true     --If you don't use DamageEventLevel/DamageEventAOE or SourceDamageEvent, set this to false
local _USE_LEGACY_API    = true     --Whether to support classic Damage Engine API (DamageModifierEvent, DamageEvent and AOEDamageEvent)
local _USE_ARMOR_MOD     = true     --If you do not modify nor detect armor/defense types, set this to false
local _USE_MELEE_RANGE   = true     --If you do not detect melee nor ranged damage, set this to false
local _USE_LETHAL        = true     --If false, LethalDamageEvent and explosive damage will be disabled.

Damage =
{   DEATH_VAL   = 0.405 --If this should ever change, it can be easily fixed here.
,   CODE        = 1     --If you use GUI, this must align with udg_DamageTypeCode.
,   PURE        = 2     --If you use GUI, this must align with udg_DamageTypePure.
}

---@class damageInfo
---@field source        unit
---@field target        unit
---@field damage        number
---@field prevAmt       number
---@field userAmt       number
---@field isAttack      boolean
---@field isRanged      boolean
---@field isMelee       boolean
---@field attackType    attacktype
---@field damageType    damagetype
---@field weaponType    weapontype
---@field isCode        boolean
---@field isSpell       boolean
---@field userData      any
---@field armorPierced  number
---@field armorType     integer
---@field defenseType   integer
---@field prevArmorT    integer
---@field prevDefenseT  integer
local currentInfo
local yieldedInfo   ---@type damageInfo
local execute = {}      ---@type { [string]: fun(info:damageInfo) }

---@diagnostic disable: undefined-global, lowercase-global, cast-local-type, param-type-mismatch, undefined-field

if _USE_ROOT_TRACKING then
    local GroupClear, IsUnitInGroup, GroupAddUnit = GroupClear, IsUnitInGroup, GroupAddUnit
    Damage.root = {
        targets = udg_DamageEventAOEGroup or CreateGroup(),
        run = function(self, info)
            if self.instance then
                execute.Source(self.instance)
            end
            if not info or not info.isCode then
                self.instance = info
                GroupClear(self.targets)
                self.level    = 1
            end
        end,
        add = function(self, info)
            if not info.isCode then
                if not self.instance or (info.source ~= self.instance.source) then
                    self:run(info)
                end
                if IsUnitInGroup(info.target, self.targets) then
                    self.level  = self.level + 1
                    if self.instance.target ~= info.target then
                        self.instance = info --the original event was not hitting the primary target. Adjust the root to this new event.
                    end
                else
                    GroupAddUnit(self.targets, info.target)
                end
            end
        end
    }
end

local setArmor
if _USE_ARMOR_MOD then
    local GetUnitField,           SetUnitField,           GetUnitArmor,    SetUnitArmor,    ARMOR_FIELD,        DEFENSE_FIELD
        = BlzGetUnitIntegerField, BlzSetUnitIntegerField, BlzGetUnitArmor, BlzSetUnitArmor, UNIT_IF_ARMOR_TYPE, UNIT_IF_DEFENSE_TYPE

    ---@param info damageInfo
    ---@param reset? boolean
    function setArmor(info, reset)
        if reset == nil then
            info.armorType      = GetUnitField(info.target, ARMOR_FIELD)
            info.defenseType    = GetUnitField(info.target, DEFENSE_FIELD)
            info.prevArmorT     = info.armorType
            info.prevDefenseT   = info.defenseType
        else
            if info.armorPierced then
                SetUnitArmor(info.target, GetUnitArmor(info.target) + (reset and info.armorPierced or -info.armorPierced))
                if reset then info.armorPierced = nil end
            end
            if info.prevArmorT   ~= info.armorType then
                SetUnitField(info.target, ARMOR_FIELD,              reset and info.prevArmorT   or  info.armorType)
            end
            if info.prevDefenseT ~= info.defenseType then
                SetUnitField(info.target, DEFENSE_FIELD,            reset and info.prevDefenseT or  info.defenseType)
            end
        end
    end
else
    setArmor = DoNothing
end

local nextMelee, nextRanged, nextData, setMeleeAndRange

local GetDamageAmt,   SetDamage,         ATTACK_TYPE_SPELLS, DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_HIDDEN,  WEAPON_TYPE_NONE
    = GetEventDamage, BlzSetEventDamage, ATTACK_TYPE_NORMAL, DAMAGE_TYPE_NORMAL,   DAMAGE_TYPE_UNKNOWN, WEAPON_TYPE_WHOKNOWS

local function finishInstance(info, keepFrozen)
    info = info or currentInfo
    if info then
        setArmor(info, true)
        if info.prevAmt ~= 0 and info.damageType ~= DAMAGE_TYPE_HIDDEN then
            execute.After(info)
        end
        currentInfo = nil
    end
    if not keepFrozen then
        Event.freeze(false)
    end
end
do
    local GetSource,            GetTarget,      GetIsAttack,         GetAttackType,         GetDamageType,         GetWeaponType,         SetAttackType,         SetDamageType,         SetWeaponType
        = GetEventDamageSource, GetTriggerUnit, BlzGetEventIsAttack, BlzGetEventAttackType, BlzGetEventDamageType, BlzGetEventWeaponType, BlzSetEventAttackType, BlzSetEventDamageType, BlzSetEventWeaponType
    if _USE_MELEE_RANGE then
        local MELEE_UNIT,               RANGED_UNIT,               IsUnitType
            = UNIT_TYPE_MELEE_ATTACKER, UNIT_TYPE_RANGED_ATTACKER, IsUnitType

        ---@param info? damageInfo
        ---@param ranged? boolean
        function setMeleeAndRange(info, ranged)
            if not info then
                nextMelee       = ranged == false --nil parameter would mean it is neither a melee nor a ranged attack.
                nextRanged      = ranged
            elseif info.isCode then
                if info.isAttack and not info.isSpell then
                    info.isMelee   = nextMelee
                    info.isRanged  = nextRanged
                end
            elseif (info.damageType == DAMAGE_TYPE_PHYSICAL) and info.isAttack then
                info.isMelee       = IsUnitType(info.source, MELEE_UNIT)
                info.isRanged      = IsUnitType(info.source, RANGED_UNIT)
                if info.isMelee and info.isRanged then
                    info.isMelee   = info.weaponType == WEAPON_TYPE_NONE  --Melee units play a sound when damaging; in naturally-occuring cases where a
                    info.isRanged  = not info.isMelee                     --unit is both ranged and melee, the ranged attack plays no sound.
                end
            end
        end
    end
    
    local timer;timer =
    {   timer = CreateTimer()
    ,   await = function()
            finishInstance()
            if _USE_ROOT_TRACKING then Damage.root:run() end
            Event.freeze(false)
            yieldedInfo, currentInfo, timer.started = nil, nil, nil
        end
    }

    onEvent(EVENT_PLAYER_UNIT_DAMAGING, function()
        local amt  = GetDamageAmt()
        local info = ---@type damageInfo
        {   source      = GetSource()
        ,   target      = GetTarget()
        ,   damage      = amt
        ,   isAttack    = GetIsAttack()
        ,   isCode      = nextData
        ,   attackType  = GetAttackType()
        ,   damageType  = GetDamageType()
        ,   weaponType  = GetWeaponType()
        ,   prevAmt     = amt
        ,   userData    = nextData
        }
        info.isSpell    = info.attackType == ATTACK_TYPE_SPELLS and not info.isAttack
        nextData        = nil
        if _USE_MELEE_RANGE then setMeleeAndRange(info) end
        if not timer.started then
            timer.started = true
            TimerStart(timer.timer, 0, false, timer.await)
            Event.freeze(true)
        elseif currentInfo then --WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
            if not yieldedInfo and not info.isCode and not currentInfo.isCode and not currentInfo.userAmt then
                yieldedInfo = currentInfo
            else
                finishInstance()
            end
        end
        if _USE_ROOT_TRACKING then Damage.root:add(info) end
        currentInfo = info
        setArmor(info)
        if amt == 0 then
            execute.Zero(info)
        elseif info.damageType ~= DAMAGE_TYPE_HIDDEN then
            execute.Pre(info)
            SetAttackType(info.attackType)
            SetDamageType(info.damageType)
            SetWeaponType(info.weaponType)
            SetDamage(info.damage)
            setArmor(info, false)
        end
    end)
end
do
    local GetUnitLife = GetWidgetLife

    onEvent(EVENT_PLAYER_UNIT_DAMAGED, function()
        local amt = GetDamageAmt()
        local info = currentInfo ---@type damageInfo
        if yieldedInfo and ((not info) or (info.userAmt)) then
            finishInstance(info, true) --spirit link or defensive/thorns recursive damage have finished, and it's time to wrap them up and load the triggering damage data.
            info, currentInfo, yieldedInfo = yieldedInfo, yieldedInfo, nil
        end
        info.userAmt, info.damage = info.damage, amt
        setArmor(info, true)
        if ((info.prevAmt ~= 0) or (amt ~= 0)) and (info.damageType ~= DAMAGE_TYPE_HIDDEN) then
            if amt > 0 then
                execute.Armor(info)
                if _USE_LETHAL then
                    Damage.life = GetUnitLife(info.target) - info.damage
                    if Damage.life <= Damage.DEATH_VAL then
                        execute.Lethal(info)
                        info.damage = GetUnitLife(info.target) - Damage.life
                        if (type(info.userData) == "number") and (info.userData < 0) and (Damage.life <= Damage.DEATH_VAL) then
                            SetUnitExploded(info.target, true)
                        end
                    end
                end
            end
            execute.On(info)
            amt = info.damage
            SetDamage(amt)
        end
        if amt == 0 then finishInstance(info) end
    end)
end
do
    local opConds =
    {   [LESS_THAN]             = "Attack"
    ,   [LESS_THAN_OR_EQUAL]    = "Melee"
    ,   [GREATER_THAN_OR_EQUAL] = "Ranged"
    ,   [GREATER_THAN]          = "Spell"
    ,   [NOT_EQUAL]             = "Code"
    }
    local eventConds =
    {   Pre    = "(info.userData ~= Damage.PURE) or (info.damageType ~= DAMAGE_TYPE_UNKNOWN)"
    ,   Armor  = "(info.damage > 0)"
    ,   Lethal = "(Damage.life <= Damage.DEATH_VAL)"
    ,   AOE    = "(BlzGroupGetSize(Damage.root.targets) > 1)"
    }
    ---@param name string
    ---@param func function
    ---@param priority? number
    ---@param limitop? limitop
    function Damage.register(name, func, priority, limitop)
        local eventCond = eventConds[name]
        if opConds[limitop] then
            local opCond = "(info.is"..opConds[limitop]..")"
            eventCond = eventCond and (eventCond .. " and " .. opCond) or opCond
        end
        if eventCond then
            func = load([[return function(func)
                return function(info)
                    if ]]..eventCond..[[ then
                        func(info)
                    end
                end
            end]])()(func)
        end
        return Event[name.."DamageEvent"].oldRegister(func, priority)
    end
end
do
    ---@param ref string
    local function createRegistry(ref)
        local event    = ref.."DamageEvent"
        local executor = Event[event].execute
        execute[ref]   = function(info)
            executor(info.userData, true, info)
        end
        Event[event].oldRegister = Event[event].register
        Event[event].register = function(func, priority, _, limitop)
            return Damage.register(ref, func, priority, limitop)
        end
    end
    Event.PreDamageEvent        = Event.new(); createRegistry "Pre"
    Event.ZeroDamageEvent       = Event.new(); createRegistry "Zero"
    Event.ArmorDamageEvent      = Event.new(); createRegistry "Armor"
    Event.OnDamageEvent         = Event.new(); createRegistry "On"
    Event.AfterDamageEvent      = Event.new(); createRegistry "After"
    if _USE_LETHAL then
        Event.LethalDamageEvent = Event.new(); createRegistry "Lethal"
    end
    if _USE_ROOT_TRACKING then
        Event.SourceDamageEvent = Event.new(); createRegistry "Source"
    end
    if _USE_LEGACY_API then
        if _USE_ROOT_TRACKING then
            Event.AOEDamageEvent             = Event.new(); createRegistry "AOE"
            Event.AOEDamageEvent.await       = Event.SourceDamageEvent.await
            Event.AOEDamageEvent.oldRegister = Event.SourceDamageEvent.oldRegister
        end
        Event.create "DamageModifierEvent"
        .register = function(func, priority, trig, op)
            return Event[priority < 4 and "PreDamageEvent" or "ArmorDamageEvent"].register(func, priority, trig, op)
        end
        Event.create "DamageEvent"
        .register = function(func, priority, trig, op)
            return Event[(priority == 0 or priority == 2) and "ZeroDamageEvent" or "OnDamageEvent"].register(func, priority, trig, op)
        end
    end
end
do
    local UDT = UnitDamageTarget
    ---Replaces UnitDamageTarget. Missing parameters are filled in.
    ---@param source unit
    ---@param target unit
    ---@param amount number
    ---@param attack? boolean
    ---@param ranged? boolean
    ---@param attackType? attacktype
    ---@param damageType? damagetype
    ---@param weaponType? weapontype
    function Damage.apply(source, target, amount, attack, ranged, attackType, damageType, weaponType)
        Event.queue(function()
            nextData = nextData or Damage.CODE
            if attack == nil then
                attack = (ranged ~= nil) or (damageType == DAMAGE_TYPE_PHYSICAL)
            end
            if _USE_MELEE_RANGE then setMeleeAndRange(nil, ranged) end
            UDT(source, target, amount, attack, ranged, attackType, damageType, weaponType)
            finishInstance()
        end)
    end
    UnitDamageTarget = Damage.apply

    ---Allow syntax like Damage.data("whatever").apply(source, target, ...)
    ---@param userData any
    function Damage.data(userData)
        nextData = userData
        return Damage
    end
end
if _USE_GUI then
    udg_NextDamageWeaponT = WEAPON_TYPE_NONE
    
    function UnitDamageTargetBJ(source, target, amount, attackType, damageType)
        local isAttack = udg_NextDamageIsAttack; udg_NextDamageIsAttack = false
        local weapon   = udg_NextDamageWeaponT;  udg_NextDamageWeaponT  = WEAPON_TYPE_NONE
        local isRanged, isMelee
        if _USE_MELEE_RANGE then
            isRanged = udg_NextDamageIsRanged
            isMelee  = udg_NextDamageIsMelee
            udg_NextDamageIsRanged = false
            udg_NextDamageIsMelee  = false
        end
        Damage.apply(source, target, amount, isAttack, isRanged or not isMelee, attackType, damageType, weapon)
        return true
    end

    ---@param str string
    ---@return string
    local function CAPStoCap(str) return str:sub(1,1)..(str:sub(2):lower()) end

    ---@param debugStrs table
    ---@param varPrefix string
    ---@param ... string
    local function setTypes(debugStrs, varPrefix, ...)
        for _,suffix in ipairs{...} do
            local handle = _G[varPrefix..suffix]
            local debugStr
            --Scan strings to translate JASS2 keywords into Editor keywords:
            if varPrefix == "ATTACK_TYPE_" then
                if     suffix == "NORMAL" then  suffix = "SPELLS"
                elseif suffix == "MELEE" then   suffix = "NORMAL"
                end
            elseif suffix == "WHOKNOWS" then --"WHOKNOWS" indicates that an on-hit effect should not play a sound.
                suffix   = "NONE"
                debugStr = "NONE"
                goto skipReformat
            elseif varPrefix == "WEAPON_TYPE_" then
                debugStr = suffix
                suffix   = suffix:gsub("^([A-Z])[A-Z]+_([A-Z])[A-Z]+", "\x251\x252") --METAL_LIGHT_SLICE -> ML_SLICE (var name only)
                goto skipOverwrite
            elseif varPrefix == "DEFENSE_TYPE_" then
                if     suffix == "NONE" then    suffix = "UNARMORED"
                elseif suffix == "LARGE" then   suffix = "HEAVY"
                elseif suffix == "FORT" then    suffix = "FORTIFIED"
                end
            end
            debugStr = suffix
            ::skipOverwrite::
            debugStr = debugStr:gsub("_", " "):gsub("([A-Z]+)", CAPStoCap) --"METAL_LIGHT_SLICE" -> "Metal Light Slice" (debug string only)
            ::skipReformat::
            debugStrs[handle] = debugStr
            _G["udg_"..varPrefix..suffix] = handle
        end
    end
    --Armor Types simply affect the sounds that play on-hit.
    setTypes(udg_ArmorTypeDebugStr,   "ARMOR_TYPE_",   "FLESH",  "WOOD",   "METAL",  "ETHEREAL", "STONE", "WHOKNOWS")
    
    --Further reading on attack types VS defense types: http://classic.battle.net/war3/basics/armorandweapontypes.shtml
    setTypes(udg_AttackTypeDebugStr,  "ATTACK_TYPE_",            "PIERCE", "MELEE",  "MAGIC",    "SIEGE", "HERO", "CHAOS",  "NORMAL")
    setTypes(udg_DefenseTypeDebugStr, "DEFENSE_TYPE_", "NONE",   "LIGHT",  "MEDIUM", "LARGE",    "FORT",  "HERO", "DIVINE", "NORMAL")

    --These can be complex to understand. I recommend this for reference: https://www.hiveworkshop.com/threads/spell-ability-damage-types-and-what-they-mean.316271/
    setTypes(udg_DamageTypeDebugStr,  "DAMAGE_TYPE_",
        "MAGIC",  "LIGHTNING", "DIVINE", "SONIC",   "COLD", "SHADOW_STRIKE", "DEFENSIVE",  "SPIRIT_LINK", "FORCE", "PLANT", "DEATH", "FIRE", "MIND",--Cannot affect spell immune units under any circumstances.
        "NORMAL", "ENHANCED",  "POISON", "DISEASE", "ACID", "SLOW_POISON",   "DEMOLITION", "UNKNOWN",     "UNIVERSAL")                              --Can affect Spell Immune units, under the right circumstances.
    
    --Weapon Types simply affect the sounds that play on-hit.
    setTypes(udg_WeaponTypeDebugStr,  "WEAPON_TYPE_", "WHOKNOWS",
        "METAL_LIGHT_CHOP",  "METAL_MEDIUM_CHOP",  "METAL_HEAVY_CHOP",   "AXE_MEDIUM_CHOP", --METAL & AXE CHOP
            "WOOD_LIGHT_BASH",   "WOOD_MEDIUM_BASH",   "WOOD_HEAVY_BASH", "METAL_MEDIUM_BASH", "METAL_HEAVY_BASH", "ROCK_HEAVY_BASH", --METAL, WOOD & ROCK BASH
        "METAL_LIGHT_SLICE", "METAL_MEDIUM_SLICE", "METAL_HEAVY_SLICE",  --METAL SLICE

        --None of the following can be selected in the Object Editor, so would not occur naturally in-game:
        "WOOD_LIGHT_SLICE",  "WOOD_MEDIUM_SLICE",  "WOOD_HEAVY_SLICE",  --WOOD SLICE
        "CLAW_LIGHT_SLICE",  "CLAW_MEDIUM_SLICE",  "CLAW_HEAVY_SLICE",  --CLAW SLICE
        "WOOD_LIGHT_STAB",   "WOOD_MEDIUM_STAB",                      "METAL_MEDIUM_STAB", "METAL_HEAVY_STAB") --WOOD & METAL STAB
    
    GlobalRemapArray("udg_CONVERTED_ATTACK_TYPE", function(attackType) return attackType end)
    GlobalRemapArray("udg_CONVERTED_DAMAGE_TYPE", function(damageType) return damageType end)
    
    if _USE_ROOT_TRACKING then
        remap("udg_DamageEventAOE",         function() return BlzGroupGetSize(Damage.root.targets) end)
        remap("udg_DamageEventLevel",       function() return Damage.root.level end)
        remap("udg_AOEDamageSource",        function() return Damage.root.instance.source end)
        remap("udg_EnhancedDamageTarget",   function() return Damage.root.instance.target end)
    end
    remap("udg_NextDamageType", nil, Damage.type)
    
    local currentEvent = Event.current
    
    ---Remap damageInstance types of variables (DamageEventSource/Target/Amount/etc)
    ---@param udgStr string
    ---@param luaStr string
    ---@param get? boolean
    ---@param set? boolean
    local function map(udgStr, luaStr, get, set)
        remap(udgStr, get and function() return currentEvent.data[luaStr] end, set and function(val) currentEvent.data[luaStr] = val end)
    end
    map("udg_DamageEventAmount",  "damage",     true, true)
    map("udg_DamageEventType",    "userData",   true, true)
    map("udg_DamageEventAttackT", "attackType", true, true)
    map("udg_DamageEventDamageT", "damageType", true, true)
    map("udg_DamageEventWeaponT", "weaponType", true, true)
    map("udg_LethalDamageHP",     "life",       true, true)
    if _USE_ARMOR_MOD then
        remap("udg_DamageEventArmorPierced", function() return currentEvent.data.armorPierced or 0 end, function(armor) currentEvent.data.armorPierced = armor end)
        map("udg_DamageEventArmorT",   "armorType",    true, true)
        map("udg_DamageEventDefenseT", "defenseType",  true, true)
    end
    map("udg_DamageEventSource",  "source",   true)
    map("udg_DamageEventTarget",  "target",   true)
    map("udg_DamageEventPrevAmt", "prevAmt",  true)
    map("udg_DamageEventUserAmt", "userAmt",  true)
    map("udg_IsDamageAttack",     "isAttack", true)
    map("udg_IsDamageCode",       "isCode",   true)
    map("udg_IsDamageSpell",      "isSpell",  true)
    if _USE_MELEE_RANGE then
        map("udg_IsDamageMelee",  "isMelee",  true)
        map("udg_IsDamageRanged", "isRanged", true)
    end
end
end, Debug and Debug.getLine())