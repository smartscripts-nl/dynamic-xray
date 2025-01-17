
local Tables = require("extensions/tables")
local Utf8Proc = require("ffi/utf8proc")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

--- accented characters:
--- ÄËÏÖÜ äëïöü ÁÉÍÓÚ áéíóú ÀÈÌÒÙ àèìòù Çç
--- n-dash –

--- @class Strings
local Strings = WidgetContainer:extend{
	curly_apo_l = "‘",
	curly_apo_r = "’",
	curly_quote_l = "“",
	curly_quote_r = "”",
}

function Strings:cleanup(text)
	if not text then
		return
	end
	-- don't cleanup hyphen, so don't use %p (stands for punctuation), because that also removed hyphens, which are important to keep for dictionary lookups:
	return text:gsub("[”“‘’\"'—.,:;!¡?¿<>]", "")
end

function Strings:getKeywordsForMatchingFrom(subject, no_lower_case, add_singulars)
	if not subject then
		return {}
	end
	-- prevent problems with special characters:
	subject = self:cleanup(subject)
	if not no_lower_case then
		subject = subject:lower()
	end
	if #subject < 3 then
		return {}
	end
	local keywords = self:split(subject, " ", false)
	local singulars = {}
	for nr, keyword in ipairs(keywords) do
		keyword = keyword:gsub("%-", "%%-"):gsub("%.", "%%.")
		if add_singulars and keyword:match("s$") then
			local singular = keyword:gsub("s$", "")
			table.insert(singulars, singular)
		end
		keywords[nr] = keyword
	end
	if add_singulars and #singulars > 0 then
		for nr in ipairs(singulars) do
			table.insert(keywords, singulars[nr])
		end
	end
	return Tables:filter(keywords, function(keyword)
		return #keyword > 2 and keyword ~= "the"
	end)
end

