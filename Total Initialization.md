## [Total Initialization](https://github.com/BribeFromTheHive/Lua/blob/main/TotalInitialization.lua)

- Allows you to initialize your script in a safe, easy-to-debug environment.
- Allows your map's triggers to be arranged in any order* (similar to JassHelper).
- Enables functionality similar to Lua modules and vJass libraries.
- Provides helpful tools to hook into certain key points in the initialization process (e.g. once all udg_ globals are declared, or once the game has started).


_*provided that Total Initialization is declared towards the top of the trigger list_

Special Thanks:

- [Eikonium](https://www.hiveworkshop.com/members/175606/) for the "try" function and for challenging bad API approaches, leading me to discovering far better API for this resource.
- [HerlySQR](https://www.hiveworkshop.com/members/286960/) for GetStackTrace, which makes debugging a much more straightforward process.
- [Tasyen](https://www.hiveworkshop.com/members/194042/) for helping me to better understand the "main" function, and for discovering MarkGameStarted can be hooked for OnInit.final's needs.
- [Luashine](https://www.hiveworkshop.com/members/300553/) for showing how I can implement OnInit.config, which - in turn - led to an actual OnInit.main (previous attempts had failed)
- [Forsakn](https://www.hiveworkshop.com/members/293833/) and Troll-Brain for help with early debugging (primarily with the pairs desync issue)



For laying the framework for requirements in WarCraft 3 Lua:

- [Almia](https://www.hiveworkshop.com/members/217293/)'s [Module System](https://www.hiveworkshop.com/threads/lua-module-system.335222/)
- [ScorpioT1000](https://www.hiveworkshop.com/members/230372/)'s [wlpm-module-manager](https://github.com/Indaxia/wc3-wlpm-module-manager/blob/master/wlpm-module-manager.lua')
- [Troll-Brain](https://www.hiveworkshop.com/members/147723/)'s [lua require ersatz](https://www.hiveworkshop.com/threads/lua-require-ersatz.326584/)


## Background
**Why not just use do...end blocks in the Lua root?**
While Lua only has the *Lua root* for initialization, Lua can use *run-time hooks* on the InitBlizzard function in order to postpone its own code until heavy WarCraft 3 natives need to be called.

- Creating WarCraft 3 objects in the Lua root is dangerous as it causes desyncs.
- The Lua root is an unstable place to initialize (e.g. it doesn't allow "print", which makes debugging extremely difficult)
- do...end blocks force you to organize your triggers from top to bottom based on their requirements.
- The Lua root is not split into separate pcalls, which means that failures can easily crash the entire loading sequence without showing an error message.
- The Lua root is not yieldable, which means you need to do everything immediately or hook onto something like InitBlizzard or MarkGameStarted to await these loading steps.


**Why I made this:**
First, let me show you the sequence of initialization that JassHelper used:

[ATTACH type="full" alt="1666109255220.png"]411349[/ATTACH]

There were two very key problems with JassHelper's initializer:

1. Initialization precedence was Module > Struct > Library > **Requirement**, rather than **Requirement** > Module > Struct > Library. This created a problem with required libraries having not been loaded in time for a module to depend on them, meaning that everything in the matured vJass era needed to be initialized with a module in order to circumvent the problem.
2. The initializers ran before InitGlobals, so it created a permanent rift between the GUI and vJass interfaces by ostracizing one from the other (if vJass changed the value of a udg_ variable, InitGlobals would just overwrite it again).


I therefore wanted to re-design the sequence to allow GUI and Lua to not suffer the same fate:

1. The Lua root runs.
2. OnInit functions that require nothing - or - already have their requirements fulfilled in the Lua root.
3. OnInit functions that have their requirements fulfilled based on other OnInit declarations.
4. OnInit "custom" initializers run sequentially, prolonging the initialization queue.
5. Repeat step 2-4 until all executables are loaded and all subsequent initializers have run.
6. OnInit.final is the final initializer, which is called after the loading screen has transitioned into the actual game screen.
7. Display error messages for missing requirements.


**Basic API for initializer functions:**

```lua
OnInit.root(function()
        print "This is called immediately"
    end)
    OnInit.config(function()
        print "This is called during the map config process (in game lobby)"
    end)
    OnInit.main(function()
        print "This is called during the loading screen"
    end)
    OnInit(function()
        print "All udg_ variables have been initialized"
    end)
    OnInit.trig(function()
        print "All InitTrig_ functions have been called"
    end)
    OnInit.map(function()
        print "All Map Initialization events have run"
    end)
    OnInit.final(function()
        print "The game has now started"
    end)
```

Note: You can optionally include a string as an argument to give your initializer a name. This is useful in two scenarios:

1. If you don't add anything to the global API but want it to be useful as a requirment.
2. If you want it to be accurately defined for initializers that optionally require it.


**API for Requirements:**
`local someLibrary = Require "SomeLibrary"`

- Functions similarly to Lua's built-in (but disabled in WarCraft 3) "require" function, provided that you use it from an OnInit callback function.
- Returns either the return value of the OnInit function that declared its name as `SomeLibrary` or will return `_G["SomeLibrary"]` or just `true` if that named library was initialized but did not return anything nor add itself to the `_G` table.
- Will throw an error if the requirement was not found by the time the map has fully loaded.
- Can also require elements of a table: Require `table.property.subProperty`


`local optionalRequirement = Require.optionally "OptionalRequirement"`

- Similar to the Require method, but will only wait if the optional requirement was already declared as an uninitialized library. This name can be whatever suits you (optional/lazy/nonStrict), since it uses the __index method rather than limit itself to one keyword.



## Library and Requirement Examples

```lua
OnInit("Yuna", function(needs)
    print("Yuna has arrived, thanks to Tidus, who is:",needs "Tidus")
    print("Yuna only optionally needs Kimhari, who is:",needs.optionally "Kimahri")
end)

OnInit("Tidus", function(requires)
    print("Tidus has loaded, thanks to Jecht, who is:", requires "Jecht")

    print "Tidus is declaring Rikku and yielding for initializers that need her."
    OnInit "Rikku"
 
    return "The Star Player of the Zanarkand Abes"
end)

OnInit("Cid", function(needs)
    print("Cid has arrived, thanks to Rikku, who is:",needs "Rikku")
end)

OnInit(function(braucht)
    print("Spira does not exist, so this library will never run.", braucht "Spira")
end)

OnInit("Jecht", function(needs)
    print("Jecht requires Blitzball, which is:",needs"Blitzball")
    print("Jecht has arrived, without Sin, who is:",needs.readyOrNot "Sin")
 
    return "A Retired Blitzball Player", "An Alcoholic", "A bad father to Tidus"
end)

OnInit("Wakka", function(needs)
    print("Wakka requires Blitzball, which is:",needs"Blitzball")
    print("Wakka optionally requires Lulu, who is:", needs.ifHeFeelsLikeIt "Lulu")
end)

OnInit("Lulu", function(needs)
    print("Lulu optionally requires Wakka, who is:", needs.ifSheFeelsLikeIt "Wakka")
end)

OnInit("Blitzball", function()
    print "Blitzball has no requirements."
    return "Round", "Popular", "Extremely Dangerous"
end)

OnInit("Bevel", function(import)
    print("Bevel will not wait for Zanarkand, which is:", import.sleepily "Zanarkand")
end)

OnInit.trig("Ronso Fangs", function()
    print "The Ronso Fangs run last, because they are late bloomers."
end)
```

Prints (with the help of the "try" function):

![screenshot](https://www.hiveworkshop.com/attachments/1668273754677-png.413631/)

## Unit Tester

Use the following site to test: [JDoodle - Online Compiler, Editor for Java, C/C++, etc](https://www.jdoodle.com/execute-lua-online/)

Ensure you copy the latest version of Total Initialization into the designated part of the script.

```lua
DoNothing = function()end
MarkGameStarted = function() bj_gameStarted = true end
InitGlobals = DoNothing --this is always found at the top of the map script, even when there are no udg_ globals

-- Total Initialization script goes here --


-- (write your own unit tests here) --


-- auto-generated functions like "CreateAllUnits" are placed here --


-- map header script is placed here --


-- GUI triggers are placed here --


-- this marks the end of the user's access to the Lua root, everything is auto-generated by World Editor beyond this point --


InitCustomTriggers = DoNothing
RunInitializationTriggers = DoNothing

function main()
    InitGlobals()
    InitCustomTriggers()
    RunInitializationTriggers()
end
config = DoNothing

-- end of Lua root --

config() --called during the game lobby menu/prior to the game's loading screen.
main() --called first during the map loading screen.
MarkGameStarted() --synthesize that the game has loaded.
```

If you don't have any need of libraries or requirements, you might find this "Lite" version to be more your taste:


```lua
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
```
