
--* Alex: simplified version of ((GetText)): ignores language of interface, only yields private user translations, separate from global translations.
--* example initialisation:
--[[
local _ = KOR:initCustomTranslations()
]]

local io = io
local loadstring = loadstring
local pairs = pairs
local string = string
local table = table
local tonumber = tonumber

--- @class GetModuleText
local GetModuleText = {
    context = {},
    translation = {},
    textdomain = "koreader",
    plural_default = "n != 1",
}

local GetModuleText_mt = {
    __index = {}
}

-- wrapUntranslated() will be overriden by bidi.lua when UI language is RTL,
-- to wrap untranslated english strings as LTR-isolated segments.
-- It should do nothing when the UI language is LTR.
GetModuleText.wrapUntranslated_nowrap = function(text)
    return text
end
GetModuleText.wrapUntranslated = GetModuleText.wrapUntranslated_nowrap
-- Note: this won't be possible if we switch from our Lua GetModuleText to
-- GetModuleText through FFI (but hopefully, RTL languages will be fully
-- translated by then).

--[[--
Returns a translation.

@function gettext

@string msgid

@treturn string translation

@usage
    local _ = require("gettext")
    local translation = _("A meaningful message.")
--]]
function GetModuleText_mt.__call(gettext, msgid)
    return gettext.translation[msgid] and gettext.translation[msgid][0] or gettext.translation[msgid] or gettext.wrapUntranslated(msgid)
end

local function c_escape(what_full, what)
    if what == "\n" then
        return ""
    elseif what == "a" then
        return "\a"
    elseif what == "b" then
        return "\b"
    elseif what == "f" then
        return "\f"
    elseif what == "n" then
        return "\n"
    elseif what == "r" then
        return "\r"
    elseif what == "t" then
        return "\t"
    elseif what == "v" then
        return "\v"
    elseif what == "0" then
        return "\0" -- shouldn't happen, though
    else
        return what_full
    end
end

--- Converts C logical operators to Lua.
local function logicalCtoLua(logical_str)
    logical_str = logical_str:gsub("&&", "and")
    logical_str = logical_str:gsub("!=", "~=")
    logical_str = logical_str:gsub("||", "or")
    return logical_str
end

--- Default getPlural function.
local function getDefaultPlural(n)
    if n ~= 1 then
        return 1
    else
        return 0
    end
end

--- Generates a proper Lua function out of logical gettext math tests.
local function getPluralFunc(pl_tests, plural_default)
    -- the return function() stuff is a bit of loadstring trickery
    local plural_func_str = "return function(n) if "

    if #pl_tests > 1 then
        for i = 1, #pl_tests do
            local pl_test = pl_tests[i]
            pl_test = logicalCtoLua(pl_test)

            if i > 1 and tonumber(pl_test) == nil then
                pl_test = " elseif " .. pl_test
            end
            if tonumber(pl_test) ~= nil then
                -- no condition, just a number
                pl_test = " else return " .. pl_test
            end
            pl_test = pl_test:gsub("?", " then return")

            -- append to plural function
            plural_func_str = plural_func_str .. pl_test
        end
        plural_func_str = plural_func_str .. " end end"
    else
        local pl_test = pl_tests[1]
        -- Ensure JIT compiled function if we're dealing with one of the many simpler languages.
        -- After all, loadstring won't be.
        -- Potential workaround: write to file and use require.
        if pl_test == plural_default then
            return getDefaultPlural
        end
        -- language with no plural forms
        if tonumber(pl_test) ~= nil then
            plural_func_str = "return function(n) return " .. pl_test .. " end"
        else
            pl_test = logicalCtoLua(pl_test)
            plural_func_str = "return function(n) if " .. pl_test .. " then return 1 else return 0 end end"
        end
    end
    --logger.dbg("gettext: plural function", plural_func_str)
    return loadstring(plural_func_str)()
end

