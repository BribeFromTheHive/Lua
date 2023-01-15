do local old = MarkGameStarted; MarkGameStarted = function() old()
    local deadItemStack
    local function checkForDeadItems()
        local item = GetEnumItem()
        if GetWidgetLife(item) == 0 then
            deadItemStack = deadItemStack or {}
            table.insert(deadItemStack, item)
        end
    end
    TimerStart(CreateTimer(), 15, true, function()
        if deadItemStack then
            for _,item in ipairs(deadItemStack) do
                SetWidgetLife(item, 1)
                RemoveItem(item)
            end
            deadItemStack = nil
        end
        EnumItemsInRect(bj_mapInitialPlayableArea, nil, checkForDeadItems)
    end)
end end