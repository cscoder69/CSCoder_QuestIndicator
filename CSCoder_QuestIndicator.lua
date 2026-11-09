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
	offsetX = 0,         -- mob icon horizontal position
	offset = -15,        -- mob icon height above the nameplate
	objectScale = 1.5,   -- object icon size
	objectOffset = 10,   -- object icon height above the object
	bounce = true,       -- floating up/down animation
	bounceHeight = 7,    -- how far it floats (pixels)
	bounceSpeed = 0.9,   -- seconds for one move up (lower = faster)
	glow = false,        -- glowing star behind the icon
	glowAlpha = 0.55,    -- glow intensity
	colorByType = true,  -- daily/repeatable in blue, group/elite in red
	combat = "show",     -- "show", "fade" or "hide" the icons in combat
	minimap = true,      -- minimap button
	minimapAngle = 220,  -- its position around the minimap (degrees)
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
local RefreshControls, UpdatePreview, UpdateMinimapButton, UpdateGates -- options UI

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

-- Reads tooltip lines (TooltipInfo data or plain strings) and answers: true = still needed,
-- false = quest-related but finished, nil = not quest-related. Second value: the quest title.
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
			if line.completed == false then return true, title end
			if line.completed == nil and ProgressUnfinished(text) then return true, title end
		elseif (titleType and lineType == titleType) or activeTitles[text] then
			sawQuest, title = true, text
		elseif sawQuest and ProgressUnfinished(text) then
			return true, title
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
	local state, title = QuestStateFromLines(lines)
	return state == true, title
end

