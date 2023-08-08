--require('Hook')

local print = print

---@diagnostic disable: duplicate-set-field

DoNothing = function() end

function Native()
    print 'Native'
end

--testhandleid = tostring(Native)

function Hook:Native()
    print 'Hook:Native 1'
    self.remove()
    self.next()
end

function Hook:Native()
    print 'Hook:Native 2'
    self.next()
end

print([[
...
After adding two hooks using modern syntax, we should print:
Hook:Native 1
Hook:Native 2
Native
->]])
Native()

local basic1, basic2, basic3
basic1 = Hook.basic('Native', function()
    print 'Hook.basic 1'
    basic1.next()
    basic1.remove()
end)

basic2 = Hook.basic('Native', function()
    print 'Hook.basic 2'
    basic2.next()
end)

print([[
...
After removing 'Hook:Native 1' and adding two basic hooks, we should print:
Hook:Native 2
Hook.basic 1
Hook.basic 2
Native
->]])
Native()

print([[
...
After removing 'Hook.basic 1', we should print:
Hook:Native 2
Hook.basic 2
Native
->]])
Native()

basic2.remove(true)

print([[
...
After removing all hooks simultaneously, we should print:
Native
->]])
Native()

function Hook:Native()
    print 'Hook:Native 3'
    self.remove()
    self.next()
end

basic3 = Hook.basic('Native', function()
    print 'Hook.basic 3'
    basic3.next()
    basic3.remove()
end)

print([[
...
After adding a modern hook and a basic hook to a freshly-cleared hooked native, we should print:
Hook:Native 3
Hook.basic 3
Native
->]])
Native()

print([[
...
After removing the last active hooks manually, we should only print:
Native
->]])
Native()

function Hook:Native()
    print 'Hook without priority'
    self.next()
end

Hook.add('Native', function(self)
    self.next()
    print 'After Hook priority 1'
end, 1)

Hook.add('Native', function(self)
    self.next()
    print 'After Hook priority 3'
end, 3)

Hook.add('Native', function(self)
    self.next()
    print 'After Hook priority 2'
end, 2)

Hook.add('Native', function(self)
    print 'Hook priority 1'
    self.next()
end, 1)

Hook.add('Native', function(self)
    print 'Hook priority 3'
    self.next()
end, 3)

Hook.add('Native', function(self)
    print 'Hook priority 2'
    self.next()
end, 2)

print([[
...
After adding in priority-based hooks out of sequential order, we should print them in this order:
Hook priority 3
Hook priority 2
Hook priority 1
Hook without priority
Native
After Hook priority 1
After Hook priority 2
After Hook priority 3
->]])
Native()
