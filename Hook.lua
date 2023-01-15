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
---@field package basic function|false

---@class Hook: Hook.property
---@field delete fun(h: Hook.property, all?: boolean) --Call Hook.delete(Hook.property) in order to remove it more efficiently than via Hook.property.remove.
---@field add   fun(key: any, callback: (fun(h: Hook.property, ...):any), priority?: number, host?: table, default?: function, metatable?: boolean, basic?: boolean):Hook.property
---@field basic fun(key: any, callback: (fun(h: Hook.property, ...):any), priority?: number, host?: table, default?: function, metatable?: boolean):Hook.property
Hook = {}

---@class HookTree: { [integer]: Hook.property } --For some reason, the extension doesn't recognize Hook[] as correct syntax.
---@field host table
---@field key any                       --What was the function indexed to (_G items are typically indexed via strings)
---@field package basic function|false
do
    local mode_v = {__mode="v"}
    local treeMap = setmetatable({ [_G] = setmetatable({}, mode_v) }, mode_v) ---@type table<table,table<any,HookTree>>

    ---@param tree HookTree
    ---@param index integer
    ---@param new? table
    local function resizeTree(tree, index, new)
        table[new and "insert" or "remove"](tree, index, new)
        local top, prev = #tree, tree[index-1]
        for i=index, top do
            local h = tree[i]
            h.index = i
            h.next = (i > 1) and prev.basic or prev
            prev = h
        end
        local basic = tree[top].basic
        if basic then
            if tree.basic ~= basic then
                tree.basic = basic
                tree.host[tree.key] = basic
            end
        elseif tree.basic ~= false then
            tree.basic = false
            tree.host[tree.key] = function(...) return tree[#tree](...) end
        end
    end

    ---@param h Hook.property
    ---@param all? boolean
    function Hook.delete(h, all)
        local tree = h.tree
        h.tree = nil
        if (all==true) or (#tree == 1) then
            tree.host[tree.key] = (tree[0] ~= DoNothing) and tree[0] or nil
            treeMap[tree.host][tree.key] = nil
        else
            resizeTree(tree, h.index)
        end
    end

    local function getIndex(h, key) return (key == "remove") and function(all) Hook.delete(h, all) end or h.next end

    function Hook.add(key, callback, priority, host, default, metatable, basic)
        priority=priority or 0; host=host or _G
        if metatable or (default and metatable==nil) then
            host = getmetatable(host) or getmetatable(setmetatable(host, {}))
        end
        treeMap[host]=treeMap[host] or setmetatable({}, mode_v)
        local index, tree = 1, treeMap[host][key]
        if tree then
            local exit = #tree
            repeat if priority <= tree[index].priority then break end
            index=index+1 until index > exit
        else
            tree = { host=host, key=key, [0] = rawget(host, key) or default or (host ~= _G or type(key)~="string") and DoNothing or (Debug and Debug.error or print)("No value found for key: "..key) }
            treeMap[host][key] = tree
        end
        local new = { priority=priority, tree=tree, basic=callback } ---@type Hook.property
        if not basic then
            setmetatable(new, {__call=callback, __index=getIndex}).basic = false
        end
        resizeTree(tree, index, new)
        return new
    end
end

function Hook.basic(k,c,p,h,d,m) return Hook.add(k,c,p,h,d,m,true) end

---@deprecated
function AddHook(...) local new = Hook.basic(...); return function(...) return new.next(...) end, new.remove end

setmetatable(Hook, { __newindex = function(_, key, callback) Hook.add(key, callback) end } )

if Debug then Debug.endFile() end