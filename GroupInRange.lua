--[[
    GroupInRange v1.2.0.1 by Bribe

    What it does:
        1) Collects all units in range of a point and adds them to a leakless group (GroupInRange_units)
        2) Automate exclusion of common unit classifications (e.g. spell immune/allies)
        3) Allows custom filters to be built in real-time.
        4) Provides GroupInRange to Lua users, which allows persistent filters without having to rebuild them from scratch each time.

    Why it can benefit:
        1) Shorter triggers and easier configuration of filters.
        2) No longer have to manually filter against really basic stuff like mechanical/structure/flying/magic immune

    How it works:
        1) Using Action, it allows you to specify custom filter definitions within the Actions block of GroupInRange_filter.
        2) Uses the same mechanics that were introduced in GUI Spell System, but built them universally for the sake of modularity (e.g. can be used with damage events).
--]]
OnInit(function()

    Require "Action" --https://github.com/BribeFromTheHive/Lua/blob/main/Action.lua
    Require "GUI"    --https://github.com/BribeFromTheHive/Lua/blob/main/Influa.lua
--[[
    GUI Variables:

    player group udg_GroupInRange_filter

    --MANDATORY variables to set:
    real    udg_GroupInRange_radius
    point   udg_GroupInRange_point

    optional boolean filters default:
    udg_GroupInRange_allow_self           false
    udg_GroupInRange_allow_allies         false
    udg_GroupInRange_allow_enemies        true        > self, allies and enmies can only be determined if a source unit is specified.

    udg_GroupInRange_allow_heroes         true
    udg_GroupInRange_allow_nonHeroes      true        > By default, all heroes and non-heroes are included.

    udg_GroupInRange_allow_living         true
    udg_GroupInRange_allow_dead           false       > By default, only living units are included.

    udg_GroupInRange_allow_flying         false
    udg_GroupInRange_allow_magicImmune    false
    udg_GroupInRange_allow_mechanical     false
    udg_GroupInRange_allow_structures     false       > By default, these are excluded.

    --Optional setonly variables for extra filtering:
    integer     udg_GroupInRange_max            > Do not pick any more units than this number (excludes units at random).
    unit        udg_GroupInRange_source         > if specified, enables filtering for enemies and allies.
    unit group  udg_GroupInRange_exclude        > Do not add any units from this group.

    --Readonly
    unit group  udg_GroupInRange_units          > The group of units who passed the filters.
    intger      udg_GroupInRange_count          > Number of units in that group

    If you want to save the units for a longer duration, assign a group variable to (Last created unit group) as this will create a copy for you to use.
--]]
    local defaultFilter = {
        allies      = false,
        enemies     = true,
        heroes      = true,
        nonHeroes   = true,
        living      = true,
        dead        = false,
        flying      = false,
        magicImmune = false,
        mechanical  = false,
        structures  = false,
        self        = false,
    }
    local enumGroup=CreateGroup()

    local getCompare,udgFilter
    local variable=function(name, getter, setter)
        GlobalRemap("udg_GroupInRange_"..name, getter, setter)
    end
    for name in pairs(defaultFilter) do
        variable("allow_"..name, nil, function(val) udgFilter[name]=val end)
    end
    for _,name in ipairs{"exclude","point","radius","max","source"} do
        variable(name, nil, function(val) udgFilter[name]=val end)
    end
    variable("units", function() return enumGroup end)
    variable("count", function() return udgFilter.count end)

    ---@param is boolean
    ---@param yes string
    ---@param no string
    ---@return boolean|nil
    local compare=function(is, yes, no)
        return (         is and getCompare(yes) --or print("GroupInRange Failed at Yes: "..yes.." boolean is: "..tostring(is))
               ) or (not is and getCompare(no)  --or print("GroupInRange Failed at No: " ..no.. " boolean is: "..tostring(is))
               )
    end
    function GroupInRange(args, filter)
        local x,y
        if args.point then
            x,y=args.point[1],args.point[2]
        elseif args.x then
            x,y=args.x,args.y
        else
            print"GroupInRange Error: No location or coordinates were provided!"
            return
        end
        filter=filter or defaultFilter
        getCompare=function(name)
            if filter[name]==nil then
                --print("GroupInRange default filter used for: "..name)
                return defaultFilter[name]
            end
            --print("GroupInRange filter is set for: "..name.." to: "..tostring(filter[name]))
            return filter[name]
        end
        local source = filter.source
        local owner = source and GetOwningPlayer(source)
        GUI.enumUnitsInRange(function(unit)
            if IsUnitInRangeXY(unit, x, y, args.radius)                                                             --and incDebug() --index 1
                and (not filter.exclude  or not IsUnitInGroup(unit, filter.exclude))                                --and incDebug() --index 2
                and ((filter.heroes~=false
                and filter.nonHeroes~=false)
                                         or     compare(IsUnitType(unit, UNIT_TYPE_HERO),   "heroes", "nonHeroes")) --and incDebug() --index 3
                and (not owner           or     compare(IsUnitEnemy(unit, owner),           "enemies","allies"))    --and incDebug() --index 4
                and                             compare(UnitAlive(unit),                    "living", "dead")       --and incDebug() --index 5
                and (filter.flying       or not IsUnitType(unit, UNIT_TYPE_FLYING))                                 --and incDebug() --index 6
                and (filter.structures   or not IsUnitType(unit, UNIT_TYPE_STRUCTURE))                              --and incDebug() --index 7
                and (filter.mechanical   or not IsUnitType(unit, UNIT_TYPE_MECHANICAL))                             --and incDebug() --index 8
                and (filter.magicImmune  or not IsUnitType(unit, UNIT_TYPE_MAGIC_IMMUNE))                           --and incDebug() --index 9
            then
                GroupAddUnit(enumGroup, unit)
            end
        end, x, y, args.radius + (filter.structures and 197 or 64), nil)
        if source then
            if not filter.self and IsUnitInGroup(source, enumGroup) then
                GroupRemoveUnit(enumGroup, source)
            end
            owner=GetOwningPlayer(source)
        end
        local inGroup=#enumGroup
        if filter.max then
            while inGroup > filter.max do
                GroupRemoveUnit(enumGroup, GroupPickRandomUnit(enumGroup))
                inGroup=inGroup-1
            end
        end
        --print("inGroup:"..inGroup)
        filter.count=inGroup
    end
    Action.create("udg_GroupInRange_filter", function(func)
        udgFilter={}
        func()
        GroupInRange(udgFilter,udgFilter)
    end)
end)