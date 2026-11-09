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
	style = "gold",      -- icon style (file in icons\)
	scale = 1.5,         -- mob icon size
	offsetX = 0,         -- mob icon X
	offset = -15,        -- mob icon Y (above the nameplate)
	objectScale = 1.5,   -- object icon size
	objectOffsetX = 0,   -- object icon X
	objectOffset = 10,   -- object icon Y (above the object)
	progress = true,     -- objective count ("8/12") on quest mobs
	progressAttach = true, -- true: X/Y from the icon (follows it); false: X/Y from the nameplate
	progressFloat = true,  -- bobs up and down with the icon (when the icon floats)
	progressSize = 13,   -- its font size
	progressFont = "friz",     -- key in TEXT_FONTS
	progressOutline = "thin",  -- "none", "thin", "thick"
	progressColor = "white",   -- "white", "gold", "green" or "kind" (same colour as the icon)
	progressX = 36,      -- its X
	progressY = 0,       -- its Y
	bounce = true,       -- floating up/down animation
	bounceHeight = 7,    -- how far it floats (pixels)
	bounceSpeed = 0.9,   -- seconds for one move up (lower = faster)
	glow = false,        -- glowing star behind the icon
	glowAlpha = 0.55,    -- glow intensity
	colorByType = true,  -- daily/repeatable in blue, group/elite in red
	combat = "show",     -- "show", "fade" or "hide" the icons in combat
	minimap = true,      -- minimap button
	minimapAngle = 220,  -- its position around the minimap (degrees)
	sound = true,        -- play a sound when a quest objective completes
	soundChoice = "quest", -- key in QUEST_SOUNDS
}
-- Saved layout: CSCoderQuestIndicatorDB = { version, language, profiles = { name = settings },
-- chars = { "Name - Realm" = profile name }, savedCVars }.
local SETTINGS_VERSION = 5
local DEFAULT_PROFILE = "Default"

local ICON_DIR = "Interface\\AddOns\\CSCoder_QuestIndicator\\icons\\"
local ICON_STYLES = { "gold", "blue", "red", "badge", "pixel" }
local GLOW_TEXTURE = "Interface\\Cooldown\\star4"
local RECHECK_SECONDS = 1.0 -- tooltip data can arrive a moment after the plate appears
local SOFT = "softinteract"  -- the game's interaction soft target (one world object)
local FADE_ALPHA = 0.35
local KIND_TINT = { daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 } }
local KIND_STYLE = { daily = "blue", group = "red" }
-- Progress text formatting: the fonts every client ships, outlines and colours.
local TEXT_FONTS = { friz = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF", skurri = "Fonts\\skurri.ttf", morpheus = "Fonts\\MORPHEUS.TTF" }
local TEXT_FONT_ORDER = { "friz", "arial", "skurri", "morpheus" }
local TEXT_OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local TEXT_COLORS = { white = { 1, 1, 1 }, gold = { 1, 0.82, 0 }, green = { 0.3, 1, 0.3 } }
local KIND_TEXT_COLOR = { normal = { 1, 0.82, 0 }, daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 } }
local POSITION_RANGE = 200 -- X/Y sliders go from -200 to 200

local root, db, charKey  -- saved variables, active profile, "Name - Realm"
local L                   -- active language table
local icons = {}          -- unit token -> icon frame
local pool = {}           -- recycled icon frames
local activeTitles = {}   -- quest title -> kind ("normal", "daily", "group")
local kindByQuestID = {}  -- questID -> kind
local inCombat = false

-- Quest objects need both the master switch and their own option.
local function ObjectsOn() return db.active and db.objects end
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
	wipe(activeTitles)
	wipe(kindByQuestID)
	local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
		or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local title, isHeader, questID, kind = nil, nil, nil, "normal"
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info then
				title, isHeader, questID = info.title, info.isHeader, info.questID
				if (tonumber(info.frequency) or 0) > 0 then
					kind = "daily"
				elseif (tonumber(info.suggestedGroup) or 0) > 1 then
					kind = "group"
				end
			end
		elseif GetQuestLogTitle then
			local t, _, tag, header, _, _, frequency, id = GetQuestLogTitle(i)
			title, isHeader, questID = t, header, id
			if frequency == true or (tonumber(frequency) or 0) > 0 then
				kind = "daily"
			elseif (type(tag) == "number" and tag > 1) or (type(tag) == "string" and tag ~= "") then
				kind = "group"
			end
		end
		if title and not isHeader then
			if kind == "normal" then kind = KindFromTag(questID) or kind end
			activeTitles[title] = kind
			if questID then kindByQuestID[questID] = kind end
		end
	end
end

local function KindOf(title)
	return (title and activeTitles[title]) or "normal"
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

-- Reads tooltip lines (TooltipInfo data or plain strings) and answers: true = still needed,
-- false = quest-related but finished, nil = not quest-related. Then the quest title and the
-- progress of the first unfinished objective ("3/10"), when there is one.
local function QuestStateFromLines(lines)
	local lineTypes = Enum and Enum.TooltipDataLineType
	local objectiveType = lineTypes and lineTypes.QuestObjective
	local titleType = lineTypes and lineTypes.QuestTitle
	local sawQuest, title = false, nil
	for _, line in ipairs(lines) do
		local text = type(line) == "table" and (line.leftText or "") or line
		local lineType = type(line) == "table" and line.type or nil
		if objectiveType and lineType == objectiveType then
			sawQuest = true
			if line.completed == false then return true, title, ProgressText(text) end
			if line.completed == nil and ProgressUnfinished(text) then return true, title, ProgressText(text) end
		elseif (titleType and lineType == titleType) or activeTitles[text] then
			sawQuest, title = true, text
		elseif sawQuest and ProgressUnfinished(text) then
			return true, title, ProgressText(text)
		end
	end
	if sawQuest then return false, title end
	return nil
