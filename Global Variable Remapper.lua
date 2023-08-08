if Debug then Debug.beginFile 'GlobalRemap' end
--[[
Global Variable Remapper v1.4 by Bribe

Turns normal GUI variables into function calls that integrate seamlessly with Lua.
--]]
local oldInit = InitGlobals
function InitGlobals()
    oldInit()

    local printError = Debug and Debug.throwError or print

    ---@param name string
    ---@param error string
    local function softErrorHandler(name, error)
        printError('!!!GlobalRemap Error!!! "' .. name .. '" ' .. error)
    end

    if not Hook then --https://github.com/BribeFromTheHive/Lua/blob/master/Hook.lua
        softErrorHandler('Hook', 'is required but not found.')
        return
    end

    local default = DoNothing
    local getters = {}
    local setters = {}

    ---@param hook Hook.property
    ---@param _G table
    ---@param key string
    ---@return unknown
    local function __index(hook, _G, key)
        if getters[key]~=nil then
            return getters[key]()
        end
        return hook.next(_G, key)
    end

    ---@param hook Hook.property
    ---@param _G table
    ---@param key string
    ---@param val unknown
    local function __newindex(hook, _G, key, val)
        if setters[key]~=nil then
            setters[key](val)
        else
            hook.next(_G, key, val)
        end
    end

    Hook.add('__index',    __index,    0, _G, rawget)
    Hook.add('__newindex', __newindex, 0, _G, rawset)

    ---Remap a global variable (non-array) to call getFunc when referenced or setFunc when assigned.
    ---This serves as a permanent hook and cannot be removed.
    --
    ---@param variableStr string            # a string such as "udg_MyVariable"
    ---@param getFunc? fun(): unknown        # a function that takes nothing but returns the expected value when `udg_MyVariable` is referenced.
    ---@param setFunc? fun(value: unknown)   # a function that takes a single argument (the value that is being assigned) and allows you to do what you want when someone uses `Set MyVariable = SomeValue`. The function doesn't need to do anything nor return anything, so it even allows read-only GUI variables.
    function GlobalRemap(variableStr, getFunc, setFunc)
        if getters[variableStr] then
            softErrorHandler(variableStr, 'has been remapped twice. There can only be one remap per variable.')
            return
        end
        _G[variableStr] = nil                     --Delete the variable from the global table.
        getters[variableStr] = getFunc or default --Assign a function that returns what should be returned when this variable is referenced.
        setters[variableStr] = setFunc or default --Assign a function that captures the value the variable is attempting to be set to.
    end

    ---This function allows you to override the behavior of a global array variable.
    ---
    ---You can provide custom getter and setter functions that will be called whenever the variable is accessed or modified.
    ---
    ---If 'preserveState' is 'true', the original array is preserved and passed to the getter and setter functions as an extra parameter.
    ---This is particularly useful when multiple resources want to remap the same array. As long as the resource that called it
    ---most recently handles the previous state correctly, multiple remappings can coexist without conflict.
    ---
    ---Like GlobalRemap, this hook cannot be reversed.
    ---
    ---@param variableStr string                                         # The name of the global array variable you want to remap, such as "udg_MyVariableArray".
    ---@param getFunc fun(index: unknown, state?: table): unknown        # A function that takes the index of the array and a table representing the current state of the variable.
    ---@param setFunc? fun(index: unknown, value: unknown, state?: table) # A function that takes the index of the array, the value that is being assigned to the variable, and a table representing the current state of the variable.
    ---@param preserveState? true                                        # If not provided, the state passed to the callback functions will simply be 'nil'
    function GlobalRemapArray(variableStr, getFunc, setFunc, preserveState)
        getFunc = getFunc or default
        setFunc = setFunc or default

        local state = _G[variableStr]
        if type(state) ~= 'table' then
            softErrorHandler(variableStr, 'is an invalid array to remap. Its type must be "table" but is instead "' .. type(state) .. '".')
            return
        end
        state = preserveState and state

        _G[variableStr] = setmetatable({}, {
            __index = function(_, index)
                return getFunc(index, state)
            end,
            __newindex = function(_, index, val)
                setFunc(index, val, state)
            end
        })
    end
end

if Debug then Debug.endFile() end