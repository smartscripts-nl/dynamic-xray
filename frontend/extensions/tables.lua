
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class Tables
local Tables = WidgetContainer:extend{}

function Tables:filter(tbl, callback)
    local filtered = {}
    for _, value in ipairs(tbl) do
        if callback(value) then
            table.insert(filtered, value)
        end
    end
    return filtered
end

function Tables:intoVerticalColumns(subject, column_count)
    if not column_count then
        column_count = 2
    end
    if #subject <= column_count then
        return {
            subject,
        }
    end

    local columnstable = {}
    local to_next_column = math.ceil(#subject / column_count)
    -- insert the rows needed:
    for i = 1, to_next_column do
        columnstable[i] = {}
    end
    -- populate per column:
    for nr, item in ipairs(subject) do
        local active_row = nr <= to_next_column and nr or nr % to_next_column
        if active_row == 0 and nr == #subject then
            active_row = to_next_column
        end
        table.insert(columnstable[active_row], item)
    end
    for i = 1, #columnstable do
        if #columnstable[i] < column_count then
            table.insert(columnstable[i], {
                text = "",
                callback = function()
                end,
            })
        end
    end
    return columnstable
end

--- @return table
function Tables:merge(t1, t2)
    for _, v in ipairs(t2) do
        table.insert(t1, v)
    end
    return t1
end

function Tables:shallowCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else
        -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- only for "flat" tables, so having no objects with text property etc.:
function Tables:sortAlphabetically(subject)
    table.sort(subject, function(v1, v2)
        return v1:lower() < v2:lower()
    end)
end

function Tables:sortByPropAscending(subject, prop)
    table.sort(subject, function(v1, v2)
        if v1[prop] == nil and v2[prop] == nil then
            if v1.text and v2.text then
                return v1.text < v2.text
            end
            return true
        elseif v1[prop] == nil then
            return true
        elseif v2[prop] == nil then
            return false
        end
        if type(v1[prop]) == "string" and type(v2[prop]) == "string" then
            return v1[prop]:lower() < v2[prop]:lower()
        end
        return v1[prop] < v2[prop]
    end)
end

--- @return table
function Tables:sortByPropAscendingAndSetTopItems(subject, prop, select_top_items_method)
    if not subject or #subject == 0 then
        return {}
    end

    local top_subjects = {}
    local other_subjects = {}
    local values = {}
    for i = 1, #subject do
        local item = subject[i]
        if select_top_items_method(item) then
            table.insert(top_subjects, item)
            table.insert(values, item[prop])
        else
            table.insert(other_subjects, item)
        end
    end
    Tables:sortByPropAscending(top_subjects, prop)
    Tables:sortByPropAscending(other_subjects, prop)

    return self:merge(top_subjects, other_subjects)
end

function Tables:sortByPrimaryOrSecondaryPropIsTrue(subject, prop_primary, prop_secondary, remove_prop_after_sort)
    local at_top1 = {}
    local at_top2 = {}
    local regular_items = {}
    for _, item in ipairs(subject) do
        if item[prop_primary] == true then
            if remove_prop_after_sort then
                item[prop_primary] = nil
            end
            table.insert(at_top1, item)
        elseif item[prop_secondary] == true then
            if remove_prop_after_sort then
                item[prop_primary] = nil
            end
            table.insert(at_top2, item)
        else
            if remove_prop_after_sort then
                item[prop_primary] = nil
            end
            table.insert(regular_items, item)
        end
    end
    if (#at_top1 == 0 and #at_top2 == 0) or #regular_items == 0 then
        return subject
    end
    local new_subject = at_top1
    for _, item in ipairs(at_top2) do
        table.insert(new_subject, item)
    end
    for _, item in ipairs(regular_items) do
        table.insert(new_subject, item)
    end
    at_top1 = nil
    at_top2 = nil
    regular_items = nil
    return new_subject
end

return Tables