end

local function ByTooltipInfo(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local data = C_TooltipInfo.GetUnit(unit)
	if not (data and data.lines) then return nil end
	return QuestStateFromLines(data.lines)
end

local scanner = CreateFrame("GameTooltip", ADDON .. "Scanner", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function ByTooltipScan(unit)
	scanner:ClearLines()
	scanner:SetUnit(unit)
	local lines = {}
	for i = 2, scanner:NumLines() do
		local fs = _G[ADDON .. "ScannerTextLeft" .. i]
		lines[#lines + 1] = fs and fs:GetText() or ""
	end
	local state, title, progress = QuestStateFromLines(lines)
	return state == true, title, progress
end

-- Returns: still needed?, quest kind, progress text.
local function IsQuestMob(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
	if UnitIsFriend("player", unit) and not UnitCanAttack("player", unit) then return false end
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
		if ok and related ~= nil then
			if not related then return false end
			local state, title, progress = ByTooltipInfo(unit)
			if state == false then return false end
			return true, KindOf(title), progress
		end
	end
	local state, title, progress = ByTooltipInfo(unit)
	if state ~= nil then return state, KindOf(title), progress end
	local scanned, scannedTitle, scannedProgress = ByTooltipScan(unit)
	return scanned, KindOf(scannedTitle), scannedProgress
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
local ATTACH_GAP = 2
local function PlaceText(f, wave)
	local text, label = f.text, f.text.label
	local lift = wave * db.bounceHeight * (f.isObject and db.objectScale or db.scale)
	text:ClearAllPoints()
	label:ClearAllPoints()
	if db.progressAttach then
		label:SetPoint("LEFT")
		text:SetPoint("LEFT", f, "RIGHT", ATTACH_GAP, lift)
	else
		label:SetPoint("CENTER")
		text:SetPoint("CENTER", f.plate or f:GetParent(), "TOP", db.progressX, db.progressY + lift)
	end
end

local function StyleIcon(f)
	-- Texture and tint: with "color by quest type" the coloured styles swap to blue/red and the
	-- others are tinted.
	local style, tint = db.style, nil
	local kind = f.kind or "normal"
	if db.colorByType and KIND_STYLE[kind] then
		if style == "gold" or style == "blue" or style == "red" then
			style = KIND_STYLE[kind]
		else
			tint = KIND_TINT[kind]
		end
	end
	f.icon:SetTexture(ICON_DIR .. style)
	if tint then f.icon:SetVertexColor(tint[1], tint[2], tint[3]) else f.icon:SetVertexColor(1, 1, 1) end

	local scale = f.isObject and db.objectScale or db.scale
	f:SetScale(scale * (f.previewRatio or 1))
	f:SetAlpha(f.isPreview and 1 or CombatAlpha())

	-- Progress text ("8/12", quest mobs only). It has its own size and position: the frame undoes
	-- the icon's scale, so its size and X/Y don't change with the icon size.
	local text = f.text
	local showText = db.progress and not f.isObject and f.progressValue ~= nil
	text:SetShown(showText)
	if showText then
		local font = TEXT_FONTS[db.progressFont] or TEXT_FONTS.friz
		text.label:SetFont(font, db.progressSize, TEXT_OUTLINES[db.progressOutline] or "OUTLINE")
		-- "Icon colour" follows the quest type like the icon does (gold, blue daily, red group).
		local color = TEXT_COLORS[db.progressColor]
		if db.progressColor == "kind" then
			color = db.colorByType and KIND_TEXT_COLOR[f.kind or "normal"] or KIND_TEXT_COLOR.normal
		end
		color = color or TEXT_COLORS.white
		text.label:SetTextColor(color[1], color[2], color[3])
		text.label:SetText(f.progressValue)
		text:SetScale(1 / scale)
		PlaceText(f, 0)
	end

	f.glow:SetVertexColor(1, 0.82, 0.2, db.glowAlpha)
	f.glow:SetShown(db.glow)
	if db.glow then
		if not f.pulse:IsPlaying() then f.pulse:Play() end
	else
		f.pulse:Stop()
	end

	-- The float itself is driven by the bobber below; without it the icon rests at the bottom.
	if not db.bounce then f.inner:SetPoint("CENTER", f, "CENTER", 0, 0) end
end

local function AnchorIcon(f, plate)
	f:ClearAllPoints()
	if f.isObject then
		f:SetPoint("BOTTOM", plate, "TOP", db.objectOffsetX, db.objectOffset)
	else
		f:SetPoint("BOTTOM", plate, "TOP", db.offsetX, db.offset)
	end
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
	return f
end

local function ShowIcon(unit, plate, kind, progress)
	kind = kind or "normal"
	local f = icons[unit]
	if f then
		if f.kind ~= kind or f.progressValue ~= progress then
			f.kind, f.progressValue = kind, progress
			StyleIcon(f)
		end
		return
	end
	f = table.remove(pool) or CreateIcon()
	icons[unit] = f
	f.unit, f.isObject, f.kind, f.progressValue = unit, unit == SOFT, kind, progress
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
	f:Hide()
	f:SetParent(UIParent)
	f.unit, f.progressValue = nil, nil
	f.text:Hide()
	table.insert(pool, f)
end

local function UpdateCombatAlpha()
	local alpha = CombatAlpha()
	for _, f in pairs(icons) do f:SetAlpha(alpha) end
end

local function Refresh(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if db.active and db.enabled and plate then
		local needed, kind, progress = IsQuestMob(unit)
		if needed then ShowIcon(unit, plate, kind, progress) return end
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
		if not C_NamePlate.GetNamePlateForUnit(unit) then HideIcon(unit) end
	end
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

local objectiveTexts = {} -- { text = lower case objective, kind = quest kind }
local objectiveStates = {} -- questID -> { [objective index] = finished }, to hear one complete

-- Sounds for "objective complete": sound kit IDs that every client has.
local QUEST_SOUNDS = { quest = 878, ping = 3175, ready = 8960, warning = 8959, levelup = 888 }
local QUEST_SOUND_ORDER = { "quest", "ping", "ready", "warning", "levelup" }

local function PlayQuestSound()
	local id = QUEST_SOUNDS[db.soundChoice] or QUEST_SOUNDS.quest
	if PlaySound then pcall(PlaySound, id, "Master") end
end

local function RebuildObjectiveTexts()
	wipe(objectiveTexts)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
	-- An objective that was unfinished on the last scan and is finished now plays the sound
	-- (once per scan). Quests seen for the first time (login, just accepted) stay silent.
	local states, completed = {}, false
	local count = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local questID = C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)
		if not questID and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			questID = info and not info.isHeader and info.questID
		end
		local objectives = questID and C_QuestLog.GetQuestObjectives(questID)
		for index, objective in ipairs(objectives or {}) do
			if objective.text and not objective.finished then
				objectiveTexts[#objectiveTexts + 1] = { text = objective.text:lower(), kind = kindByQuestID[questID] or "normal" }
			end
			local finished = objective.finished and true or false
			states[questID] = states[questID] or {}
			states[questID][index] = finished
			local before = objectiveStates[questID] and objectiveStates[questID][index]
			if finished and before == false then completed = true end
		end
	end
	objectiveStates = states
	if completed and db.active and db.sound then PlayQuestSound() end
end

local function ObjectiveKindForName(name)
	if not name or name == "" then return nil end
	name = name:lower()
	for _, objective in ipairs(objectiveTexts) do
		if objective.text:find(name, 1, true) then return objective.kind end
	end
	return nil
end

-- Returns: still needed?, quest kind.
local function IsQuestObject(unit)
	if not (UnitIsGameObject and UnitIsGameObject(unit)) then return false end
	local state, title = ByTooltipInfo(unit)
	if state ~= nil then return state, KindOf(title) end
	local kind = ObjectiveKindForName(UnitName(unit))
	return kind ~= nil, kind
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
local gateOpenedByUs = false

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
	pcall(C_CVar.SetCVar, name, value)
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
	if gateOpenedByUs then gateOpenedByUs = false; SetCV(GATE_CVAR, 0) end
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
			gateOpenedByUs = true
		end
	elseif gateOpenedByUs then
		gateOpenedByUs = false
		local othersWantIt = IsLoaded("ForeverLootSparkles") and UnitExists(SOFT)
			and ((UnitIsGameObject and UnitIsGameObject(SOFT)) or UnitIsDead(SOFT))
		if not othersWantIt then SetCV(GATE_CVAR, 0) end
	end
end

function RefreshSoftObject()
	if not ObjectsOn() then
		UpdateGate(false)
		HideIcon(SOFT)
		return
	end
	local isQuest, kind = false, nil
	if UnitExists(SOFT) then isQuest, kind = IsQuestObject(SOFT) end
	UpdateGate(isQuest)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(SOFT)
	if isQuest and plate then
		if icons[SOFT] and icons[SOFT]:GetParent() ~= plate then HideIcon(SOFT) end
		ShowIcon(SOFT, plate, kind)
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
	CSCoderQuestIndicatorDB = CSCoderQuestIndicatorDB or {}
	root = CSCoderQuestIndicatorDB
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

local function AddHeading(parent, key, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	return Loc(fs, key)
end

local function AddCheck(parent, labelKey, tipKey, settingKey, x, y)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", x, y)
	local text = check.Text or check.text
	if not text then
		text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 4, 0)
	end
	Loc(text, labelKey)
	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 4)
	note:SetWidth(268)
	note:SetJustifyH("LEFT")
	if tipKey then Loc(note, tipKey) end
	local function Sync() check:SetChecked(db[settingKey]) end
	refreshers[#refreshers + 1] = Sync
	check:SetScript("OnShow", Sync)
	check:SetScript("OnClick", function(self)
		db[settingKey] = self:GetChecked() and true or false
		ApplySettings()
	end)
	check.labelFS, check.noteFS = text, note
	return check
end

-- Up to 2 decimals, trailing zeros dropped ("12", "1,5", "1,25"), with the decimal comma in
-- every panel language except English.
local function FormatNumber(value)
	local text = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
	if text == "-0" then text = "0" end
	local lang = root and root.language
	if lang == nil or lang == "auto" then lang = GetLocale() end
	if lang ~= "enUS" and lang ~= "enGB" then text = text:gsub("%.", ",") end
	return text
end

local function AddSlider(parent, labelKey, settingKey, low, high, step, x, y, format)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", x, y)
	local slider = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	slider:SetSize(240, 16)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	if slider.SetBackdrop then
		slider:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
	end
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
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
		input:SetText(FormatNumber(value))
		input:SetCursorPosition(0)
	end
	input:SetScript("OnShow", function() ShowValue(db[settingKey]) end)
	local function UpdateLabel(value)
		title:SetText(L[labelKey])
		ShowValue(value)
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
				ApplySettings()
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
		ApplySettings()
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
local openList -- the dropdown list currently open, if any

local function AddDropdown(parent, labelKey, options, labelFor, get, set, x, y, width)
	width = width or 240
	local heading = AddHeading(parent, labelKey, x, y)
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local button = CreateFrame("Button", nil, parent, backdrop)
	button:SetSize(width, 24)
	button:SetPoint("TOPLEFT", x, y - 18)
	if button.SetBackdrop then
		button:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		button:SetBackdropColor(0, 0, 0, 0.6)
		button:SetBackdropBorderColor(0.5, 0.5, 0.5)
	end
	local value = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	value:SetPoint("LEFT", 10, 0)
	value:SetPoint("RIGHT", -26, 0)
	value:SetJustifyH("LEFT")
	local arrow = button:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	arrow:SetSize(22, 22)
	arrow:SetPoint("RIGHT", -2, 0)
	button:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
	button:GetHighlightTexture():SetAlpha(0.2)

	-- The list lives on the panel, not under the button: inside the scrolling page it would be
	-- cut off at the bottom of the view.
	local list = CreateFrame("Frame", nil, panel, backdrop)
	list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 2)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	if list.SetBackdrop then
		list:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
		list:SetBackdropBorderColor(0.6, 0.6, 0.6)
	end
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
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnClick", function(self)
			list:Hide()
			set(self.option)
			Sync()
		end)
		rows[i] = row
		return row
	end
	function Sync()
		local current = get()
		local items = type(options) == "function" and options() or options
		value:SetText(current ~= nil and labelFor(current) or "")
		for i, option in ipairs(items) do
			local row = rows[i] or MakeRow(i)
			row.option = option
			row.text:SetText(labelFor(option))
			row.check:SetShown(option == current)
			row:Show()
		end
		for i = #items + 1, #rows do rows[i]:Hide() end
		list:SetSize(width, math.max(1, #items) * DROPDOWN_ROW + 10)
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
	return button, heading
end

-- Row of clickable icon previews; the selected one gets a highlight frame.
local function AddStylePicker(parent, x, y)
	local buttons = {}
	local function Sync()
		for _, b in ipairs(buttons) do b.selected:SetShown(b.styleKey == db.style) end
	end
	for i, key in ipairs(ICON_STYLES) do
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(40, 40)
		b:SetPoint("TOPLEFT", x + (i - 1) * 48, y)
		b.styleKey = key
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.35)
		local tex = b:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("TOPLEFT", 4, -4)
		tex:SetPoint("BOTTOMRIGHT", -4, 4)
		tex:SetTexture(ICON_DIR .. key)
		b.selected = b:CreateTexture(nil, "OVERLAY")
		b.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		b.selected:SetBlendMode("ADD")
		b.selected:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			db.style = key
			Sync()
			ApplySettings()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["STYLE_" .. key])
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		buttons[i] = b
	end
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
	return buttons
end

-- Live preview, fixed on the right of the panel (it stays while the tabs change): a quest mob
-- with a fake nameplate on top, a quest item (crate) below, each with an icon that follows the
-- settings.
local preview = {}

local function BuildPreview(pane)
	local heading = pane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 2, 0)
	Loc(heading, "PREVIEW")

	local box = CreateFrame("Frame", nil, pane, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetPoint("TOPLEFT", 0, -20)
	box:SetPoint("BOTTOMRIGHT")
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		box:SetBackdropColor(0.05, 0.09, 0.05, 0.95)
		box:SetBackdropBorderColor(0.4, 0.4, 0.4)
	end
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

	preview.mob = CreateIcon()
	preview.mob:SetParent(plate)
	preview.mob.plate, preview.mob.isPreview, preview.mob.kind, preview.mob.progressValue = plate, true, "normal", "8/12"
	preview.object = CreateIcon()
	preview.object:SetParent(item)
	preview.object.plate, preview.object.isPreview, preview.object.isObject, preview.object.kind = item, true, true, "normal"
	preview.box, preview.plate, preview.bar = box, plate, bar
	box:SetScript("OnShow", function() UpdatePreview() end)
end

-- The fake nameplate copies a real one measured in the world (size, scale, health bar), so what
-- you set in the preview looks the same on real plates. previewRatio turns real plate units into
-- preview units; the mob icon is scaled by it as well.
local function ApplyPlateGeometry()
	local geom, ratio = root and root.plateGeom, 1
	if geom and geom.eff then ratio = geom.eff / preview.box:GetEffectiveScale() end
	if geom then
		preview.plate:SetSize(geom.w * ratio, geom.h * ratio)
		if geom.barW then
			preview.bar:SetSize(geom.barW * ratio, geom.barH * ratio)
			preview.bar:ClearAllPoints()
			preview.bar:SetPoint("TOP", preview.plate, "TOP", 0, -geom.barTop * ratio)
		end
	end
	preview.mob.previewRatio = ratio
end

function UpdatePreview()
	if not (preview.box and db) then return end
	ApplyPlateGeometry()
	for _, f in ipairs({ preview.mob, preview.object }) do
		-- The icons are created at LOW strata: lift them into the options window.
		f:SetFrameStrata(preview.box:GetFrameStrata())
		f:SetFrameLevel(preview.box:GetFrameLevel() + 10)
		AnchorIcon(f, f.plate)
		f:Show()
		StyleIcon(f)
	end
	-- A switched-off kind is shown faded.
	preview.mob:SetAlpha((db.active and db.enabled) and 1 or 0.25)
	preview.object:SetAlpha((db.active and db.objects) and 1 or 0.25)
end

---------------------------------------------------------------------------------------------
-- Float animation. Done by hand instead of a looping Translation animation: the game's
-- BOUNCE loop restarts for one frame at the top, which makes the icon blink.
---------------------------------------------------------------------------------------------

local function Bob(f, now)
	-- One full up-and-down cycle takes 2 * bounceSpeed seconds; cosine eases both ends.
	local period = 2 * db.bounceSpeed
	local wave = (1 - math.cos((now + f.phase) * 2 * math.pi / period)) / 2
	f.inner:SetPoint("CENTER", f, "CENTER", 0, wave * db.bounceHeight)
	if db.progressFloat and f.text:IsShown() then PlaceText(f, wave) end
end

local bobber = CreateFrame("Frame")
bobber:SetScript("OnUpdate", function()
	if not (db and db.bounce) then return end
	local now = GetTime()
	for _, f in pairs(icons) do Bob(f, now) end
	if preview.box and preview.box:IsVisible() then
		Bob(preview.mob, now)
		Bob(preview.object, now)
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
	icon:SetTexture(ICON_DIR .. "gold")
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
			OpenPanel()
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

---------------------------------------------------------------------------------------------
-- Panel layout: options on the left in four tabs (Display, Icon, Behavior, Profiles), the live
-- preview fixed on the right.
---------------------------------------------------------------------------------------------

local LEFT, TOP = 16, -96
local OPTIONS_WIDTH = 404 -- the tabbed box on the left
local PREVIEW_WIDTH, PREVIEW_HEIGHT = 240, 340 -- the preview window

-- Settings each tab owns, for its "Reset this tab" button.
local DISPLAY_KEYS = { "active", "enabled", "objects", "scale", "offsetX", "offset", "objectScale", "objectOffsetX", "objectOffset" }
local ICON_KEYS = { "style", "bounce", "bounceHeight", "bounceSpeed", "glow", "glowAlpha" }
local PROGRESS_KEYS = { "progress", "progressAttach", "progressFloat", "progressSize", "progressFont",
	"progressOutline", "progressColor", "progressX", "progressY" }
local BEHAVIOR_KEYS = { "colorByType", "combat", "minimap", "minimapAngle", "sound", "soundChoice" }

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
	local b = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
	b:SetSize(130, 20)
	b:SetPoint("TOPLEFT", tab, "TOPLEFT", LEFT + 200, TOP + SECTION_HEADER - 6)
	Loc(b, "RESET_SECTION")
	b:SetScript("OnClick", function()
		onReset()
		AfterReset()
	end)
end

-- What each control depends on.
local function AddonOn() return db.active end
local function MobsOn() return db.active and db.enabled end
local function ItemsOn() return db.active and db.objects end
local function AnyIconOn() return db.active and (db.enabled or db.objects) end
local function FloatOn() return AnyIconOn() and db.bounce end
local function GlowOn() return AnyIconOn() and db.glow end
local function ProgressOn() return MobsOn() and db.progress end

local function GateCheck(condition, check)
	Gate(condition, check, check.labelFS, check.noteFS)
	return check
end

local function BuildDisplayTab(tab)
	AddResetTabButton(tab, function() ResetKeys(DISPLAY_KEYS) end)
	AddCheck(tab, "ENABLE_ADDON", "ENABLE_ADDON_TIP", "active", LEFT, TOP)

	local y = TOP - 58
	GateCheck(AddonOn, AddSectionCheck(tab, "QUEST_MOBS", "enabled", LEFT, y))
	Gate(MobsOn, AddSlider(tab, "ICON_SIZE", "scale", 0.5, 3.0, 0.05, LEFT + 4, y - 22, "%.2f"))
	Gate(MobsOn, AddSlider(tab, "POS_X", "offsetX", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, y - 62, "%d"))
	Gate(MobsOn, AddSlider(tab, "POS_Y", "offset", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, y - 102, "%d"))

	y = y - 158
	GateCheck(AddonOn, AddSectionCheck(tab, "QUEST_ITEMS", "objects", LEFT, y))
	Gate(ItemsOn, AddSlider(tab, "ICON_SIZE", "objectScale", 0.5, 3.0, 0.05, LEFT + 4, y - 22, "%.2f"))
	Gate(ItemsOn, AddSlider(tab, "POS_X", "objectOffsetX", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, y - 62, "%d"))
	Gate(ItemsOn, AddSlider(tab, "POS_Y", "objectOffset", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, y - 102, "%d"))
end

-- The objective count ("8/12") next to quest mobs: everything about it is its own.
local function BuildProgressTab(tab)
	AddResetTabButton(tab, function() ResetKeys(PROGRESS_KEYS) end)
	GateCheck(MobsOn, AddCheck(tab, "PROGRESS", "PROGRESS_TIP", "progress", LEFT, TOP))
	GateCheck(ProgressOn, AddCheck(tab, "PROGRESS_ATTACH", "PROGRESS_ATTACH_TIP", "progressAttach", LEFT, TOP - 48))
	-- Floating with the icon needs the icon's own Float (Icon tab).
	GateCheck(function() return ProgressOn() and db.bounce end,
		AddCheck(tab, "PROGRESS_FLOAT", "PROGRESS_FLOAT_TIP", "progressFloat", LEFT, TOP - 96))
	Gate(ProgressOn, AddSlider(tab, "TEXT_SIZE", "progressSize", 8, 32, 1, LEFT + 4, TOP - 156, "%d"))
	-- Attached, the text is glued to the icon: X/Y only apply when it stands on its own.
	local function FreeTextOn() return ProgressOn() and not db.progressAttach end
	Gate(FreeTextOn, AddSlider(tab, "POS_X", "progressX", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, TOP - 196, "%d"))
	Gate(FreeTextOn, AddSlider(tab, "POS_Y", "progressY", -POSITION_RANGE, POSITION_RANGE, 1, LEFT + 4, TOP - 236, "%d"))

	-- Formatting: font and outline side by side, colour below.
	local function Choice(key) return function() return db[key] end end
	local function SetChoice(key) return function(value) db[key] = value; ApplySettings() end end
	Gate(ProgressOn, AddDropdown(tab, "TEXT_FONT", TEXT_FONT_ORDER,
		function(value) return L["FONT_" .. value] end, Choice("progressFont"), SetChoice("progressFont"),
		LEFT + 4, TOP - 282, 165))
	Gate(ProgressOn, AddDropdown(tab, "TEXT_OUTLINE", { "none", "thin", "thick" },
		function(value) return L["OUTLINE_" .. value] end, Choice("progressOutline"), SetChoice("progressOutline"),
		LEFT + 180, TOP - 282, 165))
	Gate(ProgressOn, AddDropdown(tab, "TEXT_COLOR", { "white", "gold", "green", "kind" },
		function(value) return L["COLOR_" .. value] end, Choice("progressColor"), SetChoice("progressColor"),
		LEFT + 4, TOP - 336, 165))
end

local function BuildIconTab(tab)
	AddResetTabButton(tab, function() ResetKeys(ICON_KEYS) end)
	Gate(AnyIconOn, AddHeading(tab, "ICON_STYLE", LEFT, TOP))
	Gate(AnyIconOn, unpack(AddStylePicker(tab, LEFT + 4, TOP - 18)))

	local y = TOP - 82
	GateCheck(AnyIconOn, AddSectionCheck(tab, "FLOAT", "bounce", LEFT, y))
	Gate(FloatOn, AddSlider(tab, "FLOAT_HEIGHT", "bounceHeight", 1, 20, 1, LEFT + 4, y - 22, "%d"))
	Gate(FloatOn, AddSlider(tab, "FLOAT_TIME", "bounceSpeed", 0.3, 2.0, 0.05, LEFT + 4, y - 62, "%.2f"))

	y = y - 118
	GateCheck(AnyIconOn, AddSectionCheck(tab, "GLOW_SECTION", "glow", LEFT, y))
	Gate(GlowOn, AddSlider(tab, "GLOW_INTENSITY", "glowAlpha", 0.1, 1.0, 0.05, LEFT + 4, y - 22, "%.2f"))
end

local function BuildBehaviorTab(tab)
	AddResetTabButton(tab, function()
		ResetKeys(BEHAVIOR_KEYS)
		root.language = "auto"
		L = BuildLocale("auto")
		Relabel()
	end)
	GateCheck(AnyIconOn, AddCheck(tab, "COLOR_BY_TYPE", "COLOR_BY_TYPE_TIP", "colorByType", LEFT, TOP))
	-- The minimap button stays usable with the addon off: it is how you turn it back on.
	AddCheck(tab, "MINIMAP", "MINIMAP_TIP", "minimap", LEFT, TOP - 48)

	Gate(AnyIconOn, AddDropdown(tab, "IN_COMBAT", { "show", "fade", "hide" },
		function(value) return L["COMBAT_" .. value:upper()] end,
		function() return db.combat end,
		function(value) db.combat = value; UpdateCombatAlpha() end,
		LEFT + 4, TOP - 104))

	local languages = { "auto" }
	for _, code in ipairs(ns.LANGUAGES) do languages[#languages + 1] = code end
	AddDropdown(tab, "LANGUAGE", languages,
		function(code) return code == "auto" and L.LANGUAGE_AUTO or ns.LANGUAGE_NAMES[code] end,
		function() return root.language end,
		function(code) root.language = code; L = BuildLocale(code); Relabel() end,
		LEFT + 4, TOP - 164)

	-- Sound when an objective completes: on/off, which sound, and a button to hear it.
	local function SoundOn() return AddonOn() and db.sound end
	GateCheck(AddonOn, AddCheck(tab, "SOUND", "SOUND_TIP", "sound", LEFT, TOP - 222))
	Gate(SoundOn, AddDropdown(tab, "SOUND_CHOICE", QUEST_SOUND_ORDER,
		function(value) return L["SOUND_" .. value] end,
		function() return db.soundChoice end,
		function(value) db.soundChoice = value; PlayQuestSound() end,
		LEFT + 4, TOP - 270, 165))
	local test = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
	test:SetSize(80, 22)
	test:SetPoint("TOPLEFT", LEFT + 180, TOP - 289)
	Loc(test, "SOUND_TEST")
	test:SetScript("OnClick", PlayQuestSound)
	Gate(SoundOn, test)
end

-- Profiles tab in the Ace3 layout players know from RareScanner and many others: intro, reset,
-- current profile, New + Existing profiles, Copy From, Delete a Profile (with a confirmation).
local PROFILE_TEXT_WIDTH = OPTIONS_WIDTH - 36
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

local function BuildProfilesTab(tab)
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
	local reset = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
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
	input:SetSize(168, 22)
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
	AddDropdown(tab, "PROF_CHOOSE", ProfileNames, Name, ActiveProfileName, UseProfile, LEFT + 196, TOP - 126, 180)

	Desc("PROF_COPY_DESC", TOP - 186)
	AddDropdown(tab, "PROF_COPY", OtherProfiles, Name, Nothing, function(name)
		local source = root.profiles[name]
		if not source then return end
		for key in pairs(DEFAULTS) do db[key] = source[key] end
		AfterReset()
	end, LEFT + 4, TOP - 206, 180)

	Desc("PROF_DELETE_DESC", TOP - 266)
	AddDropdown(tab, "PROF_DELETE", OtherProfiles, Name, Nothing, ConfirmDelete, LEFT + 4, TOP - 286, 180)

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
	{ key = "TAB_DISPLAY", build = BuildDisplayTab, height = 356 },
	{ key = "TAB_ICON", build = BuildIconTab, height = 260 },
	{ key = "TAB_PROGRESS", build = BuildProgressTab, height = 382 },
	{ key = "TAB_BEHAVIOR", build = BuildBehaviorTab, height = 314 },
}
local SECTION_GAP = 16
local CONTENT_WIDTH = OPTIONS_WIDTH - 34

local function BuildSettingsTab(tab, box)
	local scroll = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -8)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(CONTENT_WIDTH)
	scroll:SetScrollChild(content)
	settingsScroll = scroll

	local y = 0
	for _, s in ipairs(SETTINGS_SECTIONS) do
		local section = CreateFrame("Frame", nil, content)
		section:SetSize(CONTENT_WIDTH, 1)
		section:SetPoint("TOPLEFT", content, "TOPLEFT", -12, -(y + SECTION_HEADER) - TOP)
		local heading = section:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		heading:SetPoint("TOPLEFT", section, "TOPLEFT", LEFT, TOP + SECTION_HEADER - 8)
		Loc(heading, s.key)
		local line = section:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 0.82, 0, 0.25)
		line:SetSize(CONTENT_WIDTH - 24, 1)
		line:SetPoint("TOPLEFT", section, "TOPLEFT", LEFT, TOP + 6)
		s.build(section)
		y = y + SECTION_HEADER + s.height + SECTION_GAP
	end
	content:SetHeight(y)
end

local function BuildPanel()
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 16, -16)
	header:SetText(TITLE)
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", panel, "RIGHT", -140, 0)
	sub:SetJustifyH("LEFT")
	Loc(sub, "DESC")

	-- Options box over the whole panel, in the Ace3 tab style players know (BlizzMove and many others):
	-- the game's options-frame tab textures on top of a bordered pane, tabs stretched to fill it.
	local box = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetPoint("TOPLEFT", 8, -84)
	box:SetPoint("BOTTOMRIGHT", -8, 8)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 3, right = 3, top = 5, bottom = 3 } })
		box:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
		box:SetBackdropBorderColor(0.4, 0.4, 0.4)
	end

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
	if window.SetBackdrop then
		window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function() root.previewHidden = true; window:Hide() end)
	local pane = CreateFrame("Frame", nil, window)
	pane:SetPoint("TOPLEFT", 14, -12)
	pane:SetPoint("BOTTOMRIGHT", -14, 14)
	BuildPreview(pane)
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

	local toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	toggle:SetSize(110, 22)
	toggle:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -14)
	Loc(toggle, "PREVIEW")
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

	local TAB_ACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-ActiveTab"
	local TAB_INACTIVE = "Interface\\OptionsFrame\\UI-OptionsFrame-InActiveTab"
	local function TabPieces(tab, file, point, y)
		local left = tab:CreateTexture(nil, "BORDER")
		left:SetTexture(file)
		left:SetSize(20, 24)
		left:SetPoint(point, 0, y)
		left:SetTexCoord(0, 0.15625, 0, 1)
		local middle = tab:CreateTexture(nil, "BORDER")
		middle:SetTexture(file)
		middle:SetHeight(24)
		middle:SetPoint("LEFT", left, "RIGHT")
		middle:SetTexCoord(0.15625, 0.84375, 0, 1)
		local right = tab:CreateTexture(nil, "BORDER")
		right:SetTexture(file)
		right:SetSize(20, 24)
		right:SetPoint("LEFT", middle, "RIGHT")
		right:SetTexCoord(0.84375, 1, 0, 1)
		return { left, middle, right }
	end

	local builders = { BuildSettingsTab, BuildProfilesTab }
	local keys = { "TAB_SETTINGS", "TAB_PROFILES" }
	local tabs, frames = {}, {}
	local selected = 1
	local TAB_OVERLAP = 10
	local tabWidth = 100 -- until LayoutTabs measures the labels

	local function SelectTab(index)
		selected = index
		for i, frame in ipairs(frames) do frame:SetShown(i == index) end
		for i, tab in ipairs(tabs) do
			local isActive = i == index
			for _, piece in ipairs(tab.active) do piece:SetShown(isActive) end
			for _, piece in ipairs(tab.inactive) do piece:SetShown(not isActive) end
			tab.text:SetFontObject(isActive and "GameFontHighlightSmall" or "GameFontNormalSmall")
			tab.text:ClearAllPoints()
			tab.text:SetPoint("CENTER", tab, "CENTER", 0, isActive and -2 or -3)
			if isActive then tab:Disable() else tab:Enable() end
		end
	end

	for i, build in ipairs(builders) do
		local tab = CreateFrame("Button", nil, panel)
		tab:SetSize(tabWidth, 24)
		tab:SetFrameLevel(box:GetFrameLevel() + 5)
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 4, -4)
		else
			tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -TAB_OVERLAP, 0)
		end
		tab.active = TabPieces(tab, TAB_ACTIVE, "BOTTOMLEFT", -3)
		tab.inactive = TabPieces(tab, TAB_INACTIVE, "TOPLEFT", 0)
		tab.active[2]:SetWidth(tabWidth - 40)
		tab.inactive[2]:SetWidth(tabWidth - 40)
		tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		Loc(tab.text, keys[i])
		tab:SetHighlightTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight", "ADD")
		local highlight = tab:GetHighlightTexture()
		highlight:ClearAllPoints()
		highlight:SetPoint("LEFT", tab, "LEFT", 10, -4)
		highlight:SetPoint("RIGHT", tab, "RIGHT", -10, -4)
		tab:SetScript("OnClick", function() SelectTab(i) end)
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
			local width = math.max(80, math.floor(tab.text:GetStringWidth() + 44))
			tab:SetWidth(width)
			tab.active[2]:SetWidth(width - 40)
			tab.inactive[2]:SetWidth(width - 40)
		end
	end
	LayoutTabs()
	panel:HookScript("OnShow", function() SelectTab(selected) end)
	SelectTab(1)

	local parent = GetCSCoderParent()
	if Settings and Settings.RegisterCanvasLayoutSubcategory and parent.category then
		settingsCategory = Settings.RegisterCanvasLayoutSubcategory(parent.category, panel, SUBTITLE)
	elseif InterfaceOptions_AddCategory then
		panel.parent = parent.name
		InterfaceOptions_AddCategory(panel)
	end
