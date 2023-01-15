OnInit("AttackEvent", function()
    local anyUnitEvent = Require.strict "RegisterAnyPlayerUnitEvent"
    local remap        = Require.lazily "Remap.global"
--[[
    Attack Event version 1.0.0.0 by Bribe

    Detect when a unit starts an attack, finishes an attack or has its attack interrupted. Data can be
    indexed to the attack itself, making this MAI (multi-attack instantiable, or having "indexed attacks").

    Years ago, Nestharus had "cracked" the concept of attack indexing with an idea to set a unit's damage
    to an integer value between 1 and 8191 in order to track the flow of events from "unit is attacked" to
    "unit is damaged". This approach never took off, mostly because it would have required an enormous Object
    Editor overhaul to make it work.

    Thanks to many new natives which weren't around when Nestharus was active, I was able to index attacks by
    setting a unit's "weapon sound" to an integer between 0 and 23. This allows 24 unique damage indices per
    unit at a time, or 12 if we want to distinguish between attack 1 and attack 2 (which this system does).
    WarCraft 3 does not allow you to set the weapon type nor attack type to be out-of-bounds.
    
    Disclaimer: Timer system
    Attack Event uses a timer to detect when a unit actually finishes its attack (either on projectile
    launch, or an instant before the damage event fires for a melee attack). However, maps with custom attack
    speed bonus abilities/items will need to "declare" themselves, and their respective buffs, in the code
    below. I've noted where they can be added.
    
    Disclaimer: Max simultaneous attacks before damaging
    While this does not happen in normal WarCraft 3, the system could bug in a custom map with a unit with a
    very long range combined with very slow projectiles and a very fast attack. Depending on the environment,
    it is possible to use attacktypes in combination with changing a unit's weapon type to have up to 84
    distinct indices, or 168 if we ditched the weapon index detection. What I've done here is the least buggy
    and most practical, functional approach.
    
    Credits:
        Nestharus for the concept of indexing attacks based on a property of the attacking unit:
            https://www.hiveworkshop.com/threads/indexing-vanilla-warcraft-3-attacks-solved.253120/
        MyPad and Lt_Hawkeye for doing investigative work into the Blz integer fields.
            https://www.hiveworkshop.com/threads/list-of-non-working-object-data-constants.317769
        Almia, even though timers didn't work in all cases, thank you for making the effort.
            https://www.hiveworkshop.com/threads/attack-indexer.279304/
        Everyone on the Hive Discord channel who helped answer some critical questions along the way that
        saved me a lot of time (e.g. MindWorX, Tasyen, WaterKnight).
]]
    --values that should align with Gameplay Constants:
    local _AGI_BONUS                = 0.02      --"Hero Attributes - Attack speed bonus per agility point"
    local _FROST_SPEED_DEC          = 0.25      --"Spells - Frost Attack Speed Reduction"
    local _EXPIRE_AFTER             = 5         --expire an attack after this many seconds of it not hitting (should match what's in Gameplay Constants)
    local _MAX_SPEED                = 4         --WarCraft 3 has a hard cap of 400 percent attack speed buff.
    local _MIN_SPEED                = 0.2       --WarCraft 3 has a hard cap of 80 percent attack speed debuff.
    local _SLOW_POISON_DEC          = 0.25      --Slow poison must be hardcoded as it will crash the thread if attempted to be read dynamically
    local _ENDURANCE_AURA_PER_LVL   = 0.05      --Assumes rate of 5 percent speed increase per level is constant amongst all Endurance Aura clones and levels (which is the case by default in WarCraft 3).
    local _ENDURANCE_AURA_RADIUS    = 900       --Assumes the aura radius is consistent at 900 across the board.
    local _PRIORITY                 = -99999    --should be lower than any other damage event.
    local _USE_MELEE_RANGE          = true      --should line up with whatever you have Damage Engine configured to.
    
    local buffIndexTable = {}
    local triggeringUnit = GetTriggerUnit
    local getUnitDamagePoint
    do
        local getAgi            = GetHeroAgi
        local isType            = IsUnitType
        local isHero            = UNIT_TYPE_HERO
        local rawcode           = FourCC
        local getAbilityLvl     = GetUnitAbilityLevel
        local getSpellAbility   = GetSpellAbility
        local getUnitAbility    = BlzGetUnitAbility
        local getAbilityReal    = BlzGetAbilityRealLevelField
        local getAbilId         = GetSpellAbilityId
        local getTarget         = GetSpellTargetUnit

        local abilities = {}    ---@type table[]
        local debuffs = {}      ---@type table[]
        local buffTypes = {}    ---@type {string:boolean} indexes based on abil ID or buff ID
        local g = CreateGroup()

        ---Register an ability and buff and their properties.
        ---@param abilId string
        ---@param buffId string
        ---@param multiplier integer -1 or 1
        ---@param buffType string
        ---@param field abilityreallevelfield
        local function registerAbil(abilId, buffId, multiplier, buffType, field)
            local id = rawcode(abilId)

            buffTypes[buffType == "spell" and id or buffId] = buffType
            
            local data = {id, rawcode(buffId), multiplier, field}
            
            abilities[#abilities+1] = data
            
            if buffType == "damage" then
                debuffs[#debuffs+1] = data --a shorter list to avoid having to check too much on a damage event.
            end
        end

        --Register spells that apply a buff or debuff
        registerAbil("Aslo", "Bslo", -1, "spell",  ABILITY_RLF_ATTACK_SPEED_FACTOR_SLO2)            --Slow
        registerAbil("Acri", "Bcri", -1, "spell",  ABILITY_RLF_ATTACK_SPEED_REDUCTION_PERCENT_CRI2) --Cripple
        registerAbil("Ablo", "Bblo",  1, "spell",  ABILITY_RLF_ATTACK_SPEED_INCREASE_PERCENT_BLO1)  --Bloodlust
        registerAbil("Auhf", "BUhf",  1, "spell",  ABILITY_RLF_ATTACK_SPEED_BONUS_PERCENT)          --Unholy Frenzy, field 'Uhf1'
        registerAbil("Absk", "Bbsk",  1, "spell",  ABILITY_RLF_ATTACK_SPEED_INCREASE_BSK2)          --Berserk

        --Register debuffs that are applied on-hit
        registerAbil("AHtc", "BHtc", -1, "damage", ABILITY_RLF_ATTACK_SPEED_REDUCTION_PERCENT_HTC4) --Thunderclap
        registerAbil("ACtc", "BCtc", -1, "damage", ABILITY_RLF_ATTACK_SPEED_REDUCTION_CTC4)         --Slam
        registerAbil("AHca", "BHca", -1, "damage", ABILITY_RLF_ATTACK_SPEED_FACTOR_HCA3)            --Cold Arrows
        registerAbil("Aliq", "Bliq", -1, "damage", ABILITY_RLF_ATTACK_SPEED_REDUCTION_LIQ3)         --Liquid Fire
        
        --building a custom function for gloves of haste as I'm sure many custom maps will have several copies of their own variations with different values.
        --There's an ability 'Als2' which is "Item attack speed bonus (greater)", but I can't find the corresponding item ID.
        local gloves = {} ---@type { [1]: integer, [2]: integer }[]
        local function registerGloves(itemId, abilId)
            gloves[#gloves+1] = {rawcode(itemId), rawcode(abilId)}
        end
        registerGloves("gcel", "Alsx")
        
        --ABILITY_RLF_ATTACK_SPEED_INCREASE_PERCENT_OAE2 is for Endurance Aura (AOae, SCae, AOr2 and AIae*).
        --*Item ability used by 'ajen' (Ancient Janggo of Endurance)
        --None of these have a way for their attack speed bonuses be correctly read, so I have hardcoded their values.

        --[[Set to have 0 attack speed modification, so I'll ignore them:
        
            ABILITY_RLF_ATTACK_SPEED_FACTOR_DEF4            --Defend
            ABILITY_RLF_ATTACK_SPEED_MODIFIER --'Nsi4'      --Silence
            ABILITY_RLF_ATTACK_SPEED_FACTOR_ESH3            --Shadow Strike
            ABILITY_RLF_ATTACK_SPEED_REDUCTION_PERCENT_HBN2 --Banish
            ABILITY_RLF_ATTACK_SPEED_REDUCTION_PERCENT_NAB2 --Acid Bomb
            ABILITY_RLF_ATTACK_SPEED_REDUCTION_PERCENT_NSO5 --Soul Burn

            These completely crash because they read bad memory (attack speed and movement speed are swapped by some kind of implementation error):
            ABILITY_RLF_ATTACK_SPEED_FACTOR_SPO3            --Slow Poison.
            ABILITY_RLF_ATTACK_SPEED_FACTOR_POI2            --Poison Sting.
            ABILITY_RLF_ATTACK_SPEED_FACTOR_POA3            --Poison Arrows.
        ]]
        anyUnitEvent(EVENT_PLAYER_UNIT_SPELL_EFFECT, function()
            local id = getAbilId()
            if buffTypes[id] then
                buffIndexTable[getTarget() or triggeringUnit()][id] = getSpellAbility()
            end
        end)
        
        anyUnitEvent(EVENT_PLAYER_UNIT_DAMAGED, function()
            local u = triggeringUnit()
            for _,list in ipairs(debuffs) do
                if getAbilityLvl(u, list[2]) > 0 then
                    local abil = list[1]
                    local index = buffIndexTable[u]
                    if not index[abil] then
                        index[abil] = getUnitAbility(GetEventDamageSource(), abil)
                    end
                end
            end
        end)

        local math              = math
        local getWeaponReal     = BlzGetUnitWeaponRealField
        local damagePt          = UNIT_WEAPON_RF_ATTACK_DAMAGE_POINT
        local _FROST            = rawcode("bfro")
        local _POISON           = rawcode("Bspo")
        local _ENDURANCE_AURA   = rawcode("BOae")
        local _ENDURANCE_AURA_ABIL = rawcode("AOae")
        getUnitDamagePoint = function(unit)
            local bonus = 1
            local buffs = buffIndexTable[unit]
            for _,list in ipairs(abilities) do
                local abil = list[1]
                local buff = buffs[abil]
                if buff then
                    local lvl = getAbilityLvl(unit, list[2])
                    if lvl > 0 then
                        local factor = getAbilityReal(buff, list[4], lvl - 1)
                        --print(factor)
                        bonus = bonus + factor*list[3]
                    else
                        buffIndexTable[unit][abil] = nil
                    end
                end
            end
            if getAbilityLvl(unit, _FROST) > 0 then
                bonus = bonus - _FROST_SPEED_DEC
            end
            if getAbilityLvl(unit, _POISON) > 0 then
                bonus = bonus - _SLOW_POISON_DEC
            end
            if getAbilityLvl(unit, _ENDURANCE_AURA) > 0 then
                GroupEnumUnitsInRange(g, GetUnitX(unit), GetUnitY(unit), _ENDURANCE_AURA_RADIUS)
                local level = 0
                for i=0, BlzGroupGetSize(g)-1 do
        
                    local u = BlzGroupUnitAt(g, i)
                    local lvl = getAbilityLvl(u, _ENDURANCE_AURA_ABIL)
                    
                    if lvl > level and IsUnitAlly(u, GetOwningPlayer(unit)) then
                        level = lvl
                    end
                end
                bonus = bonus + level*_ENDURANCE_AURA_PER_LVL
            end
            if isType(unit, isHero) then
                bonus = bonus + _AGI_BONUS*getAgi(unit, true)
                if #gloves > 0 then
                    for i = 0, UnitInventorySize(unit) - 1 do
                        local item = UnitItemInSlot(unit, i)
                        if item then
                            local id = GetItemTypeId(item)
                            for j = 1, #gloves do
                                if id == gloves[j][1] then
                                    bonus = bonus + getAbilityReal(BlzGetItemAbility(item, gloves[j][2]), ABILITY_RLF_ATTACK_SPEED_INCREASE_ISX1, 0)
                                end
                            end
                        end
                    end
                end
            end
            return getWeaponReal(unit, damagePt, 0) / math.min(math.max(bonus, _MIN_SPEED), _MAX_SPEED)
        end
    end

    Event.create "AttackEvent"
    Event.create "AttackLaunchEvent"
    
    local attackFunc    = 13
    local damageFunc    = 14
    local numAttacks    = 15
    local queuedAttack  = 16
    local setOriginal   = 17
    local getWeaponInt  = BlzGetUnitWeaponIntegerField
    local setWeaponInt  = BlzSetUnitWeaponIntegerField
    local weapon        = UNIT_WEAPON_IF_ATTACK_WEAPON_SOUND

    ---@class attackIndexTable : table
    ---@field source unit
    ---@field target unit
    ---@field index integer
    ---@field data integer
    ---@field package active boolean
    local attackIndexTable = {} ---@type attackIndexTable[]

    ---@return attackIndexTable
    local function getTable()
        local data = Event.current.data
        if data then
            return data[1]
        else
            return Damage.index.attack
        end
    end
    
    --[[Optional GUI compatibility.
        
        AttackEventSource will return the attacking unit in "AttackEvent" or any of DamageEngine's events.
        AttackEventTarget will return the attacked unit in "AttackEvent" or any of DamageEngine's events (even if it is different from the damaged unit)
            This means that for an AOE attack or a multishot (barrage) attack, the AttackEventTarget can still be read successfully as the originally-attacked unit.
        AttackEventIndex is unknown at the time that the "AttackEvent" runs, but is set to 0 or 1 depending on whether the unit used its first attack or its second.
            If it is -1, that means it's not been set yet. So if it is -1 from an AttackEvent Not Equal event, then the attack never hit (e.g. evasion/curse/hasn't hit yet due to slow projectile).
        AttackEventData is meant to be set from an AttackEvent and read by a Damage event. See the below GUI pseudo-code for an example.
        
        Event:
            AttackEvent
        Actions:
            Set AttackEventData = DamageTypeCriticalStrike
        ...
        Event:
            PreDamageEvent
        Actions:
            Set DamageEventType = AttackEventData
    ]]
    if remap then
        remap("udg_AttackEventSource",  function() return getTable().source end)
        remap("udg_AttackEventTarget",  function() return getTable().target end)
        remap("udg_AttackEventIndex",   function() return getTable().index  end)
        remap("udg_AttackEventData",    function() return getTable().data   end, function(val) getTable().data = val end)
    end

    ---@param attack attackIndexTable
    local function cleanup(attack)
        if attack.active then
            local data = attackIndexTable[attack.source]
            data[numAttacks] = data[numAttacks] - 1
            attack.active = nil
            Event.AttackEvent.execute(attack, false, attack)
        end
    end

    local currentAttack ---@type table

    Damage.PreDamageEvent.register(function()
        local damage = Damage.index ---@type damageInfo
        if damage.isAttack and not damage.isCode then
            local unit = damage.source
            local data = attackIndexTable[unit]
            if data then
                local attackPoint = GetHandleId(damage.weaponType)
                local tablePoint = attackPoint // 2
                local offset = (tablePoint * 2 == attackPoint) and 0 or 1 --whether it's using the primary or secondary attack
                local attack = data[tablePoint + 1]
                if attack ~= currentAttack then --make sure not to re-allocate for splash damage.
                    if currentAttack then cleanup(currentAttack) end
                    currentAttack = attack
                    attack.index = offset
                    damage.attack = attack
                    data[damageFunc](damage, offset)
                end
            end
        end
    end, _PRIORITY)

    Event.DamageSourceEvent.register(function()
        if currentAttack then
            cleanup(currentAttack)
        end
        currentAttack = nil ---@diagnostic disable-line
    end).minAOE = 0
    
    anyUnitEvent(EVENT_PLAYER_UNIT_ATTACKED, function()
        local data = attackIndexTable[GetAttacker()]
        if data then data[attackFunc]() end
    end)
    
    Event.OnUnitTransform.register(function(ut) 
        local data = attackIndexTable[ut.unit]
        if data then data[setOriginal]() end
    end)

    Event.OnUnitCreation.register(
    function(ut)
        local attacker = ut.unit
        local data = {}
        attackIndexTable[attacker] = data
        buffIndexTable[attacker] = {}
        local original, point ---@type table, integer
        
        data[setOriginal] =
        function()
            original = {
                getWeaponInt(attacker, weapon, 0),
                getWeaponInt(attacker, weapon, 1)
            }
        end

        data[attackFunc] =
        function()
            if original then
                data[numAttacks] = data[numAttacks] + 1
            else
                data[numAttacks] = 1
                point = 0
                data[setOriginal]()
            end
            local thisAttack = { ---@type attackIndexTable
                source = attacker,
                target = triggeringUnit(),
                active = true,
                index = -1
            }
            setWeaponInt(attacker, weapon, 0, point*2)
            setWeaponInt(attacker, weapon, 1, point*2 + 1) --the system doesn't know if attack 0 or 1 is used at this point. Try them both.
            point = point + 1
            local old = data[point]
            if old and old.active then
                cleanup(old)
            end
            data[point] = thisAttack

            if point > 11 then point = 0 end

            Event.AttackEvent(thisAttack)
            data[queuedAttack] = function(fail)
                data[queuedAttack] = nil
                if fail then thisAttack.active = nil ; return end
                if thisAttack.active then
                    Timed.call(IsUnitType(attacker, UNIT_TYPE_RANGED_ATTACKER) and _EXPIRE_AFTER or 0.01, function()
                        if thisAttack.active then
                            cleanup(thisAttack)
                        end
                    end)
                    --print "attack launched"
                    Event.AttackLaunchEvent(thisAttack)
                    --[[
                    This could be useful to have as an event if you want to instantly detect if a melee attack fails, or
                    if you ended up changing the attack type at the end of the attack sequence and wanted to fix it before
                    it made a visual change to the UI (e.g. if you need more missiles indexed than currently possible).
                    
                    It is technically possible to calculate the duration between missile launch and target impact point,
                    in order to instantly detect if a missile misses, but that would require a periodic event in case the
                    target moves.
                    
                    Timed.call(0.01, function() print "clean up attack data" end)
                    ]]
                end
            end
            Timed.call(getUnitDamagePoint(attacker), data[queuedAttack])
        end
        data[damageFunc] =
        function(damage, offset)
            damage.weaponType = original[offset]
            if _USE_MELEE_RANGE and damage.isMelee and offset == 1 and original[2] == 0 and IsUnitType(attacker, UNIT_TYPE_RANGED_ATTACKER) then
                damage.isMelee = nil
                damage.isRanged = true
            end
        end
    end)
    local function cancelAttack()
        local data = attackIndexTable[triggeringUnit()]
        print (data)
        if data and data[queuedAttack] then
            data[queuedAttack](true)
            Event.AttackLaunchEvent.execute(data, false, data)
        end
    end
    anyUnitEvent(EVENT_PLAYER_UNIT_ISSUED_ORDER, cancelAttack)
    anyUnitEvent(EVENT_PLAYER_UNIT_ISSUED_POINT_ORDER, cancelAttack)
    anyUnitEvent(EVENT_PLAYER_UNIT_ISSUED_TARGET_ORDER, cancelAttack)
    Event.OnUnitRemoval.register(function(ut)
        if attackIndexTable[ut.unit] then
            attackIndexTable[ut.unit] = nil
            buffIndexTable[ut.unit] = nil
        end
    end)
end, Debug and Debug.getLine())