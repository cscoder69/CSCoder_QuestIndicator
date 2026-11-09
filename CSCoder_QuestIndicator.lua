-- CS.Coder - Quest Indicator
-- A floating quest "!" above the nameplate of every mob you still need for an active quest,
-- and over the nearest quest object in front of you (herbs, sprouts, crates...).
--
-- Settings: Options > AddOns > "CS.Coder - Quest Indicator" (or /cqi to open it).
-- Nameplates must be on (V) for the mob icons.

local ADDON = ...
local TITLE = "CS.Coder - Quest Indicator"
local DEFAULTS = {
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
}
-- Bump to re-apply changed defaults to existing saved settings once.
local SETTINGS_VERSION = 4
local ICON_DIR = "Interface\\AddOns\\CSCoder_QuestIndicator\\icons\\"
local ICON_STYLES = {
	{ key = "gold", label = "Gold" },
	{ key = "blue", label = "Blue" },
	{ key = "red", label = "Red" },
	{ key = "badge", label = "Badge" },
	{ key = "pixel", label = "Pixel" },
}
local GLOW_TEXTURE = "Interface\\Cooldown\\star4"
local RECHECK_SECONDS = 1.0 -- tooltip data can arrive a moment after the plate appears
local SOFT = "softinteract"  -- the game's interaction soft target (one world object)

local db
local icons = {}        -- unit token -> icon frame
local pool = {}         -- recycled icon frames
local activeTitles = {} -- quest title -> true
local RefreshSoftObject, EnableObjectNameplates, RestoreObjectCVars -- defined below (soft-target objects)

local function IconPath()
	for _, s in ipairs(ICON_STYLES) do
		if s.key == db.style then return ICON_DIR .. s.key end
	end
	return ICON_DIR .. "gold"
end

---------------------------------------------------------------------------------------------
-- Quest detection
---------------------------------------------------------------------------------------------

local function RebuildQuestTitles()
	wipe(activeTitles)
	local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
		or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local title, isHeader
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info then title, isHeader = info.title, info.isHeader end
		elseif GetQuestLogTitle then
			local t, _, _, header = GetQuestLogTitle(i)
			title, isHeader = t, header
		end
		if title and not isHeader then activeTitles[title] = true end
	end
end

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin": true while the left number is below the right.
local function ProgressUnfinished(text)
	local have, need = text:match("(%d+)%s*/%s*(%d+)")
	if have and need then return tonumber(have) < tonumber(need) end
	return nil
end

-- Reads tooltip lines (TooltipInfo data or plain strings) and answers: true = still needed,
-- false = quest-related but finished, nil = not quest-related.
local function QuestStateFromLines(lines)
	local lineTypes = Enum and Enum.TooltipDataLineType
	local objectiveType = lineTypes and lineTypes.QuestObjective
	local titleType = lineTypes and lineTypes.QuestTitle
	local sawQuest = false
	for _, line in ipairs(lines) do
		local text = type(line) == "table" and (line.leftText or "") or line
		local lineType = type(line) == "table" and line.type or nil
		if objectiveType and lineType == objectiveType then
			sawQuest = true
			if line.completed == false then return true end
			if line.completed == nil and ProgressUnfinished(text) then return true end
		elseif (titleType and lineType == titleType) or activeTitles[text] then
			sawQuest = true
		elseif sawQuest and ProgressUnfinished(text) then
			return true
		end
	end
	if sawQuest then return false end
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
	return QuestStateFromLines(lines) == true
end

