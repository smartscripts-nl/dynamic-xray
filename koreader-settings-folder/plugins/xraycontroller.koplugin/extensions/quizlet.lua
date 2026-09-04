
local require = require

local Input = require("modules/input")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = KOR:initCustomTranslations()

local DX = DX
local T = T

--- @class Quizlet
local Quizlet = WidgetContainer:new{
    key_events = {
        ViewPreviousQuizlet = { { Input.group.PgBack }, doc = "show previous Quizlet question" },
        ViewPreviousQuizletWithShiftSpace = Input.group.ShiftSpace,
        ViewNextQuizlet = { { Input.group.PgFwd }, doc = "show next Quizlet question" },
    },
    --* set from ((XrayButtons#forQuizletQuestions)):
    quizlet_answer = nil,
    quizlet_current_question = 1,
    quizlet_dialog = nil,
    quizlet_items = nil,
    quizlet_show_answers_also = false,
}

function Quizlet:initQuizletQuestions()

    self.quizlet_items = KOR.tables:randomize(DX.vd.items)
    self.quizlet_current_question = 1
    KOR.registry:unset("maintain_overlay")
end

--- @private
function Quizlet:showQuizletQuestion()

    local item = self.quizlet_items[self.quizlet_current_question]
    local dialog_queue_id = "quizlet_question"
    KOR.dialogsqueue:register({
        id = dialog_queue_id,
        restore = function()
            self:showQuizletQuestion()
        end
    })

    local info = self.quizlet_show_answers_also and item.name .. "\n_______________________________\n\n" .. item.description .. "\n" or item.name .. "  =  ?"

    self:initHotkeys()
    KOR.dialogs:showOverlay()
    KOR.registry:set("maintain_overlay", true)
    self.quizlet_dialog = KOR.dialogs:niceAlert(T(_ ("Quizlet-question, %1 of %2"), self.quizlet_current_question, #self.quizlet_items), info, {
        modal = true,
        dialog_queue_id = dialog_queue_id,
        dismissable = true,
        with_close_button = true,
        top_buttons_left = DX.b:forQuizletQuestionsTopLeft(self),
        close_callback = function()
            self:closeQuizletQuestion()
            return true
        end,
        tap_close_callback = function()
            self:closeQuizletQuestion("reset_all_rprops")
        end,
        buttons = DX.b:forQuizletQuestions(self, item)
    })
end

function Quizlet:closeQuizletQuestion(reset_all_rprops)
    if reset_all_rprops then
        self:resetRegistryProps()
    else
        KOR.registry:unset("maintain_overlay")
    end
    KOR.dialogs:closeOverlay()
    UIManager:close(self.quizlet_dialog)
    self.quizlet_dialog = nil
end

function Quizlet:resetRegistryProps()
    KOR.registry:unset("maintain_overlay", "add_parent_hotkeys")
end

--- @private
function Quizlet:initHotkeys()
    local actions = {
        ViewPreviousQuizlet = {
            { { Input.group.PgBack } },
            function()
                return self:onViewPreviousQuizlet()
            end },
        ViewPreviousQuizletWithShiftSpace = {
            Input.group.ShiftSpace,
            function()
                return self:onViewPreviousQuizlet()
            end },
        ViewNextQuizlet = {
            { { Input.group.PgFwd } },
            function()
                return self:onViewNextQuizlet()
            end },
    }

    --! this ensures that hotkeys will be available in ((TextBoxWidget#initHotkeys)):
    KOR.registry:set("add_parent_hotkeys", actions)
end

function Quizlet:viewAnswer(item)
    UIManager:close(self.quizlet_dialog)
    local dialog_queue_id = "quizlet_answer"
    KOR.dialogsqueue:register({
        id = dialog_queue_id,
        restore = function()
            self:showQuizletQuestion()
        end
    })
    self.quizlet_answer = KOR.dialogs:niceAlert(item.name, item.description, {
        modal = true,
        top_buttons_left = {},
        dialog_queue_id = dialog_queue_id,
        with_close_button = true,
        close_callback = function()
            KOR.registry:unset("maintain_overlay")
            KOR.dialogs:closeOverlay()
            UIManager:close(self.quizlet_answer)
            UIManager:close(self.quizlet_answer)
            return true
        end,
        tap_close_callback = function()
            KOR.registry:unset("maintain_overlay")
            KOR.dialogs:closeOverlay()
        end,
    })
end

function Quizlet:onViewNextQuizlet()
    self.quizlet_current_question = self.quizlet_current_question + 1
    if self.quizlet_current_question > #self.quizlet_items then
        self.quizlet_current_question = 1
    end
    UIManager:close(self.quizlet_dialog)
    self:showQuizletQuestion()
    return true
end

function Quizlet:onViewPreviousQuizlet()
    self.quizlet_current_question = self.quizlet_current_question - 1
    if self.quizlet_current_question < 1 then
        self.quizlet_current_question = #self.quizlet_items
    end
    UIManager:close(self.quizlet_dialog)
    self:showQuizletQuestion()
    return true
end

function Quizlet:onViewPreviousQuizletWithShiftSpace()
    return self:onViewPreviousQuizlet()
end

return Quizlet
