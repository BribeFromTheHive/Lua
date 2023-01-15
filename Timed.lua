if Debug then Debug.beginFile "Timed" end
--———————————————————————————————————————
-- Timed Call and Echo version 2.1
-- Created by Bribe
-- Special thanks to Eikonium
-- Inspiration: Jesus4Lyf and Nestharus
--—————————————————————————————————————

---@class Timed
---@field echo async fun(timeout_or_userFunc: number|Timed.echoCallback, duration_or_timeout_or_userFunc?: number|Timed.echoCallback, userFunc?: Timed.echoCallback, onExpire?: function, tolerance?: number):fun(doNotDestroy:boolean):number
---@field call async fun(delay_or_userFunc: number|function, userFunc?: function):nil|fun(doNotDestroy:boolean):number
Timed = {}
do
    local _DEFAULT_ECHO_TIMEOUT = 0.03125
    local _EXIT_WHEN_FACTOR = 0.5 --Will potentially stop the echo before it has fully run its course (via rounding). Set to 0 to disable. Can also override this from the Timed.echo 5th parameter.
    local zeroList, _ZERO_TIMER ---@type function[]|nil, timer
    local insert = table.insert

    ---@alias Timed.echoCallback async fun(duration?:number):boolean? --if it returns true, echo will stop.

    ---@class Timed.list: { [integer]: Timed.echoCallback }
    ---@field timer timer
    ---@field queue Timed.echoCallback[]

    local timerLists = {} ---@type { [number]: Timed.list }
    
--[[
    **Timed.call**  \
    **Info:** After `delay` seconds, call `userFunc`.  \
    **Args:** `[delay = 0,] userFunc`  \
    **Example:** `Timed.call(5.00, function() print "calling this after 5 seconds." end)`
]]
function Timed.call(delay_or_userFunc, userFunc)
    local delay
    if type(delay_or_userFunc)=="function" then
        userFunc,delay = delay,userFunc or 0 ---@cast delay number
    else
        delay = delay_or_userFunc
    end
    if delay <= 0 then
        if zeroList then
            insert(zeroList, userFunc)
        else
            zeroList = {userFunc}
            _ZERO_TIMER = _ZERO_TIMER or CreateTimer()
            TimerStart(_ZERO_TIMER, 0, false, function()
                local tempList = zeroList
                zeroList = nil
                for _, func in ipairs(tempList) do func() end
            end)
        end
    else
        local t = CreateTimer()
        TimerStart(t, delay, false, function()
            DestroyTimer(t)
            t=nil ---@diagnostic disable-line
            userFunc()
        end)
        return function(doNotDestroy)
            local result = 0
            if t then
                result = TimerGetRemaining(t)
                if not doNotDestroy then
                    PauseTimer(t)
                    DestroyTimer(t)
                    t=nil ---@diagnostic disable-line
                end
            end
            return result
        end
    end
end

--[[
    ## Timed.echo
    Info: Calls `userFunc` every `timeout` seconds until `userFunc` returns true. \
    - Will also stop calling userFunc if the `duration` is reached. \
    - Returns a function you can call to manually stop echoing the `userFunc`. \
    Args: [timeout, duration,] userFunc[, onExpire, tolerance]
    ---
    Note: This merges all matching timeouts together, so it is advisable only to use this for smaller numbers (e.g. <.3 seconds) where the difference is less noticeable.
]]
function Timed.echo(timeout_or_userFunc, duration_or_timeout_or_userFunc, userFunc, onExpire, tolerance)
    local timeout, duration
    if type(timeout) == "function" then
        --params align to original API of (function[, timeout])
        userFunc, timeout, duration = timeout_or_userFunc, duration_or_timeout_or_userFunc, userFunc
    else
        timeout = timeout_or_userFunc
        if userFunc then
            --params were (timeout, duration, userFunc[, onExpire, tolerance])
            duration = duration_or_timeout_or_userFunc
        else
            --params were (timeout, userFunc)
            userFunc, duration = duration_or_timeout_or_userFunc, nil
        end
    end
    ---@cast timeout number
    ---@cast duration number
    ---@cast userFunc Timed.echoCallback

    --this wrapper function allows manual removal to be understood and processed accordingly.
    local wrapper = function() return not userFunc or userFunc(duration) end
    
    timeout = timeout or _DEFAULT_ECHO_TIMEOUT
    if duration then
        local old=wrapper
        local exitwhen = timeout*(tolerance or _EXIT_WHEN_FACTOR)
        wrapper=function() --this wrapper function enables automatic removal once the duration is reached.
            if not old() then
                duration = duration - timeout
                if duration > exitwhen then
                    return
                elseif onExpire then
                    onExpire()
                end
            end
            return true
        end
    else
        duration=0
    end
    local timerList = timerLists[timeout]
    if timerList then
        local remaining = TimerGetRemaining(timerList.timer)
        if remaining >= timeout * 0.50 then
            duration = duration + timeout --The delay is large enough to execute on the next tick, therefore increase the duration to avoid double-deducting.
            insert(timerList, wrapper)
        elseif timerList.queue then
            insert(timerList.queue, wrapper)
        else
            timerList.queue = {wrapper}
        end
        duration = duration - remaining --decrease the duration to compensate for the extra remaining time before the next tick.
    else
        timerList = {wrapper} ---@type Timed.list
        timerLists[timeout] = timerList
        timerList.timer = CreateTimer()
        TimerStart(timerList.timer, timeout, true, function()
            local top=#timerList
            for i=top,1,-1 do
                if timerList[i]() then --The userFunc is to be removed:
                    if i~=top then
                        timerList[i]=timerList[top]
                    end
                    timerList[top]=nil
                    top=top-1
                end
            end
            if timerList.queue then --Now we can add the queued items to the main list
                for i,func in ipairs(timerList.queue) do
                    timerList[top+i]=func
                end
                timerList.queue = nil
            elseif top == 0 then --list is empty; clear its data.
                timerLists[timeout] = nil
                PauseTimer(timerList.timer)
                DestroyTimer(timerList.timer)
            end
        end)
    end
    return function(doNotDestroy)
        if not doNotDestroy then userFunc=nil end
        return duration
    end
end
end
if Debug then Debug.endFile() end