local function IsQuestMob(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return false end
	if UnitIsFriend("player", unit) and not UnitCanAttack("player", unit) then return false end
	if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
		local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
		if ok and related ~= nil then
			if not related then return false end
			return ByTooltipInfo(unit) ~= false
		end
	end
	local viaInfo = ByTooltipInfo(unit)
	if viaInfo ~= nil then return viaInfo end
	return ByTooltipScan(unit)
end

---------------------------------------------------------------------------------------------
-- Icons (mobs and the soft-targeted object share the same frame type)
---------------------------------------------------------------------------------------------

local function StyleIcon(f)
	local isObject = f.unit == SOFT
	f.icon:SetTexture(IconPath())
	f:SetScale(isObject and db.objectScale or db.scale)

	f.glow:SetVertexColor(1, 0.82, 0.2, db.glowAlpha)
	f.glow:SetShown(db.glow)
	if db.glow then
		if not f.pulse:IsPlaying() then f.pulse:Play() end
	else
		f.pulse:Stop()
	end

	-- Changing a playing Translation can jump, so restart it with the new values.
	f.bob:Stop()
	f.move:SetOffset(0, db.bounceHeight)
	f.move:SetDuration(db.bounceSpeed)
	if db.bounce then f.bob:Play() end
end

local function AnchorIcon(f, plate)
	f:ClearAllPoints()
	if f.unit == SOFT then
		f:SetPoint("BOTTOM", plate, "TOP", 0, db.objectOffset)
	else
		f:SetPoint("BOTTOM", plate, "TOP", db.offsetX, db.offset)
	end
end

local function CreateIcon()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(26, 26)
	f:SetFrameStrata("LOW")

	local glow = f:CreateTexture(nil, "BACKGROUND")
	glow:SetTexture(GLOW_TEXTURE)
	glow:SetBlendMode("ADD")
	glow:SetPoint("CENTER")
	glow:SetSize(40, 40)
	f.glow = glow

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	f.icon = icon

	local bob = f:CreateAnimationGroup()
	bob:SetLooping("BOUNCE")
	local move = bob:CreateAnimation("Translation")
	move:SetSmoothing("IN_OUT")
	f.bob, f.move = bob, move

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

local function ShowIcon(unit, plate)
	if icons[unit] then return end
	local f = table.remove(pool) or CreateIcon()
	icons[unit] = f
	f.unit = unit
	f:SetParent(plate)
	AnchorIcon(f, plate)
	f:Show()
	StyleIcon(f)
	f.pop:Play()
end

local function HideIcon(unit)
	local f = icons[unit]
	if not f then return end
	icons[unit] = nil
	f.bob:Stop()
	f.pulse:Stop()
	f:Hide()
	f:SetParent(UIParent)
	f.unit = nil
	table.insert(pool, f)
end

local function Refresh(unit)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
	if db.enabled and plate and IsQuestMob(unit) then ShowIcon(unit, plate) else HideIcon(unit) end
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
	if db.objects then EnableObjectNameplates() else RestoreObjectCVars() end
	RefreshAll()
end

---------------------------------------------------------------------------------------------
-- Icon over the soft-targeted quest object. World objects only get a nameplate as the game's
-- interaction soft target ("softinteract", one object at a time, the nearest in front of you);
-- the cvars below make the game give it one.
---------------------------------------------------------------------------------------------

local objectiveTexts = {}

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
				objectiveTexts[#objectiveTexts + 1] = objective.text:lower()
			end
		end
	end
end

local function NameMatchesObjective(name)
	if not name or name == "" then return false end
	name = name:lower()
	for _, text in ipairs(objectiveTexts) do
		if text:find(name, 1, true) then return true end
	end
	return false
end

local function IsQuestObject(unit)
	if not (UnitIsGameObject and UnitIsGameObject(unit)) then return false end
	local state = ByTooltipInfo(unit)
	if state ~= nil then return state end
	return NameMatchesObjective(UnitName(unit))
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
		db.savedCVars = db.savedCVars or {}
		if db.savedCVars[name] == nil then db.savedCVars[name] = current end
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
	if InCombatLockdown() then pendingCVars = "restore"; return end
	if gateOpenedByUs then gateOpenedByUs = false; SetCV(GATE_CVAR, 0) end
	for name, value in pairs(db.savedCVars or {}) do pcall(C_CVar.SetCVar, name, value) end
	db.savedCVars = nil
end

local function IsLoaded(addon)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(addon) end
	return IsAddOnLoaded and IsAddOnLoaded(addon)
end

-- Opens the soft target's nameplate for quest objects only, so NPCs and mailboxes don't get one.
-- When ForeverLootSparkles is loaded it manages the plate for ore, herbs and corpses itself.
local function UpdateGate(isQuest)
	if InCombatLockdown() then return end
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
	if not db.objects then
		UpdateGate(false)
		HideIcon(SOFT)
		return
	end
	local isQuest = UnitExists(SOFT) and IsQuestObject(SOFT)
	UpdateGate(isQuest)
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(SOFT)
	if isQuest and plate then
		if icons[SOFT] and icons[SOFT]:GetParent() ~= plate then HideIcon(SOFT) end
		ShowIcon(SOFT, plate)
	else
		HideIcon(SOFT) -- the plate follows the gate; NAME_PLATE_UNIT_ADDED shows the icon
	end
end

---------------------------------------------------------------------------------------------
-- Options panel: Options > AddOns > CS.Coder - Quest Indicator
---------------------------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = TITLE
local settingsCategory
local refreshers = {} -- re-read db into every control (used by Reset)

local function RefreshControls()
	for _, fn in ipairs(refreshers) do fn() end
end

local function AddHeading(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function AddCheck(parent, label, tip, key, x, y)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", x, y)
	local text = check.Text or check.text or check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	if not (check.Text or check.text) then text:SetPoint("LEFT", check, "RIGHT", 4, 0) end
	text:SetText(label)
	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 4)
	note:SetText(tip)
	local function Sync() check:SetChecked(db[key]) end
	refreshers[#refreshers + 1] = Sync
	check:SetScript("OnShow", Sync)
	check:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		ApplySettings()
	end)
	return check
end

local function AddSlider(parent, label, key, low, high, step, x, y, format)
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
	local function UpdateLabel(value) title:SetText(label .. ":  |cffffd200" .. string.format(format, value) .. "|r") end
	local syncing = false
	local function Sync()
		syncing = true
		slider:SetValue(db[key]); UpdateLabel(db[key])
		syncing = false
	end
	refreshers[#refreshers + 1] = Sync
	slider:SetScript("OnShow", Sync)
	slider:SetScript("OnValueChanged", function(_, value)
		if syncing then return end
		value = math.floor(value / step + 0.5) * step
		if db[key] == value then return end
		db[key] = value
		UpdateLabel(value)
		ApplySettings()
	end)
	return slider
end

-- Row of clickable icon previews; the selected one gets a highlight frame.
local function AddStylePicker(parent, x, y)
	local buttons = {}
	local function Sync()
		for _, b in ipairs(buttons) do b.selected:SetShown(b.styleKey == db.style) end
	end
	for i, s in ipairs(ICON_STYLES) do
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(40, 40)
		b:SetPoint("TOPLEFT", x + (i - 1) * 48, y)
		b.styleKey = s.key
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.35)
		local tex = b:CreateTexture(nil, "ARTWORK")
		tex:SetPoint("TOPLEFT", 4, -4)
		tex:SetPoint("BOTTOMRIGHT", -4, 4)
		tex:SetTexture(ICON_DIR .. s.key)
		b.selected = b:CreateTexture(nil, "OVERLAY")
		b.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		b.selected:SetBlendMode("ADD")
		b.selected:SetAllPoints()
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			db.style = s.key
			Sync()
			ApplySettings()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(s.label)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		buttons[i] = b
	end
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
end

local function BuildPanel()
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 16, -16)
	header:SetText(TITLE)
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	sub:SetText("Shows a quest icon over mobs and objects you still need. Turn enemy nameplates on (V).")

	-- Left column: what to show and how it looks
	local L, R = 16, 330
	AddHeading(panel, "Show", L, -64)
	AddCheck(panel, "Icons over quest mobs", "Floating icon above the nameplate of quest mobs.", "enabled", L, -82)
	AddCheck(panel, "Icon over the nearest quest object", "Herbs, crates, sprouts: the nearest one in front of you.", "objects", L, -122)

	AddHeading(panel, "Icon style", L, -172)
	AddStylePicker(panel, L + 4, -192)

	AddHeading(panel, "Animation", L, -252)
	AddCheck(panel, "Floating up and down", "The icon gently bobs above the target.", "bounce", L, -270)
	AddCheck(panel, "Glow behind the icon", "A soft spinning star behind the icon.", "glow", L, -310)

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(160, 24)
	reset:SetPoint("TOPLEFT", L, -370)
	reset:SetText("Reset to defaults")
	reset:SetScript("OnClick", function()
		for key, value in pairs(DEFAULTS) do db[key] = value end
		RefreshControls()
		ApplySettings()
	end)

	-- Right column: sizes, positions and animation strength
	AddHeading(panel, "Quest mobs", R, -64)
	AddSlider(panel, "Icon size", "scale", 0.5, 3.0, 0.05, R, -86, "%.2f")
	AddSlider(panel, "Horizontal position", "offsetX", -80, 80, 1, R, -130, "%d")
	AddSlider(panel, "Height above the nameplate", "offset", -40, 80, 1, R, -174, "%d")

	AddHeading(panel, "Quest objects", R, -228)
	AddSlider(panel, "Icon size", "objectScale", 0.5, 3.0, 0.05, R, -250, "%.2f")
	AddSlider(panel, "Height above the object", "objectOffset", -40, 80, 1, R, -294, "%d")

	AddHeading(panel, "Animation strength", R, -348)
	AddSlider(panel, "Float height", "bounceHeight", 1, 20, 1, R, -370, "%d")
	AddSlider(panel, "Float time (seconds)", "bounceSpeed", 0.3, 2.0, 0.05, R, -414, "%.2f")
	AddSlider(panel, "Glow intensity", "glowAlpha", 0.1, 1.0, 0.05, R, -458, "%.2f")

	if Settings and Settings.RegisterCanvasLayoutCategory then
		settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
		Settings.RegisterAddOnCategory(settingsCategory)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

local function OpenPanel()
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
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "PLAYER_SOFT_INTERACT_CHANGED")
pcall(events.RegisterEvent, events, "CVAR_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		CSCoderQuestIndicatorDB = CSCoderQuestIndicatorDB or {}
		local saved = CSCoderQuestIndicatorDB
		if (saved.version or 1) < 3 then
			saved.scale, saved.offset, saved.glow = DEFAULTS.scale, DEFAULTS.offset, DEFAULTS.glow
		end
		saved.cursor = nil -- removed option
		saved.version = SETTINGS_VERSION
		for key, value in pairs(DEFAULTS) do
			if saved[key] == nil then saved[key] = value end
		end
		db = saved
		BuildPanel()
		return
	end
	if not db then return end
	if event == "NAME_PLATE_UNIT_ADDED" then
		if arg1 ~= SOFT then Refresh(arg1) end
		RefreshSoftObject()
	elseif event == "PLAYER_LOGIN" then
		if db.objects then EnableObjectNameplates() end
		RebuildQuestTitles(); RebuildObjectiveTexts()
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		RefreshSoftObject()
	elseif event == "CVAR_UPDATE" then
		-- Another addon changed a cvar we need: take it back next frame (writes only on change,
		-- so this can't loop).
		if db.objects and type(arg1) == "string" and WATCHED_CVARS[arg1:lower()] then
			C_Timer.After(0, function()
				if db.objects then EnableObjectNameplates(); RefreshSoftObject() end
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		local pending = pendingCVars
		pendingCVars = nil
		if pending == "apply" and db.objects then EnableObjectNameplates()
		elseif pending == "restore" and not db.objects then RestoreObjectCVars() end
		RefreshSoftObject()
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		HideIcon(arg1)
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
-- Slash command: /cqi opens the options
---------------------------------------------------------------------------------------------

SLASH_CSCODERQUESTINDICATOR1 = "/cqi"
SlashCmdList.CSCODERQUESTINDICATOR = function(msg)
	local cmd = (msg or ""):lower():match("^(%S*)")
	if cmd == "toggle" then
		db.enabled = not db.enabled
		ApplySettings()
		print("|cffffd200" .. TITLE .. "|r " .. (db.enabled and "on" or "off"))
	else
		OpenPanel()
	end
end
