OnInit.module("Retro", function()
--------------------------------------------
--    ___  ___  ___  ___  ___
--   /__/ /__   /   /__/ /  /
--  /  | /__   /   /  \ /__/
-- Lua version 1.0          Created by Bribe
--------------------------------------------
--
-- Description:
-- Retro provides data retrieval and callback operators for use in simulating a time-travel effect for units.

    local echo      = Require.strict "Timed.echo"           --https://github.com/BribeFromTheHive/Lua/blob/master/Timed.lua
    local unitEvent = Require.lazily "UnitEvent"            --https://github.com/BribeFromTheHive/Lua/blob/master/UnitEvent.lua

    ---@class RetroTimeStamp
    ---@field x number
    ---@field y number
    ---@field z number
    ---@field f number
    
    ---@class RetroData:RetroTimeStamp[]
    ---@field pos integer
    ---@field rewinding function
    ---@field remove function

    ---@class Retro: {[unit]:RetroData}
    local Retro = {}

    -- Values are in seconds:
    local _RECORD_FREQUENCY     = 0.125     --How often to record a unit's x,y,z,facing.
    local _REWIND_SPEED         = 0.03125   --by default is 4x faster than real time.
    local _MAX_MEMORY           = 20.0      --Retro will not store data older than this.
    
    local _ERASE_POINT          = R2I(_MAX_MEMORY/_RECORD_FREQUENCY + 0.5)

    local function resetPropWindow(unit)
        SetUnitPropWindow(unit, GetUnitDefaultPropWindow(unit))
    end

    local getX,     getY,     getZ,             getF,          setX,     setY,     setZ,             setF
    =     GetUnitX, GetUnitY, GetUnitFlyHeight, GetUnitFacing, SetUnitX, SetUnitY, SetUnitFlyHeight, BlzSetUnitFacingEx

    function Retro.record(unit)
        local retro = Retro[unit]
        if not retro then
            if UnitAlive(unit)
            and GetUnitDefaultMoveSpeed(unit) > 0
            and GetUnitAbilityLevel(unit, FourCC'Aloc') == 0
            and not IsUnitType(unit, UNIT_TYPE_STRUCTURE)
            then
                retro = {unit=unit, pos=1}
                Retro[unit] = retro

                local x, y, z, f = getX(unit), getY(unit), getZ(unit), getF(unit)
                for _=1, _ERASE_POINT do
                    table.insert(retro, {x=x, y=y, z=z, f=f})
                end
                retro.remove = echo
                (   function()
                        local pos = retro.pos + 1
                        if pos > _ERASE_POINT then pos = 1 end
                        retro.pos = pos
                        local save = retro[pos]
                        save.x,     save.y,     save.z,     save.f =
                        getX(unit), getY(unit), getZ(unit), getF(unit)
                    end
                , _RECORD_FREQUENCY
                )
            end
        end
        return retro
    end

    ---@param unit unit
    function Retro.remove(unit)
        local retro = Retro[unit]
        if retro then
            if retro.rewinding then
                resetPropWindow(unit)
                retro.rewinding()
            end
            retro.remove()
            Retro[unit] = nil
        end
    end

    if unitEvent then
        Event.OnUnitActive.register(function(unitTable) Retro.record(unitTable.unit) end)
        Event.OnUnitPassive.register(function(unitTable) Retro.remove(unitTable.unit) end)
    end

    ---Rewind a unit through time
    ---@param unit unit
    ---@param duration number
    ---@param cumulative? boolean
    function Retro.rewind(unit, duration, cumulative)
        local retro = Retro[unit]
        if retro then
            if retro.rewinding then
                if cumulative then
                    duration = duration + retro.rewinding()
                else
                    duration = math.max(duration, retro.rewinding())
                end
            else
                retro.at = retro.pos
                SetUnitPropWindow(unit, 0)
            end
            retro.rewinding = echo(_REWIND_SPEED, duration, function()
                local at = retro.at - 1
                if at < 1 then at = _ERASE_POINT end
                retro.at = at
                local save = retro[at]
                setX(unit, save.x)
                setY(unit, save.y)
                setZ(unit, save.z, 0)
                setF(unit, save.f)
            end, function() resetPropWindow(unit) end)
        end
    end
    return Retro
end, Debug and Debug.endFile())