local function addTranslation(msgctxt, msgid, msgstr, n)
    -- translated string
    local unescaped_string = string.gsub(msgstr, "(\\(.))", c_escape)
    if msgctxt and msgctxt ~= "" then
        if not GetModuleText.context[msgctxt] then
            GetModuleText.context[msgctxt] = {}
        end
        if n then
            if not GetModuleText.context[msgctxt][msgid] then
                GetModuleText.context[msgctxt][msgid] = {}
            end
            GetModuleText.context[msgctxt][msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetModuleText.context[msgctxt][msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    else
        if n then
            if not GetModuleText.translation[msgid] then
                GetModuleText.translation[msgid] = {}
            end
            GetModuleText.translation[msgid][n] = unescaped_string ~= "" and unescaped_string or nil
        else
            GetModuleText.translation[msgid] = unescaped_string ~= "" and unescaped_string or nil
        end
    end
end

function GetModuleText_mt.__index.openTranslationsSource(file)
    local po = io.open(file, "r")

    if not po then
        return false
    end

    local data = {}
    local fuzzy = false
    local headers
    local what
    local n, msgstr, line, plural_forms, nplurals, plurals, pl_tests, w, s
    while true do
        line = po:read("*l")
        if line == nil or line == "" then
            if data.msgid and data.msgid_plural and data["msgstr[0]"] then
                for k, v in pairs(data) do
                    n = tonumber(k:match("msgstr%[([0-9]+)%]"))
                    msgstr = v

                    if n and msgstr then
                        addTranslation(data.msgctxt, data.msgid, msgstr, n)
                    end
                end
            elseif data.msgid and data.msgstr and data.msgstr ~= "" then
                -- header
                if not headers and data.msgid == "" then
                    headers = data.msgstr
                    plural_forms = data.msgstr:match("Plural%-Forms: (.*)")
                    nplurals = plural_forms:match("nplurals=([0-9]+);") or 2
                    plurals = plural_forms:match("plural=%((.*)%);")

                    -- Hardcoded workaround for Hebrew which has 4 plural forms.
                    if plurals == "n == 1) ? 0 : ((n == 2) ? 1 : ((n > 10 && n % 10 == 0) ? 2 : 3)" then
                        plurals = "n == 1 ? 0 : (n == 2) ? 1 : (n > 10 && n % 10 == 0) ? 2 : 3"
                    end
                    -- Hardcoded workaround for Latvian.
                    if plurals == "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19) ? 0 : ((n % 10 == 1 && n % 100 != 11) ? 1 : 2" then
                        plurals = "n % 10 == 0 || n % 100 >= 11 && n % 100 <= 19 ? 0 : (n % 10 == 1 && n % 100 != 11) ? 1 : 2"
                    end
                    -- Hardcoded workaround for Romanian which has 3 plural forms.
                    if plurals == "n == 1) ? 0 : ((n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2" then
                        plurals = "n == 1 ? 0 : (n == 0 || n != 1 && n % 100 >= 1 && n % 100 <= 19) ? 1 : 2"
                    end

                    if not plurals then
                        -- Some languages (e.g., Arabic) may not use parentheses.
                        -- However, the following more inclusive match is more likely
                        -- to accidentally include junk and seldom relevant.
                        -- We might also be dealing with a language without plurals.
                        -- That would look like `plural=0`.
                        plurals = plural_forms:match("plural=(.*);")
                    end

                    if plurals:find("[^n!=%%<>&:%(%)|?0-9 ]") then
                        -- we don't trust this input, go with default instead
                        plurals = GetModuleText.plural_default
                    end

                    pl_tests = {}
                    for pl_test in plurals:gmatch("[^:]+") do
                        table.insert(pl_tests, pl_test)
                    end

                    GetModuleText.getPlural = getPluralFunc(pl_tests, GetModuleText.plural_default)
                    if not GetModuleText.getPlural then
                        GetModuleText.getPlural = getDefaultPlural
                    end
                end

                addTranslation(data.msgctxt, data.msgid, data.msgstr)
            end
            -- stop at EOF:
            if line == nil then
                break
            end
            data = {}
            what = nil
        else
            -- comment
            if not line:match("^#") then
                -- new data item (msgid, msgstr, ...
                w, s = line:match("^%s*([%a_%[%]0-9]+)%s+\"(.*)\"%s*$")
                if w then
                    what = w
                else
                    -- string continuation
                    s = line:match("^%s*\"(.*)\"%s*$")
                end
                if what and s and not fuzzy then
                    -- unescape \n or msgid won't match
                    s = s:gsub("\\n", "\n")
                    -- unescape " or msgid won't match
                    s = s:gsub('\\"', '"')
                    -- unescape \\ or msgid won't match
                    s = s:gsub("\\\\", "\\")
                    data[what] = (data[what] or "") .. s
                elseif what and s == "" and fuzzy then
                    -- luacheck: ignore 542
                    -- Ignore the likes of msgid "" and msgstr ""
                else
                    -- Don't save this fuzzy string and unset fuzzy for the next one.
                    fuzzy = false
                end
            elseif line:match("#, fuzzy") then
                fuzzy = true
            end
        end
    end
    po:close()
end

-- for PO file syntax, see
-- https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html
-- we only implement a sane subset for now

GetModuleText_mt.__index.getPlural = getDefaultPlural

--[[--
Returns a plural form.

Many languages have more forms than just singular and plural. This function
abstracts the complexity away. The translation can contain as many
pluralizations as it requires.

See [gettext plural forms](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html)
and [translating plural forms](https://www.gnu.org/software/gettext/manual/html_node/Translating-plural-forms.html)
for more information.

It's required to pass along the number twice, because @{ngettext}() doesn't do anything with placeholders.
See @{ffi.util.template}() for more information about the template function.

@function ngettext

@string msgid
@string msgid_plural
@int n

@treturn string translation

@usage
    local _ = require("gettext")
    local N_ = _.ngettext
    local T = require("ffi/util").template

    local items_string = T(N_("1 item", "%1 items", num_items), num_items)
--]]
function GetModuleText_mt.__index.ngettext(msgid, msgid_plural, n)
    local plural = GetModuleText.getPlural(n)

    if plural == 0 then
        return GetModuleText.translation[msgid] and GetModuleText.translation[msgid][plural] or GetModuleText.wrapUntranslated(msgid)
    else
        return GetModuleText.translation[msgid] and GetModuleText.translation[msgid][plural] or GetModuleText.wrapUntranslated(msgid_plural)
    end
end

--[[--
Returns a context-disambiguated plural form.

This is the logical combination between @{ngettext}() and @{pgettext}().
Please refer there for more information.

@function npgettext

@string msgctxt
@string msgid
@string msgid_plural
@int n

@treturn string translation

@usage
    local _ = require("gettext")
    local NC_ = _.npgettext
    local T = require("ffi/util").template

    local statistics_items_string = T(NC_("Statistics", "1 item", "%1 items", num_items), num_items)
    local books_items_string = T(NC_("Books", "1 item", "%1 items", num_items), num_items)
--]]
function GetModuleText_mt.__index.npgettext(msgctxt, msgid, msgid_plural, n)
    local plural = GetModuleText.getPlural(n)

    if plural == 0 then
        return GetModuleText.context[msgctxt] and GetModuleText.context[msgctxt][msgid] and GetModuleText.context[msgctxt][msgid][plural] or GetModuleText.wrapUntranslated(msgid)
    else
        return GetModuleText.context[msgctxt] and GetModuleText.context[msgctxt][msgid] and GetModuleText.context[msgctxt][msgid][plural] or GetModuleText.wrapUntranslated(msgid_plural)
    end
end

--[[--
Returns a context-disambiguated translation.

The same string might occur multiple times, but require a different translation based on context.
An example within KOReader is **Pages** meaning *page styles* (within the context of style tweaks)
and **Pages** meaning *number of pages*.

We generally don't apply context unless a conflict is known. This is only likely to occur with
short strings, of which of course there are many.

See [gettext contexts](https://www.gnu.org/software/gettext/manual/html_node/Contexts.html) for more information.

@function pgettext

@string msgctxt
@string msgid

@treturn string translation

@usage
    local _ = require("gettext")
    local C_ = _.pgettext

    local copy_file = C_("File", "Copy")
    local copy_text = C_("Text", "Copy")
--]]
function GetModuleText_mt.__index.pgettext(msgctxt, msgid)
    return GetModuleText.context[msgctxt] and GetModuleText.context[msgctxt][msgid] or GetModuleText.wrapUntranslated(msgid)
end

setmetatable(GetModuleText, GetModuleText_mt)

return GetModuleText