-- keywords were obtained with ((Strings#getKeywordsForMatchingFrom)):
function Strings:hasUnmodifiedMatch(keywords, haystack, allow_fuzzy)
	if not haystack or not keywords or #keywords == 0 then
		return false
	end
	haystack = self:cleanup(haystack)
	local hits_count = 0
	for _, s in ipairs(keywords) do
		hits_count = hits_count + (haystack:match(s) and 1 or 0)
	end
	-- only for check of required hits, not used in the search itself:
	-- #self:getKeywordsForMatchingFrom(haystack): correction for when defined names have 2 parts, but selected text only contains one word:
	local need_to_find = math.min(#keywords, #self:getKeywordsForMatchingFrom(haystack, "no_lower_case"))
	return allow_fuzzy and hits_count > 0 or hits_count == need_to_find, hits_count
end

function Strings:htmlToPlainTextIfHtml(text)
	return util.htmlToPlainTextIfHtml(text)
end

function Strings:limitLength(text, max_length)
	if text and text:len() > max_length then
		text = text:sub(1, max_length - 3) .. "..."
	end
	return text
end

function Strings:removeNotes(text)
	-- remove (foot)note markings in text:
	-- double colon excluded, because otherwise clock hours destroyed:
	-- exclude h, so we don't damage html headings:
	text = text:gsub("([a-g,i-z?!;)])[0-9]+", "%1")
	text = text:gsub("([a-zA-Z][.,])[0-9]+([ \n\r])", "%1%2")
	text = text:gsub("%.[0-9]+$", "")
	text = text:gsub("(”%.?)[0-9]+", "%1")

	return text:gsub(" ?%*", ""):gsub(" ?%†", ""):gsub(" ?%‡", "")
end

-- count is meant for loops: only on first loop convert strings to singular:
function Strings:singular(text, count)
	if count == 1 then
		-- third substitution: personen -> persoon, fourth: boeken -> boek:
		return text:gsub("’s$", ""):gsub("s$", ""):gsub("onen$", "oon"):gsub("ken$", "k")
	end
	return text
end

function Strings:split(str, pat, capture_empty_entity)
	return util.splitToArray(str, pat, capture_empty_entity)
end

function Strings:substrCount(subject, needle)
	-- select() selects the indexed item of multiple vars returned:
	return select(2, subject:gsub(needle, ""))
end

-- only return ucfirst variant of string if it not contains uppercase characters:
function Strings:lcfirst(str, force_only_first)
	-- %u matches upper case characters:
	return (force_only_first and Utf8Proc.lowercase(util.fixUtf8(str, "?")) or str:gsub("^%u", string.lower))
end

-- only return ucfirst variant of string if it not contains uppercase characters:
function Strings:ucfirst(str, force_only_first)
	-- %l matches lower case characters:
	return (force_only_first and str:sub(1, 1):upper() .. Utf8Proc.lowercase(util.fixUtf8(str:sub(2), "?")) or str:gsub("^%l", string.upper))
end

-- return utf8-safe lowercase string:
function Strings:lower(text)
	return Utf8Proc.lowercase_dumb(util.fixUtf8(text, "?"))
end

-- return utf8-safe uppercase string:
function Strings:upper(text)
	return Utf8Proc.uppercase_dumb(util.fixUtf8(text, "?"))
end

function Strings:formatListItemNumber(nr, title, use_spacer)
	local spacer = ""
	if use_spacer then
		if nr < 10 then
			spacer = "    "
		elseif nr < 100 then
			spacer = "  "
		end
	end
	return nr .. ". " .. spacer .. self:removeListItemNumber(title)
end

function Strings:removeListItemNumber(text)
	if not text then
		return
	end
	if type(text) == "table" and text.text then
		text = text.text
	end
	return text:gsub("^[0-9]+[.][ ]*", "")
end

function Strings:splitLinesToMaxLength(text, max_length, indent, first_word)
	if not has_text(text) then
		return ""
	end
	if has_text(first_word) then
		text = first_word .. text
	end
	local test = text
	if indent then
		test = indent .. text
	end
	if test:len() <= max_length then
		return test
	end
	local words = self:split(text, " ")
	local lined_text = { "" }
	local index = 1
	for _, word in ipairs(words) do
		local for_next_line, for_previous_line
		if word:match("\n") then
			local parts = self:split(word, "\n")
			for_previous_line = parts[1]
			for_next_line = parts[2]
			test = lined_text[index] .. for_previous_line
		else
			test = lined_text[index] .. word
		end
		if test:len() < max_length then
			lined_text[index] = test .. " "
			if for_next_line then
				index = index + 1
				table.insert(lined_text, for_next_line .. " ")
			end
		else
			index = index + 1
			if for_previous_line then
				table.insert(lined_text, for_previous_line)
				index = index + 1
			end
			local insert = for_previous_line or word
			table.insert(lined_text, insert .. " ")
		end
	end

	for i = 1, #lined_text do
		if indent then
		lined_text[i] = indent .. lined_text[i]
		end
		lined_text[i] = lined_text[i]:gsub(" $", "")
	end
	return table.concat(lined_text, "\n")
end

function Strings:wholeWordMatch(haystack, haystack_lower, needle, case_sensitive)

	local case_insensitive = not case_sensitive
	if case_insensitive then
		needle = self:lower(needle)
		return haystack_lower:match(needle)
		and (
		-- e.g. matches for Xray items after cleaning of paragraph texts in ((CreDocument#paragraphCleanForXrayMatching)):
		haystack_lower:match(" " .. needle .. " ")
		or
		(not haystack_lower:match("%l" .. needle) and not haystack_lower:match(needle .. "%l"))
		)
	end

	-- case sensitive:
	return haystack:match(needle)
	and (
	haystack:match(" " .. needle .. " ")
	or
	(not haystack:match("%l" .. needle) and not haystack:match(needle .. "%l"))
	)
end

return Strings
