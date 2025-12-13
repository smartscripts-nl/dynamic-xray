
local require = require

local DocSettings = require("docsettings")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local KOR = require("extensions/kor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen

local DX = DX
local G_reader_settings = G_reader_settings
local last_file = last_file

--- @class ScreenHelpers
local ScreenHelpers = WidgetContainer:extend{}

function ScreenHelpers:autoRotate(full_path, rotate_callback)

    if not full_path then
        full_path = last_file()
    end

    local debug = true
    local rotate_on_this_device = debug or DX.s.is_android
    if not rotate_on_this_device or not full_path then
        return
    end

    local doc_settings = DocSettings:open(full_path)
    local rotation_mode = doc_settings:readSetting("copt_rotation_mode")

    if rotation_mode ~= Screen:getRotationMode() then
        KOR.registry:set("skip_partial_rerendering", true)
        -- rotate_callback e.g. defined in ((DynamicRefreshControl#forceOrientation)):
        rotate_callback(rotation_mode)
    end
end

function ScreenHelpers:screenOrientationHasChanged()
    local previous_orientation = KOR.registry:get("previous_orientation")
    local current_orientation = self:getOrientation()
    return previous_orientation and previous_orientation ~= current_orientation, current_orientation
end

function ScreenHelpers:toggleDisplayMode(overrule_mode)
    -- overrule_mode can be set from ((UIManager#forceMainReaderScreenBackToNightDisplay)), but can also be nil, in which case it is inert:
    KOR.registry:set("force_display_mode", overrule_mode)
    -- call ((DeviceListener#onToggleNightMode)):
    KOR.ui:handleEvent(Event:new("ToggleNightMode"))
end

function ScreenHelpers:forceToDayDisplay()
    local night_mode_active = G_reader_settings:isTrue("night_mode")
    if night_mode_active then
        self:toggleDisplayMode()
    end
end

function ScreenHelpers:forceToNightDisplay(overrule)
    local day_mode_active = G_reader_settings:isFalse("night_mode")
    if day_mode_active or overrule then
        self:toggleDisplayMode(overrule)
    end
end

function ScreenHelpers:getOrientation()
    return Screen:getScreenOrientation()
end

function ScreenHelpers:isLandscapeScreen()
    return Screen:getScreenMode() == "landscape"
end

function ScreenHelpers:isPortraitScreen()
    return Screen:getScreenMode() == "portrait"
end

function ScreenHelpers:refreshDialog()
    -- refresh dialog, so e.g. no shadows of dialog lines remain:
    UIManager:setDirty(nil, "ui")
end

function ScreenHelpers:refreshScreen()
    -- refresh the screen, so e.g. no shadows of dialog lines remain:
    UIManager:setDirty(nil, "full")
end

function ScreenHelpers:refreshScreenFlash()
    -- refresh the screen with a flash, so e.g. no image shadows remain:
    UIManager:setDirty(nil, "flashui")
end

-- same as ScreenHelpers:refreshScreen(), but without flash:
function ScreenHelpers:refreshUI()
    UIManager:setDirty(nil, function()
        return "ui", Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
    end)
end

-- see ((ANDROID_ON_SCREEN_RESIZE)) for more info:
function ScreenHelpers:hasScreenSizeChanged(orientation, current_dims)
    local device_dims
    if orientation == "landscape" then
        device_dims = KOR.registry:get("device_landscape_dims")
        if not device_dims then
            device_dims = Screen:getSize()
            KOR.registry:set("device_landscape_dims", device_dims)
        end
    else
        device_dims = KOR.registry:get("device_portrait_dims")
        if not device_dims then
            device_dims = Screen:getSize()
            KOR.registry:set("device_portrait_dims", device_dims)
        end
    end

    return device_dims.w ~= current_dims.w, device_dims
end

-- called from ((Tracker#getPageloadMessage)); see ((ANDROID_ON_SCREEN_RESIZE)) for more info:
function ScreenHelpers:detectScreenSizeChangedAfterResume(orientation)
    local current_dims = Screen:getSize()
    if self:hasScreenSizeChanged(orientation, current_dims) then
        KOR.registry:set("update_screen_size", true)
        return true
    end
    return false
end

-- called from ((Tracker#onReaderReady)); see ((ANDROID_ON_SCREEN_RESIZE)) for more info:
function ScreenHelpers:storeScreenSize(orientation)

    local current_dims = Screen:getSize()
    if orientation == "landscape" then
        KOR.registry:set("device_landscape_dims", current_dims)
        KOR.registry:set("device_portrait_dims", {
            w = current_dims.h,
            h = current_dims.w,
        })
    else
        KOR.registry:set("device_portrait_dims", current_dims)
        KOR.registry:set("device_landscape_dims", {
            w = current_dims.h,
            h = current_dims.w,
        })
    end
end

--* incorrect night_mode after resume probably caused onSuspend by ((UIManager#forceMainReaderScreenBackToNightDisplay)):
function ScreenHelpers:restoreNightOrDayModeAfterResume()
    --* set in ((ReaderUI#showReaderCoroutine)), upon KOReader start, or in ((DeviceListener#onToggleNightMode)) after gesture:
    local main_night_mode = KOR.registry:get("main_night_mode_mode")
    if main_night_mode ~= nil and G_reader_settings:readSetting("night_mode") ~= main_night_mode then
        -- calls ((framebuffer.lua#toggleNightMode))
        -- Screen is an alias for Device.screen:
        Screen:toggleNightMode(main_night_mode)
        G_reader_settings:saveSetting("night_mode", main_night_mode)
        --* to get rid of white footer in case night mode was enabled and has just been restored:
        KOR.pagejumper:refreshPage()
    end
end

-- called from ((Tracker#onReaderReady)); see ((ANDROID_ON_SCREEN_RESIZE)) for more info:
function ScreenHelpers:restoreScreenSize(orientation, force_resize)
    if not orientation then
        orientation = self:getOrientation()
    end

    local current_dims = Screen:getSize()

    --- AFTER RESIZE DETECTED:

    -- this prop set in ((Tracker#getPageloadMessage)) > ((detect screen resize upon resume)) > ((ScreenHelpers#detectScreenSizeChangedAfterResume)):
    if force_resize or KOR.registry:getOnce("update_screen_size") then
        UIManager:scheduleIn(1.5, function()

            local screen_size_was_changed, device_dims = self:hasScreenSizeChanged(orientation, current_dims)

            if screen_size_was_changed then
                UIManager:setDirty(self.dialog, "full")
                KOR.ui:handleEvent(Event:new("SetDimensions", device_dims))
                KOR.ui:onScreenResize(device_dims)
                if KOR.ui.document.info.has_pages then
                    KOR.paging:onInitScrollPageStates()
                end
            end
        end)
    end
end

--* compare preparation in ((ReaderUI#showReaderCoroutine)):
--! see ((AUTO_ROTATION_FOR_BOOX_GO_10)):
function ScreenHelpers:forceBooxGo10Orientation()
    if DX.s.is_tablet_device then
        --! on Boox Go 10.3 we want device orientation 0 (DEVICE_ROTATED_UPRIGHT) with orientation "landscape":
        if Screen:getRotationMode() ~= 0 then
            Screen:setRotationMode(0)
        end
        --[[if Screen:getScreenOrientation() ~= "landscape" then
            KOR.view:onSetRotationMode("landscape")
        end]]

        local orientation = Screen:getScreenOrientation()
        if orientation ~= "landscape" then
            UIManager:nextTick(function()
                KOR.view:onSetRotationMode("landscape")
            end)
        end
    end
end

--* see also ((DynamicRefreshControl#onReaderReady)), where this method is used to prevent call of ((DynamicRefreshControl#forceOrientation)):
function ScreenHelpers:hasLockedRotation()
    --* for Boox Go 10.3, Bigme and Ubuntu we don't want any rotation:
    return DX.s.is_tablet_device
        or DX.s.is_mobile_device
        or DX.s.is_ubuntu
        or G_reader_settings:isTrue("lock_rotation")
end

return ScreenHelpers
