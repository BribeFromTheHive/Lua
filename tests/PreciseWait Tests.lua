--[[
    Build a mini-engine to imitate very basic War3 behavior.
--]]

function InitGlobals()
end
function DoNothing()
end

local function sleep()
    print 'Test failure - original sleep action called'
end

local trigs, timers = {}, {} ---@type {[number]: function}, {[number]: function}

local function runTimers()
    for _, timer in ipairs(timers) do
        timer()
    end
    timers = {}
end

local function runTriggers()
    for _, trig in ipairs(trigs) do
        trig()
    end
    trigs = {}
end

local function initTests()
    function SyncSelections()
    end
    TriggerSleepAction = sleep
    PolledWait = sleep

    function TriggerAddAction(trig, actionFn)
        table.insert(trigs, actionFn)
    end

    require('Precise Wait')

    InitGlobals()
end

function ExecuteFunc(func)
    _G[func]()
end

function CreateTimer()
end
function TimerStart(timer, duration, repeating, asyncFn)
    table.insert(timers, asyncFn)
end
function DestroyTimer()
end

require('Hook')

local function executeTest()
    TriggerAddAction(nil, function()
        print 'Step 2) Trigger is about to wait'
        TriggerSleepAction()
        print 'Step 4) Trigger has waited'
    end)

    print [[
Test is only successful when steps are printed in sequential order.
Step 1) Running trigger]]

    runTriggers()

    print 'Step 3) Waiting for timer expiration'

    runTimers()

    print 'Step 5) Test completed\n'
end

local function resetTest()
    Hook.basic('TriggerSleepAction').remove(true)
    Hook.basic('PolledWait').remove(true)
    Hook.basic('TriggerAddAction').remove(true)

    package.loaded['Precise Wait'] = nil
end

print 'First test is without Total Initialization:\n'

initTests()
executeTest()

print 'Second test is with Total Initialization:\n'

resetTest()

require('Total Initialization')
initTests()
executeTest()
