
local require = require

local DataStorage = require("datastorage")
--! don't use KOR.dialogs here!
local KOR = require("extensions/kor")
local SQ3 = require("lua-ljsqlite3/init")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local pairs = pairs
local table = table
local tonumber = tonumber
local type = type

--- @class Databases
local Databases = WidgetContainer:extend{
    --* ONLY FOR REPOSITORY-version of DX; this will be the default database filename for most users, but in case of a differing name, e.g. PT_bookinfo_cache.sqlite3, that name can be made known to DX via the XraySettings setting database_filename and ((XrayModel#setDatabaseFile)) > ((Databases#setDatabaseFileName)):
    database_filename = "bookinfo_cache.sqlite3",
    database_folder = nil,
    home_dir = nil,
    home_dir_needle = nil,
}

function Databases:setDatabaseFileName(database_filename)
    self.database_filename = database_filename
end

function Databases:closeConnAndStmt(conn, stmt)
    self:closeInfoStmts(stmt)
    self:closeInfoConnections(conn)
    return nil, nil
end

function Databases:closeInfoConnections(conn)
    if conn and not conn._closed then
        conn:close()
        conn = nil
    end
    KOR.registry:unset("db_conn_info")
    return nil
end

function Databases:closeInfoStmts(stmt, ...)
    if stmt then
        stmt:clearbind():reset():close()
        stmt = nil
    end
    local args = { ... }
    local istmt
    local count = #args
    for i = 1, count do
        istmt = args[i]
        istmt:clearbind():reset():close()
        istmt = nil
    end
    --* return nil, nil, nil, nil etc.
end

function Databases:_getConn()
    self.database_folder = self.database_folder or DataStorage:getSettingsDir()
    return SQ3.open(self.database_folder .. "/" .. self.database_filename)
end

function Databases:getDBconnForBookInfo()
    local keep_open_conn = KOR.registry:get("db_conn_info")
    if keep_open_conn then
        if not keep_open_conn._closed then
            return keep_open_conn, true
        else
            local conn = self:_getConn()
            KOR.registry:set("db_conn_info", conn)
            return conn, true
        end
    end

    return self:_getConn(), false
end

function Databases:getNewItemId(conn)
    return tonumber(conn:rowexec("SELECT last_insert_rowid()"))
end

function Databases:escape(parameter)
    if not parameter then
        return parameter
    end
    --! don't remove this conditional block, otherwise errors when trying to get statistics id of an ebook:
    if not parameter:match("'") then
        return parameter
    end
    return parameter:gsub("'", "''")
end

function Databases:unescape(field_content)
    if type(field_content) ~= "string" then
        return field_content
    end
    return field_content:gsub("''+", "'")
end

--* inject filename with apostrophs escaped. Presupposes a query in this format: UPDATE ... WHERE path = 'safe_path'
--* to prevent errors because of
--* Wallabag filenames with apostrophs:
function Databases:injectSafePath(sql, path)
    return sql:gsub("safe_path", self:escape(path))
end

function Databases:resultsetToItemset(resultset)
    local field_names = {}
    for field_name in pairs(resultset) do
        if type(field_name) ~= "number" then
            table.insert(field_names, field_name)
        end
    end
    table.sort(field_names)
    local row, field
    local itemset = {}
    local rows = #resultset[1]
    local fields_count = #field_names
    for r = 1, rows do
        row = {}
        for f = 1, fields_count do
            field = field_names[f]
            row[field] = resultset[field][r]
        end
        table.insert(itemset, row)
    end
    return itemset
end

return Databases
