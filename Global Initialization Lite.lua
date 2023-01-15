--Global Initialization 'Lite' by Bribe, with special thanks to Tasyen and Eikonium
--Last updated 11 Nov 2022
do
    local addInit
    function OnGlobalInit(initFunc) addInit("InitGlobals",               initFunc) end -- Runs once all GUI variables are instantiated.
    function OnTrigInit  (initFunc) addInit("InitCustomTriggers",        initFunc) end -- Runs once all InitTrig_ are called.
    function OnMapInit   (initFunc) addInit("RunInitializationTriggers", initFunc) end -- Runs once all Map Initialization triggers are run.
    function OnGameStart (initFunc) addInit("MarkGameStarted",           initFunc) end -- Runs once the game has actually started.
    do
        local initializers = {}
        addInit=function(initName, initFunc)
            initializers[initName] = initializers[initName] or {}
            table.insert(initializers[initName], initFunc)
        end
        local function init(initName, continue)
            if initializers[initName] then
                for _,initFunc in ipairs(initializers[initName]) do pcall(initFunc) end
            end
            if continue then continue() end
        end
        local function hook(name, continue)
            local _name=rawget(_G, name)
            if _name then
                rawset(_G, name, function()
                    _name()
                    init(name, continue) --run the initializer after the hooked handler function has been called.
                end)
            else
                init(name, continue) --run initializer immediately
            end
        end
        hook("InitGlobals",function()
            hook("InitCustomTriggers",function() --InitCustomTriggers and RunInitializationTriggers are declared after the users' code,
                hook "RunInitializationTriggers" --hence users need to wait until they have been declared.
            end)
        end)
        hook "MarkGameStarted"
    end
end