end

function OpenPanel()
	if Settings and Settings.OpenToCategory and settingsCategory then
		Settings.OpenToCategory(settingsCategory:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------

-- Measures a real enemy nameplate (size, effective scale, health bar) for the preview. Saved, so
-- the preview is right even before a plate shows up in a new session.
local plateMeasured = false

local function MeasurePlate(unit)
	if plateMeasured or not (root and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	local w, h = plate:GetSize()
	local eff = plate:GetEffectiveScale()
	if not (w and h and eff) or w <= 0 or h <= 0 then return end
	local geom = { w = w, h = h, eff = eff }
	local frame = plate.UnitFrame
	local bar = frame and (frame.healthBar or frame.HealthBar
		or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar))
	local plateTop, barTop = plate:GetTop(), bar and bar.GetTop and bar:GetTop()
	if bar and plateTop and barTop then
		local bw, bh = bar:GetSize()
		local barEff = bar:GetEffectiveScale()
		geom.barW, geom.barH = bw * barEff / eff, bh * barEff / eff
		geom.barTop = (plateTop * eff - barTop * barEff) / eff
	end
	root.plateGeom = geom
	plateMeasured = true
	if UpdatePreview then UpdatePreview() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "PLAYER_SOFT_INTERACT_CHANGED")
pcall(events.RegisterEvent, events, "CVAR_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		LoadSavedVariables()
		L = BuildLocale(root.language)
		BuildPanel()
		return
	end
	if not db then return end
	if event == "NAME_PLATE_UNIT_ADDED" then
		if arg1 ~= SOFT then
			Refresh(arg1)
			-- Enemy plates are what the preview imitates; measure one per session once it is laid out.
			if not plateMeasured and UnitCanAttack and UnitCanAttack("player", arg1) then
				local unit = arg1
				C_Timer.After(0.2, function() MeasurePlate(unit) end)
			end
		end
		RefreshSoftObject()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		HideIcon(arg1)
		RefreshSoftObject()
	elseif event == "PLAYER_LOGIN" then
		ResolveCharacter() -- the character name is certain by now
		RebuildQuestTitles(); RebuildObjectiveTexts()
		RefreshControls()
		ApplySettings()
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		RefreshSoftObject()
	elseif event == "CVAR_UPDATE" then
		-- Another addon changed a cvar we need: take it back next frame (writes only on change,
		-- so this can't loop).
		if ObjectsOn() and type(arg1) == "string" and WATCHED_CVARS[arg1:lower()] then
			C_Timer.After(0, function()
				if ObjectsOn() then EnableObjectNameplates(); RefreshSoftObject() end
			end)
		end
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
		RefreshSoftObject()
	else
		RebuildQuestTitles(); RebuildObjectiveTexts()
		RefreshAll()
	end
end)

-- Light periodic recheck: objectives finish, tooltips load late, mobs die.
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < RECHECK_SECONDS or not db then return end
	elapsed = 0
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
	else
		OpenPanel()
	end
end
