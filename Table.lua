Table       = {}
HandleTable = Table
StringTable = Table

--One map, no hashtables. Welcome to Lua Table version 1.1.1.0
--Made by Bribe, special thanks to Vexorian

function Table.create()
    return setmetatable({}, Table)
end

function Table:has(key)             --Bribe's API
    return rawget(self, key)~=nil
end
Table.exists=Table.has              --Vexorian's API

--Vexorian's API:
function Table:reset()
    for key in pairs(self) do
        self[key]=nil
    end
end
Table.destroy=Table.reset --Destruction only exists for backwards-compatibility. Lua's GC will handle this.

--Bribe's API:
function Table:remove(key)
    self[key]=nil
end

function Table:flush(key)
    if key then
        self[key]=nil   --Vexorian's version of flush
    else
        self:reset()    --Bribe's version of flush
    end
end

do
    local repeater
    local function makeRepeater(parent, key)
        local new=rawget(TableArray, key)
        if not new then
            new=Table.create()
            rawset(parent, key, new)
        end
        return new
    end
    local function create2D(_, size)
        if not repeater then
            repeater={__index=makeRepeater}
        end
        return setmetatable({size=size}, repeater)
    end
    HashTable={
        create=create2D,
        flush=Table.reset,
        destroy=Table.destroy,
        remove=Table.remove,
        has=Table.has
    }
    TableArray=setmetatable(HashTable, {__index=create2D})

    --Create a table just to store the types that will be ignored
    local dump={
        handle=true,          agent=true,       real=true,              boolean=true,
        string=true,          integer=true,     player=true,            widget=true,
        destructable=true,    item=true,        unit=true,              ability=true,
        timer=true,           trigger=true,     triggercondition=true,  triggeraction=true,
        event=true,           force=true,       group=true,             location=true,
        rect=true,            boolexpr=true,    sound=true,             effect=true,
        unitpool=true,        itempool=true,    quest=true,             questitem=true,
        defeatcondition=true, timerdialog=true, leaderboard=true,       multiboard=true,
        multiboarditem=true,  trackable=true,   dialog=true,            button=true,
        texttag=true,         lightning=true,   image=true,             ubersplat=true,
        region=true,          fogstate=true,    fogmodifier=true,       hashtable=true
    }
    --Create a table that handles Vexorian's static 2D Table syntax.
    local indexer2D={}
    function Table.flush2D(index)
        indexer2D[index]=nil
    end
    
    function Table:__index(index)
        local get
        if self==Table then
            --static method operator (for supporting Vexorian's static 2D Table syntax):
            get=indexer2D[index]
            if get then
                return get
            end
            get=Table.create()
            self=indexer2D
        else
            --regular method operator (but only called when the value wasn't found, or if nothing was assigned yet):
            get=dump[index] and self
            if not get then
                return
            end
        end
        rawset(self, index, get) --cache for better performance on subsequent calls
        return get
    end
end
setmetatable(Table, Table)