
local require = require

local KOR = require("extensions/kor")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local md5 = require("ffi/sha2").md5

local has_no_items = has_no_items
local math_ceil = math.ceil
local pairs = pairs
local table = table
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack

local count

--- @class Tables
local Tables = WidgetContainer:extend{}

function Tables:getSortedRelationalTable(subject)
    --* change a relational table into a numerical one, with each new item having a table { key, value }:
    local keys = {}
    for key in pairs(subject) do
        table_insert(keys, key)
    end
    table_sort(keys)
    local ordered = {}
    count = #keys
    for k = 1, count do
        table_insert(ordered, { keys[k], subject[keys[k]] })
    end
    return ordered
end

function Tables:filter(tbl, callback)
    local filtered = {}
    local value
    for i = 1, #tbl do
        value = tbl[i]
        if callback(value) then
            table_insert(filtered, value)
        end
    end
    return filtered
end

function Tables:filterIpairsTable(itable, key_or_value, by_key)
    for i = #itable, 1, -1 do
        if not by_key and itable[i] == key_or_value then
            table_remove(itable, i)
            break
        elseif by_key and i == key_or_value then
            table_remove(itable, i)
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
        table_insert(t1, v)
    end
    if not add_indices then
        return t1
    end

    --* this is a correction set in ((XrayViewsData#getLinkedItems)) for linked items, because on top of the linked items the parent item will be injected, which should have index 1:
    local starting_index = KOR.registry:getOnce("starting_sorting_index")
    local correction = starting_index and starting_index - 1 or 0
    count = #t1
    for i = 1, count do
        t1[i].index = i + correction
    end
    return t1
end

function Tables:populateWithPlaceholders(items_count, default_value)
    local temp = {}
    local value
    for i = 1, items_count do
        value = default_value or i
        --* these values MUST be replaced by the calling routine:
        table_insert(temp, value)
    end
    return temp
end

function Tables:concatField(itable, prop, separator)
    local texts = {}
    count = #itable
    for i = 1, count do
        table_insert(texts, itable[i][prop])
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

--- @return table
function Tables:slice(subject, startpos, icount)
    local sliced = {}
    if icount > 0 then
        for _, value in pairs({ unpack(subject, startpos, icount) }) do
            table_insert(sliced, value)
        end
        return sliced
    end

    --* "negative" slice, from end of table:
    local endpos = #subject
    startpos = endpos - (-icount) + 1
    for x = startpos, endpos do
        table_insert(sliced, subject[x])
    end
    return sliced
end

function Tables:sortByPropAscending(subject, prop)
    table_sort(subject, function(v1, v2)
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
            table_insert(top_subjects, item)
            table_insert(values, item[sorting_prop])
        else
            table_insert(other_subjects, item)
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
            table_insert(top_subjects, item)
            table_insert(values, item[sorting_prop])
        else
            table_insert(other_subjects, item)
        end
    end
    self:sortByPropAscending(top_subjects, sorting_prop)
    self:sortByPropAscending(other_subjects, sorting_prop)

    return self:merge(top_subjects, other_subjects, "add_indices")
end

--* was used in ((XrayViewsData#indexItems)), but since sorting already done in query in ((XrayDataLoader#_loadAllData)), not needed anymore:
--- @return table
function Tables:sortByPropDescending(subject, prop)
    table_sort(subject, function(v1, v2)
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

--* this method requires a numerical table with numerical values:
function Tables:makeItemsNumerical(subject)
    count = #subject
    for i = 1, count do
        subject[i] = tonumber(subject[i])
    end
    return subject
end

--* this method requires a numerical table with numerical values:
function Tables:getMaxValue(subject)
    local max = 0
    count = #subject
    for i = 1, count do
        if subject[i] > max then
            max = subject[i]
        end
    end
    return max
end

function Tables:tableHas(itable, needle)
    if not needle or not itable or #itable == 0 then
        return false
    end
    for nr = 1, #itable do
        if itable[nr] == needle then
            return nr
        end
    end
    return false
end

function Tables:tableHasNot(itable, needle)
    return not self:tableHas(itable, needle)
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

function Tables:arrangeInVerticalColumns(subject, column_count)
    if not column_count then
        column_count = 2
    end
    if #subject <= column_count then
        return {
            subject,
        }
    end

    local columns_table = {}
    local to_next_column = math_ceil(#subject / column_count)
    --* insert the rows needed:
    for i = 1, to_next_column do
        columns_table[i] = {}
    end
    --* populate per column:
    local item
    count = #subject
    for nr = 1, count do
        item = subject[nr]
        local active_row = nr <= to_next_column and nr or nr % to_next_column
        if active_row == 0 and nr == #subject then
            active_row = to_next_column
        end
        table_insert(columns_table[active_row], item)
    end
    for i = 1, #columns_table do
        if #columns_table[i] < column_count then
            table_insert(columns_table[i], {
                text = "",
                callback = function()
                end,
            })
        end
    end
    return columns_table
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

function Tables:tablesAreEqual(t1, t2)
    --* different types or one is nil:
    if type(t1) ~= "table" or type(t2) ~= "table" then
        return false
    end

    --* compare each key/value in t1
    for k, v in pairs(t1) do
        if t2[k] ~= v then
            return false
        end
    end

    --* Make sure t2 doesn’t have extra keys:
    for k, v in pairs(t2) do
        if t1[k] ~= v then
            return false
        end
    end

    return true
end

function Tables:tablesAreNotEqual(t1, t2)
    return not self:tablesAreEqual(t1, t2)
end

function Tables:normalizeTableIndex(index)
    return index and index:lower():gsub("[%p%s]+$", "")
end

return Tables
