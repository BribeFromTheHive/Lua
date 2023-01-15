OnInit(function(require)
    
    ---@diagnostic disable: cast-local-type, param-type-mismatch, assign-type-mismatch

    local echo = require "Timed.echo" --https://github.com/BribeFromTheHive/Lua/blob/master/Timed.lua

    ----------------------------------------------------
    ---------------MOVESPEED SYSTEM CONFIG--------------
    ----------------------------------------------------
    local _CHECK_PERIOD = 0.03125

    local abs, atan, deg, sqrt = math.abs, math.atan, math.deg, math.sqrt

    ---@alias MoveSpeedX {x: number, y: number, extraSpeed: number, remove: fun()}

    ---@type { [unit]: MoveSpeedX }
    local listed = {}
    
    local oldSums = SetUnitMoveSpeed
    function SetUnitMoveSpeed(u, speed)
        oldSums(u, speed)
        if speed > 522 then
            --[[if not listed then
                listed = {}
                local trig = CreateTrigger()
                TriggerRegisterAnyUnitEventBJ(trig, EVENT_PLAYER_UNIT_ISSUED_POINT_ORDER)
                TriggerRegisterAnyUnitEventBJ(trig, EVENT_PLAYER_UNIT_ISSUED_TARGET_ORDER)
                TriggerAddCondition(trig, Filter(function()
                    local tu = GetTriggerUnit()
                    if listed[tu] then
                        listed[tu].x = GetOrderPointX()
                        listed[tu].y = GetOrderPointY()
                    end
                end))
                trig = CreateTrigger()
                TriggerRegisterAnyUnitEventBJ(trig, EVENT_PLAYER_UNIT_ISSUED_ORDER)
                TriggerAddCondition(trig, Filter(function()
                    local tu = GetTriggerUnit()
                    if listed[tu] then
                        listed[tu].x = nil
                        listed[tu].y = nil
                    end
                end))
            end]]

            if listed[u] then
                listed[u].remove() --remove the original callback
            end

            local t = {} ---@type MoveSpeedX
            listed[u] = t
            speed = speed - 512
            t.extraSpeed = speed
            local period = 1 / (speed / 50) * _CHECK_PERIOD
            speed = speed * period
            local lastX = GetUnitX(u)
            local lastY = GetUnitY(u)
            --local lastFace = GetUnitFacing(u)

            listed[u].remove = echo(period, function()
                if GetUnitTypeId(u) > 0 then
                    local newX = GetUnitX(u)
                    local newY = GetUnitY(u)
                    --local face = GetUnitFacing(u)
                    if --[[(abs(face - lastFace) < 2.5) and]] ((abs(newX - lastX) > period) or (abs(newY - lastY) > period)) and not IsUnitPaused(u) then
                        local deltaX = newX - lastX
                        local deltaY = newY - lastY
                        local distance  = sqrt(deltaX * deltaX + deltaY * deltaY)
                        --face = deg(atan(deltaY, deltaX))
                        --BlzSetUnitFacingEx(u, face)
                        local nextX = deltaX / distance * speed
                        local nextY = deltaY / distance * speed
                        
                        newX = newX + nextX
                        newY = newY + nextY

                        SetUnitX(u, newX)
                        SetUnitY(u, newY)
                    end
                    lastX = newX
                    lastY = newY
                    --lastFace = face
                else
                    listed[u] = nil
                    return true --stop echoing
                end
            end)
        elseif listed and listed[u] then
            listed[u].remove()
            listed[u] = nil
        end
    end

    local oldGums = GetUnitMoveSpeed
    function GetUnitMoveSpeed(whichUnit)
        if listed and listed[whichUnit] then
            return (listed[whichUnit].extraSpeed) + 522
        end
        return oldGums(whichUnit)
    end
end)