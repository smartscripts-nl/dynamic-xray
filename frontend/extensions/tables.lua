
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local md5 = require("ffi/sha2").md5

local has_no_items = has_no_items
local pairs = pairs
local table = table
local tostring = tostring
local type = type

local count

--- @class Tables
local Tables = WidgetContainer:extend{}

function Tables:filter(tbl, callback)
    local filtered = {}
    local value
    for i = 1, #tbl do
        value = tbl[i]
        if callback(value) then
            table.insert(filtered, value)
        end
    end
    return filtered
end

function Tables:filterIpairsTable(itable, key_or_value, by_key)
    for i = #itable, 1, -1 do
        if not by_key and itable[i] == key_or_value then
            table.remove(itable, i)
            break
        elseif by_key and i == key_or_value then
            table.remove(itable, i)
            break
        end
    end
end

--* merge two tables and add prop to the items of the resulting table; add_indices for now only set for Xray items:
--- @return table
function Tables:merge(t1, t2, add_indices)
    local v
    count = #t2
    for i = 1, count do
        v = t2[i]
        table.insert(t1, v)
    end
    if not add_indices then
        return t1
    end

    count = #t1
    for i = 1, count do
        t1[i].index = i
    end
    return t1
end

function Tables:concatField(itable, prop, separator)
    local texts = {}
    count = #itable
    for i = 1, count do
        table.insert(texts, itable[i][prop])
    end

    if not separator then
        separator = " "
    end
    return table.concat(texts, separator)
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
        --* number, string, boolean, etc
        copy = orig
    end
    return copy
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

--* was used in ((XrayViewsData#indexItems)), but since sorting already done in query in ((XrayDataLoader#_loadAllData)), not needed anymore:
--- @return table
function Tables:sortByPropDescendingAndSetTopItems(subject, sorting_prop, top_items_selector_callback)
    if has_no_items(subject) then
        return {}
    end

    local top_subjects = {}
    local other_subjects = {}
    local values = {}
    count = #subject
    local item
    for i = 1, count do
        item = subject[i]
        if top_items_selector_callback(item) then
            table.insert(top_subjects, item)
            table.insert(values, item[sorting_prop])
        else
            table.insert(other_subjects, item)
        end
    end
    self:sortByPropDescending(top_subjects, sorting_prop)
    self:sortByPropDescending(other_subjects, sorting_prop)

    return self:merge(top_subjects, other_subjects, "add_indices")
end

--- @return table
function Tables:sortByPropAscendingAndSetTopItems(subject, sorting_prop, top_items_selector_callback)
    if has_no_items(subject) then
        return {}
    end

    local top_subjects = {}
    local other_subjects = {}
    local values = {}
    count = #subject
    local item
    for i = 1, count do
        item = subject[i]
        if top_items_selector_callback(item) then
            table.insert(top_subjects, item)
            table.insert(values, item[sorting_prop])
        else
            table.insert(other_subjects, item)
        end
    end
    self:sortByPropAscending(top_subjects, sorting_prop)
    self:sortByPropAscending(other_subjects, sorting_prop)

    return self:merge(top_subjects, other_subjects, "add_indices")
end

--* was used in ((XrayViewsData#indexItems)), but since sorting already done in query in ((XrayDataLoader#_loadAllData)), not needed anymore:
--- @return table
function Tables:sortByPropDescending(subject, prop)
    table.sort(subject, function(v1, v2)
        if v1[prop] == nil and v2[prop] == nil then
            if v1.text and v2.text then
                return v1.text < v2.text
            end
            return false
        elseif v1[prop] == nil then
            return false
        elseif v2[prop] == nil then
            return true
        end
        if type(v1[prop]) == "string" and type(v2[prop]) == "string" then
            return v1[prop]:lower() > v2[prop]:lower()
        end
        return v1[prop] > v2[prop]
    end)
end

function Tables:tableToMd5(subject)
    local text = self:tableToText(subject, false, "get_unclipped_table")
    return md5(text)
end

function Tables:tableToText(o, add_line_endings, get_unclipped_table, remove_indices)
    local ellipsis = "…"
    local max_string_length = 120
    if o == nil then
        o = "nil"
    end
    if type(o) == "table" then
        local spacer = add_line_endings and "\n" or " "
        local s = "{" .. spacer
        for k, v in pairs(o) do
            if type(k) == "function" then
                k = "function"
            elseif type(k) ~= "number" then
                k = "\"" .. k .. "\""
            end
            s = s .. "[" .. k .. "] = " .. self:tableToText(v, add_line_endings, get_unclipped_table) .. "," .. spacer
        end
        s = s .. "}" .. spacer
        s = s:gsub(", %}", " }"):gsub(",\n%}", "\n}"):gsub("\n%[", "\n   [")
        if remove_indices then
            s = s:gsub("%[%d+%] = ", "")
        end
        return s
    else
        local value = tostring(o)
        value = value:gsub("\n", " ")
        --* second condition: don't clip paths:
        if not get_unclipped_table and not value:match("[A-Za-z]/[A-Za-z]") and value:len() > max_string_length then
            value = value:sub(1, max_string_length) .. ellipsis
        end
        return value
    end
end

function Tables:isNumericalTable(t)
    --* count how many sequential integer keys we have:
    count = 0
    for k in pairs(t) do
        if type(k) ~= "number" then
            return false
        end
        count = count + 1
    end
    --* check if it's 1..n contiguous
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return true
end

function Tables:normalizeTableIndex(index)
    return index and index:lower():gsub("[%p%s]+$", "")
end

return Tables
