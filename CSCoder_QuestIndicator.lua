-- CS.Coder - Quest Indicator
-- A floating quest "!" above the nameplate of every mob you still need for an active quest,
-- and over the nearest quest object in front of you (herbs, sprouts, crates...).
--
-- Settings: Options > AddOns > CS.Coder > Quest Indicator, the minimap button, or /cqi.
-- Nameplates must be on (V) for the mob icons.

local ADDON, ns = ...
local TITLE = "CS.Coder - Quest Indicator"
local PARENT_NAME = "CS.Coder"
local SUBTITLE = "Quest Indicator"

-- Per-profile settings.
local DEFAULTS = {
	active = true,       -- master switch: the whole addon on or off
	enabled = true,      -- icons over quest mobs
	objects = true,      -- icon over the soft-targeted quest object in the world
	style = "standard/classic_gold", -- icon style: "category/name" (file in icons\)
	scale = 1.5,         -- mob icon size
	offsetX = 0,         -- mob icon X
	offset = -15,        -- mob icon Y (above the nameplate)
	anchor = "top",      -- mob icon side of the nameplate: "top", "bottom", "left", "right"
	objectAnchor = "top", -- object icon side of its nameplate
	objectScale = 1.5,   -- object icon size
	objectOffsetX = 0,   -- object icon X
	objectOffset = 10,   -- object icon Y (above the object)
	progress = true,     -- objective count ("8/12") on quest mobs
	objectProgress = true, -- the same count on the quest item icon
	progressAttach = true, -- true: X/Y from the icon (follows it); false: X/Y from the nameplate
	progressFloat = true,  -- bobs up and down with the icon (when the icon floats)
	progressSize = 13,   -- its font size
	progressFont = "friz",     -- key in TEXT_FONTS
	progressOutline = "thin",  -- "none", "thin", "thick"
	progressColor = "white",   -- "white", "gold", "green", "kind" (same colour as the icon) or "progress" (red to green)
	progressFormat = "slash",  -- "slash" 8/12, "spaced" 8 / 12, "both" 8/12 (67%), "percent" 67%, "left" 4 left
	progressShadow = false,   -- drop shadow behind the text
	progressPulse = true,     -- the count pulses when it goes up and turns gold with one left
	progressX = 36,      -- its X
	progressY = 0,       -- its Y
	bounce = true,       -- floating up/down animation
	bounceHeight = 7,    -- how far it floats (pixels)
	bounceSpeed = 0.9,   -- seconds for one move up (lower = faster)
	glow = false,        -- glowing star behind the icon
	glowAlpha = 0.55,    -- glow intensity
	objectOwnLook = false, -- quest items use the object* look below instead of the mobs' one
	objectStyle = "standard/classic_gold", -- their icon
	objectBounce = true,  -- their float
	objectGlow = false,   -- their glow
	colorByType = true,  -- daily/repeatable in blue, group/elite in red
	combat = "show",     -- "show", "fade" or "hide" the icons in combat
	minimap = true,      -- minimap button
	minimapAngle = 220,  -- its position around the minimap (degrees)
	sound = true,        -- play a sound when a quest objective completes
	doneCheck = true,    -- an icon that stops being needed turns into a check mark, then fades
	readyAlert = true,   -- chat line when every objective of a quest is done
	minimapSummary = true, -- the minimap button's tooltip lists the open objectives
	hideWhileFighting = false, -- a mob you are fighting loses its icon (back if it survives)
	highLevelRed = true,  -- level alert: red icon for quests 2+ levels above you (deeper per level)
	soundChoice = "coins", -- key in QUEST_SOUNDS
	soundVolume = 100,   -- its volume in percent
}
-- Saved layout: CSCoderQuestIndicatorDB = { version, language, profiles = { name = settings },
-- chars = { "Name - Realm" = profile name }, savedCVars }.
local SETTINGS_VERSION = 5

-- The addon's version from the .toc (the packager fills it in; a dev copy shows "dev").
local function AddonVersion()
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta(ADDON, "Version")
	if type(version) ~= "string" or version:find("^@") then version = "dev" end
	return version
end
local DEFAULT_PROFILE = "Default"

local ICON_DIR = "Interface\\AddOns\\CSCoder_QuestIndicator\\icons\\"
-- Icon styles, in three categories (one row each in the picker). A style key is
-- "category/name", the file icons\category\name.tga.
local ICON_CATEGORIES = {
	{ key = "standard", sample = "standard/classic_gold", icons = {
		"classic_gold", "classic_blue", "classic_red", "classic_badge", "classic_pixel", -- the original five
		"yellow", "blue", "red", "green", "purple", "orange",
		"circle_yellow", "circle_blue", "circle_red", "circle_green", "circle_purple", "shield_yellow", "shield_blue", "shield_red" } },
	{ key = "themed", sample = "themed/laurels", icons = { "laurels", "horde", "alliance", "banner", "scroll", "sign",
		"gear", "crystal", "leaves", "arcane", "stone" } },
	{ key = "states", sample = "states/highlight", icons = { "highlight", "ring", "signal", "orbit", "white", "alert",
		"fire", "bright", "inactive", "blocked", "hourglass", "refresh" } },
}
local VALID_STYLE = {}
for _, category in ipairs(ICON_CATEGORIES) do
	for _, name in ipairs(category.icons) do VALID_STYLE[category.key .. "/" .. name] = true end
end
local DEFAULT_STYLE = "standard/classic_gold"
-- Style keys from before the categories (v1.0-1.2): the same five icons, now "classic".
local OLD_STYLES = { gold = "standard/classic_gold", blue = "standard/classic_blue", red = "standard/classic_red",
	badge = "standard/classic_badge", pixel = "standard/classic_pixel" }
-- "Color by quest type": styles that come in colours swap to their blue (daily) or red (group)
-- sibling; the rest get tinted.
local KIND_SIBLING = {}
for _, family in ipairs({
	{ prefix = "standard/classic_", names = { "gold", "blue", "red" } },
	{ prefix = "standard/", names = { "yellow", "blue", "red", "green", "purple", "orange" } },
	{ prefix = "standard/circle_", names = { "yellow", "blue", "red", "green", "purple" } },
	{ prefix = "standard/shield_", names = { "yellow", "blue", "red" } },
}) do
	for _, name in ipairs(family.names) do
		KIND_SIBLING[family.prefix .. name] = { daily = family.prefix .. "blue", group = family.prefix .. "red" }
	end
end

local function IconPath(style)
	return ICON_DIR .. (style or DEFAULT_STYLE):gsub("/", "\\")
end
local GLOW_TEXTURE = "Interface\\Cooldown\\star4"
local RECHECK_SECONDS = 1.0 -- tooltip data can arrive a moment after the plate appears
local SOFT = "softinteract"  -- the game's interaction soft target (one world object)
local FADE_ALPHA = 0.35
-- (high: the level alert, not a quest kind. One clearly different shade per level above you:
-- 2 = light red, 3 = red, 4 or more = full red.)
local KIND_TINT = { daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 },
	high = { [2] = { 1, 0.68, 0.62 }, [3] = { 1, 0.4, 0.34 }, [4] = { 1, 0.12, 0.1 } } }
-- Progress text formatting: the fonts every client ships, outlines and colours.
local TEXT_FONTS = { friz = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF", skurri = "Fonts\\skurri.ttf", morpheus = "Fonts\\MORPHEUS.TTF" }
local TEXT_FONT_ORDER = { "friz", "arial", "skurri", "morpheus" }
local PROGRESS_FORMATS = { "slash", "spaced", "both", "percent", "left" }

local TEXT_OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local TEXT_COLORS = { white = { 1, 1, 1 }, gold = { 1, 0.82, 0 }, green = { 0.3, 1, 0.3 } }
local KIND_TEXT_COLOR = { normal = { 1, 0.82, 0 }, daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 } }
local POSITION_RANGE = 200 -- X/Y sliders go from -200 to 200
local SLIDER_WIDTH = 200 -- sliders fit a half-width column with their value box

