
local DataStorage = require("datastorage")
-- ! don't use Dialogs here!
local Registry = require("extensions/registry")
local SQ3 = require("lua-ljsqlite3/init")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class Databases
local Databases = WidgetContainer:extend{
    settings_folder = nil,
}

function Databases:closeConnections(conn, ...)
    if conn and not conn._closed then
        conn:close()
        conn = nil
    end
    for _, iconn in ipairs({ ... }) do
        iconn:close()
        iconn = nil
    end
    Registry:unset("db_conn")
    -- return nil, nil etc.
end

function Databases:closeStmts(stmt, ...)
    if stmt then
        stmt:clearbind():reset():close()
        stmt = nil
    end
    for _, istmt in ipairs({ ... }) do
        istmt:clearbind():reset():close()
        istmt = nil
    end
    -- return nil, nil etc.
end

function Databases:closeInfoConnections(conn)
    if conn and not conn._closed then
        conn:close()
        conn = nil
    end
    Registry:unset("db_conn_info")
    return nil
end

function Databases:closeInfoStmts(stmt, ...)
    if stmt then
        stmt:clearbind():reset():close()
        stmt = nil
    end
    for _, istmt in ipairs({ ... }) do
        istmt:clearbind():reset():close()
        istmt = nil
    end
    -- return nil, nil, nil, nil etc.
end

function Databases:getDBconnForBookInfo()
    local external_conn = Registry:get("db_conn_info")
    if external_conn then
        return external_conn
    end

    self.settings_folder = self.settings_folder or DataStorage:getSettingsDir()
    return SQ3.open(self.settings_folder .. "/bookinfo_cache.sqlite3")
end

function Databases:getDBconnForStatistics()
    local external_conn = Registry:get("db_conn")
    if external_conn then
        return external_conn
    end

    self.settings_folder = self.settings_folder or DataStorage:getSettingsDir()
    return SQ3.open(self.settings_folder
    .. "/statistics.sqlite3")
end

function Databases:escape(parameter)
    -- don't remove this conditional block, otherwise errors when trying to get statistics id of an ebook:
    if not parameter:match("'") then
        return parameter
    end
    return parameter:gsub("'", "''")
end

-- inject filename with apostrophs escaped. Presupposes a query in this format: UPDATE ... WHERE path = 'safe_path'
-- e.g. to prevent errors because of Wallabag filenames with apostrophs:
function Databases:injectSafePath(sql_stmt, path)
    return sql_stmt:gsub("safe_path", self:escape(path))
end

return Databases
