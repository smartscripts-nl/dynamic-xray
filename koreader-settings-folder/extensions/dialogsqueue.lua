
local require = require

local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local os_time = os.time
local table_insert = table.insert
local table_remove = table.remove

local count

--- @class DialogsQueue
local DialogsQueue = WidgetContainer:extend{
    dialog_ids = {},
    hold_action_alert_shown = false,
    last_id = nil,
    last_register_time = nil,
    queue = {},
}

function DialogsQueue:getFirstDialogDescription()
    return self.queue[1].id:gsub("_", " ")
end

function DialogsQueue:getLastId()
    --* this way we can filter out dialogs which didn't register themselves via a call to ((DialogsQueue#register)):
    if self.last_register_time and os_time() - self.last_register_time > 1 then
        return
    end
    count = #self.queue
    if count == 0 then
        return
    end
    return self.queue[count].id
end

function DialogsQueue:getParentId()
    return #self.queue > 1 and self.queue[#self.queue - 1]
end

function DialogsQueue:getQueueCount()
    return #self.queue
end

--* queue_props is a table containing an id and a "restore" method to return to the previous dialog:
function DialogsQueue:register(queue_props)
    self.last_register_time = os_time()

    --* no repositioning needed if the entry is already the last entry:
    if queue_props.id == self.last_id then
        return
    end

    --! change position of already registered dialogs! (by removing the previous entry and then re-registering):
    if self.dialog_ids[queue_props.id] then
        self:unregister(queue_props.id)
    end
    table_insert(self.queue, queue_props)
    self.dialog_ids[queue_props.id] = true
    self.last_id = queue_props.id

    --* sometimes previous dialogs are not closed; with this statement we fix that:
    KOR.dialogs:closeAllWidgets()
end

function DialogsQueue:reset()
    self.last_register_time = nil
    self.dialog_ids = {}
    self.queue = {}
end

--* closing the current dialog has been done by the caller; now check whether there was a previous dialog to restore:
function DialogsQueue:restorePrevious(id)
    count = #self.queue
    if count == 0 or self.queue[count].id ~= id then
        return false
    end

    --* no previous dialogs, so reset queue:
    if count == 1 then
        self:reset()
        return true
    end

    --* remove the current dialog from the queue:
    self.dialog_ids[id] = nil
    table_remove(self.queue)

    --* restore the previous dialog:
    self.queue[count - 1].restore()

    if not self.hold_action_alert_shown and not DX.s.no_back_to_previous_dialog_notification then
        KOR.dialogs:niceAlert(_("For your information"), _("You have used the button for returning to a previous dialog.\n\nWhen you longpress this button, you'll be presented a dialog from which you can jump to the very first opened dialog in the dialog history.\n\nThis notifcation will be displayed once per KOReader session, unless you disable it forever with the below button" .. KOR.strings.ellipsis), {
            buttons = {{
                {
                    text = _("disable message") .. KOR.strings.ellipsis,
                    callback = function()
                        DX.s:saveSetting("no_back_to_previous_dialog_notification", true)
                        UIManager:close(self.navigation_help_info)
                        KOR.messages:notify(_("message disabled"))
                    end,
                }
            }},
        })
        self.hold_action_alert_shown = true
    end

    return true
end

function DialogsQueue:returnToFirstDialog()
    if #self.queue == 0 then
        return
    end
    --* we want to exec this restore callback only after the dialogs queue has been reset; otherwise back button would be incorrectly shown in the titlebar:
    local restore = KOR.tables:shallowCopy(self.queue[1].restore)
    self.queue = {
        self.queue[1]
    }
    self.dialog_ids = {
        [self.queue[1].id] = true
    }
    self.last_id = self.queue[1].id
    restore()
end

--- @private
function DialogsQueue:unregister(id)
    local pruned = {}
    self.dialog_ids[id] = nil
    count = #self.queue
    for i = 1, count do
        if self.queue[i].id ~= id then
            table_insert(pruned, self.queue[i])
        end
    end
    self.queue = pruned
end

return DialogsQueue