local root, db, charKey  -- saved variables, active profile, "Name - Realm"
local L                   -- active language table
local icons = {}          -- unit token -> icon frame
local pool = {}           -- recycled icon frames
-- The quest log, by title and by questID: kind ("normal", "daily", "group") and level.
-- (One table: the main chunk is at Lua's 200-locals limit.)
local quests = { kindByTitle = {}, kindByID = {}, levelByTitle = {}, levelByID = {} }
local inCombat = false

-- Fonts shared by other addons (Plater, ElvUI, WeakAuras, Details... register theirs with
-- LibSharedMedia). Looked up when needed, since those addons may load after this one; without
-- it the menu just has the four game fonts. A shared font is saved as "lsm:<name>".
local function SharedMedia()
	local stub = _G.LibStub
	return stub and stub("LibSharedMedia-3.0", true)
end

local function FontPath(key)
	if TEXT_FONTS[key] then return TEXT_FONTS[key] end
	local name = type(key) == "string" and key:match("^lsm:(.+)$")
	local lsm = name and SharedMedia()
	return (lsm and lsm:Fetch("font", name, true)) or TEXT_FONTS.friz
end

local function FontOptions()
	local list, seen = {}, {}
	for _, key in ipairs(TEXT_FONT_ORDER) do
		list[#list + 1] = key
		seen[TEXT_FONTS[key]:lower()] = true
	end
	local lsm = SharedMedia()
	if lsm then
		for _, name in ipairs(lsm:List("font") or {}) do
			local path = lsm:Fetch("font", name, true)
			if path and not seen[path:lower()] then
				seen[path:lower()] = true
				list[#list + 1] = "lsm:" .. name
			end
		end
	end
	return list
end

local function FontLabel(key)
	if TEXT_FONTS[key] then return L["FONT_" .. key] end
	return (type(key) == "string" and key:match("^lsm:(.+)$")) or tostring(key)
end

-- The progress as shown, in the chosen format, plus how far along it is (0..1).
-- raw is "8/12" or "45%" (percentage objectives always show as a percentage).
local function FormatProgress(raw)
	local have, need = raw:match("^(%d+)/(%d+)$")
	if have then
		have, need = tonumber(have), tonumber(need)
		local fraction = need > 0 and have / need or 0
		local percent = math.floor(fraction * 100 + 0.5)
		local format = db.progressFormat
		if format == "spaced" then return have .. " / " .. need, fraction end
		if format == "both" then return string.format("%d/%d (%d%%)", have, need, percent), fraction end
		if format == "percent" then return percent .. "%", fraction end
		if format == "left" then return string.format(L.FORMAT_LEFT_N, need - have), fraction end
		return have .. "/" .. need, fraction
	end
	local pct = tonumber(raw:match("^(%d+)%%$") or "")
	return raw, pct and pct / 100 or 0
end

-- Red at the start, yellow halfway, green when nearly done.
local function ProgressColor(fraction)
	fraction = math.max(0, math.min(1, fraction or 0))
	if fraction < 0.5 then return { 1, fraction * 2, 0.1 } end
	return { 1 - (fraction - 0.5) * 2, 1, 0.1 }
end

-- Quest objects need both the master switch and their own option.
local function ObjectsOn() return db.active and db.objects end
local UsablePlate -- defined with the icons
local RefreshSoftObject, EnableObjectNameplates, RestoreObjectCVars -- soft-target objects
local RefreshControls, UpdatePreview, UpdateMinimapButton, UpdateGates, LayoutTabs -- options UI
local settingsScroll -- the scrolling settings page

---------------------------------------------------------------------------------------------
-- Language
---------------------------------------------------------------------------------------------

local function BuildLocale(code)
	if code == nil or code == "auto" then code = GetLocale() end
	if code == "enGB" then code = "enUS" end
	local base = ns.locales.enUS
	local chosen = ns.locales[code] or base
	return setmetatable({}, { __index = function(_, key) return chosen[key] or base[key] or key end })
end

---------------------------------------------------------------------------------------------
-- Quest detection
---------------------------------------------------------------------------------------------

local GROUP_TAGS = { [1] = true, [62] = true, [81] = true, [85] = true, [88] = true, [89] = true }

local function KindFromTag(questID)
	if not (questID and C_QuestLog and C_QuestLog.GetQuestTagInfo) then return nil end
	local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, questID)
	if ok and type(tag) == "table" and (tag.isElite or GROUP_TAGS[tag.tagID or 0]) then return "group" end
	return nil
end

local function RebuildQuestTitles()
	wipe(quests.kindByTitle)
	wipe(quests.kindByID)
	wipe(quests.levelByTitle)
	wipe(quests.levelByID)
	local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
		or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local title, isHeader, questID, kind, level = nil, nil, nil, "normal", nil
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info then
				title, isHeader, questID, level = info.title, info.isHeader, info.questID, tonumber(info.level)
				if (tonumber(info.frequency) or 0) > 0 then
					kind = "daily"
				elseif (tonumber(info.suggestedGroup) or 0) > 1 then
					kind = "group"
				end
			end
		elseif GetQuestLogTitle then
			local t, questLevel, tag, header, _, _, frequency, id = GetQuestLogTitle(i)
			title, isHeader, questID, level = t, header, id, tonumber(questLevel)
			if frequency == true or (tonumber(frequency) or 0) > 0 then
				kind = "daily"
			elseif (type(tag) == "number" and tag > 1) or (type(tag) == "string" and tag ~= "") then
				kind = "group"
			end
		end
		if title and not isHeader then
			if kind == "normal" then kind = KindFromTag(questID) or kind end
			quests.kindByTitle[title] = kind
			quests.levelByTitle[title] = level
			if questID then quests.kindByID[questID] = kind; quests.levelByID[questID] = level end
		end
	end
end

-- The quest kind for a title, and its level as a second value (nil when unknown).
local function KindOf(title)
	return (title and quests.kindByTitle[title]) or "normal", title and quests.levelByTitle[title]
end

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin": true while the left number is below the right.
local function ProgressUnfinished(text)
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have and need then return tonumber(have) < tonumber(need) end
	return nil
end

-- The count shown next to the icon: "3/10", or "45%" for percentage objectives.
local function ProgressText(text)
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have then return have .. "/" .. need end
	return text:match("(%d+%%)")
end

-- WoW Forever can hide values from addons ("secret values"): inside instances nearly everything,
-- and in the open world a quest object's tooltip during combat. A secret can't be compared,
-- searched or used as a table key (that raises an error), so values are tested first. Detection
-- then answers Hidden.UNKNOWN and the icon is left as it was until the game shows the data again.
-- (One table, not three locals: the main chunk is near Lua's 200-locals limit.)
local Hidden = { UNKNOWN = "unknown" }
function Hidden.Value(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end
function Hidden.Table(value)
	return not Hidden.Value(value) and type(value) == "table" and not (issecrettable and issecrettable(value))
end

-- Reads tooltip lines (TooltipInfo data or plain strings) and answers: true = still needed,
-- false = quest-related but finished, nil = not quest-related, Hidden.UNKNOWN = the game hides them.
-- Then the quest title and the progress of the first unfinished objective ("3/10").
-- In a group the tooltip also lists each member's progress, under a row with their name
-- (QuestPlayer): those objectives are theirs, not ours, and are skipped.
local function QuestStateFromLines(lines)
	local lineTypes = Enum and Enum.TooltipDataLineType
	local objectiveType = lineTypes and lineTypes.QuestObjective
	local titleType = lineTypes and lineTypes.QuestTitle
	local playerType = lineTypes and lineTypes.QuestPlayer
	local sawQuest, title, others = false, nil, false
	for _, line in ipairs(lines) do
		if Hidden.Value(line) then return Hidden.UNKNOWN end
		local text, lineType, completed = line, nil, nil
		if type(line) == "table" then
			if not Hidden.Table(line) then return Hidden.UNKNOWN end
			text, lineType, completed = line.leftText, line.type, line.completed
			if Hidden.Value(text) or Hidden.Value(lineType) or Hidden.Value(completed) then return Hidden.UNKNOWN end
			text = text or ""
		end
		if playerType and lineType == playerType then
			local guid = line.guid
			others = Hidden.Value(guid) or guid ~= UnitGUID("player")
		elseif objectiveType and lineType == objectiveType then
			if not others then
				sawQuest = true
				if completed == false then return true, title, ProgressText(text) end
				if completed == nil and ProgressUnfinished(text) then return true, title, ProgressText(text) end
			end
		elseif (titleType and lineType == titleType) or quests.kindByTitle[text] then
			sawQuest, title, others = true, text, false
		elseif sawQuest and not others and ProgressUnfinished(text) then
			return true, title, ProgressText(text)
		end
	end
	if sawQuest then return false, title end
	return nil
end

local function ByTooltipInfo(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local data = C_TooltipInfo.GetUnit(unit)
	if Hidden.Value(data) then return Hidden.UNKNOWN end
	if not Hidden.Table(data) then return nil end
	local lines = data.lines
	if Hidden.Value(lines) or (lines ~= nil and not Hidden.Table(lines)) then return Hidden.UNKNOWN end
	if not lines then return nil end
	return QuestStateFromLines(lines)
end

local scanner = CreateFrame("GameTooltip", ADDON .. "Scanner", nil, "GameTooltipTemplate")
scanner.lines = {}

local function ByTooltipScan(unit)
	-- A hidden tooltip can lose its owner and then shows no lines: set it on every scan.
	scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanner:ClearLines()
	scanner:SetUnit(unit)
	local scanLines = scanner.lines
	wipe(scanLines)
	for i = 2, scanner:NumLines() do
		local fs = _G[ADDON .. "ScannerTextLeft" .. i]
		scanLines[#scanLines + 1] = fs and fs:GetText() or ""
	end
	local state, title, progress = QuestStateFromLines(scanLines)
	if state == Hidden.UNKNOWN then return Hidden.UNKNOWN end
	return state == true, title, progress
end

-- Unfinished objectives from the quest log, rebuilt on QUEST_LOG_UPDATE.
local objectiveTexts = {} -- { text = lower case objective, kind = quest kind }
-- What the last quest log scan found: unfinished objectives per quest (the minimap tooltip
-- summary) and when an objective last finished (icons that stop being needed right after show
-- the check mark).
local questLog = { summary = {}, completedAt = -100, byName = {} }

-- A name found in an unfinished objective ("Kobold Vermin slain: 3/10", "Crate of Supplies:
-- 1/4"): its quest kind and progress.
-- Answers are kept per name until the quest log changes (questLog.byName is emptied with each
-- scan), so a crowded area with a full quest log stays light: one search per mob name, not one
-- per nameplate every second.
local function ObjectiveKindForName(name)
	if Hidden.Value(name) or type(name) ~= "string" or name == "" then return nil end
	name = name:lower()
	local known = questLog.byName[name]
	if known == nil then
		known = false
		for _, objective in ipairs(objectiveTexts) do
			if objective.text:find(name, 1, true) then
				known = { kind = objective.kind, progress = ProgressText(objective.text), level = objective.level }
				break
			end
		end
		questLog.byName[name] = known
	end
	if known then return known.kind, known.progress, known.level end
	return nil
end

-- The unit's name in an unfinished objective of the quest log: needed?, kind, progress, level.
function questLog.FromName(unit)
	local kind, progress, level = ObjectiveKindForName((UnitName(unit)))
	return kind ~= nil, kind, progress, level
end

-- Questie as a helper, never a replacement: the game's answers always come first and a "no" from
-- the game is never overruled. Questie is only asked where the game leaves a gap: which quest and
-- what count when the game says a mob matters but its tooltip shows nothing open (often a drop),
-- or whether a mob matters at all on clients where the game can't tell.
-- Only when Questie is actually LOADED (installed but disabled on this character = not there).
-- Read-only and fully guarded: no Questie, or a Questie whose insides changed, simply answers nil.
do
	local tooltips -- Questie's QuestieTooltips module, once found
	local function Module()
		if tooltips then return tooltips end
		local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie"))
			or (IsAddOnLoaded and IsAddOnLoaded("Questie"))
		if not loaded or type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then return nil end
		local module = QuestieLoader:ImportModule("QuestieTooltips")
		if type(module) == "table" and type(module.lookupByKey) == "table" then tooltips = module end
		return tooltips
	end

	-- The first unfinished objective Questie has for this mob/object, in a quest of our log.
	local function Read(key)
		local module = Module()
		local list = module and module.lookupByKey[key]
		if type(list) ~= "table" then return nil end
		for _, entry in pairs(list) do
			local objective = type(entry) == "table" and entry.objective
			local quest = type(entry) == "table" and entry.questId
			-- Only objectives (quest starters have no objective) of quests still in our log.
			if type(objective) == "table" and quest and quests.kindByID[quest] then
				if type(objective.Update) == "function" and not (objective.IsSourceItem or objective.IsRequiredSourceItem) then
					pcall(objective.Update, objective)
				end
				if not objective.Completed then
					local have, need = tonumber(objective.Collected), tonumber(objective.Needed)
					local progress = (have and need and need > 0) and (have .. "/" .. need) or nil
					return quests.kindByID[quest], progress, quests.levelByID[quest]
				end
			end
		end
		return nil
	end

	-- Returns: needed?, kind, progress (nil when Questie isn't loaded or doesn't know the unit).
	function questLog.FromQuestie(unit)
		local guid = UnitGUID and UnitGUID(unit)
		if Hidden.Value(guid) or type(guid) ~= "string" then return nil end
		-- "Creature-0-server-instance-zone-npcID-spawn"; objects are "GameObject-...".
		local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
		local prefix = (kind == "Creature" or kind == "Vehicle") and "m_" or (kind == "GameObject" and "o_")
		if not (prefix and id) then return nil end
		local ok, questKind, progress, level = pcall(Read, prefix .. id)
		if ok and questKind then return true, questKind, progress, tonumber(level) end
		return nil
	end
end

-- Needed, with the quest kind, progress and level of the quest named by a tooltip title.
function questLog.FromTitle(title, progress)
	local kind, level = KindOf(title)
	return true, kind, progress, level
end

-- Returns: still needed? (Hidden.UNKNOWN while the game hides the data), quest kind, progress
-- text, quest level (nil when unknown).
local function IsQuestMob(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
	if UnitIsFriend("player", unit) and not UnitCanAttack("player", unit) then return false end
	local related
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		local ok, value = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
		if ok then related = value end
	end
	if Hidden.Value(related) then return Hidden.UNKNOWN end
	if related == false then return false end
	local state, title, progress = ByTooltipInfo(unit)
	if state == Hidden.UNKNOWN then return Hidden.UNKNOWN end
	if state == true then return questLog.FromTitle(title, progress) end
	if related then
		-- The tooltip shows nothing open, yet the game says the mob still matters: another quest
		-- needs it without showing in the tooltip (often a drop). Its name in an unfinished
		-- objective of the quest log gives that quest's count; Questie (if loaded) knows drops by
		-- their mob even when the item is named nothing like it.
		local found, kind, extra, level = questLog.FromName(unit)
		if found then return true, kind, extra, level end
		found, kind, extra, level = questLog.FromQuestie(unit)
		if found then return true, kind, extra, level end
		-- No objective names it (an item with another name): trust the game and mark the mob,
		-- without a count. Players who collect many quests hit this often; a missing mark
		-- is worse than a count we can't know.
		return true, "normal", nil
	end
	-- No answer from the game (older clients). The tooltip's quests are done: another quest may
	-- still name this mob.
	if state == false then return questLog.FromName(unit) end
	local scanned, scannedTitle, scannedProgress = ByTooltipScan(unit)
	if scanned == Hidden.UNKNOWN then return Hidden.UNKNOWN end
	if scanned then return questLog.FromTitle(scannedTitle, scannedProgress) end
	-- Last resort, for clients whose tooltips show no quest lines: Questie, then the quest log.
	local found, kind, extra, level = questLog.FromQuestie(unit)
	if found then return true, kind, extra, level end
	return questLog.FromName(unit)
end

---------------------------------------------------------------------------------------------
-- Icons (quest mobs, the soft-targeted object and the options preview share one frame type)
---------------------------------------------------------------------------------------------

local function CombatAlpha()
	if not inCombat then return 1 end
	if db.combat == "hide" then return 0 end
	if db.combat == "fade" then return FADE_ALPHA end
	return 1
end

-- Places the progress text. Attached: glued to the right of the icon, so it follows the icon's
-- position and size (its X/Y are locked). Detached: X/Y from the nameplate. wave (0..1) is the
-- float phase when it floats with the icon; the icon moves bounceHeight in its own scale, so the
-- text moves bounceHeight * scale.
-- full = true re-anchors the label too (styling); the float only moves the text frame, every
-- frame, with the same single point (SetPoint replaces it, no ClearAllPoints needed).
local ATTACH_GAP = 2
local function PlaceText(f, wave, full)
	local text, label = f.text, f.text.label
	local lift = wave * db.bounceHeight * (f.isObject and db.objectScale or db.scale)
	if full then
		text:ClearAllPoints()
		label:ClearAllPoints()
		label:SetPoint(db.progressAttach and "LEFT" or "CENTER")
	end
	if db.progressAttach then
		text:SetPoint("LEFT", f, "RIGHT", ATTACH_GAP, lift)
	else
		text:SetPoint("CENTER", f.plate or f:GetParent(), "TOP", db.progressX, db.progressY + lift)
	end
end

-- "style", "bounce" or "glow" for this icon: quest items with their own look use objectStyle,
-- objectBounce and objectGlow; everything else uses the shared setting. (A fixed table: the
-- float asks every frame.)
local Look
do
	local OBJECT_LOOK = { style = "objectStyle", bounce = "objectBounce", glow = "objectGlow" }
	function Look(f, key)
		if f.isObject and db.objectOwnLook then return db[OBJECT_LOOK[key]] end
		return db[key]
	end
end

local function StyleIcon(f)
	-- Texture and tint: with "color by quest type" the coloured styles swap to their blue/red
	-- sibling and the others are tinted.
	local style, tint = Look(f, "style"), nil
	local kind = f.kind or "normal"
	if db.colorByType and KIND_TINT[kind] then
		local sibling = KIND_SIBLING[style]
		if sibling then style = sibling[kind] else tint = KIND_TINT[kind] end
	end
	f.icon:SetTexture(IconPath(style))
	-- Level alert: a quest 2+ levels above you tints the icon red, a shade deeper per level up to
	-- full red at 4+, over any other tint.
	if db.highLevelRed and f.questLevel and UnitLevel then
		local gap = f.questLevel - (UnitLevel("player") or 0)
		if gap >= 2 then tint = KIND_TINT.high[math.min(gap, 4)] end
	end
	if tint then f.icon:SetVertexColor(tint[1], tint[2], tint[3]) else f.icon:SetVertexColor(1, 1, 1) end

	local scale = f.isObject and db.objectScale or db.scale
	f:SetScale(scale * (f.previewRatio or 1))
	f:SetAlpha(f.isPreview and 1 or CombatAlpha())

	-- Progress text ("8/12", on mobs and, if wanted, on the quest item). It has its own size and
	-- position: the frame undoes the icon's scale, so its size and X/Y don't change with the icon size.
	local text = f.text
	local wanted = f.isObject and db.objectProgress or (not f.isObject and db.progress)
	local showText = wanted and f.progressValue ~= nil
	text:SetShown(showText)
	if showText then
		local label = text.label
		local flags = TEXT_OUTLINES[db.progressOutline] or "OUTLINE"
		-- A font that fails to load (e.g. a removed shared font) falls back to the game's own.
		if label:SetFont(FontPath(db.progressFont), db.progressSize, flags) == false then
			label:SetFont(TEXT_FONTS.friz, db.progressSize, flags)
		end
		if db.progressShadow then
			label:SetShadowColor(0, 0, 0, 1)
			label:SetShadowOffset(1, -1)
		else
			label:SetShadowOffset(0, 0)
		end
		local shown, fraction = FormatProgress(f.progressValue)
		-- "Same as the icon" follows the quest type (gold, blue daily, red group); "By progress"
		-- goes from red (just started) through yellow to green (almost done).
		local color = TEXT_COLORS[db.progressColor]
		if db.progressColor == "kind" then
			color = db.colorByType and KIND_TEXT_COLOR[f.kind or "normal"] or KIND_TEXT_COLOR.normal
		elseif db.progressColor == "progress" then
			color = ProgressColor(fraction)
		end
		color = color or TEXT_COLORS.white
		-- One left: gold, whatever the colour setting (with "Animate the count").
		if db.progressPulse then
			local have, need = tostring(f.progressValue):match("(%d+)%s*/%s*(%d+)")
			if have and tonumber(need) - tonumber(have) == 1 then color = TEXT_COLORS.gold end
		end
		label:SetTextColor(color[1], color[2], color[3])
		label:SetText(shown)
		text:SetScale(1 / scale)
		PlaceText(f, 0, true)
	end

	local glow = Look(f, "glow")
	f.glow:SetVertexColor(1, 0.82, 0.2, db.glowAlpha)
	f.glow:SetShown(glow)
	if glow then
		if not f.pulse:IsPlaying() then f.pulse:Play() end
	else
		f.pulse:Stop()
	end

	-- The float itself is driven by the bobber below; without it the icon rests at the bottom.
	if not Look(f, "bounce") then f.inner:SetPoint("CENTER", f, "CENTER", 0, 0) end
end

-- Where the icon sits around the nameplate; X/Y move it from there. "top" keeps the plate frame
-- as before; the other sides use the health bar (the part you see) when the plate has one.
local ICON_ANCHORS = { top = { "BOTTOM", "TOP" }, bottom = { "TOP", "BOTTOM" }, left = { "RIGHT", "LEFT" }, right = { "LEFT", "RIGHT" } }
local ICON_ANCHOR_ORDER = { "top", "bottom", "left", "right" }

local function PlateBar(plate)
	if plate.previewBar then return plate.previewBar end
	local frame = plate.UnitFrame
	return frame and (frame.healthBar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))
end

local function AnchorIcon(f, plate)
	f:ClearAllPoints()
	local anchor, x, y
	if f.isObject then
		anchor, x, y = db.objectAnchor, db.objectOffsetX, db.objectOffset
	else
		anchor, x, y = db.anchor, db.offsetX, db.offset
	end
	local points = ICON_ANCHORS[anchor] or ICON_ANCHORS.top
	local target = (anchor ~= "top" and PlateBar(plate)) or plate
	f:SetPoint(points[1], target, points[2], x, y)
end

local function CreateIcon()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(26, 26)
	f:SetFrameStrata("LOW")

	-- The textures sit on an inner frame that the bobber moves up and down, so the outer frame
	-- keeps its anchor to the nameplate.
	local inner = CreateFrame("Frame", nil, f)
	inner:SetSize(26, 26)
	inner:SetPoint("CENTER")
	f.inner = inner
	f.phase = math.random() * 10 -- icons don't all float in step
	f.previewRatio = 1 -- set by the options preview to match real plates

	local glow = inner:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(GLOW_TEXTURE)
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER")
	glow:SetSize(40, 40)
	f.glow = glow

	local icon = inner:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	f.icon = icon

	local text = CreateFrame("Frame", nil, f)
	text:SetSize(60, 20)
	text.label = text:CreateFontString(nil, "OVERLAY")
	text.label:SetPoint("CENTER")
	text.label:SetFont(TEXT_FONTS.friz, DEFAULTS.progressSize, "OUTLINE")
	text.label:SetTextColor(1, 1, 1)
	text:Hide()
	f.text = text

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local spin = pulse:CreateAnimation("Rotation")
	spin:SetDegrees(-360)
	spin:SetDuration(6)
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.45)
	fade:SetToAlpha(1)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	f.pulse = pulse

	local pop = f:CreateAnimationGroup()
	local grow = pop:CreateAnimation("Scale")
	grow:SetScaleFrom(0.3, 0.3)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(0.18)
	grow:SetSmoothing("OUT")
	f.pop = pop

	-- Done: the check mark swells a little and fades out; then the icon goes back to the pool.
	local done = f:CreateAnimationGroup()
	local swell = done:CreateAnimation("Scale")
	swell:SetScaleFrom(1, 1)
	swell:SetScaleTo(1.35, 1.35)
	swell:SetDuration(0.25)
	swell:SetSmoothing("OUT")
	local fadeOut = done:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(0.6)
	fadeOut:SetDuration(0.5)
	done:SetScript("OnFinished", function() if f.onDone then f.onDone(f) end end)
	f.done = done

	-- The count's pulse when it goes up: out to 1.4x and back.
	local textPop = text:CreateAnimationGroup()
	local out = textPop:CreateAnimation("Scale")
	out:SetScale(1.4, 1.4)
	out:SetDuration(0.12)
	out:SetOrder(1)
	local back = textPop:CreateAnimation("Scale")
	back:SetScale(1 / 1.4, 1 / 1.4)
	back:SetDuration(0.18)
	back:SetOrder(2)
	f.textPop = textPop
	return f
end

local function ShowIcon(unit, plate, kind, progress, level)
	kind = kind or "normal"
	local f = icons[unit]
	if f then
		if f.completing then return end
		if f.kind ~= kind or f.progressValue ~= progress or f.questLevel ~= level then
			f.questLevel = level
			local before = tonumber(tostring(f.progressValue):match("%d+"))
			local now = tonumber(tostring(progress):match("%d+"))
			f.kind, f.progressValue = kind, progress
			StyleIcon(f)
			if db.progressPulse and before and now and now > before and f.text:IsShown() then
				f.textPop:Stop()
				f.textPop:Play()
			end
		end
		return
	end
	f = table.remove(pool) or CreateIcon()
	icons[unit] = f
	f.unit, f.isObject, f.kind, f.progressValue, f.questLevel = unit, unit == SOFT, kind, progress, level
	f:SetParent(plate)
	f:SetFrameStrata("LOW")
	AnchorIcon(f, plate)
	f:Show()
	StyleIcon(f)
	f.pop:Play()
end

local function HideIcon(unit)
	local f = icons[unit]
	if not f then return end
	icons[unit] = nil
	f.pulse:Stop()
	f.done:Stop()
	f.pop:Stop()
	f.textPop:Stop()
	f.completing, f.onDone = nil, nil
	f:Hide()
	-- Let go of the plate completely: a pooled icon must not stay anchored to a plate the game
	-- may later hand out as forbidden.
	f:ClearAllPoints()
	f:SetParent(UIParent)
	f.unit, f.progressValue = nil, nil
	f.text:Hide()
	table.insert(pool, f)
end

-- An icon that stops being needed right after an objective finished turns into a green check
-- mark, then fades; otherwise it just goes.
local function HideOrComplete(unit)
	local f = icons[unit]
	if not f or f.completing then return end
	if not (db.doneCheck and GetTime() - questLog.completedAt < 3) then -- 3 s after an objective finished
		HideIcon(unit)
		return
	end
	f.completing = true
	f.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	f.icon:SetVertexColor(1, 1, 1)
	f.glow:SetVertexColor(0.3, 1, 0.3, 0.9)
	f.glow:Show()
	f.text:Hide()
	f.onDone = function(self) if icons[unit] == self then HideIcon(unit) end end
	f.done:Play()
end

local function UpdateCombatAlpha()
	local alpha = CombatAlpha()
	for _, f in pairs(icons) do f:SetAlpha(alpha) end
end

-- A unit's nameplate if the addon may use it. In dungeons and raids the game can hand out
-- "forbidden" plates (other addons may not touch them): anchoring to one, or measuring it,
-- raises errors, so those count as no plate.
function UsablePlate(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return nil end
	if plate.IsForbidden then
		local ok, forbidden = pcall(plate.IsForbidden, plate)
		if not ok or forbidden then return nil end
	end
	return plate
end

-- Inside any instance (dungeon, raid, battleground, arena, scenario). Always off there, not an
-- option: WoW Forever makes nameplates forbidden and unit/tooltip data secret inside instances,
-- so no addon can read or mark quest mobs there (Questie switches its nameplate icons off the
-- same way). The options say so next to an info icon.
local function InstanceHidden()
	return IsInInstance and IsInInstance() and true or false
end

local function Refresh(unit)
	local plate = UsablePlate(unit)
	if db.active and db.enabled and plate and not InstanceHidden() then
		local needed, kind, progress, level = IsQuestMob(unit)
		if needed == Hidden.UNKNOWN then return end -- hidden by the game for now: leave the icon as it is
		-- "Hide while fighting it": the mob has you on its threat list. Not a check mark: it isn't
		-- done. If it survives (you run, it resets) the threat ends and the icon comes back.
		if needed and db.hideWhileFighting and UnitThreatSituation then
			local ok, threat = pcall(UnitThreatSituation, "player", unit)
			if ok and not Hidden.Value(threat) and threat ~= nil then HideIcon(unit) return end
		end
		if needed then ShowIcon(unit, plate, kind, progress, level) return end
		if not UnitIsDead(unit) then HideOrComplete(unit) return end
	end
	HideIcon(unit)
end

local function RefreshAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and unit ~= SOFT then Refresh(unit) end
	end
	RefreshSoftObject()
	for unit in pairs(icons) do
		if not UsablePlate(unit) then HideIcon(unit) end
	end
end

-- Only the look (size, position, float, glow, text): what sliders change. They fire on every
-- frame of a drag, so no cvars, tooltips or gates here.
local function ApplyLook()
	for _, f in pairs(icons) do
		AnchorIcon(f, f:GetParent())
		StyleIcon(f)
	end
	if UpdatePreview then UpdatePreview() end
end

local function ApplySettings()
	for _, f in pairs(icons) do
		AnchorIcon(f, f:GetParent())
		StyleIcon(f)
	end
	if ObjectsOn() then EnableObjectNameplates() else RestoreObjectCVars() end
	if UpdatePreview then UpdatePreview() end
	if UpdateGates then UpdateGates() end
	if UpdateMinimapButton then UpdateMinimapButton() end
	RefreshAll()
end

---------------------------------------------------------------------------------------------
-- Icon over the soft-targeted quest object. World objects only get a nameplate as the game's
-- interaction soft target ("softinteract", one object at a time, the nearest in front of you).
---------------------------------------------------------------------------------------------

local objectiveStates = {} -- questID -> { [objective index] = finished }, to hear one complete

-- Sounds for "objective complete" (sound kit IDs), picked by ear in game on 2026-11-09 from a
-- longer list. The old choices (ping, ready, warning, level up) fall back to the default.
local QUEST_SOUNDS = { coins = 120, auction = 5274, auctionclose = 1204, worldquest = 44295, bell = 6674, questlog = 875, quest = 878 }
local QUEST_SOUND_ORDER = { "coins", "auction", "auctionclose", "worldquest", "bell", "questlog", "quest" }

-- Plays a sound at the chosen volume. The game has no volume per sound, only per channel: at
-- 100% it plays on Master as before; below, it plays on the Dialog channel, whose volume is set
-- for a moment and put back 3 s after the last sound (also at the next login, if the game was
-- closed meanwhile: root.dialogVolume).
local PlaySoundAt
do
	local pending -- the latest sound waiting to restore the volume
	function PlaySoundAt(id)
		if not (PlaySound and id) then return end
		local volume = (tonumber(db.soundVolume) or 100) / 100
		local canSet = C_CVar and C_CVar.GetCVar and C_CVar.SetCVar
		local dialogOn = canSet and tostring(C_CVar.GetCVar("Sound_EnableDialog")) ~= "0"
		if volume >= 0.995 or not dialogOn then
			pcall(PlaySound, id, "Master")
			return
		end
		if volume <= 0 then return end
		if root.dialogVolume == nil then root.dialogVolume = C_CVar.GetCVar("Sound_DialogVolume") end
		pcall(C_CVar.SetCVar, "Sound_DialogVolume", volume)
		pcall(PlaySound, id, "Dialog")
		local token = {}
		pending = token
		C_Timer.After(3, function()
			if pending ~= token or root.dialogVolume == nil then return end
			pcall(C_CVar.SetCVar, "Sound_DialogVolume", root.dialogVolume)
			root.dialogVolume = nil
		end)
	end
end

local function PlayQuestSound()
	PlaySoundAt(QUEST_SOUNDS[db.soundChoice] or QUEST_SOUNDS[DEFAULTS.soundChoice])
end

local RebuildObjectiveTexts
do -- (own block: the main chunk is near Lua's 200-locals limit)
local function QuestTitle(questID, logIndex)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if not title and C_QuestLog.GetInfo then
		local info = C_QuestLog.GetInfo(logIndex)
		title = info and info.title
	end
	if not title and GetQuestLogTitle then title = GetQuestLogTitle(logIndex) end
	return title or "?"
end

function RebuildObjectiveTexts()
	wipe(objectiveTexts)
	wipe(questLog.byName)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
	-- An objective that was unfinished on the last scan and is finished now plays the sound
	-- (once per scan); a quest whose last objective just finished is announced as ready.
	-- Quests seen for the first time (login, just accepted) stay silent.
	local states, completed, ready, summary = {}, false, {}, {}
	local count = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local questID = C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)
		if not questID and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			questID = info and not info.isHeader and info.questID
		end
		local objectives = questID and C_QuestLog.GetQuestObjectives(questID)
		local before = objectiveStates[questID]
		local allDone, wasAllDone, open = #(objectives or {}) > 0, true, nil
		for index, objective in ipairs(objectives or {}) do
			local finished = objective.finished and true or false
			if objective.text and not finished then
				objectiveTexts[#objectiveTexts + 1] = { text = objective.text:lower(), kind = quests.kindByID[questID] or "normal", level = quests.levelByID[questID] }
				open = open or {}
				open[#open + 1] = objective.text
			end
			states[questID] = states[questID] or {}
			states[questID][index] = finished
			if not finished then allDone = false end
			if before and before[index] == false then
				wasAllDone = false
				if finished then completed = true end
			end
		end
		if open then summary[#summary + 1] = { title = QuestTitle(questID, i), lines = open } end
		if before and allDone and not wasAllDone then ready[#ready + 1] = QuestTitle(questID, i) end
	end
	objectiveStates = states
	questLog.summary = summary
	if completed then questLog.completedAt = GetTime() end
	if not db.active then return end
	if completed and db.sound then PlayQuestSound() end
	if db.readyAlert then
		for _, title in ipairs(ready) do
			print(string.format("|cffffd200%s|r " .. L.READY_TO_TURN_IN, TITLE, "|cff00ff00" .. title .. "|r"))
		end
	end
end
end

-- Returns: still needed?, quest kind, progress text.
local function IsQuestObject(unit)
	if not (UnitIsGameObject and UnitIsGameObject(unit)) then return false end
	local state, title, progress = ByTooltipInfo(unit)
	if state == Hidden.UNKNOWN then return Hidden.UNKNOWN end -- objects' tooltips turn secret in combat
	if state == true then return questLog.FromTitle(title, progress) end
	if state == false then return false end
	-- The tooltip says nothing: Questie (if loaded), then the quest log.
	local found, kind, extra, level = questLog.FromQuestie(unit)
	if found then return true, kind, extra, level end
	return questLog.FromName(unit)
end

-- Cvars this addon depends on. Other addons (e.g. ForeverLootSparkles) change the same ones and
-- put them back when their own options go off, so they are re-applied on CVAR_UPDATE.
-- Original values are saved and restored when "objects" is switched off here.
local OBJECT_CVARS = {
	SoftTargetIconGameObject = 1,      -- world objects can get a nameplate
	SoftTargetInteractRange = 60,      -- find objects further away (the client caps it lower)
	SoftTargetInteractOnlyInRange = 0, -- also objects outside the interact range
}
local GATE_CVAR = "SoftTargetNameplateInteract" -- nameplate on the interaction soft target
local WATCHED_CVARS = { softtargetinteract = true, softtargetnameplateinteract = true }
for name in pairs(OBJECT_CVARS) do WATCHED_CVARS[name:lower()] = true end
local pendingCVars       -- "apply" or "restore" once combat ends
-- writing: our own SetCVar is running (its CVAR_UPDATE is ours, not another addon's).
-- queued: a re-apply is already scheduled. recent/since: re-applies in the last few seconds,
-- so two addons that keep undoing each other can't loop forever.
-- gateOpened: the quest-object gate (see UpdateGate) was opened by this addon.
local cvarGuard = { writing = false, queued = false, recent = 0, since = 0, gateOpened = false }

local function GetCV(name)
	local ok, value = pcall(C_CVar.GetCVar, name)
	if ok then return value end
end

-- Writes only when the value changes; remembers the player's original the first time.
local function SetCV(name, value, remember)
	local current = GetCV(name)
	if current == nil or tostring(current) == tostring(value) then return end
	if remember then
		root.savedCVars = root.savedCVars or {}
		if root.savedCVars[name] == nil then root.savedCVars[name] = current end
	end
	cvarGuard.writing = true
	pcall(C_CVar.SetCVar, name, value)
	cvarGuard.writing = false
end

function EnableObjectNameplates()
	if not (C_CVar and C_CVar.SetCVar) then return end
	if InCombatLockdown() then pendingCVars = "apply"; return end
	if tonumber(GetCV("SoftTargetInteract") or 0) == 0 then SetCV("SoftTargetInteract", 3, true) end
	for name, value in pairs(OBJECT_CVARS) do
		if name == "SoftTargetInteractRange" then
			if (tonumber(GetCV(name)) or 0) < value then SetCV(name, value, true) end
		else
			SetCV(name, value, true)
		end
	end
end

function RestoreObjectCVars()
	if not (C_CVar and C_CVar.SetCVar) then return end
	if InCombatLockdown() then pendingCVars = "restore"; return end
	if cvarGuard.gateOpened then cvarGuard.gateOpened = false; SetCV(GATE_CVAR, 0) end
	for name, value in pairs(root.savedCVars or {}) do pcall(C_CVar.SetCVar, name, value) end
	root.savedCVars = nil
end

local function IsLoaded(addon)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) end
	return IsAddOnLoaded and IsAddOnLoaded(addon)
end

-- Opens the soft target's nameplate for quest objects only, so NPCs and mailboxes don't get one.
-- When ForeverLootSparkles is loaded it manages the plate for ore, herbs and corpses itself.
local function UpdateGate(isQuest)
	if InCombatLockdown() or not (C_CVar and C_CVar.SetCVar) then return end
	if isQuest then
		if tostring(GetCV(GATE_CVAR)) ~= "1" then
			SetCV(GATE_CVAR, 1)
			cvarGuard.gateOpened = true
		end
	elseif cvarGuard.gateOpened then
		cvarGuard.gateOpened = false
		local othersWantIt = IsLoaded("ForeverLootSparkles") and UnitExists(SOFT)
			and ((UnitIsGameObject and UnitIsGameObject(SOFT)) or UnitIsDead(SOFT))
		if not othersWantIt then SetCV(GATE_CVAR, 0) end
	end
end

function RefreshSoftObject()
	if not ObjectsOn() or InstanceHidden() then
		UpdateGate(false)
		HideIcon(SOFT)
		return
	end
	local isQuest, kind, progress, level = false, nil, nil, nil
	if UnitExists(SOFT) then isQuest, kind, progress, level = IsQuestObject(SOFT) end
	if isQuest == Hidden.UNKNOWN then return end -- hidden by the game for now: keep gate and icon as they are
	UpdateGate(isQuest)
	local plate = UsablePlate(SOFT)
	if isQuest and plate then
		if icons[SOFT] and icons[SOFT]:GetParent() ~= plate then HideIcon(SOFT) end
		ShowIcon(SOFT, plate, kind, progress, level)
	else
		HideIcon(SOFT) -- the plate follows the gate; NAME_PLATE_UNIT_ADDED shows the icon
	end
end

---------------------------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------------------------

local function FillDefaults(profile)
	for key, value in pairs(DEFAULTS) do
		if profile[key] == nil then profile[key] = value end
	end
	profile.cursor = nil -- removed option
	profile.style = OLD_STYLES[profile.style] or profile.style
	if not VALID_STYLE[profile.style] then profile.style = DEFAULT_STYLE end
	if not QUEST_SOUNDS[profile.soundChoice] then profile.soundChoice = DEFAULTS.soundChoice end
	for _, key in ipairs({ "anchor", "objectAnchor" }) do
		if not ICON_ANCHORS[profile[key]] then profile[key] = "top" end
	end
	return profile
end

local function CopySettings(source)
	local copy = {}
	for key in pairs(DEFAULTS) do copy[key] = source[key] end
	return copy
end

local function ProfileNames()
	local names = {}
	for name in pairs(root.profiles) do names[#names + 1] = name end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

local function ActiveProfileName()
	return root.chars[charKey]
end

local function ResolveCharacter()
	local name, realm = UnitName("player"), GetRealmName and GetRealmName()
	charKey = (name or "?") .. " - " .. (realm or "?")
	local profile = root.chars[charKey]
	if not (profile and root.profiles[profile]) then
		profile = root.profiles[DEFAULT_PROFILE] and DEFAULT_PROFILE or ProfileNames()[1]
		root.chars[charKey] = profile
	end
	db = root.profiles[profile]
end

local function LoadSavedVariables()
	local fresh = CSCoderQuestIndicatorDB == nil
	CSCoderQuestIndicatorDB = CSCoderQuestIndicatorDB or {}
	root = CSCoderQuestIndicatorDB
	-- Characters that used the addon before the setup guide existed don't get it on update.
	if not root.setupSeen then
		root.setupSeen = {}
		if not fresh then
			for key in pairs(root.chars or {}) do root.setupSeen[key] = true end
		end
	end
	if not root.profiles then
		-- Up to version 4 the settings sat directly in the saved table: they become "Default".
		local profile = {}
		for key in pairs(DEFAULTS) do
			profile[key] = root[key]
			root[key] = nil
		end
		if (root.version or 1) < 3 then profile.scale, profile.offset, profile.glow = nil, nil, nil end
		root.cursor = nil
		root.profiles = { [DEFAULT_PROFILE] = profile }
	end
	if next(root.profiles) == nil then root.profiles[DEFAULT_PROFILE] = {} end
	root.chars = root.chars or {}
	root.language = root.language or "auto"
	root.version = SETTINGS_VERSION
	for _, profile in pairs(root.profiles) do FillDefaults(profile) end
	ResolveCharacter()
end

local function UseProfile(name)
	if not root.profiles[name] then return end
	root.chars[charKey] = name
	db = root.profiles[name]
	RefreshControls()
	ApplySettings()
end

---------------------------------------------------------------------------------------------
-- Options panel: Options > AddOns > CS.Coder > Quest Indicator
---------------------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = SUBTITLE
local settingsCategory
local refreshers = {} -- re-read db into every control
local localized = {}  -- { object, locale key } for static texts

function RefreshControls()
	if UpdateGates then UpdateGates() end
	for _, fn in ipairs(refreshers) do fn() end
end

local function Loc(object, key)
	localized[#localized + 1] = { object, key }
	object:SetText(L[key])
	return object
end

local function Relabel()
	for _, entry in ipairs(localized) do entry[1]:SetText(L[entry[2]]) end
	if LayoutTabs then LayoutTabs() end
	RefreshControls()
end

-- The shared "CS.Coder" options entry: a small landing page listing the CS.Coder addons.
-- Kept in a global so every CS.Coder addon lands under the same entry, whichever loads first.
local function GetCSCoderParent()
	local parent = _G.CSCoderOptionsParent
	if parent then return parent end
	parent = { name = PARENT_NAME }
	local frame = CreateFrame("Frame")
	frame.name = PARENT_NAME
	local header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 16, -16)
	header:SetText(PARENT_NAME)
	local sub = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
	sub:SetJustifyH("LEFT")
	Loc(sub, "CATEGORY_DESC")
	parent.frame = frame
	if Settings and Settings.RegisterCanvasLayoutCategory then
		parent.category = Settings.RegisterCanvasLayoutCategory(frame, PARENT_NAME)
		Settings.RegisterAddOnCategory(parent.category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(frame)
	end
	_G.CSCoderOptionsParent = parent
	return parent
end

---------------------------------------------------------------------------------------------
-- Skin: the look of every window and control, drawn with flat colour textures (no art files
-- except one smooth circle). Inspired by OneForAll: dark warm panels, a thin gold ring, gold
-- text, switches instead of check boxes, gold-filled sliders. Hover is drawn on the HIGHLIGHT
-- layer, so it can never get stuck.
---------------------------------------------------------------------------------------------

local Skin = {}
do
	local CIRCLE = "Interface\\AddOns\\" .. ADDON .. "\\icons\\ui\\circle"
	Skin.CIRCLE = CIRCLE
	Skin.GOLD = { 1, 0.82, 0.2 }
	Skin.RING = { 0.50, 0.42, 0.30, 0.85 }

	-- Four 1-pixel lines around a frame.
	function Skin.Edges(f, r, g, b, a, layer)
		local edges = {}
		for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local e = f:CreateTexture(nil, layer or "BORDER")
			e:SetColorTexture(r, g, b, a or 1)
			if side == "TOP" or side == "BOTTOM" then
				e:SetPoint(side .. "LEFT")
				e:SetPoint(side .. "RIGHT")
				e:SetHeight(1)
			else
				e:SetPoint("TOP" .. side)
				e:SetPoint("BOTTOM" .. side)
				e:SetWidth(1)
			end
			edges[i] = e
		end
		return edges
	end

	function Skin.Recolor(f, fill, ring)
		if fill and f.skinBg then f.skinBg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1) end
		if ring and f.skinEdges then
			for _, e in ipairs(f.skinEdges) do e:SetColorTexture(ring[1], ring[2], ring[3], ring[4] or 1) end
		end
	end

	-- A flat panel: fill and a thin ring.
	function Skin.Panel(f, fill, ring)
		fill, ring = fill or { 0.045, 0.045, 0.055, 0.96 }, ring or Skin.RING
		f.skinBg = f:CreateTexture(nil, "BACKGROUND")
		f.skinBg:SetAllPoints()
		f.skinBg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
		f.skinEdges = Skin.Edges(f, ring[1], ring[2], ring[3], ring[4])
		return f
	end

	-- A window: warm dark fill, gold ring with a faint inner glow, and a header band that
	-- fades into the background (bandHeight 0 = none).
	function Skin.Window(f, bandHeight)
		Skin.Panel(f, { 0.065, 0.058, 0.048, 0.97 }, { 0.50, 0.38, 0.19, 1 })
		local glow = CreateFrame("Frame", nil, f)
		glow:SetPoint("TOPLEFT", 1, -1)
		glow:SetPoint("BOTTOMRIGHT", -1, 1)
		Skin.Edges(glow, 0.95, 0.72, 0.32, 0.12)
		bandHeight = bandHeight or 40
		if bandHeight > 0 then
			local band = f:CreateTexture(nil, "BORDER")
			band:SetPoint("TOPLEFT", 1, -1)
			band:SetPoint("TOPRIGHT", -1, -1)
			band:SetHeight(bandHeight)
			band:SetColorTexture(1, 1, 1, 1)
			local ok = band.SetGradient and CreateColor and pcall(band.SetGradient, band, "VERTICAL",
				CreateColor(0.065, 0.058, 0.048, 0), CreateColor(0.22, 0.15, 0.07, 0.9))
			if not ok then
				ok = band.SetGradientAlpha and pcall(band.SetGradientAlpha, band, "VERTICAL", 0.065, 0.058, 0.048, 0, 0.22, 0.15, 0.07, 0.9)
			end
			if not ok then band:SetColorTexture(0.14, 0.10, 0.06, 0.8) end
			local line = f:CreateTexture(nil, "BORDER")
			line:SetPoint("TOPLEFT", 1, -bandHeight)
			line:SetPoint("TOPRIGHT", -1, -bandHeight)
			line:SetHeight(1)
			line:SetColorTexture(0.50, 0.38, 0.19, 0.7)
		end
		return f
	end

	-- A gold button: dark plate, warm inner tint, gold edges, gold label that sinks 1 px when
	-- pressed. Size it after; SetText works as on Blizzard buttons.
	function Skin.Button(parent)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(120, 24)
		Skin.Panel(b, { 0.075, 0.065, 0.050, 1 }, { 0.72, 0.50, 0.16, 0.72 })
		local inner = b:CreateTexture(nil, "BORDER")
		inner:SetPoint("TOPLEFT", 1, -1)
		inner:SetPoint("BOTTOMRIGHT", -1, 1)
		inner:SetColorTexture(0.30, 0.22, 0.10, 0.28)
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(0.78, 0.55, 0.18, 0.18)
		local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("CENTER")
		label:SetTextColor(0.95, 0.82, 0.50)
		b:SetFontString(label)
		b:SetPushedTextOffset(1, -1)
		b:SetScript("OnDisable", function() label:SetTextColor(0.5, 0.5, 0.5) end)
		b:SetScript("OnEnable", function() label:SetTextColor(0.95, 0.82, 0.50) end)
		return b
	end

	-- A small square close button with a gold X; it hides its parent unless told otherwise.
	function Skin.Close(parent)
		local b = Skin.Button(parent)
		b:SetSize(24, 22)
		b:SetText("X")
		b:SetScript("OnClick", function() parent:Hide() end)
		return b
	end

	-- A check box drawn as a switch: a pill track and a round knob that slides right when on.
	function Skin.Switch(check)
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture", "GetDisabledCheckedTexture", "GetDisabledTexture" }) do
			local t = check[getter] and check[getter](check)
			if t and t.SetAlpha then t:SetAlpha(0) end
		end
		check:SetSize(34, 18)
		local parts = {}
		local function Part(layer, l, r)
			local t = check:CreateTexture(nil, layer)
			t:SetTexture(CIRCLE)
			t:SetTexCoord(l, r, 0, 1)
			parts[#parts + 1] = t
			return t
		end
		local left, middle, right = Part("ARTWORK", 0, 0.5), Part("ARTWORK", 0.49, 0.51), Part("ARTWORK", 0.5, 1)
		left:SetSize(9, 18)
		left:SetPoint("LEFT")
		right:SetSize(9, 18)
		right:SetPoint("RIGHT")
		middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
		middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
		local knob = check:CreateTexture(nil, "OVERLAY")
		knob:SetTexture(CIRCLE)
		knob:SetSize(14, 14)
		local hover = check:CreateTexture(nil, "HIGHLIGHT")
		hover:SetTexture(CIRCLE)
		hover:SetSize(20, 20)
		hover:SetVertexColor(1, 0.85, 0.4, 0.25)
		hover:SetPoint("CENTER", knob, "CENTER")
		local function Paint()
			local on = check:GetChecked() and true or false
			local track = on and { 0.62, 0.49, 0.27 } or { 0.23, 0.23, 0.25 }
			for _, t in ipairs(parts) do t:SetVertexColor(track[1], track[2], track[3]) end
			if on then knob:SetVertexColor(0.90, 0.87, 0.80) else knob:SetVertexColor(0.55, 0.56, 0.58) end
			knob:ClearAllPoints()
			knob:SetPoint(on and "RIGHT" or "LEFT", check, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
		end
		local setChecked = check.SetChecked
		check.SetChecked = function(self, value)
			setChecked(self, value)
			Paint()
		end
		check:HookScript("OnClick", Paint)
		Paint()
		return check
	end

	-- A slider drawn flat: dark 6-px track with a ring, a gold fill up to the thumb, a round
	-- light thumb. Paint(value) after every change keeps the fill in step.
	function Skin.Slider(slider, low, high, width)
		local track = CreateFrame("Frame", nil, slider)
		track:SetPoint("LEFT", 0, 0)
		track:SetPoint("RIGHT", 0, 0)
		track:SetHeight(6)
		track:SetFrameLevel(math.max(0, slider:GetFrameLevel() - 1))
		Skin.Panel(track, { 0.04, 0.04, 0.05, 1 }, { 0.55, 0.42, 0.20, 0.9 })
		local fill = track:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMLEFT", 1, 1)
		fill:SetColorTexture(0.85, 0.64, 0.24, 0.75)
		slider:SetThumbTexture(CIRCLE)
		local thumb = slider:GetThumbTexture()
		if thumb then
			thumb:SetSize(14, 14)
			thumb:SetVertexColor(0.95, 0.85, 0.62)
		end
		function slider.Paint(value)
			local share = (high > low) and math.max(0, math.min(1, ((value or low) - low) / (high - low))) or 0
			fill:SetWidth(math.max(1, share * ((width or 200) - 2)))
		end
		return slider
	end
end

local function AddHeading(parent, key, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	return Loc(fs, key)
end

local function AddCheck(parent, labelKey, tipKey, settingKey, x, y)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", x + 4, y - 6)
	Skin.Switch(check)
	-- Our own label right of the switch (the template's would sit over it).
	if check.Text then check.Text:SetText("") end
	if check.text then check.text:SetText("") end
	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 8, 0)
	check:SetHitRectInsets(0, -200, -4, -4) -- the label is clickable too
	Loc(text, labelKey)
	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 42, -2)
	note:SetWidth(250)
	note:SetJustifyH("LEFT")
	if tipKey then Loc(note, tipKey) end
	local function Sync() check:SetChecked(db[settingKey]) end
	refreshers[#refreshers + 1] = Sync
	check:SetScript("OnShow", Sync)
	check:HookScript("OnClick", function(self) -- (Hook: the switch repaints on click too)
		db[settingKey] = self:GetChecked() and true or false
		ApplySettings()
	end)
	check.labelFS, check.noteFS = text, note
	return check
end

-- 2 decimals ("1,50", "1,25"), none on whole-number sliders ("12"), with the decimal comma in
-- every panel language except English.
local function FormatNumber(value, step)
	local whole = step and step >= 1 and step % 1 == 0
	local text = whole and string.format("%d", math.floor(value + 0.5)) or string.format("%.2f", value)
	if text == "-0.00" then text = "0.00" elseif text == "-0" then text = "0" end
	local lang = root and root.language
	if lang == nil or lang == "auto" then lang = GetLocale() end
	if lang ~= "enUS" and lang ~= "enGB" then text = text:gsub("%.", ",") end
	return text
end

-- Hover help for sliders and dropdowns: the option's name, its explanation (TIP_<label key>,
-- when there is one) and, for sliders, how to set an exact value.
local function AddOptionTip(widget, labelKey, isSlider)
	widget:HookScript("OnEnter", function(self)
		if not GameTooltip.SetOwner then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L[labelKey], 1, 0.82, 0)
		local tipKey = "TIP_" .. labelKey
		if L[tipKey] ~= tipKey then GameTooltip:AddLine(L[tipKey], 1, 1, 1, true) end
		if isSlider then GameTooltip:AddLine(L.SLIDER_HINT, 0.6, 0.6, 0.6, true) end
		GameTooltip:Show()
	end)
	widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function AddSlider(parent, labelKey, settingKey, low, high, step, x, y, format)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", x, y)
	local slider = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	slider:SetSize(SLIDER_WIDTH, 16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	Skin.Slider(slider, low, high, SLIDER_WIDTH)
	-- A small box next to the slider shows the value; type a number and press Enter to set it,
	-- Escape (or clicking away) puts the current value back.
	local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	input:SetSize(52, 20)
	input:SetPoint("LEFT", slider, "RIGHT", 14, 0)
	input:SetAutoFocus(false)
	input:SetMaxLetters(8)
	input:SetJustifyH("CENTER")
	input:SetFontObject("GameFontHighlightSmall")
	-- Text set while the box is hidden stays scrolled to its end and looks empty: rewind it.
	local function ShowValue(value)
		input:SetText(FormatNumber(value, step))
		input:SetCursorPosition(0)
	end
	input:SetScript("OnShow", function() ShowValue(db[settingKey]) end)
	local function UpdateLabel(value)
		title:SetText(L[labelKey])
		ShowValue(value)
		slider.Paint(value)
	end
	local syncing = false
	-- Typed values keep up to 2 decimals, finer than the slider's step; the slider just follows.
	input:SetScript("OnEnterPressed", function(self)
		local typed = tonumber(((self:GetText() or ""):gsub(",", ".")))
		if typed then
			typed = math.max(low, math.min(high, math.floor(typed * 100 + 0.5) / 100))
			if db[settingKey] ~= typed then
				db[settingKey] = typed
				syncing = true
				slider:SetValue(typed)
				syncing = false
				slider.Paint(typed)
				ApplyLook()
			end
		end
		ShowValue(db[settingKey])
		self:ClearFocus()
	end)
	input:SetScript("OnEscapePressed", function(self)
		ShowValue(db[settingKey])
		self:ClearFocus()
	end)
	input:SetScript("OnEditFocusLost", function() ShowValue(db[settingKey]) end)
	local function Sync()
		syncing = true
		slider:SetValue(db[settingKey]); UpdateLabel(db[settingKey])
		syncing = false
	end
	refreshers[#refreshers + 1] = Sync
	slider:SetScript("OnShow", Sync)
	slider:SetScript("OnValueChanged", function(_, value)
		if syncing then return end
		value = math.floor(value / step + 0.5) * step
		if db[settingKey] == value then return end
		db[settingKey] = value
		UpdateLabel(value)
		ApplyLook() -- sliders only change the look
	end)
	-- Shift + mouse wheel moves one step (fine tuning on the wide X/Y ranges); the plain wheel
	-- keeps scrolling the settings page.
	slider:EnableMouseWheel(true)
	slider:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown and IsShiftKeyDown() then
			self:SetValue(math.max(low, math.min(high, db[settingKey] + delta * step)))
		elseif settingsScroll then
			local range = settingsScroll:GetVerticalScrollRange() or 0
			local target = (settingsScroll:GetVerticalScroll() or 0) - delta * 40
			settingsScroll:SetVerticalScroll(math.max(0, math.min(range, target)))
		end
	end)
	AddOptionTip(slider, labelKey, true)
	return slider, title, input
end

-- A section heading with its own on/off check on the left.
local function AddSectionCheck(parent, labelKey, settingKey, x, y)
	local check = AddCheck(parent, labelKey, nil, settingKey, x - 4, y + 6)
	check.labelFS:SetFontObject("GameFontNormal")
	return check
end

-- Controls that only make sense while a condition holds are faded and locked otherwise.
local gates = {}
local function Gate(condition, ...)
	gates[#gates + 1] = { condition = condition, widgets = { ... } }
end

function UpdateGates()
	if not db then return end
	for _, gate in ipairs(gates) do
		local on = gate.condition() and true or false
		for _, widget in ipairs(gate.widgets) do
			if widget.SetEnabled then
				widget:SetEnabled(on)
			elseif widget.Enable and widget.Disable then
				if on then widget:Enable() else widget:Disable() end
			end
			widget:SetAlpha(on and 1 or 0.4)
		end
	end
end

-- Dropdown. options: list of values; labelFor(value) -> text; get() / set(value).
-- Self-made (no UIDropDownMenu): that API differs or is deprecated across WoW clients.
local DROPDOWN_ROW = 18
local DROPDOWN_MAX_ROWS = 16 -- longer lists wrap into more columns
local openList -- the dropdown list currently open, if any
local dropdownHost -- window that holds new dropdown lists (default: the options panel)

local function AddDropdown(parent, labelKey, options, labelFor, get, set, x, y, width, fontFor, preview)
	width = width or 240
	local heading = AddHeading(parent, labelKey, x, y)
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local button = CreateFrame("Button", nil, parent, backdrop)
	button:SetSize(width, 24)
	button:SetPoint("TOPLEFT", x, y - 18)
	Skin.Panel(button, { 0.075, 0.065, 0.050, 0.95 }, Skin.RING)
	local value = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	value:SetPoint("LEFT", 10, 0)
	value:SetPoint("RIGHT", -26, 0)
	value:SetJustifyH("LEFT")
	local arrow = button:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -8, -3)
	arrow:SetVertexColor(0.95, 0.82, 0.50)
	local buttonHover = button:CreateTexture(nil, "HIGHLIGHT")
	buttonHover:SetAllPoints()
	buttonHover:SetColorTexture(0.78, 0.55, 0.18, 0.14)

	-- The list lives on the panel, not under the button: inside the scrolling page it would be
	-- cut off at the bottom of the view.
	local list = CreateFrame("Frame", nil, dropdownHost or panel, backdrop)
	list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 2)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	Skin.Panel(list, { 0.045, 0.045, 0.055, 0.98 }, Skin.RING)
	list:Hide()

	-- options can be a function (lists that change, like profiles): rows are made as needed.
	local rows = {}
	local Sync
	local function MakeRow(i)
		local row = CreateFrame("Button", nil, list)
		row:SetSize(width - 8, DROPDOWN_ROW)
		row:SetPoint("TOPLEFT", 4, -5 - (i - 1) * DROPDOWN_ROW)
		row.check = row:CreateTexture(nil, "ARTWORK")
		row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row.check:SetSize(16, 16)
		row.check:SetPoint("LEFT", 2, 0)
		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 22, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		local rowHover = row:CreateTexture(nil, "HIGHLIGHT")
		rowHover:SetAllPoints()
		rowHover:SetColorTexture(0.90, 0.66, 0.22, 0.18)
		-- preview(option), when given, adds a play button to each row (the sound menu).
		if preview then
			row.text:SetPoint("RIGHT", -22, 0)
			local play = CreateFrame("Button", nil, row)
			play:SetSize(16, 16)
			play:SetPoint("RIGHT", -2, 0)
			play:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
			play:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
			play:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
			play:SetScript("OnClick", function() preview(row.option) end)
		end
		row:SetScript("OnClick", function(self)
			list:Hide()
			set(self.option)
			Sync()
		end)
		rows[i] = row
		return row
	end
	-- fontFor(option), when given, draws each entry in its own font (the font menu).
	local function UseFont(fs, option)
		if not (fontFor and option ~= nil and fs:SetFont(fontFor(option), 12, "") ~= false) then
			fs:SetFontObject("GameFontHighlightSmall")
		end
	end
	function Sync()
		local current = get()
		local items = type(options) == "function" and options() or options
		value:SetText(current ~= nil and labelFor(current) or "")
		UseFont(value, current)
		-- Long lists (many shared fonts) wrap into columns instead of running off the screen.
		local columns = math.max(1, math.ceil(#items / DROPDOWN_MAX_ROWS))
		for i, option in ipairs(items) do
			local row = rows[i] or MakeRow(i)
			row.option = option
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 4 + math.floor((i - 1) / DROPDOWN_MAX_ROWS) * width,
				-5 - ((i - 1) % DROPDOWN_MAX_ROWS) * DROPDOWN_ROW)
			row.text:SetText(labelFor(option))
			UseFont(row.text, option)
			row.check:SetShown(option == current)
			if option == current then row.text:SetTextColor(1, 0.82, 0.2) else row.text:SetTextColor(0.92, 0.90, 0.84) end
			row:Show()
		end
		for i = #items + 1, #rows do rows[i]:Hide() end
		list:SetSize(width * columns, math.max(1, math.min(#items, DROPDOWN_MAX_ROWS)) * DROPDOWN_ROW + 10)
	end

	button:SetScript("OnClick", function()
		if list:IsShown() then list:Hide() return end
		if openList then openList:Hide() end
		Sync()
		list:Show()
		openList = list
	end)
	list:SetScript("OnHide", function(self) if openList == self then openList = nil end end)
	-- A click anywhere else closes the list.
	list:SetScript("OnUpdate", function(self)
		if IsMouseButtonDown and IsMouseButtonDown("LeftButton") and not self:IsMouseOver() and not button:IsMouseOver() then
			self:Hide()
		end
	end)
	parent:HookScript("OnHide", function() list:Hide() end)
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
	AddOptionTip(button, labelKey)
	return button, heading
end

-- Icon style picker. The panel shows one button with the current icon; it opens a window with
-- the three categories on the left (each with a sample icon) and that category's icons on the
-- right. The window stays open while you try icons, so the preview can follow; X or Esc closes.
local PICKER_COLUMNS, PICKER_CELL = 7, 46
local iconPicker

local function CategoryOf(style) return (style or DEFAULT_STYLE):match("^(%w+)/") or "standard" end

local function StyleName(style)
	local name = style and style:match("/(.+)$")
	return name and L["ICON_" .. name] or ""
end

local function BuildIconPicker()
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local f = CreateFrame("Frame", ADDON .. "IconPicker", UIParent, backdrop)
	f:SetSize(212 + PICKER_COLUMNS * PICKER_CELL + 24, 226)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Skin.Window(f, 40)
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, f:GetName()) end -- Esc closes it
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 20, -18)
	Loc(title, "ICON_STYLE")
	local close = Skin.Close(f)
	close:SetPoint("TOPRIGHT", -4, -4)
	f:Hide()

	f.key = "style" -- the setting the picker edits; set by the button that opens it
	local shownCategory = CategoryOf(db.style)
	local categoryButtons, cells = {}, {}

	-- Left: one button per category, with its sample icon.
	for i, category in ipairs(ICON_CATEGORIES) do
		local b = CreateFrame("Button", nil, f, backdrop)
		b:SetSize(190, 44)
		b:SetPoint("TOPLEFT", 18, -48 - (i - 1) * 54)
		Skin.Panel(b)
		local label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", 12, 0)
		label:SetPoint("RIGHT", -46, 0)
		label:SetJustifyH("LEFT")
		Loc(label, "ICONCAT_" .. category.key)
		local sample = b:CreateTexture(nil, "ARTWORK")
		sample:SetSize(34, 34)
		sample:SetPoint("RIGHT", -6, 0)
		sample:SetTexture(IconPath(category.sample))
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(0.90, 0.66, 0.22, 0.10)
		b.categoryKey = category.key
		b:SetScript("OnClick", function() shownCategory = category.key; f:Refresh() end)
		categoryButtons[i] = b
	end

	-- Right: the shown category's icons in a grid; cells are reused between categories.
	local function Cell(i)
		if cells[i] then return cells[i] end
		local c = CreateFrame("Button", nil, f)
		c:SetSize(PICKER_CELL - 6, PICKER_CELL - 6)
		local row, col = math.floor((i - 1) / PICKER_COLUMNS), (i - 1) % PICKER_COLUMNS
		c:SetPoint("TOPLEFT", 222 + col * PICKER_CELL, -48 - row * PICKER_CELL)
		local bg = c:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.4)
		c.tex = c:CreateTexture(nil, "ARTWORK")
		c.tex:SetPoint("TOPLEFT", 3, -3)
		c.tex:SetPoint("BOTTOMRIGHT", -3, 3)
		c.selected = c:CreateTexture(nil, "OVERLAY")
		c.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		c.selected:SetBlendMode("ADD")
		c.selected:SetAllPoints()
		c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		c:SetScript("OnClick", function(self)
			db[f.key] = self.style
			ApplySettings()
			RefreshControls()
		end)
		c:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(StyleName(self.style))
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cells[i] = c
		return c
	end

	function f:Refresh()
		local current = CategoryOf(db[f.key])
		for _, b in ipairs(categoryButtons) do
			local isShown = b.categoryKey == shownCategory
			-- Gold ring and warm plate on the shown category; a dimmer ring on the chosen icon's.
			local ring = isShown and { 1, 0.80, 0.40 } or (b.categoryKey == current and { 0.70, 0.55, 0.28 } or { 0.36, 0.28, 0.16 })
			Skin.Recolor(b, isShown and { 0.21, 0.15, 0.08, 0.95 } or { 0.085, 0.078, 0.066, 0.95 }, ring)
		end
		local icons = {}
		for _, category in ipairs(ICON_CATEGORIES) do
			if category.key == shownCategory then icons = category.icons end
		end
		for i, name in ipairs(icons) do
			local c = Cell(i)
			c.style = shownCategory .. "/" .. name
			c.tex:SetTexture(IconPath(c.style))
			c.selected:SetShown(c.style == db[f.key])
			c:Show()
		end
		for i = #icons + 1, #cells do cells[i]:Hide() end
	end
	f:SetScript("OnShow", function() shownCategory = CategoryOf(db[f.key]); f:Refresh() end)
	panel:HookScript("OnHide", function() f:Hide() end)
	return f
end

-- The button on the panel: current icon, its name and category; a click opens the picker.
local function AddIconPicker(parent, x, y, key)
	key = key or "style"
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local b = CreateFrame("Button", nil, parent, backdrop)
	b:SetSize(260, 48)
	b:SetPoint("TOPLEFT", x, y)
	Skin.Panel(b, { 0.075, 0.065, 0.050, 0.95 }, { 0.72, 0.50, 0.16, 0.72 })
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(38, 38)
	icon:SetPoint("LEFT", 6, 0)
	local name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -4)
	name:SetPoint("RIGHT", -30, 0)
	name:SetJustifyH("LEFT")
	local category = b:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	category:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 4)
	category:SetPoint("RIGHT", -30, 0)
	category:SetJustifyH("LEFT")
	local arrow = b:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(16, 16)
	arrow:SetPoint("RIGHT", -10, 0)
	local pickerHover = b:CreateTexture(nil, "HIGHLIGHT")
	pickerHover:SetAllPoints()
	pickerHover:SetColorTexture(0.78, 0.55, 0.18, 0.14)

	local function Sync()
		icon:SetTexture(IconPath(db[key]))
		name:SetText(StyleName(db[key]))
		category:SetText(L["ICONCAT_" .. CategoryOf(db[key])])
		if iconPicker and iconPicker:IsShown() then iconPicker:Refresh() end
	end
	b:SetScript("OnClick", function(self)
		iconPicker = iconPicker or BuildIconPicker()
		if iconPicker:IsShown() and iconPicker.key == key then iconPicker:Hide() return end
		iconPicker.key = key
		iconPicker:Hide() -- reopening re-reads the setting and its category
		iconPicker:ClearAllPoints()
		iconPicker:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
		iconPicker:Show()
	end)
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
	return b
end

-- Live preview: a quest mob with a fake nameplate on top, a quest item (crate) below, each with
-- an icon that follows the settings. There can be several (the options' preview window and the
-- setup guide); all of them follow every change.
local previews = {}

local function BuildPreview(pane, width)
	local p = { width = width } -- known width: anchored frames can report 0 before the first layout
	previews[#previews + 1] = p
	local heading = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 2, 0)
	Loc(heading, "PREVIEW")

	local box = CreateFrame("Frame", nil, pane, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetPoint("TOPLEFT", 0, -20)
	box:SetPoint("BOTTOMRIGHT")
	Skin.Panel(box, { 0.05, 0.08, 0.05, 0.95 }, Skin.RING)
	if box.SetClipsChildren then box:SetClipsChildren(true) end

	local divider = box:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.08)
	divider:SetHeight(1)
	divider:SetPoint("LEFT", box, "LEFT", 8, 0)
	divider:SetPoint("RIGHT", box, "RIGHT", -8, 0)

	-- Quest mob, upper half. Real nameplate frames reach well above the name, so the fake one does too.
	local plate = CreateFrame("Frame", nil, box)
	plate:SetSize(100, 56)
	plate:SetPoint("BOTTOM", box, "CENTER", 0, 14)
	local bar = CreateFrame("StatusBar", nil, plate)
	bar:SetSize(90, 8)
	bar:SetPoint("BOTTOM", 0, 8)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.85, 0.1, 0.1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0, 0, 0, 0.7)
	local mobName = plate:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	mobName:SetPoint("BOTTOM", bar, "TOP", 0, 2)
	Loc(mobName, "PREVIEW_MOB")

	-- Quest item, lower half.
	local item = CreateFrame("Frame", nil, box)
	item:SetSize(100, 30)
	item:SetPoint("BOTTOM", box, "BOTTOM", 0, 26)
	local crate = item:CreateTexture(nil, "ARTWORK")
	crate:SetSize(28, 28)
	crate:SetPoint("CENTER", 0, 2)
	crate:SetTexture("Interface\\Icons\\INV_Crate_01")
	local itemName = item:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	itemName:SetPoint("TOP", crate, "BOTTOM", 0, -2)
	Loc(itemName, "PREVIEW_OBJECT")

	p.mob = CreateIcon()
	p.mob:SetParent(plate)
	p.mob.plate, p.mob.isPreview, p.mob.kind, p.mob.progressValue = plate, true, "normal", "8/12"
	p.object = CreateIcon()
	p.object:SetParent(item)
	p.object.plate, p.object.isPreview, p.object.isObject, p.object.kind, p.object.progressValue = item, true, true, "normal", "1/4"
	p.box, p.plate, p.bar = box, plate, bar
	plate.previewBar = bar -- side anchors use the bar, as on real plates
	box:SetScript("OnShow", function() UpdatePreview() end)
	return p
end

-- The fake nameplate copies a real one measured in the world (size, scale, health bar), so what
-- you set in the preview looks the same on real plates. previewRatio turns real plate units into
-- preview units; the mob icon is scaled by it as well.
local function ApplyPlateGeometry(p)
	local geom, ratio = root and root.plateGeom, 1
	if geom and geom.eff then ratio = geom.eff / p.box:GetEffectiveScale() end
	-- A big plate (or a small UI scale) would fill the box and push side-anchored icons out of
	-- view: then the whole scene shrinks, plate and icon together, so proportions still match.
	local boxWidth = geom and geom.w and (p.width or p.box:GetWidth())
	if boxWidth and boxWidth > 0 then ratio = math.min(ratio, boxWidth * 0.45 / geom.w) end
	if geom then
		p.plate:SetSize(geom.w * ratio, geom.h * ratio)
		if geom.barW then
			p.bar:SetSize(geom.barW * ratio, geom.barH * ratio)
			if geom.barTop then
				p.bar:ClearAllPoints()
				p.bar:SetPoint("TOP", p.plate, "TOP", 0, -geom.barTop * ratio)
			end
		end
	end
	p.mob.previewRatio = ratio
end

function UpdatePreview()
	if not db then return end
	for _, p in ipairs(previews) do
		ApplyPlateGeometry(p)
		for _, f in ipairs({ p.mob, p.object }) do
			-- The icons are created at LOW strata: lift them into the window.
			f:SetFrameStrata(p.box:GetFrameStrata())
			f:SetFrameLevel(p.box:GetFrameLevel() + 10)
			AnchorIcon(f, f.plate)
			f:Show()
			StyleIcon(f)
		end
		-- A switched-off kind is shown faded.
		p.mob:SetAlpha((db.active and db.enabled) and 1 or 0.25)
		p.object:SetAlpha((db.active and db.objects) and 1 or 0.25)
	end
end

---------------------------------------------------------------------------------------------
-- Float animation. Done by hand instead of a looping Translation animation: the game's
-- BOUNCE loop restarts for one frame at the top, which makes the icon blink.
---------------------------------------------------------------------------------------------

local function Bob(f, now)
	-- Nothing to move: no float, the check mark fading out, or hidden in combat (alpha 0).
	if f.completing or not Look(f, "bounce") or f:GetAlpha() == 0 then return end
	-- One full up-and-down cycle takes 2 * bounceSpeed seconds; cosine eases both ends.
	local period = 2 * db.bounceSpeed
	local wave = (1 - math.cos((now + f.phase) * 2 * math.pi / period)) / 2
	f.inner:SetPoint("CENTER", f, "CENTER", 0, wave * db.bounceHeight)
	if db.progressFloat and f.text:IsShown() then PlaceText(f, wave) end
end

local bobber = CreateFrame("Frame")
bobber:SetScript("OnUpdate", function()
	if not (db and (db.bounce or (db.objectOwnLook and db.objectBounce))) then return end
	local now = GetTime()
	for _, f in pairs(icons) do Bob(f, now) end
	for _, p in ipairs(previews) do
		if p.box:IsVisible() then
			Bob(p.mob, now)
			Bob(p.object, now)
		end
	end
end)

---------------------------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------------------------

local minimapButton
local OpenPanel -- defined below

local function PlaceMinimapButton()
	local angle = math.rad(db.minimapAngle or DEFAULTS.minimapAngle)
	local radius = (Minimap:GetWidth() / 2) + 6
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
	local b = CreateFrame("Button", ADDON .. "MinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(IconPath(DEFAULT_STYLE))
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			db.active = not db.active
			ApplySettings()
			RefreshControls()
			print("|cffffd200" .. TITLE .. "|r " .. (db.active and L.ON or L.OFF))
		else
			OpenPanel(true)
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			PlaceMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(TITLE)
		GameTooltip:AddLine(L.TIP_LEFT, 1, 1, 1)
		GameTooltip:AddLine(L.TIP_RIGHT, 1, 1, 1)
		GameTooltip:AddLine(L.TIP_DRAG, 0.7, 0.7, 0.7)
		-- What's left, per quest (up to 8 quests).
		if db.minimapSummary and #questLog.summary > 0 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L.SUMMARY_TITLE, 1, 0.82, 0)
			for i, quest in ipairs(questLog.summary) do
				if i > 8 then
					GameTooltip:AddLine(string.format(L.SUMMARY_MORE, #questLog.summary - 8), 0.7, 0.7, 0.7)
					break
				end
				GameTooltip:AddLine(quest.title, 1, 0.82, 0)
				for _, line in ipairs(quest.lines) do GameTooltip:AddLine("   " .. line, 1, 1, 1) end
			end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

function UpdateMinimapButton()
	if not (db and Minimap) then return end
	if db.minimap then
		minimapButton = minimapButton or CreateMinimapButton()
		minimapButton.icon:SetDesaturated(not db.active)
		PlaceMinimapButton()
		minimapButton:Show()
	elseif minimapButton then
		minimapButton:Hide()
	end
end

local BuildPanel, ShowWizard, ShowNews, ShowDebug
do -- the options window, its sections, the setup guide and what's new (one block: the main
   -- chunk would pass Lua's 200-locals limit)
---------------------------------------------------------------------------------------------
-- Panel layout: options on the left in four tabs (Display, Icon, Behavior, Profiles), the live
-- preview fixed on the right.
---------------------------------------------------------------------------------------------

local LEFT, TOP = 16, -96
local PREVIEW_WIDTH, PREVIEW_HEIGHT = 400, 400 -- the preview window: room for a real-size plate with icons on any side

-- Settings each tab owns, for its "Reset this tab" button.
local DISPLAY_KEYS = { "active", "enabled", "objects", "anchor", "scale", "offsetX", "offset",
	"objectAnchor", "objectScale", "objectOffsetX", "objectOffset" }
local ICON_KEYS = { "style", "bounce", "bounceHeight", "bounceSpeed", "glow", "glowAlpha",
	"objectOwnLook", "objectStyle", "objectBounce", "objectGlow" }
local PROGRESS_KEYS = { "progress", "objectProgress", "progressPulse", "progressAttach", "progressFloat", "progressSize", "progressFont",
	"progressOutline", "progressColor", "progressFormat", "progressShadow", "progressX", "progressY" }
local BEHAVIOR_KEYS = { "colorByType", "combat", "minimap", "minimapAngle", "sound", "soundChoice",
	"soundVolume", "doneCheck", "readyAlert", "minimapSummary", "hideWhileFighting", "highLevelRed" }

local function ResetKeys(keys)
	for _, key in ipairs(keys) do db[key] = DEFAULTS[key] end
end

local function AfterReset()
	RefreshControls()
	UpdateCombatAlpha()
	ApplySettings()
end

-- Sections share one scrolling page; each has a heading row with its own small reset button.
local SECTION_HEADER = 34
local function AddResetTabButton(tab, onReset)
	local b = Skin.Button(tab)
	b:SetSize(130, 20)
	b:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -16, TOP + SECTION_HEADER - 6)
	Loc(b, "RESET_SECTION")
	b:SetScript("OnClick", function()
		onReset()
		AfterReset()
	end)
end

-- What each control depends on (one table: the main chunk is near Lua's 200-locals limit).
local On = {}
function On.AddonOn() return db.active end
function On.MobsOn() return db.active and db.enabled end
function On.ItemsOn() return db.active and db.objects end
function On.AnyIconOn() return db.active and (db.enabled or db.objects) end
function On.ItemLookOn() return On.ItemsOn() and db.objectOwnLook end
function On.AnyFloat() return db.bounce or (db.objectOwnLook and db.objectBounce) end
function On.AnyGlow() return db.glow or (db.objectOwnLook and db.objectGlow) end
function On.FloatOn() return On.AnyIconOn() and On.AnyFloat() end
function On.GlowOn() return On.AnyIconOn() and On.AnyGlow() end
-- The text's look applies while either count is on.
function On.ProgressOn() return (On.MobsOn() and db.progress) or (On.ItemsOn() and db.objectProgress) end

local function GateCheck(condition, check)
	Gate(condition, check, check.labelFS, check.noteFS)
	return check
end

-- Two columns per section: related groups side by side (mobs | items, float | glow, ...).
local COL1, COL2 = LEFT, LEFT + 290
local COLUMN_DROPDOWN = 200

-- Anchor menu: which side of the nameplate the icon sits on. Picking a side starts X/Y from
-- that side (the defaults for "top", zero for the others), so the icon lands right there.
local function AddAnchorMenu(tab, key, xKey, yKey, x, y, gate)
	Gate(gate, AddDropdown(tab, "ICON_ANCHOR", ICON_ANCHOR_ORDER, function(value) return L["ANCHOR_" .. value] end,
		function() return db[key] end,
		function(value)
			if db[key] ~= value then
				db[key] = value
				db[xKey] = value == "top" and DEFAULTS[xKey] or 0
				db[yKey] = value == "top" and DEFAULTS[yKey] or 0
			end
			ApplySettings(); RefreshControls()
		end, x, y, COLUMN_DROPDOWN))
end

local function BuildDisplayTab(tab)
	AddResetTabButton(tab, function() ResetKeys(DISPLAY_KEYS) end)
	AddCheck(tab, "ENABLE_ADDON", "ENABLE_ADDON_TIP", "active", COL1, TOP)

	local y = TOP - 58
	GateCheck(On.AddonOn, AddSectionCheck(tab, "QUEST_MOBS", "enabled", COL1, y))
	AddAnchorMenu(tab, "anchor", "offsetX", "offset", COL1 + 4, y - 26, On.MobsOn)
	Gate(On.MobsOn, AddSlider(tab, "ICON_SIZE", "scale", 0.5, 3.0, 0.05, COL1 + 4, y - 80, "%.2f"))
	Gate(On.MobsOn, AddSlider(tab, "POS_X", "offsetX", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, y - 120, "%d"))
	Gate(On.MobsOn, AddSlider(tab, "POS_Y", "offset", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, y - 160, "%d"))

	GateCheck(On.AddonOn, AddSectionCheck(tab, "QUEST_ITEMS", "objects", COL2, y))
	AddAnchorMenu(tab, "objectAnchor", "objectOffsetX", "objectOffset", COL2 + 4, y - 26, On.ItemsOn)
	Gate(On.ItemsOn, AddSlider(tab, "ICON_SIZE", "objectScale", 0.5, 3.0, 0.05, COL2 + 4, y - 80, "%.2f"))
	Gate(On.ItemsOn, AddSlider(tab, "POS_X", "objectOffsetX", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, y - 120, "%d"))
	Gate(On.ItemsOn, AddSlider(tab, "POS_Y", "objectOffset", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, y - 160, "%d"))
end

-- The objective count ("8/12") next to quest mobs: everything about it is its own.
local function BuildProgressTab(tab)
	AddResetTabButton(tab, function() ResetKeys(PROGRESS_KEYS) end)
	-- Left: what it does. Right: how it looks.
	GateCheck(On.MobsOn, AddCheck(tab, "PROGRESS", "PROGRESS_TIP", "progress", COL1, TOP))
	GateCheck(On.ItemsOn, AddCheck(tab, "PROGRESS_ITEMS", "PROGRESS_ITEMS_TIP", "objectProgress", COL1, TOP - 48))
	GateCheck(On.ProgressOn, AddCheck(tab, "PROGRESS_ATTACH", "PROGRESS_ATTACH_TIP", "progressAttach", COL1, TOP - 96))
	-- Floating with the icon needs the icon's own Float.
	GateCheck(function() return On.ProgressOn() and On.AnyFloat() end,
		AddCheck(tab, "PROGRESS_FLOAT", "PROGRESS_FLOAT_TIP", "progressFloat", COL1, TOP - 144))
	Gate(On.ProgressOn, AddSlider(tab, "TEXT_SIZE", "progressSize", 8, 32, 1, COL1 + 4, TOP - 198, "%d"))

	local function Choice(key) return function() return db[key] end end
	local function SetChoice(key) return function(value) db[key] = value; ApplySettings() end end
	Gate(On.ProgressOn, AddDropdown(tab, "TEXT_FORMAT", PROGRESS_FORMATS,
		function(value) return L["FORMAT_" .. value] end, Choice("progressFormat"), SetChoice("progressFormat"),
		COL2 + 4, TOP, COLUMN_DROPDOWN))
	-- The font menu also lists fonts shared by other addons, each drawn in its own font.
	Gate(On.ProgressOn, AddDropdown(tab, "TEXT_FONT", FontOptions, FontLabel, Choice("progressFont"), SetChoice("progressFont"),
		COL2 + 4, TOP - 54, COLUMN_DROPDOWN, FontPath))
	Gate(On.ProgressOn, AddDropdown(tab, "TEXT_OUTLINE", { "none", "thin", "thick" },
		function(value) return L["OUTLINE_" .. value] end, Choice("progressOutline"), SetChoice("progressOutline"),
		COL2 + 4, TOP - 108, COLUMN_DROPDOWN))
	Gate(On.ProgressOn, AddDropdown(tab, "TEXT_COLOR", { "white", "gold", "green", "kind", "progress" },
		function(value) return L["COLOR_" .. value] end, Choice("progressColor"), SetChoice("progressColor"),
		COL2 + 4, TOP - 162, COLUMN_DROPDOWN))
	GateCheck(On.ProgressOn, AddCheck(tab, "TEXT_SHADOW", "TEXT_SHADOW_TIP", "progressShadow", COL1, TOP - 244))
	GateCheck(On.ProgressOn, AddCheck(tab, "PROGRESS_PULSE", "PROGRESS_PULSE_TIP", "progressPulse", COL2, TOP - 244))

	-- Attached, the text is glued to the icon: X/Y only apply when it stands on its own.
	local function FreeTextOn() return On.ProgressOn() and not db.progressAttach end
	Gate(FreeTextOn, AddSlider(tab, "POS_X", "progressX", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, TOP - 300, "%d"))
	Gate(FreeTextOn, AddSlider(tab, "POS_Y", "progressY", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, TOP - 300, "%d"))
end

local function BuildIconTab(tab)
	-- Quick themes: one click sets size, float, glow and text size (the icon itself stays).
	local THEMES = {
	classic = { scale = 1.5, objectScale = 1.5, bounce = true, bounceHeight = 7, bounceSpeed = 0.9, glow = false, glowAlpha = 0.55, progressSize = 13 },
	subtle = { scale = 1.0, objectScale = 1.0, bounce = false, glow = false, progressSize = 11 },
	flashy = { scale = 2.0, objectScale = 2.0, bounce = true, bounceHeight = 12, bounceSpeed = 0.7, glow = true, glowAlpha = 0.85, progressSize = 15 },
}
	local THEME_ORDER = { "classic", "subtle", "flashy" }
	AddResetTabButton(tab, function() ResetKeys(ICON_KEYS) end)
	Gate(On.AnyIconOn, AddHeading(tab, "ICON_STYLE", COL1, TOP))
	Gate(On.AnyIconOn, AddIconPicker(tab, COL1 + 4, TOP - 18))
	Gate(On.AnyIconOn, AddDropdown(tab, "QUICK_THEME", THEME_ORDER, function(value) return L["THEME_" .. value] end,
		function() return nil end,
		function(value)
			for key, v in pairs(THEMES[value]) do db[key] = v end
			AfterReset()
		end, COL2 + 4, TOP, COLUMN_DROPDOWN))

	local y = TOP - 82
	GateCheck(On.AnyIconOn, AddSectionCheck(tab, "FLOAT", "bounce", COL1, y))
	Gate(On.FloatOn, AddSlider(tab, "FLOAT_HEIGHT", "bounceHeight", 1, 20, 1, COL1 + 4, y - 22, "%d"))
	Gate(On.FloatOn, AddSlider(tab, "FLOAT_TIME", "bounceSpeed", 0.3, 2.0, 0.05, COL1 + 4, y - 62, "%.2f"))

	GateCheck(On.AnyIconOn, AddSectionCheck(tab, "GLOW_SECTION", "glow", COL2, y))
	Gate(On.GlowOn, AddSlider(tab, "GLOW_INTENSITY", "glowAlpha", 0.1, 1.0, 0.05, COL2 + 4, y - 22, "%.2f"))

	-- Quest items can have a look of their own (icon, float, glow); then the above is for mobs.
	y = y - 112
	GateCheck(On.ItemsOn, AddSectionCheck(tab, "ITEM_LOOK", "objectOwnLook", COL1, y))
	local note = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", COL1 + 26, y - 18)
	note:SetWidth(560)
	note:SetJustifyH("LEFT")
	Gate(On.ItemsOn, Loc(note, "ITEM_LOOK_TIP"))
	Gate(On.ItemLookOn, AddIconPicker(tab, COL1 + 4, y - 50, "objectStyle"))
	GateCheck(On.ItemLookOn, AddCheck(tab, "FLOAT", nil, "objectBounce", COL2, y - 48))
	GateCheck(On.ItemLookOn, AddCheck(tab, "GLOW_SECTION", nil, "objectGlow", COL2, y - 80))
end

local function BuildBehaviorTab(tab)
	AddResetTabButton(tab, function()
		ResetKeys(BEHAVIOR_KEYS)
		root.language = "auto"
		L = BuildLocale("auto")
		Relabel()
	end)
	-- Left: how the icons behave. Right: language and sound.
	GateCheck(On.AnyIconOn, AddCheck(tab, "COLOR_BY_TYPE", "COLOR_BY_TYPE_TIP", "colorByType", COL1, TOP))
	-- The minimap button stays usable with the addon off: it is how you turn it back on.
	AddCheck(tab, "MINIMAP", "MINIMAP_TIP", "minimap", COL1, TOP - 48)
	Gate(On.AnyIconOn, AddDropdown(tab, "IN_COMBAT", { "show", "fade", "hide" },
		function(value) return L["COMBAT_" .. value:upper()] end,
		function() return db.combat end,
		function(value) db.combat = value; UpdateCombatAlpha() end,
		COL1 + 4, TOP - 100, COLUMN_DROPDOWN))
	GateCheck(On.MobsOn, AddCheck(tab, "HIDE_FIGHTING", "HIDE_FIGHTING_TIP", "hideWhileFighting", COL1, TOP - 256))
	GateCheck(On.AnyIconOn, AddCheck(tab, "HIGH_LEVEL", "HIGH_LEVEL_TIP", "highLevelRed", COL1, TOP - 304))

	local languages = { "auto" }
	for _, code in ipairs(ns.LANGUAGES) do languages[#languages + 1] = code end
	AddDropdown(tab, "LANGUAGE", languages,
		function(code) return code == "auto" and L.LANGUAGE_AUTO or ns.LANGUAGE_NAMES[code] end,
		function() return root.language end,
		function(code) root.language = code; L = BuildLocale(code); Relabel() end,
		COL2 + 4, TOP, COLUMN_DROPDOWN)

	-- Sound when an objective completes: on/off, which sound, and a button to hear it.
	local function SoundOn() return On.AddonOn() and db.sound end
	GateCheck(On.AddonOn, AddCheck(tab, "SOUND", "SOUND_TIP", "sound", COL2, TOP - 56))
	Gate(SoundOn, AddDropdown(tab, "SOUND_CHOICE", QUEST_SOUND_ORDER,
		function(value) return L["SOUND_" .. value] end,
		function() return db.soundChoice end,
		function(value) db.soundChoice = value; PlayQuestSound() end,
		COL2 + 4, TOP - 104, 140, nil,
		function(value) PlaySoundAt(QUEST_SOUNDS[value]) end))
	local test = Skin.Button(tab)
	test:SetSize(70, 22)
	test:SetPoint("TOPLEFT", COL2 + 152, TOP - 123)
	Loc(test, "SOUND_TEST")
	test:SetScript("OnClick", PlayQuestSound)
	Gate(SoundOn, test)
	Gate(SoundOn, AddSlider(tab, "SOUND_VOLUME", "soundVolume", 0, 100, 5, COL2 + 4, TOP - 160, "%d"))

	GateCheck(On.AnyIconOn, AddCheck(tab, "DONE_CHECK", "DONE_CHECK_TIP", "doneCheck", COL1, TOP - 160))
	GateCheck(On.AddonOn, AddCheck(tab, "READY_ALERT", "READY_ALERT_TIP", "readyAlert", COL1, TOP - 208))
	GateCheck(function() return db.minimap end,
		AddCheck(tab, "MINIMAP_SUMMARY", "MINIMAP_SUMMARY_TIP", "minimapSummary", COL2, TOP - 210))
	-- Not a switch: icons are always off in instances (the game's limit, see InstanceHidden).
	-- A note with an info icon whose tooltip explains why.
	local info = CreateFrame("Frame", nil, tab)
	info:SetSize(18, 18)
	info:SetPoint("TOPLEFT", COL2 + 12, TOP - 266)
	local disc = info:CreateTexture(nil, "ARTWORK")
	disc:SetAllPoints()
	disc:SetTexture(Skin.CIRCLE)
	disc:SetVertexColor(1, 0.82, 0)
	local letter = info:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	letter:SetPoint("CENTER", 0, 0)
	letter:SetText("i")
	letter:SetTextColor(0.1, 0.08, 0.05)
	local label = info:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", info, "RIGHT", 8, 0)
	Loc(label, "HIDE_INSTANCES")
	info:SetHitRectInsets(0, -260, -4, -4) -- hovering the text shows the tip too
	info:EnableMouse(true)
	info:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.HIDE_INSTANCES, 1, 0.82, 0)
		GameTooltip:AddLine(L.HIDE_INSTANCES_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	info:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Profiles tab in the Ace3 layout players know from RareScanner and many others: intro, reset,
-- current profile, New + Existing profiles, Copy From, Delete a Profile (with a confirmation).
local PROFILE_TEXT_WIDTH = 560
local DELETE_POPUP = "CSCODER_QUESTINDICATOR_DELETE_PROFILE"

local function OtherProfiles()
	local names = {}
	for _, name in ipairs(ProfileNames()) do
		if name ~= ActiveProfileName() then names[#names + 1] = name end
	end
	return names
end

-- Characters on a deleted profile fall back to "Default" (or the first one) on their next login.
local function DeleteProfile(name)
	if not root.profiles[name] or name == ActiveProfileName() then return end
	root.profiles[name] = nil
	for character, profile in pairs(root.chars) do
		if profile == name then root.chars[character] = nil end
	end
	RefreshControls()
end

local function ConfirmDelete(name)
	local popups, show = _G.StaticPopupDialogs, _G.StaticPopup_Show
	if not (popups and show) then DeleteProfile(name) return end
	popups[DELETE_POPUP] = {
		text = L.PROF_DELETE_CONFIRM,
		button1 = _G.YES or "Yes",
		button2 = _G.NO or "No",
		OnAccept = function(_, data) DeleteProfile(data) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	show(DELETE_POPUP, name, nil, name)
end

-- Profile sharing: the active profile as one line of text ("CQI1:key=value;..."), to copy to a
-- friend or another PC, and back. Only known settings of the right type are read back.
local OpenShareWindow
do
	local PREFIX = "CQI1:"
	local function Escape(text) return (text:gsub("[%%;=]", function(c) return string.format("%%%02X", c:byte()) end)) end
	local function Unescape(text) return (text:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

	local function Export()
		local keys = {}
		for key in pairs(DEFAULTS) do keys[#keys + 1] = key end
		table.sort(keys)
		local parts = {}
		for _, key in ipairs(keys) do
			local value = db[key]
			local kind = type(value)
			if kind == "boolean" then parts[#parts + 1] = key .. "=b" .. (value and "1" or "0")
			elseif kind == "number" then parts[#parts + 1] = key .. "=n" .. tostring(value)
			elseif kind == "string" then parts[#parts + 1] = key .. "=s" .. Escape(value) end
		end
		return PREFIX .. table.concat(parts, ";")
	end

	-- Returns how many settings were read, or nil when the text isn't a profile.
	local function Import(text)
		text = (text or ""):match("^%s*(.-)%s*$")
		if text:sub(1, #PREFIX) ~= PREFIX then return nil end
		local read = 0
		for key, kind, value in text:sub(#PREFIX + 1):gmatch("([%w_]+)=(%a)([^;]*)") do
			local default = DEFAULTS[key]
			if kind == "b" and type(default) == "boolean" then db[key] = value == "1"; read = read + 1
			elseif kind == "n" and type(default) == "number" and tonumber(value) then db[key] = tonumber(value); read = read + 1
			elseif kind == "s" and type(default) == "string" then db[key] = Unescape(value); read = read + 1 end
		end
		FillDefaults(db) -- validates styles, anchors and sounds
		return read
	end

	local window, input, title, hint, action
	local function Build()
		local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
		window = CreateFrame("Frame", ADDON .. "Share", UIParent, backdrop)
		window:SetSize(520, 170)
		window:SetPoint("CENTER", 0, 120)
		window:SetFrameStrata("FULLSCREEN_DIALOG")
		window:EnableMouse(true)
		window:SetMovable(true)
		window:RegisterForDrag("LeftButton")
		window:SetScript("OnDragStart", window.StartMoving)
		window:SetScript("OnDragStop", window.StopMovingOrSizing)
		Skin.Window(window, 50)
		if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, window:GetName()) end
		title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 24, -22)
		hint = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
		hint:SetWidth(470)
		hint:SetJustifyH("LEFT")
		input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
		input:SetSize(462, 22)
		input:SetPoint("TOPLEFT", 30, -84)
		input:SetAutoFocus(false)
		input:SetMaxLetters(0)
		input:SetScript("OnEscapePressed", function() window:Hide() end)
		local close = Skin.Button(window)
		close:SetSize(110, 24)
		close:SetPoint("BOTTOMRIGHT", -24, 20)
		Loc(close, "SHARE_CLOSE")
		close:SetScript("OnClick", function() window:Hide() end)
		action = Skin.Button(window)
		action:SetSize(130, 24)
		action:SetPoint("RIGHT", close, "LEFT", -8, 0)
		Loc(action, "SHARE_IMPORT_BUTTON")
		action:SetScript("OnClick", function()
			local read = Import(input:GetText())
			if not read then
				hint:SetText("|cffff5555" .. L.SHARE_BAD .. "|r")
				return
			end
			window:Hide()
			AfterReset()
			print(string.format("|cffffd200%s|r " .. L.SHARE_DONE, TITLE, read, tostring(ActiveProfileName())))
		end)
		window:Hide()
	end

	-- mode: "export" (text ready to copy) or "import" (paste and press Import).
	-- mode: "export" (text ready to copy), "import" (paste and press Import), or "copy" with a
	-- title, a hint and the text to copy (debug report, bug link).
	function OpenShareWindow(mode, copyTitle, copyHint, copyText)
		if not window then Build() end
		local copying = mode ~= "import"
		if mode == "copy" then
			title:SetText(copyTitle)
			hint:SetText(copyHint)
		else
			title:SetText(mode == "export" and L.SHARE_EXPORT_TITLE or L.SHARE_IMPORT_TITLE)
			hint:SetText(mode == "export" and L.SHARE_EXPORT_HINT or string.format(L.SHARE_IMPORT_HINT, tostring(ActiveProfileName())))
		end
		action:SetShown(not copying)
		window:Show()
		input:SetText((mode == "copy" and copyText) or (mode == "export" and Export()) or "")
		input:SetFocus()
		if copying then
			input:SetCursorPosition(0)
			input:HighlightText()
		end
	end
end

-- /cqi debug: one line with what helps to find a problem (versions, client, language, the
-- profile's main switches, the place, other quest/nameplate addons, the last errors of this
-- addon), shown ready to copy.
local BUG_URL = "https://github.com/cscoder69/CSCoder_QuestIndicator/issues"
function ShowDebug()
	local parts = {}
	local function Add(label, value) parts[#parts + 1] = label .. "=" .. tostring(value) end
	Add("addon", AddonVersion())
	if GetBuildInfo then
		local version, build, _, toc = GetBuildInfo()
		Add("client", tostring(version) .. "." .. tostring(build) .. " (" .. tostring(toc) .. ")")
	end
	Add("locale", GetLocale and GetLocale())
	Add("language", root.language)
	Add("profile", ActiveProfileName())
	for _, key in ipairs({ "active", "enabled", "objects", "progress", "objectProgress", "sound", "soundVolume", "style", "anchor" }) do
		Add(key, db[key])
	end
	if IsInInstance then
		local inside, kind = IsInInstance()
		Add("instance", inside and tostring(kind) or "no")
	end
	if C_CVar and C_CVar.GetCVar then
		Add("enemyPlates", C_CVar.GetCVar("nameplateShowEnemies"))
		Add("softInteract", C_CVar.GetCVar("SoftTargetInteract"))
	end
	local plate = root.plateGeom
	Add("plate", plate and string.format("%.0fx%.0f", plate.w or 0, plate.h or 0) or "none")
	local others = {}
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	for _, name in ipairs({ "ForeverLootSparkles", "Questie", "Plater", "TidyPlates", "Kui_Nameplates", "ElvUI", "OneForAll", "pfQuest" }) do
		if isLoaded and isLoaded(name) then others[#others + 1] = name end
	end
	Add("addons", #others > 0 and table.concat(others, ",") or "none")
	local errors = root.lastErrors or {}
	Add("errors", #errors)
	for i = #errors, math.max(1, #errors - 2), -1 do parts[#parts + 1] = "err" .. i .. "=" .. errors[i] end
	OpenShareWindow("copy", L.DEBUG_TITLE, L.DEBUG_HINT, "CQI-DEBUG " .. table.concat(parts, " | "))
end

-- "Report a bug": the issues page, ready to copy.
local function ShowBugLink()
	OpenShareWindow("copy", L.BUG_TITLE, L.BUG_HINT, BUG_URL)
end

local function BuildProfilesTab(tab)
	-- This tab is laid out from the panel's top; the box starts lower in the options window.
	local TOP, LEFT = TOP - 48, LEFT + 20
	local function Desc(key, y)
		local fs = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", LEFT, y)
		fs:SetWidth(PROFILE_TEXT_WIDTH)
		fs:SetJustifyH("LEFT")
		return Loc(fs, key)
	end
	local function Name(name) return name end
	local function Nothing() return nil end

	Desc("PROF_INTRO", TOP)

	Desc("PROF_RESET_DESC", TOP - 24)
	local reset = Skin.Button(tab)
	reset:SetSize(160, 22)
	reset:SetPoint("TOPLEFT", LEFT, TOP - 42)
	Loc(reset, "PROF_RESET")
	reset:SetScript("OnClick", function()
		for key, value in pairs(DEFAULTS) do db[key] = value end
		AfterReset()
	end)

	local current = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	current:SetPoint("TOPLEFT", LEFT, TOP - 80)

	Desc("PROF_CHOOSE_DESC", TOP - 106)
	AddHeading(tab, "PROF_NEW", LEFT, TOP - 126)
	local input = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
	input:SetSize(200, 22)
	input:SetPoint("TOPLEFT", LEFT + 6, TOP - 144)
	input:SetAutoFocus(false)
	input:SetMaxLetters(32)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	input:SetScript("OnEnterPressed", function(self)
		local name = (self:GetText() or ""):match("^%s*(.-)%s*$")
		self:SetText("")
		self:ClearFocus()
		if name == "" then return end
		if not root.profiles[name] then root.profiles[name] = FillDefaults({}) end
		UseProfile(name)
	end)
	AddDropdown(tab, "PROF_CHOOSE", ProfileNames, Name, ActiveProfileName, UseProfile, LEFT + 294, TOP - 126, 220)

	Desc("PROF_COPY_DESC", TOP - 186)
	AddDropdown(tab, "PROF_COPY", OtherProfiles, Name, Nothing, function(name)
		local source = root.profiles[name]
		if not source then return end
		for key in pairs(DEFAULTS) do db[key] = source[key] end
		AfterReset()
	end, LEFT + 4, TOP - 206, 220)

	Desc("PROF_DELETE_DESC", TOP - 266)
	AddDropdown(tab, "PROF_DELETE", OtherProfiles, Name, Nothing, ConfirmDelete, LEFT + 4, TOP - 286, 220)

	Desc("SHARE_DESC", TOP - 346)
	local export = Skin.Button(tab)
	export:SetSize(160, 22)
	export:SetPoint("TOPLEFT", LEFT, TOP - 366)
	Loc(export, "SHARE_EXPORT")
	export:SetScript("OnClick", function() OpenShareWindow("export") end)
	local import = Skin.Button(tab)
	import:SetSize(160, 22)
	import:SetPoint("LEFT", export, "RIGHT", 8, 0)
	Loc(import, "SHARE_IMPORT")
	import:SetScript("OnClick", function() OpenShareWindow("import") end)

	local function Sync()
		current:SetText(L.PROF_CURRENT .. " |cffffffff" .. tostring(ActiveProfileName()) .. "|r")
	end
	refreshers[#refreshers + 1] = Sync
	tab:HookScript("OnShow", Sync)
end

-- All settings on one scrolling page, in sections (Profiles keeps its own tab). Each builder
-- places its controls from (LEFT, TOP) as on a full panel, so a section frame is shifted to put
-- TOP right under its heading.
local SETTINGS_SECTIONS = {
	{ key = "TAB_DISPLAY", build = BuildDisplayTab, height = 258 },
	{ key = "TAB_ICON", build = BuildIconTab, height = 312 },
	{ key = "TAB_PROGRESS", build = BuildProgressTab, height = 340 },
	{ key = "TAB_BEHAVIOR", build = BuildBehaviorTab, height = 388 },
}
local SECTION_GAP = 18
local CONTENT_WIDTH = 600 -- until the scroll frame reports its real width

local function BuildSettingsTab(tab, box)
	local scroll = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -14)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -32, 14)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(CONTENT_WIDTH)
	scroll:SetScrollChild(content)
	-- The page is as wide as the visible area, so headings and lines reach the right edge.
	scroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then content:SetWidth(width) end end)
	settingsScroll = scroll

	local y = 0
	for _, s in ipairs(SETTINGS_SECTIONS) do
		local section = CreateFrame("Frame", nil, content)
		section:SetHeight(1)
		section:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + SECTION_HEADER) - TOP)
		section:SetPoint("RIGHT", content, "RIGHT")
		local heading = section:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		heading:SetPoint("TOPLEFT", section, "TOPLEFT", LEFT, TOP + SECTION_HEADER - 8)
		Loc(heading, s.key)
		local line = section:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 0.82, 0, 0.25)
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", section, "TOPLEFT", LEFT, TOP + 6)
		line:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, TOP + 6)
		s.build(section)
		y = y + SECTION_HEADER + s.height + SECTION_GAP
	end
	content:SetHeight(y)
end

local configWindow -- the options window (the panel lives inside it)

local function BuildConfigWindow()
	local w = CreateFrame("Frame", ADDON .. "Config", UIParent)
	w:SetSize(840, 730)
	w:SetFrameStrata("DIALOG")
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		if x and y then root.windowPos = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	Skin.Window(w, 84)
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, w:GetName()) end -- Esc closes it
	local close = Skin.Close(w)
	close:SetPoint("TOPRIGHT", -18, -18)
	w:SetScript("OnShow", function(self)
		self:ClearAllPoints()
		local pos = root.windowPos
		if pos then self:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else self:SetPoint("CENTER") end
		if PlaySound then pcall(PlaySound, 839) end -- igCharacterInfoOpen
	end)
	w:SetScript("OnHide", function() if PlaySound then pcall(PlaySound, 840) end end) -- igCharacterInfoClose
	w:Hide()
	panel:SetParent(w)
	panel:ClearAllPoints()
	panel:SetAllPoints(w)
	panel:Show()
	return w
end

-- The page under Options > AddOns > CS.Coder > Quest Indicator: a few words and a button that
-- opens the options window.
local function BuildSettingsLanding()
	local page = CreateFrame("Frame")
	page.name = SUBTITLE
	local logo = page:CreateTexture(nil, "ARTWORK")
	logo:SetSize(96, 96)
	logo:SetPoint("TOPLEFT", 16, -16)
	logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icons\\logo")
	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 16, -10)
	title:SetText(TITLE)
	local version = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
	version:SetText(AddonVersion())
	local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(420)
	text:SetJustifyH("LEFT")
	Loc(text, "LANDING_TEXT")
	local open = Skin.Button(page)
	open:SetSize(200, 28)
	open:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
	Loc(open, "LANDING_OPEN")
	open:SetScript("OnClick", function() OpenPanel() end)
	local parent = GetCSCoderParent()
	if Settings and Settings.RegisterCanvasLayoutSubcategory and parent.category then
		settingsCategory = Settings.RegisterCanvasLayoutSubcategory(parent.category, page, SUBTITLE)
	elseif InterfaceOptions_AddCategory then
		page.parent = parent.name
		InterfaceOptions_AddCategory(page)
	end
end

function BuildPanel()
	configWindow = BuildConfigWindow()
	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetSize(52, 52)
	logo:SetPoint("TOPLEFT", 22, -16)
	logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icons\\logo")
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -8)
	header:SetFont(header:GetFont(), 20, "")
	header:SetTextColor(1, 0.93, 0.80)
	header:SetText(TITLE)
	-- Version next to the title (the packager fills it in; a dev copy shows "dev").
	local version = AddonVersion()
	local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	versionText:SetPoint("BOTTOMLEFT", header, "BOTTOMRIGHT", 8, 1)
	versionText:SetText(version)
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", panel, "RIGHT", -190, 0)
	sub:SetJustifyH("LEFT")
	sub:SetTextColor(0.90, 0.68, 0.30)
	Loc(sub, "DESC")

	-- Options box over the whole panel, in the Ace3 tab style players know (BlizzMove and many others):
	-- the game's options-frame tab textures on top of a bordered pane, tabs stretched to fill it.
	local box = CreateFrame("Frame", nil, panel)
	box:SetPoint("TOPLEFT", 22, -128)
	box:SetPoint("BOTTOMRIGHT", -22, 22)
	Skin.Panel(box, { 0.045, 0.045, 0.055, 0.85 }, Skin.RING)

	-- The preview lives in its own small window (movable, closable), so the options get the whole
	-- panel. It opens with the options and closes with them; the Preview button toggles it.
	local window = CreateFrame("Frame", ADDON .. "PreviewWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	window:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		root.previewPos = { point, relativePoint, x, y }
	end)
	Skin.Window(window, 0)
	local close = Skin.Close(window)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() root.previewHidden = true; window:Hide() end)
	local pane = CreateFrame("Frame", nil, window)
	pane:SetPoint("TOPLEFT", 14, -12)
	pane:SetPoint("BOTTOMRIGHT", -14, 14)
	BuildPreview(pane, PREVIEW_WIDTH - 28)
	window:Hide()

	local function PlaceWindow()
		window:ClearAllPoints()
		local pos = root.previewPos
		if pos then
			window:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		else
			window:SetPoint("TOPLEFT", panel, "TOPRIGHT", 12, 0) -- first time: beside the options
		end
	end
	panel:HookScript("OnShow", function()
		if not root.previewHidden then PlaceWindow(); window:Show() end
	end)
	panel:HookScript("OnHide", function() window:Hide() end)

	local toggle = Skin.Button(panel)
	toggle:SetSize(110, 22)
	toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -50, -18)
	Loc(toggle, "PREVIEW")
	local bug = Skin.Button(panel)
	bug:SetSize(130, 22)
	bug:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -6)
	Loc(bug, "BUG_BUTTON")
	bug:SetScript("OnClick", ShowBugLink)
	toggle:SetScript("OnClick", function()
		if window:IsShown() then
			root.previewHidden = true
			window:Hide()
		else
			root.previewHidden = false
			PlaceWindow()
			window:Show()
		end
	end)

	-- Flat tabs: a plate with edges on three sides; the active one is warmer, gold-edged, with
	-- a gold line on top, and covers the box's top line so it joins the page.
	local function TabPieces(tab, active)
		local plate = tab:CreateTexture(nil, "BACKGROUND")
		plate:SetPoint("TOPLEFT")
		plate:SetPoint("BOTTOMRIGHT", 0, active and -1 or 0)
		if active then plate:SetColorTexture(0.21, 0.15, 0.08, 1) else plate:SetColorTexture(0.085, 0.078, 0.066, 1) end
		local edge = active and { 1, 0.80, 0.40, 0.9 } or { 0.36, 0.28, 0.16, 1 }
		local pieces = { plate }
		for _, side in ipairs({ "TOP", "LEFT", "RIGHT" }) do
			local e = tab:CreateTexture(nil, "BORDER")
			e:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
			if side == "TOP" then
				e:SetPoint("TOPLEFT")
				e:SetPoint("TOPRIGHT")
				e:SetHeight(active and 2 or 1)
			else
				e:SetPoint("TOP" .. side)
				e:SetPoint("BOTTOM" .. side)
				e:SetWidth(1)
			end
			pieces[#pieces + 1] = e
		end
		return pieces
	end

	local builders = { BuildSettingsTab, BuildProfilesTab }
	local keys = { "TAB_SETTINGS", "TAB_PROFILES" }
	local tabs, frames = {}, {}
	local selected = 1
	local TAB_GAP = 4
	local tabWidth = 100 -- until LayoutTabs measures the labels

	local function SelectTab(index)
		selected = index
		for i, frame in ipairs(frames) do frame:SetShown(i == index) end
		for i, tab in ipairs(tabs) do
			local isActive = i == index
			for _, piece in ipairs(tab.active) do piece:SetShown(isActive) end
			for _, piece in ipairs(tab.inactive) do piece:SetShown(not isActive) end
			tab.text:SetFontObject("GameFontNormal")
			if isActive then tab.text:SetTextColor(1, 0.90, 0.62) else tab.text:SetTextColor(0.84, 0.80, 0.72) end
			tab.text:ClearAllPoints()
			tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
			if isActive then tab:Disable() else tab:Enable() end
		end
	end

	for i, build in ipairs(builders) do
		local tab = CreateFrame("Button", nil, panel)
		tab:SetSize(tabWidth, 28)
		tab:SetFrameLevel(box:GetFrameLevel() + 5)
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 10, 0)
		else
			tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", TAB_GAP, 0)
		end
		tab.active = TabPieces(tab, true)
		tab.inactive = TabPieces(tab, false)
		tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		Loc(tab.text, keys[i])
		local tabHover = tab:CreateTexture(nil, "HIGHLIGHT")
		tabHover:SetAllPoints()
		tabHover:SetColorTexture(0.90, 0.66, 0.22, 0.10)
		tab:SetScript("OnClick", function()
			if selected ~= i and PlaySound then pcall(PlaySound, 841) end -- igCharacterInfoTab
			SelectTab(i)
		end)
		tabs[i] = tab
		local frame = CreateFrame("Frame", nil, box)
		frame:SetPoint("TOPLEFT", panel, "TOPLEFT")
		frame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
		frames[i] = frame
		build(frame, box)
	end

	-- Each tab is as wide as its label (Ace3 style), so translations never squeeze or cut it.
	function LayoutTabs()
		for _, tab in ipairs(tabs) do
			tab:SetWidth(math.max(90, math.floor(tab.text:GetStringWidth() + 40)))
		end
	end
	LayoutTabs()
	panel:HookScript("OnShow", function() SelectTab(selected) end)
	SelectTab(1)

	BuildSettingsLanding()
end

-- Opens the options window (closing the game's Settings if it sent us here). toggle: a second
-- click closes it (the minimap button).
function OpenPanel(toggle)
	if not configWindow then return end
	if toggle and configWindow:IsShown() then configWindow:Hide() return end
	if _G.SettingsPanel and _G.SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(_G.SettingsPanel) end
	if _G.InterfaceOptionsFrame and _G.InterfaceOptionsFrame:IsShown() and HideUIPanel then HideUIPanel(_G.InterfaceOptionsFrame) end
	configWindow:Show()
	configWindow:Raise()
end

---------------------------------------------------------------------------------------------
-- Setup guide: shown the first time the addon runs on a character (and by /cqi setup).
-- Page 1 greets and offers "Use default settings" or "Configure"; Configure walks through the
-- basics with Back / Next, each page beside a live preview. Its controls are the same as the
-- options panel's, so both stay in sync.
---------------------------------------------------------------------------------------------

do -- (a block of its own: the main chunk is near Lua's 200-locals limit)
local WIZARD_WIDTH, WIZARD_HEIGHT = 860, 480
local wizard

local function MarkSetupSeen()
	root.setupSeen = root.setupSeen or {}
	root.setupSeen[charKey] = true
end

local function AddWizardText(page, titleKey, textKey)
	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 28, -54)
	Loc(title, titleKey)
	local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(400)
	text:SetJustifyH("LEFT")
	text:SetSpacing(2)
	Loc(text, textKey)
end

local function Always() return true end

local function BuildWizard()
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local f = CreateFrame("Frame", ADDON .. "Setup", UIParent, backdrop)
	f:SetSize(WIZARD_WIDTH, WIZARD_HEIGHT)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Skin.Window(f, 44)
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, f:GetName()) end -- Esc closes it
	local header = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT", 24, -20)
	header:SetText(TITLE)
	local close = Skin.Close(f)
	close:SetPoint("TOPRIGHT", -6, -6)
	f:Hide()
	-- However it closes (X, Esc, a button), the guide doesn't come back on its own.
	f:SetScript("OnHide", function()
		MarkSetupSeen()
		if iconPicker then iconPicker:Hide() end
	end)

	-- Live preview on the right of the configure pages.
	local previewPane = CreateFrame("Frame", nil, f)
	previewPane:SetSize(370, 360)
	previewPane:SetPoint("TOPRIGHT", -28, -50)
	BuildPreview(previewPane, 370)

	dropdownHost = f -- the guide's dropdown lists open over the guide, not the hidden panel
	local pages = {}
	local function NewPage()
		local page = CreateFrame("Frame", nil, f)
		page:SetAllPoints()
		page:Hide()
		pages[#pages + 1] = page
		return page
	end

	-- 1. Welcome.
	local welcome = NewPage()
	local logo = welcome:CreateTexture(nil, "ARTWORK")
	logo:SetSize(150, 150)
	logo:SetPoint("TOP", 0, -44)
	logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icons\\logo")
	local hello = welcome:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	hello:SetPoint("TOP", logo, "BOTTOM", 0, -14)
	local greeting = welcome:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	greeting:SetPoint("TOP", hello, "BOTTOM", 0, -12)
	greeting:SetWidth(520)
	greeting:SetSpacing(3)
	Loc(greeting, "WIZ_WELCOME_TEXT")
	local version = welcome:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOMRIGHT", -24, 20)
	version:SetText(AddonVersion())
	local useDefault = Skin.Button(welcome)
	useDefault:SetSize(240, 30)
	useDefault:SetPoint("BOTTOMRIGHT", welcome, "BOTTOM", -8, 40)
	Loc(useDefault, "WIZ_USE_DEFAULT")
	local configure = Skin.Button(welcome)
	configure:SetSize(240, 30)
	configure:SetPoint("BOTTOMLEFT", welcome, "BOTTOM", 8, 40)
	Loc(configure, "WIZ_CONFIGURE")

	-- 2. The icon's whole look on one page: icon, size, side of the plate, X/Y, float, glow.
	local lookPage = NewPage()
	AddWizardText(lookPage, "WIZ_LOOK_TITLE", "WIZ_LOOK_TEXT")
	AddIconPicker(lookPage, 28, -112)
	local lookDefault = Skin.Button(lookPage)
	lookDefault:SetSize(130, 24)
	lookDefault:SetPoint("TOPLEFT", 300, -124)
	Loc(lookDefault, "WIZ_LOOK_DEFAULT")
	lookDefault:SetScript("OnClick", function()
		ResetKeys({ "style", "scale", "anchor", "offsetX", "offset", "bounce", "glow" })
		AfterReset()
	end)
	AddSlider(lookPage, "ICON_SIZE", "scale", 0.5, 3.0, 0.05, 32, -172, "%.2f")
	AddAnchorMenu(lookPage, "anchor", "offsetX", "offset", 32, -216, Always)
	AddSlider(lookPage, "POS_X", "offsetX", -POSITION_RANGE, POSITION_RANGE, 1, 32, -272, "%d")
	AddSlider(lookPage, "POS_Y", "offset", -POSITION_RANGE, POSITION_RANGE, 1, 32, -314, "%d")
	AddCheck(lookPage, "FLOAT", nil, "bounce", 28, -358)
	AddCheck(lookPage, "GLOW_SECTION", nil, "glow", 220, -358)

	-- 3. What to show.
	local showPage = NewPage()
	AddWizardText(showPage, "WIZ_SHOW_TITLE", "WIZ_SHOW_TEXT")
	AddCheck(showPage, "QUEST_MOBS", "WIZ_MOBS_TIP", "enabled", 28, -126)
	AddCheck(showPage, "QUEST_ITEMS", "WIZ_ITEMS_TIP", "objects", 28, -176)
	AddCheck(showPage, "PROGRESS", "PROGRESS_TIP", "progress", 28, -226)
	AddCheck(showPage, "PROGRESS_ITEMS", "PROGRESS_ITEMS_TIP", "objectProgress", 28, -276)
	AddCheck(showPage, "SOUND", "SOUND_TIP", "sound", 28, -326)

	-- 4. Combat and warnings.
	local extraPage = NewPage()
	AddWizardText(extraPage, "WIZ_EXTRA_TITLE", "WIZ_EXTRA_TEXT")
	AddCheck(extraPage, "HIGH_LEVEL", "HIGH_LEVEL_TIP", "highLevelRed", 28, -126)
	AddCheck(extraPage, "HIDE_FIGHTING", "HIDE_FIGHTING_TIP", "hideWhileFighting", 28, -204)

	-- 5. Done.
	local donePage = NewPage()
	AddWizardText(donePage, "WIZ_DONE_TITLE", "WIZ_DONE_TEXT")
	dropdownHost = nil

	-- Footer of the configure pages: step, Back, Next (Finish on the last page).
	local footer = CreateFrame("Frame", nil, f)
	footer:SetAllPoints()
	local step = footer:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	step:SetPoint("BOTTOMLEFT", 28, 26)
	local nextButton = Skin.Button(footer)
	nextButton:SetSize(130, 26)
	nextButton:SetPoint("BOTTOMRIGHT", -24, 20)
	local back = Skin.Button(footer)
	back:SetSize(110, 26)
	back:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)
	Loc(back, "WIZ_BACK")
	local openOptions = Skin.Button(footer)
	openOptions:SetSize(200, 26)
	openOptions:SetPoint("RIGHT", back, "LEFT", -8, 0)
	Loc(openOptions, "WIZ_OPEN_OPTIONS")

	local current = 1
	function f:ShowPage(index)
		current = index
		for i, page in ipairs(pages) do page:SetShown(i == index) end
		local configuring = index > 1
		previewPane:SetShown(configuring)
		footer:SetShown(configuring)
		if iconPicker then iconPicker:Hide() end
		if configuring then
			step:SetText(string.format(L.WIZ_STEP, index - 1, #pages - 1))
			nextButton:SetText(index == #pages and L.WIZ_FINISH or L.WIZ_NEXT)
			openOptions:SetShown(index == #pages)
			UpdatePreview()
		else
			hello:SetText(string.format(L.WIZ_HELLO, UnitName("player") or ""))
		end
	end

	useDefault:SetScript("OnClick", function()
		f:Hide()
		print(string.format(L.WIZ_DEFAULT_DONE, "|cffffd200" .. TITLE .. "|r", "|cff00ff00/cqi|r"))
	end)
	configure:SetScript("OnClick", function() f:ShowPage(2) end)
	back:SetScript("OnClick", function() f:ShowPage(current - 1) end)
	nextButton:SetScript("OnClick", function()
		if current < #pages then f:ShowPage(current + 1) else f:Hide() end
	end)
	openOptions:SetScript("OnClick", function()
		f:Hide()
		OpenPanel()
	end)
	return f
end

function ShowWizard()
	wizard = wizard or BuildWizard()
	RefreshControls()
	wizard:Show()
	wizard:ShowPage(1)
end
end

-- "What's new": shown once after an update (not on a fresh install, which gets the setup
-- guide), and by /cqi news. The text is NEWS_TEXT in Locales.lua: update it for each release.
do
	local news
	function ShowNews()
		if not news then
			local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
			news = CreateFrame("Frame", ADDON .. "News", UIParent, backdrop)
			news:SetSize(540, 450)
			news:SetPoint("CENTER", 0, 60)
			news:SetFrameStrata("DIALOG")
			news:EnableMouse(true)
			news:SetMovable(true)
			news:RegisterForDrag("LeftButton")
			news:SetScript("OnDragStart", news.StartMoving)
			news:SetScript("OnDragStop", news.StopMovingOrSizing)
			Skin.Window(news, 92)
			if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, news:GetName()) end
			local logo = news:CreateTexture(nil, "ARTWORK")
			logo:SetSize(64, 64)
			logo:SetPoint("TOPLEFT", 22, -20)
			logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\icons\\logo")
			news.title = news:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
			news.title:SetPoint("LEFT", logo, "RIGHT", 12, 8)
			local sub = news:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			sub:SetPoint("TOPLEFT", news.title, "BOTTOMLEFT", 0, -4)
			sub:SetText(TITLE)
			local body = news:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			body:SetPoint("TOPLEFT", 28, -100)
			body:SetWidth(484)
			body:SetJustifyH("LEFT")
			body:SetSpacing(4)
			Loc(body, "NEWS_TEXT")
			local ok = Skin.Button(news)
			ok:SetSize(120, 26)
			ok:SetPoint("BOTTOM", 0, 20)
			Loc(ok, "NEWS_OK")
			ok:SetScript("OnClick", function() news:Hide() end)
			local close = Skin.Close(news)
			close:SetPoint("TOPRIGHT", -6, -6)
		end
		news.title:SetText(string.format(L.NEWS_TITLE, AddonVersion()))
		news:Show()
	end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------

end -- options window, setup guide, what's new

-- Measures a real enemy nameplate (size, effective scale, health bar) for the preview. Saved, so
-- the preview is right even before a plate shows up in a new session.
local plateMeasured = false
local MeasurePlate
do -- (own block: keeps the helpers out of the main chunk, near the 200-locals limit)

-- The game shrinks far plates and enlarges the target's (it scales the plate or its UnitFrame),
-- and a plate is often first seen far away: those scales are taken out, so the saved size is
-- the plate at its normal, close-range scale. force = measure again (for /cqi plate).
-- Nameplates are restricted regions: some clients refuse to measure them (GetTop and friends
-- raise "Can't measure restricted regions"), so every read is protected.
local function Read(obj, method)
	if not (obj and obj[method]) then return end
	local ok, a, b = pcall(obj[method], obj)
	if ok then return a, b end
end

-- Where a point sits from the top of a region of height h ("TOPLEFT" 0, "LEFT" h/2, "BOTTOM" h).
local function PointDepth(point, h)
	if point:find("TOP") then return 0 elseif point:find("BOTTOM") then return h end
	return h / 2
end

-- How far below the top of the plate a region's top is, following its anchors (bar -> container
-- -> UnitFrame -> plate) when positions can't be measured. Assumes one scale along the chain.
local function TopFromAnchors(region, plate, frame, depth)
	if region == plate or region == frame then return 0 end
	if depth > 4 then return end
	local h = select(2, Read(region, "GetSize"))
	local ok, count = pcall(region.GetNumPoints, region)
	if not (h and ok and type(count) == "number") then return end
	for i = 1, count do
		local ok2, point, rel, relPoint, _, y = pcall(region.GetPoint, region, i)
		if ok2 and type(point) == "string" and type(relPoint) == "string" and rel then
			local relTop = TopFromAnchors(rel, plate, frame, depth + 1)
			local relH = select(2, Read(rel, "GetSize"))
			if relTop and relH then
				return relTop + PointDepth(relPoint, relH) - (y or 0) - PointDepth(point, h)
			end
		end
	end
end

function MeasurePlate(unit, force)
	if (plateMeasured and not force) or not (root and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	local plate = UsablePlate(unit)
	if not plate or (IsInInstance and IsInInstance()) then return end -- measured in the open world only
	local w, h = Read(plate, "GetSize")
	local eff = Read(plate, "GetEffectiveScale")
	if not (w and h and eff) or w <= 0 or h <= 0 then return end
	local plateScale = Read(plate, "GetScale") or 1
	local frame = plate.UnitFrame
	local frameScale = Read(frame, "GetScale") or 1
	local geom = { w = w, h = h, eff = eff / plateScale, plateScale = plateScale, frameScale = frameScale }
	local bar = frame and (frame.healthBar or frame.HealthBar
		or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))
	local bw, bh = Read(bar, "GetSize")
	local barEff = Read(bar, "GetEffectiveScale")
	if bw and bh and barEff then
		local unitScale = eff * frameScale -- screen pixels per base plate unit, inside the UnitFrame
		geom.barW, geom.barH = bw * barEff / unitScale, bh * barEff / unitScale
		local plateTop, barTop = Read(plate, "GetTop"), Read(bar, "GetTop")
		if plateTop and barTop then
			geom.barTop = (plateTop * eff - barTop * barEff) / unitScale
		else
			geom.barTop = TopFromAnchors(bar, plate, frame, 0) -- positions are restricted here
		end
		if not geom.barTop then
			-- Even anchors are restricted (WoW Forever): assume the bar sits in the middle of the plate.
			geom.barTop, geom.barGuess = (h / frameScale - geom.barH) / 2, true
		end
		-- What the bar hangs from, for /cqi plate.
		local ok, point, rel, relPoint, x, y = pcall(bar.GetPoint, bar, 1)
		if ok and point then
			local relName = rel == plate and "plate" or rel == frame and "UnitFrame"
				or (rel and Read(rel, "GetDebugName")) or (rel and Read(rel, "GetName")) or tostring(rel)
			geom.barAnchor = string.format("%s -> %s %s (%s, %s)", tostring(point), tostring(relName), tostring(relPoint), tostring(x), tostring(y))
		end
	end
	root.plateGeom = geom
	plateMeasured = true
	if UpdatePreview then UpdatePreview() end
	return geom
end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("QUEST_LOG_UPDATE")
-- Only the player's own quest log: party members' changes would rebuild it for nothing.
if events.RegisterUnitEvent then
	events:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
else
	events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
end
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "PLAYER_SOFT_INTERACT_CHANGED")
pcall(events.RegisterEvent, events, "CVAR_UPDATE")
pcall(events.RegisterEvent, events, "UNIT_THREAT_LIST_UPDATE") -- "hide while fighting it"
pcall(events.RegisterEvent, events, "PLAYER_LEVEL_UP") -- "warn about high-level quests"

-- Work that events ask for in bursts is done once, a moment later. The game fires
-- QUEST_LOG_UPDATE several times per kill, loot or accept, and nameplates come and go in
-- groups: one quest log rebuild and one quest item check per burst instead of one per event.
-- (0.1 s stays well inside the 3 s window of the check mark.)
local later = { questLog = false, soft = false, measure = false }
local function FlushQuestLog()
	later.questLog = false
	if not db then return end
	RebuildQuestTitles(); RebuildObjectiveTexts()
	RefreshAll()
end
local function FlushSoft()
	later.soft = false
	if db then RefreshSoftObject() end
end
local function QueueSoft()
	if later.soft then return end
	later.soft = true
	C_Timer.After(0, FlushSoft)
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		LoadSavedVariables()
		L = BuildLocale(root.language)
		BuildPanel()
		if geterrorhandler and seterrorhandler then
			local previous = geterrorhandler()
			seterrorhandler(function(message, ...)
				if type(message) == "string" and message:find(ADDON, 1, true) then
					root.lastErrors = root.lastErrors or {}
					local line = (date and date("%H:%M ") or "") .. message:gsub("[\r\n|]+", " "):sub(1, 300)
					table.insert(root.lastErrors, line)
					while #root.lastErrors > 10 do table.remove(root.lastErrors, 1) end
				end
				if previous then return previous(message, ...) end
			end)
		end
		return
	end
	if not db then return end
	if event == "NAME_PLATE_UNIT_ADDED" then
		if arg1 ~= SOFT then
			Refresh(arg1)
			-- Enemy plates are what the preview imitates; measure one per session once it is laid
			-- out (one at a time, and never inside instances, where plates can't be measured).
			if not plateMeasured and not later.measure and not (IsInInstance and IsInInstance())
				and UnitCanAttack and UnitCanAttack("player", arg1) then
				later.measure = true
				local unit = arg1
				C_Timer.After(0.2, function() later.measure = false; MeasurePlate(unit) end)
			end
		end
		QueueSoft()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		HideIcon(arg1)
		QueueSoft()
	elseif event == "PLAYER_LOGIN" then
		ResolveCharacter() -- the character name is certain by now
		if root.dialogVolume ~= nil and C_CVar and C_CVar.SetCVar then
			pcall(C_CVar.SetCVar, "Sound_DialogVolume", root.dialogVolume)
			root.dialogVolume = nil
		end
		print(string.format(L.WELCOME, "|cffffd200" .. TITLE .. "|r", AddonVersion(), "|cff00ff00/cqi|r"))
		-- First time on this character: the setup guide, once the loading screen is gone.
		-- After an update: what's new, once (not in a dev copy, whose version is "dev").
		local version = AddonVersion()
		if not root.setupSeen[charKey] then
			C_Timer.After(3, function()
				if not root.setupSeen[charKey] then ShowWizard() end
			end)
		elseif version ~= "dev" and root.lastVersion ~= version then -- (nil: updated from 1.2.0 or older)
			C_Timer.After(3, ShowNews)
		end
		if version ~= "dev" then root.lastVersion = version end
		RebuildQuestTitles(); RebuildObjectiveTexts()
		RefreshControls()
		ApplySettings()
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		QueueSoft()
	elseif event == "CVAR_UPDATE" then
		-- Another addon changed a cvar we need: take it back next frame. Our own writes are
		-- ignored, several changes at once make one re-apply, and after 20 re-applies within
		-- 10 s we stop fighting (two addons undoing each other would loop forever).
		if cvarGuard.writing or cvarGuard.queued or not ObjectsOn() then return end
		if type(arg1) ~= "string" or not WATCHED_CVARS[arg1:lower()] then return end
		local now = GetTime()
		if now - cvarGuard.since > 10 then cvarGuard.since, cvarGuard.recent = now, 0 end
		cvarGuard.recent = cvarGuard.recent + 1
		if cvarGuard.recent > 20 then return end
		cvarGuard.queued = true
		C_Timer.After(0, function()
			cvarGuard.queued = false
			if ObjectsOn() then EnableObjectNameplates(); RefreshSoftObject() end
		end)
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
		UpdateCombatAlpha()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		UpdateCombatAlpha()
		local pending = pendingCVars
		pendingCVars = nil
		if pending == "apply" and ObjectsOn() then EnableObjectNameplates()
		elseif pending == "restore" and not ObjectsOn() then RestoreObjectCVars() end
		RefreshAll() -- (also brings back icons hidden while fighting a mob that survived)
	elseif event == "PLAYER_LEVEL_UP" then
		-- Quests above you are now closer: restyle the icons for the level alert (a moment
		-- later, so UnitLevel already reports the new level).
		C_Timer.After(1, ApplyLook)
	elseif event == "UNIT_THREAT_LIST_UPDATE" then
		-- A mob started or stopped fighting you: hide or bring back its icon right away.
		if db.hideWhileFighting and type(arg1) == "string" and arg1:find("^nameplate") then Refresh(arg1) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- New zone or instance: rebuild now (instances switch every icon off).
		FlushQuestLog()
	elseif not later.questLog then -- QUEST_LOG_UPDATE, UNIT_QUEST_LOG_CHANGED
		later.questLog = true
		C_Timer.After(0.1, FlushQuestLog)
	end
end)

-- Light periodic recheck: objectives finish, tooltips load late, mobs die. With the addon
-- switched off there is nothing to check (one last pass clears what is left).
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < RECHECK_SECONDS or not db then return end
	elapsed = 0
	if not db.active and not next(icons) then return end
	RefreshAll()
end)

---------------------------------------------------------------------------------------------
-- Slash command: /cqi opens the options, /cqi toggle turns the mob icons on or off
---------------------------------------------------------------------------------------------

SLASH_CSCODERQUESTINDICATOR1 = "/cqi"
SlashCmdList.CSCODERQUESTINDICATOR = function(msg)
	local cmd = (msg or ""):lower():match("^(%S*)")
	if cmd == "toggle" then
		db.active = not db.active
		ApplySettings()
		RefreshControls()
		print("|cffffd200" .. TITLE .. "|r " .. (db.active and L.ON or L.OFF))
	elseif cmd == "setup" then
		ShowWizard()
	elseif cmd == "news" then
		ShowNews()
	elseif cmd == "debug" then
		ShowDebug()
	elseif cmd == "plate" then
		-- Measures the target's nameplate for the preview and prints what was found.
		-- Protected: an error here would leave the text stuck in the chat box.
		local ok, geom = pcall(function() return UnitExists("target") and MeasurePlate("target", true) end)
		if not ok then
			print("|cffffd200" .. TITLE .. "|r plate error: " .. tostring(geom))
			return
		end
		if not geom then
			print("|cffffd200" .. TITLE .. "|r target an enemy with a visible nameplate, then /cqi plate")
			return
		end
		local function n(v) return tonumber(v) or 0 end
		print(string.format("|cffffd200%s|r plate %.0fx%.0f, base scale %.2f (plate x%.2f, frame x%.2f), bar %s",
			TITLE, n(geom.w), n(geom.h), n(geom.eff), n(geom.plateScale), n(geom.frameScale),
			geom.barW and string.format("%.0fx%.0f at %s from the top", n(geom.barW), n(geom.barH),
				geom.barTop and string.format(geom.barGuess and "~%.0f (estimated)" or "%.0f", geom.barTop) or "?") or "not found"))
		if geom.barAnchor then print("|cffffd200" .. TITLE .. "|r bar anchor: " .. geom.barAnchor) end
	else
		OpenPanel()
	end
end