-- Returns: still needed?, quest kind.
local function IsQuestMob(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
	if UnitIsFriend("player", unit) and not UnitCanAttack("player", unit) then return false end
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
		if ok and related ~= nil then
			if not related then return false end
			local state, title = ByTooltipInfo(unit)
			if state == false then return false end
			return true, KindOf(title)
		end
	end
	local state, title = ByTooltipInfo(unit)
	if state ~= nil then return state, KindOf(title) end
	local scanned, scannedTitle = ByTooltipScan(unit)
	return scanned, KindOf(scannedTitle)
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

	f:SetScale(f.isObject and db.objectScale or db.scale)
	f:SetAlpha(f.isPreview and 1 or CombatAlpha())

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
		f:SetPoint("BOTTOM", plate, "TOP", 0, db.objectOffset)
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

	local glow = inner:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(GLOW_TEXTURE)
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER")
	glow:SetSize(40, 40)
	f.glow = glow

	local icon = inner:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	f.icon = icon

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

local function ShowIcon(unit, plate, kind)
	kind = kind or "normal"
	local f = icons[unit]
	if f then
		if f.kind ~= kind then f.kind = kind; StyleIcon(f) end
		return
	end
	f = table.remove(pool) or CreateIcon()
	icons[unit] = f
	f.unit, f.isObject, f.kind = unit, unit == SOFT, kind
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
	f.unit = nil
	table.insert(pool, f)
end

local function UpdateCombatAlpha()
	local alpha = CombatAlpha()
	for _, f in pairs(icons) do f:SetAlpha(alpha) end
end

local function Refresh(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if db.active and db.enabled and plate then
		local needed, kind = IsQuestMob(unit)
		if needed then ShowIcon(unit, plate, kind) return end
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

local function RebuildObjectiveTexts()
	wipe(objectiveTexts)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
	local count = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local questID = C_QuestLog.GetQuestIDForLogIndex and C_QuestLog.GetQuestIDForLogIndex(i)
		if not questID and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			questID = info and not info.isHeader and info.questID
		end
		local objectives = questID and C_QuestLog.GetQuestObjectives(questID)
		for _, objective in ipairs(objectives or {}) do
			if objective.text and not objective.finished then
				objectiveTexts[#objectiveTexts + 1] = { text = objective.text:lower(), kind = kindByQuestID[questID] or "normal" }
			end
		end
	end
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
	local function UpdateLabel(value) title:SetText(L[labelKey] .. ":  |cffffd200" .. string.format(format, value) .. "|r") end
	local syncing = false
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
	return slider, title
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

local function AddDropdown(parent, labelKey, options, labelFor, get, set, x, y)
	local heading = AddHeading(parent, labelKey, x, y)
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local button = CreateFrame("Button", nil, parent, backdrop)
	button:SetSize(240, 24)
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

	local list = CreateFrame("Frame", nil, button, backdrop)
	list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, 2)
	list:SetSize(240, #options * DROPDOWN_ROW + 10)
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	if list.SetBackdrop then
		list:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
		list:SetBackdropBorderColor(0.6, 0.6, 0.6)
	end
	list:Hide()

	local rows = {}
	local function Sync()
		value:SetText(labelFor(get()))
		for i, row in ipairs(rows) do
			row.text:SetText(labelFor(options[i]))
			row.check:SetShown(options[i] == get())
		end
	end
	for i, option in ipairs(options) do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(232, DROPDOWN_ROW)
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
		row:SetScript("OnClick", function()
			list:Hide()
			set(option)
			Sync()
		end)
		rows[i] = row
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
	preview.mob.plate, preview.mob.isPreview, preview.mob.kind = plate, true, "normal"
	preview.object = CreateIcon()
	preview.object:SetParent(item)
	preview.object.plate, preview.object.isPreview, preview.object.isObject, preview.object.kind = item, true, true, "normal"
	preview.box = box
	box:SetScript("OnShow", function() UpdatePreview() end)
end

function UpdatePreview()
	if not (preview.box and db) then return end
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

-- Settings each tab owns, for its "Reset this tab" button.
local DISPLAY_KEYS = { "active", "enabled", "objects", "scale", "offsetX", "offset", "objectScale", "objectOffset" }
local ICON_KEYS = { "style", "bounce", "bounceHeight", "bounceSpeed", "glow", "glowAlpha" }
local BEHAVIOR_KEYS = { "colorByType", "combat", "minimap", "minimapAngle" }

local function ResetKeys(keys)
	for _, key in ipairs(keys) do db[key] = DEFAULTS[key] end
end

local function AfterReset()
	RefreshControls()
	UpdateCombatAlpha()
	ApplySettings()
end

local function AddResetTabButton(tab, onReset)
	local b = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
	b:SetSize(200, 24)
	b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
	Loc(b, "RESET_TAB")
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
	Gate(MobsOn, AddSlider(tab, "HORIZONTAL", "offsetX", -80, 80, 1, LEFT + 4, y - 62, "%d"))
	Gate(MobsOn, AddSlider(tab, "HEIGHT_PLATE", "offset", -40, 80, 1, LEFT + 4, y - 102, "%d"))

	y = y - 158
	GateCheck(AddonOn, AddSectionCheck(tab, "QUEST_ITEMS", "objects", LEFT, y))
	Gate(ItemsOn, AddSlider(tab, "ICON_SIZE", "objectScale", 0.5, 3.0, 0.05, LEFT + 4, y - 22, "%.2f"))
	Gate(ItemsOn, AddSlider(tab, "HEIGHT_ITEM", "objectOffset", -40, 80, 1, LEFT + 4, y - 62, "%d"))
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
end

local MAX_PROFILE_ROWS = 10
local PROFILE_LIST_WIDTH = 170
local PROFILE_ACTIONS_X = LEFT + PROFILE_LIST_WIDTH + 14
local PROFILE_ACTIONS_WIDTH = 190

local function BuildProfilesTab(tab)
	local active = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	active:SetPoint("TOPLEFT", LEFT, TOP)
	active:SetWidth(OPTIONS_WIDTH - 30)
	active:SetJustifyH("LEFT")
	local tip = tab:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tip:SetPoint("TOPLEFT", LEFT, TOP - 18)
	Loc(tip, "PROFILES_TIP")

	local rows = {}
	for i = 1, MAX_PROFILE_ROWS do
		local row = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
		row:SetSize(PROFILE_LIST_WIDTH, 22)
		row:SetPoint("TOPLEFT", LEFT, TOP - 40 - (i - 1) * 25)
		row:SetScript("OnClick", function(self) UseProfile(self.profileName) end)
		rows[i] = row
	end

	local x = PROFILE_ACTIONS_X
	AddHeading(tab, "PROFILE_NAME", x, TOP - 40)
	local input = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
	input:SetSize(PROFILE_ACTIONS_WIDTH - 8, 22)
	input:SetPoint("TOPLEFT", x + 6, TOP - 58)
	input:SetAutoFocus(false)
	input:SetMaxLetters(32)
	input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	local message = tab:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	message:SetPoint("TOPLEFT", x, TOP - 290)
	message:SetWidth(PROFILE_ACTIONS_WIDTH)
	message:SetJustifyH("LEFT")
	local function Say(key) message:SetText(key and L[key] or "") end

	local function TypedName()
		local name = (input:GetText() or ""):match("^%s*(.-)%s*$")
		if name == "" then Say("ERR_NAME_EMPTY") return nil end
		if root.profiles[name] then Say("ERR_NAME_TAKEN") return nil end
		return name
	end

	local function AddButton(key, y, onClick)
		local b = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
		b:SetSize(PROFILE_ACTIONS_WIDTH, 24)
		b:SetPoint("TOPLEFT", x, y)
		Loc(b, key)
		b:SetScript("OnClick", onClick)
		return b
	end

	AddButton("NEW_PROFILE", TOP - 88, function()
		local name = TypedName()
		if not name then return end
		root.profiles[name] = FillDefaults({})
		input:SetText(""); Say(nil)
		UseProfile(name)
	end)
	AddButton("COPY_PROFILE", TOP - 116, function()
		local name = TypedName()
		if not name then return end
		root.profiles[name] = FillDefaults(CopySettings(db))
		input:SetText(""); Say(nil)
		UseProfile(name)
	end)
	AddButton("RENAME_PROFILE", TOP - 144, function()
		local name = TypedName()
		if not name then return end
		local old = ActiveProfileName()
		root.profiles[name], root.profiles[old] = root.profiles[old], nil
		for character, profile in pairs(root.chars) do
			if profile == old then root.chars[character] = name end
		end
		input:SetText(""); Say(nil)
		UseProfile(name)
	end)

	local armed = false
	local deleteButton
	deleteButton = AddButton("DELETE_PROFILE", TOP - 184, function(self)
		if #ProfileNames() <= 1 then Say("ERR_LAST_PROFILE") return end
		if not armed then
			armed = true
			self:SetText(L.CONFIRM_DELETE)
			C_Timer.After(3, function()
				if armed then armed = false; deleteButton:SetText(L.DELETE_PROFILE) end
			end)
			return
		end
		armed = false
		self:SetText(L.DELETE_PROFILE)
		local old = ActiveProfileName()
		root.profiles[old] = nil
		local fallback = root.profiles[DEFAULT_PROFILE] and DEFAULT_PROFILE or ProfileNames()[1]
		for character, profile in pairs(root.chars) do
			if profile == old then root.chars[character] = fallback end
		end
		Say(nil)
		UseProfile(fallback)
	end)

	-- Everything in the active profile back to defaults, plus the language.
	AddButton("RESET_ALL", TOP - 236, function()
		for key, value in pairs(DEFAULTS) do db[key] = value end
		root.language = "auto"
		L = BuildLocale("auto")
		Say(nil)
		Relabel()
		AfterReset()
	end)

	local function Sync()
		local current = ActiveProfileName()
		active:SetText(string.format(L.ACTIVE_PROFILE, "|cffffd200" .. tostring(current) .. "|r"))
		local names = ProfileNames()
		for i, row in ipairs(rows) do
			local name = names[i]
			row.profileName = name
			if name then
				row:SetText(name == current and ("> " .. name .. " <") or name)
				if name == current then row:LockHighlight() else row:UnlockHighlight() end
				row:Show()
			else
				row:Hide()
			end
		end
	end
	refreshers[#refreshers + 1] = Sync
	tab:HookScript("OnShow", Sync)
end

local function BuildPanel()
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 16, -16)
	header:SetText(TITLE)
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	sub:SetJustifyH("LEFT")
	Loc(sub, "DESC")

	-- Options box on the left, in the Ace3 tab style players know (BlizzMove and many others):
	-- the game's options-frame tab textures on top of a bordered pane, tabs stretched to fill it.
	local box = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetPoint("TOPLEFT", 8, -84)
	box:SetPoint("BOTTOMLEFT", 8, 8)
	box:SetWidth(OPTIONS_WIDTH)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 3, right = 3, top = 5, bottom = 3 } })
		box:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
		box:SetBackdropBorderColor(0.4, 0.4, 0.4)
	end

	-- Preview on the right, outside the tabs.
	local pane = CreateFrame("Frame", nil, panel)
	pane:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, 20)
	pane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
	BuildPreview(pane)

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

	local builders = { BuildDisplayTab, BuildIconTab, BuildBehaviorTab, BuildProfilesTab }
	local keys = { "TAB_DISPLAY", "TAB_ICON", "TAB_BEHAVIOR", "TAB_PROFILES" }
	local tabs, frames = {}, {}
	local selected = 1
	local TAB_OVERLAP = 10
	-- Equal widths that fill the box, as Ace3 does.
	local tabWidth = math.floor((OPTIONS_WIDTH - 8 + TAB_OVERLAP * (#builders - 1)) / #builders)

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
		build(frame)
	end
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
		if arg1 ~= SOFT then Refresh(arg1) end
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
