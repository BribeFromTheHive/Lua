---@diagnostic disable: lowercase-global, missing-parameter, missing-return

require('Hook')

function InitGlobals()
end
function DoNothing()
end

require('Global Variable Remapper')

InitGlobals()

--Test 1: GlobalRemap

scalar1 = 10

print('the variable has a pre-assigned value:', scalar1 == 10)

GlobalRemap('scalar1', function()
    return 20
end)

print('although we\'ve not directly set the variable, it now possesses a new value defined by GlobalRemap:', scalar1 == 20)

scalar1 = 30

print('after attempting to set the variable when it does not have a setter function, the setter call is ignored:', scalar1 == 20)

GlobalRemap('scalar1', function()
    return 40
end)

print('After attempting to remap a second time, the second remap should fail and the original remap should persist:', scalar1 == 20)


-- Test 2: GlobalRemapArray

print('An error should be thrown when trying to invoke GlobalRemapArray on a non-array variable:')
GlobalRemapArray('scalar1')


rebelArray = {[0]="Luke", [1]="Leia"}

GlobalRemapArray('rebelArray',
    function(index)
        if index == 0 then return "Han" end
        if index == 1 then return "Chewbacca" end
    end
)

print('Getter should return "Han" for index 0:', rebelArray[0] == "Han")
print('Getter should return "Chewbacca" for index 1:', rebelArray[1] == "Chewbacca")

-- Test 3: Preserve State for GlobalRemapArray

sithArray = {[0]="Vader", [1]="Sidious"}

GlobalRemapArray('sithArray',
    function(index, state)
        if index == 0 then return "Darth " .. state[0] end
        if index == 1 then return "Darth " .. state[1] end
    end,
    function(index, value, state)
        state[index] = value
    end, true
)

print('Getter should return "Darth Vader" for index 0:', sithArray[0] == "Darth Vader")
print('Getter should return "Darth Sidious" for index 1:', sithArray[1] == "Darth Sidious")

--Test 3: Extra Remapping for GlobalRemapArray

GlobalRemapArray('sithArray',
    function(index, state)
        if index == 0 then return state[0] .. " and Starkiller" end
        if index == 1 then return state[1] .. " and Count Dooku" end
    end,
    function(index, value, state)
        state[index] = value
    end, true
)

print('Getter should return "Darth Vader and Starkiller" for index 0:', sithArray[0] == "Darth Vader and Starkiller")
print('Getter should return "Darth Sidious and Count Dooku" for index 1:', sithArray[1] == "Darth Sidious and Count Dooku")

--Test 4: Setting the previous state

sithArray[0] = 'Maul'
sithArray[1] = 'Plagueis'

print('Getter should return "Darth Maul and Starkiller" for index 0:', sithArray[0] == "Darth Maul and Starkiller")
print('Getter should return "Darth Plagueis and Count Dooku" for index 1:', sithArray[1] == "Darth Plagueis and Count Dooku")

--Test 5: Extra remapping discarding previous state:

GlobalRemapArray('sithArray',
    function(index, state)
        if state then
            print 'Test has failed because "state" is still somehow defined.'
        end
        if index == 0 then return "Kylo Ren" end
        if index == 1 then return "Snoke" end
    end
)

print('Getter should only return "Kylo Ren" for index 0:', sithArray[0] == "Kylo Ren")
print('Getter should only return "Snoke" for index 1:', sithArray[1] == "Snoke")