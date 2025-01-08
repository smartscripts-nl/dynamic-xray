
local DataStorage = require("datastorage")
-- ! don't use Dialogs here!
local Registry = require("extensions/registry")
local SQ3 = require("lua-ljsqlite3/init")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--- @class Databases
local Databases = WidgetContainer:extend{}

function Databases:closeConnections(conn, conn2)
    if conn and not conn._closed then
        conn:close()
    end
    if conn2 and not conn2._closed then
        conn2:close()
    end
    Registry:unset("db_conn")
    return nil, nil
end

function Databases:closeStmts(stmt, stmt2, stmt3, stmt4)
    if stmt then
        stmt:clearbind():reset():close()
    end
    if stmt2 then
        stmt2:clearbind():reset():close()
    end
    if stmt3 then
        stmt3:clearbind():reset():close()
    end
    if stmt4 then
        stmt4:clearbind():reset():close()
    end
    return nil, nil, nil, nil
end

function Databases:closeInfoConnections(conn)
    if conn and not conn._closed then
        conn:close()
    end
    Registry:unset("db_conn_info")
    return nil
end

function Databases:closeInfoStmts(stmt, stmt2, stmt3, stmt4)
    if stmt then
        stmt:clearbind():reset():close()
    end
    if stmt2 then
        stmt2:clearbind():reset():close()
    end
    if stmt3 then
        stmt3:clearbind():reset():close()
    end
    if stmt4 then
        stmt4:clearbind():reset():close()
    end
    return nil, nil, nil, nil
end

function Databases:getDBconnForBookInfo()
    local external_conn = Registry:get("db_conn_info")
    if external_conn then
        return external_conn
    end

    return SQ3.open(DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3")
end

function Databases:getDBconnForStatistics()
    local external_conn = Registry:get("db_conn")
    if external_conn then
        return external_conn
    end

    return SQ3.open(DataStorage:getSettingsDir()
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
