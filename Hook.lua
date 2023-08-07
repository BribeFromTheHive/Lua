if Debug then Debug.beginFile "Hook" end
--——————————————————————————————————————
-- Hook version 7.1
-- Created by: Bribe
-- Contributors: Eikonium, Jampion, MyPad, Wrda
--—————————————————————————————————————————————
---@class Hook.property
---@field next function|Hook.property   --Call the next/native function. Also works with any given name (old/native/original/etc.). The args and return values align with the original function.
---@field remove fun(all?: boolean)     --Remove the hook. Pass the boolean "true" to remove all hooks.
---@field package tree HookTree         --Reference to the tree storing each hook on that particular key in that particular host.
---@field package priority number
---@field package index integer
---@field package hookAsBasicFn? function
---@field package debugId? string
---@field package debugNext? string

---@class Hook: {[integer]: Hook.property, [string]: function}
Hook = {}

do
    local looseValuesMT = { __mode = "v" }
    local hostKeyTreeMatrix = ---@type table<table, table<any, HookTree>>
        setmetatable({
            --Already add a hook matrix for _G right away.
            [_G] = setmetatable({}, looseValuesMT)
        }, looseValuesMT)

    ---@class HookTree: { [number]: Hook.property }
    ---@field host table
    ---@field key unknown --What the function was indexed to (_G items are typically indexed via strings)
    ---@field hasHookAsBasicFn boolean

    ---Reindexes a HookTree, inserting or removing a hook and updating the properties of each hook.
    ---@param tree HookTree
    ---@param index integer
    ---@param newHook? table
    local function reindexTree(tree, index, newHook)
        if newHook then
            table.insert(tree, index, newHook)
        else
            table.remove(tree, index)
        end

        local top = #tree
        local prevHook = tree[index - 1]

        -- `table.insert` and `table.remove` shift the elements upwards or downwards,
        -- so this loop manually aligns the tree elements with this shift.
        for i = index, top do
            local currentHook = tree[i]
            currentHook.index = i
            currentHook.next = (i > 1) and
                rawget(prevHook, 'hookAsBasicFn') or
                prevHook
            currentHook.debugNext = tostring(currentHook.next)
            prevHook = currentHook
        end
        local topHookBasicFn = rawget(tree[top], 'hookAsBasicFn')
        if topHookBasicFn then
            if not tree.hasHookAsBasicFn or rawget(tree.host, tree.key) ~= topHookBasicFn then
                tree.hasHookAsBasicFn = true

                --a different basic function should be called for this hook
                --instead of the one that was previously there.
                tree.host[tree.key] = topHookBasicFn
            end
        else
            --The below comparison rules out 'nil' and 'true'.
            --Q: Why rule out nil?
            --A: There is no need to reassign a host hook handler if there is already one in place.
            if tree.hasHookAsBasicFn ~= false then
                tree.host[tree.key] = function(...)
                    return tree[#tree](...)
                end
            end
            tree.hasHookAsBasicFn = false
        end
    end

    ---@param hookProperty Hook.property
    ---@param deleteAllHooks? boolean
    function Hook.delete(hookProperty, deleteAllHooks)
        local tree = hookProperty.tree
        hookProperty.tree = nil
        if deleteAllHooks or #tree == 1 then
            --Reset the host table's native behavior for the hooked key.


            tree.host[tree.key] =
                (tree[0] ~= DoNothing) and
                    tree[0] or
                    nil

            hostKeyTreeMatrix[tree.host][tree.key] = nil
        else
            reindexTree(tree, hookProperty.index)
        end
    end

    ---@param self Hook.property
    ---@param key unknown
    local function getIndex(self, key)
        return self.next
    end

    ---@param hostTableToHook? table
    ---@param defaultNativeBehavior? function
    ---@param hookedTableIsMetaTable? boolean
    local function setupHostTable(hostTableToHook, defaultNativeBehavior, hookedTableIsMetaTable)
        hostTableToHook = hostTableToHook or _G
        if hookedTableIsMetaTable or
            (defaultNativeBehavior and hookedTableIsMetaTable == nil)
        then
            hostTableToHook = getmetatable(hostTableToHook) or
                getmetatable(setmetatable(hostTableToHook, {}))
        end
        return hostTableToHook
    end

    ---@param tree HookTree
    ---@param priority number
    local function huntThroughPriorityList(tree, priority)
        local index = 1
        local topIndex = #tree
        repeat
            if priority <= tree[index].priority then
                break
            end
            index = index + 1
        until index > topIndex
        return index
    end

    ---@param hostTableToHook table
    ---@param key unknown
    ---@param defaultNativeBehavior? function
    ---@return HookTree | nil
    local function createHookTree(hostTableToHook, key, defaultNativeBehavior)
        local nativeFn = rawget(hostTableToHook, key) or
            defaultNativeBehavior or
            ((hostTableToHook ~= _G or type(key) ~= "string") and
            DoNothing)

        if not nativeFn then
            --Logging is used here instead of directly throwing an error, because
            --no one can be sure that we're running within a debug-friendly thread.
            (Debug and Debug.throwError or print)("Hook Error: No value found for key: " .. tostring(key))

            return
        end

        ---@class HookTree
        local tree = {
            host = hostTableToHook,
            key = key,
            [0] = nativeFn,
            --debugNativeId = tostring(nativeFn)
        }
        hostKeyTreeMatrix[hostTableToHook][key] = tree

        return tree
    end

    ---@param key        unknown                Usually `string` (the name of the native you wish to hook)
    ---@param callbackFn fun(Hook, ...):any     The function you want to run when the native is called. The first parameter is type "Hook", and the remaining parameters (and return value(s)) align with the original function.
    ---@param priority?  number                 Defaults to 0. Hooks are called in order of highest priority down to lowest priority. The native itself has the lowest priority.
    ---@param hostTableToHook? table            Defaults to _G (the table that stores all global variables).
    ---@param defaultNativeBehavior? function   If the native does not exist in the host table, use this default instead.
    ---@param hookedTableIsMetaTable? boolean   Whether to store into the host's metatable instead. Defaults to true if the "default" parameter is given.
    ---@param hookAsBasicFn? boolean            When adding a hook instance, the default behavior is to use the __call metamethod in metatables to govern callbacks. If this is `true`, it will instead use normal function callbacks.
    ---@return Hook.property
    function Hook.add(
        key,
        callbackFn,
        priority,
        hostTableToHook,
        defaultNativeBehavior,
        hookedTableIsMetaTable,
        hookAsBasicFn
    )
        priority = priority or 0

        hostTableToHook = setupHostTable(hostTableToHook, defaultNativeBehavior, hookedTableIsMetaTable)

        hostKeyTreeMatrix[hostTableToHook] =
            hostKeyTreeMatrix[hostTableToHook] or
            setmetatable({}, looseValuesMT)

        local index = 1
        local tree = hostKeyTreeMatrix[hostTableToHook][key]
        if tree then
            index = huntThroughPriorityList(tree, priority)
        else
            ---@diagnostic disable-next-line: cast-local-type
            tree = createHookTree(hostTableToHook, key, defaultNativeBehavior)
            if not tree then
                return ---@diagnostic disable-line: missing-return-value
            end
        end
        local new = {
            priority = priority,
            tree = tree
        }
        function new.remove(deleteAllHooks)
            Hook.delete(new, deleteAllHooks)
        end
        --new.debugId = tostring(callbackFn) .. ' and ' .. tostring(new)
        if hookAsBasicFn then
            new.hookAsBasicFn = callbackFn
        else
            setmetatable(new, {
                __call = callbackFn,
                __index = getIndex
            })
        end
        reindexTree(tree, index, new)
        return new
    end
end

---Hook.basic avoids creating a metatable for the hook.
---This is necessary for adding hooks to metatable methods such as __index.
---It is also useful if the user only needs a simple hook.
---@param key        unknown
---@param callbackFn fun(Hook, ...):any
---@param priority?  number
---@param hostTableToHook? table
---@param defaultNativeBehavior? function
---@param hookedTableIsMetaTable? boolean
function Hook.basic(key, callbackFn, priority, hostTableToHook, defaultNativeBehavior, hookedTableIsMetaTable)
    return Hook.add(key, callbackFn, priority, hostTableToHook, defaultNativeBehavior, hookedTableIsMetaTable, true)
end

---@deprecated
---@see Hook.add for args
function AddHook(...)
    local new = Hook.basic(...)
    return function(...)
        return new.next(...)
    end, new.remove
end

setmetatable(Hook, {
    __newindex = function(_, key, callback)
        Hook.add(key, callback)
    end
})

if Debug then Debug.endFile() end
