---@diagnostic disable: cast-local-type, missing-return-value
--[[
    Doubly-Linked List v1.5.4.1 by Wrda, Eikonium and Bribe, with special thanks to Jampion
    ------------------------------------------------------------------------------
    A script that enables linking objects together with "previous" and "next"
    syntax.
    ------------------------------------------------------------------------------
    
LinkedList API:
    LinkedList.create() -> LinkedListHead
      - Creates a new LinkedListHead that can have nodes inserted to itself.
    list.head -> the head (internal implementation) of the list. [node.head] has the same result.
    list.next -> next item in the same list. [list.next] is always the first node of the list.
                 Doesn't skip the head.
    list.prev -> previous item in the same list. [list.prev] is always the last node of the list.
                 Doesn't skip the head.
    
    list:insert([value : any, after : boolean]) -> LinkedListNode
      - Inserts *before* the given LinkedList object unless "after" is true.
      - If a value is passed, the system will attach it to the node as a generic "value"
      - Returns the inserted node that was added to the list.
    for node in LinkedList.loop(start : LinkedList [, finish : LinkedList , backwards : boolean]) do [stuff] end
      - Shows how to iterate over all nodes in "list". Inclusive range.
      - An example of how to iterate while skipping the first and last nodes of the list:
        for node in list.next.next:loop(list.prev.prev) do print(node.value) end
        
API specific to LinkedListHead:
    list.remove(node)
      - Removes a node from list.
    list.n
      - The number of LinkedListNodes in the list.
    fromList:merge(intoList : LinkedList [, mergeBefore : boolean])
      - Removes all nodes of list "fromList" and adds them to the end of list "intoList" (or
        at the beginning, if "mergeBefore" is true).
        "fromList" needs to be the linked list head, but "into" can be anywhere in that list.
      
LinkedListNode API:
    node:remove()
      - Removes a node from whatever list it is a part of.
    node:getNext()
      - Gets the next node, ignoring the head.
    node:getPrev()
      - Gets the previous node, ignoring the head.
    node.value
      - Whatever value might have been assigned from list:insert([value])
]]
---@class LinkedList     : table
---@field head LinkedListHead
---@field next LinkedList
---@field prev LinkedList
---@class LinkedListNode : LinkedList
---@field value any
---@class LinkedListHead : LinkedList
---@field n integer
LinkedList = {}
LinkedList.__index = LinkedList
---Creates a new LinkedList head node.
---@return LinkedListHead new_list_head
function LinkedList.create()
    local head = {}
    setmetatable(head, LinkedList)
    head.next = head
    head.prev = head
    head.head = head
    head.n = 0
    return head
end
---Inserts *before* the given head/node, unless "backward" is true.
---@param value? any
---@param insertAfter? boolean
---@return LinkedListNode new_node
function LinkedList:insert(value, insertAfter)
    local node = {}   ---@type LinkedListNode
    setmetatable(node, LinkedList)
    local from = insertAfter and self.next or self
    from.prev.next = node
    node.prev = from.prev
    from.prev = node
    node.next = from
 
    node.value = value
    local head = from.head
    node.head = head
    head.n = head.n + 1
    return node
end
---Removes a node from whatever list it is a part of.
function LinkedList:remove()
    self.prev.next = self.next
    self.next.prev = self.prev
    self.head.n = self.head.n - 1
    self:destroy()
end
---Nullify the linked list's inheritance (as a matter of principle).
function LinkedList:destroy()
    setmetatable(self, nil)
end
--Gets the next node in the sequence of the list it is in, ignoring the head.
function LinkedList:getNext()
    if self.next == self.head then
        return self.head.next
    end
    return self.next
end
--Gets the previous node in the sequence of the list it is in, ignoring the head.
function LinkedList:getPrev()
    if self.prev == self.head then
        return self.head.prev
    end
    return self.prev
end

---Merges LinkedListHead "from" to a LinkedList "into"
---@param from LinkedListHead
---@param into LinkedList
---@param mergeBefore? boolean
function LinkedList.merge(from, into, mergeBefore)
    local head = into.head
    into = mergeBefore and into.next or into
 
    for node in from:loop() do node.head = head end
    head.n = head.n + from.n
    from.n = 0
 
    from.next.prev = into.prev
    into.prev.next = from.next
    into.prev = from.prev
    from.prev.next = into
    --reset the original list to a simple LinkedListHead
    from.next = from
    from.prev = from
end
---Loop a LinkedList from a starting node/head to a finish node/head in either direction.
---Inclusive range.
---@param start LinkedList
---@param finish? LinkedList
---@param backward? boolean
---@return function
function LinkedList.loop(start, finish, backward)
    local head = start.head
    if head.n == 0 then return end
    local direction = backward and "prev" or "next"
    local skip = start ~= head or start == finish
    if not finish or finish == head then
        return function()
            if skip then
                skip = nil
            else
                start = start[direction]
            end
            return start ~= head and start or nil
        end
    else
        return function()
            if start ~= finish or skip then
                if skip and skip ~= 1 then
                    skip = start == finish and 1
                else
                    start = start[direction]
                    if start == head then
                        start = start[direction]
                    end
                end
                return start
            end
        end
    end
end
--End of LinkedList library
