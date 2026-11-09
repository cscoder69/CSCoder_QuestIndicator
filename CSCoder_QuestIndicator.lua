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
	progressAttach = true, -- true: X/Y from the icon (follows it); false: X/Y from the nameplate
	progressFloat = true,  -- bobs up and down with the icon (when the icon floats)
	progressSize = 13,   -- its font size
	progressFont = "friz",     -- key in TEXT_FONTS
	progressOutline = "thin",  -- "none", "thin", "thick"
	progressColor = "white",   -- "white", "gold", "green", "kind" (same colour as the icon) or "progress" (red to green)
	progressFormat = "slash",  -- "slash" 8/12, "spaced" 8 / 12, "both" 8/12 (67%), "percent" 67%, "left" 4 left
	progressShadow = false,   -- drop shadow behind the text
	progressBadge = true,     -- the text sits in a badge -- experiment
	badgeShape = "rounded",   -- "square", "rounded" or "pill"
	badgeBorderSize = 1,      -- border thickness in pixels (0 = none)
	badgeColor = { 0.05, 0.04, 0.02, 0.85 },  -- fill (r, g, b, a); replaced, never changed in place
	badgeBorderColor = { 1, 0.82, 0, 0.9 },   -- border
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
local KIND_TINT = { daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 } }
-- Progress text formatting: the fonts every client ships, outlines and colours.
local TEXT_FONTS = { friz = "Fonts\\FRIZQT__.TTF", arial = "Fonts\\ARIALN.TTF", skurri = "Fonts\\skurri.ttf", morpheus = "Fonts\\MORPHEUS.TTF" }
local TEXT_FONT_ORDER = { "friz", "arial", "skurri", "morpheus" }
local PROGRESS_FORMATS = { "slash", "spaced", "both", "percent", "left" }
-- Badge behind the progress text: a border shape with the fill shape inset by the border
-- thickness. Rounded and pill ends are white cap textures (left end; the right end is the same
-- texture mirrored), tinted and stretched to the badge height; the middle is a plain colour.
local BADGE_PAD_X, BADGE_PAD_Y = 8, 4
local BADGE_SHAPES = { "square", "rounded", "pill" }
local BADGE_CAPS = {
	rounded = { file = "badge\\rounded", ratio = 16 / 64 }, -- cap width / height
	pill = { file = "badge\\pill", ratio = 32 / 64 },
}

local function BadgeLayer(text, layer, sublevel)
	local left = text:CreateTexture(nil, layer, nil, sublevel)
	local middle = text:CreateTexture(nil, layer, nil, sublevel)
	local right = text:CreateTexture(nil, layer, nil, sublevel)
	return { left = left, middle = middle, right = right }
end

-- Lays out one layer (border or fill) inside the text frame, inset by `inset` pixels.
local function ShapeLayer(parts, text, shape, inset, width, height, color)
	local r, g, b, a = color[1], color[2], color[3], color[4] or 1
	local h = height - inset * 2
	local cap = BADGE_CAPS[shape]
	parts.middle:ClearAllPoints()
	parts.middle:SetColorTexture(r, g, b, a)
	if not cap or h <= 0 then
		parts.left:Hide(); parts.right:Hide()
		parts.middle:SetPoint("TOPLEFT", text, "TOPLEFT", inset, -inset)
		parts.middle:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", -inset, inset)
		parts.middle:SetShown(h > 0)
		return
	end
	local capWidth = math.min(h * cap.ratio, (width - inset * 2) / 2)
	for _, side in ipairs({ "left", "right" }) do
		local tex = parts[side]
		tex:SetTexture(IconPath(cap.file))
		tex:SetVertexColor(r, g, b, a)
		tex:SetSize(capWidth, h)
		tex:ClearAllPoints()
		if side == "left" then
			tex:SetTexCoord(0, 1, 0, 1)
			tex:SetPoint("LEFT", text, "LEFT", inset, 0)
		else
			tex:SetTexCoord(1, 0, 0, 1)
			tex:SetPoint("RIGHT", text, "RIGHT", -inset, 0)
		end
		tex:Show()
	end
	parts.middle:SetPoint("TOPLEFT", parts.left, "TOPRIGHT")
	parts.middle:SetPoint("BOTTOMRIGHT", parts.right, "BOTTOMLEFT")
	parts.middle:Show()
end

local function ShowBadge(text, show)
	for _, layer in ipairs({ text.badgeBorder, text.badgeFill }) do
		for _, tex in pairs(layer) do tex:SetShown(show) end
	end
end

local TEXT_OUTLINES = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
local TEXT_COLORS = { white = { 1, 1, 1 }, gold = { 1, 0.82, 0 }, green = { 0.3, 1, 0.3 } }
local KIND_TEXT_COLOR = { normal = { 1, 0.82, 0 }, daily = { 0.55, 0.8, 1 }, group = { 1, 0.5, 0.45 } }
local POSITION_RANGE = 200 -- X/Y sliders go from -200 to 200
local SLIDER_WIDTH = 200 -- sliders fit a half-width column with their value box

local root, db, charKey  -- saved variables, active profile, "Name - Realm"
local L                   -- active language table
local icons = {}          -- unit token -> icon frame
local pool = {}           -- recycled icon frames
local activeTitles = {}   -- quest title -> kind ("normal", "daily", "group")
local kindByQuestID = {}  -- questID -> kind
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
		-- In a badge the text is centred in the pill; plain, it starts right at the icon.
		label:SetPoint(db.progressBadge and "CENTER" or "LEFT")
		text:SetPoint("LEFT", f, "RIGHT", ATTACH_GAP, lift)
	else
		label:SetPoint("CENTER")
		text:SetPoint("CENTER", f.plate or f:GetParent(), "TOP", db.progressX, db.progressY + lift)
	end
end

local function StyleIcon(f)
	-- Texture and tint: with "color by quest type" the coloured styles swap to their blue/red
	-- sibling and the others are tinted.
	local style, tint = db.style, nil
	local kind = f.kind or "normal"
	if db.colorByType and KIND_TINT[kind] then
		local sibling = KIND_SIBLING[style]
		if sibling then style = sibling[kind] else tint = KIND_TINT[kind] end
	end
	f.icon:SetTexture(IconPath(style))
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
		label:SetTextColor(color[1], color[2], color[3])
		label:SetText(shown)
		-- Badge: the chosen shape sized to the text, in the chosen fill and border colours.
		if db.progressBadge then
			local height = math.floor((label:GetStringHeight() or 12) + BADGE_PAD_Y * 2 + 0.5)
			local width = math.floor((label:GetStringWidth() or 30) + BADGE_PAD_X * 2 + 0.5)
			if BADGE_CAPS[db.badgeShape] then width = width + height * BADGE_CAPS[db.badgeShape].ratio * 0.6 end
			width = math.max(width, height)
			text:SetSize(width, height)
			local border = db.badgeBorderSize or 0
			ShapeLayer(text.badgeBorder, text, db.badgeShape, 0, width, height, border > 0 and db.badgeBorderColor or { 0, 0, 0, 0 })
			ShapeLayer(text.badgeFill, text, db.badgeShape, border, width, height, db.badgeColor)
			ShowBadge(text, true)
			if border == 0 then for _, tex in pairs(text.badgeBorder) do tex:Hide() end end
		else
			ShowBadge(text, false)
			text:SetSize(60, 20)
		end
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
	-- Badge layers under the text (see ShapeLayer): border, then the fill on top of it.
	text.badgeBorder = BadgeLayer(text, "BACKGROUND", 1)
	text.badgeFill = BadgeLayer(text, "BORDER", 1)
	ShowBadge(text, false)
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
	profile.style = OLD_STYLES[profile.style] or profile.style
	if not VALID_STYLE[profile.style] then profile.style = DEFAULT_STYLE end
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
	note:SetWidth(250)
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
	slider:SetSize(SLIDER_WIDTH, 16)
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

-- Opens the game's colour picker (with opacity) on `color` ({ r, g, b, a }); onChange gets a
-- new table on every change, and the original back on cancel. Handles both the current
-- picker API (SetupColorPickerAndShow) and the older one (fields + Show).
local function OpenColorPicker(color, onChange)
	local picker = _G.ColorPickerFrame
	if not picker then return end
	local r, g, b, a = color[1], color[2], color[3], color[4] or 1
	local function Current()
		local nr, ng, nb = picker:GetColorRGB()
		local na = a
		if picker.GetColorAlpha then
			na = picker:GetColorAlpha()
		elseif _G.OpacitySliderFrame then
			na = 1 - _G.OpacitySliderFrame:GetValue() -- the old slider holds transparency
		end
		onChange({ nr, ng, nb, na })
	end
	local function Cancel() onChange({ r, g, b, a }) end
	if picker.SetupColorPickerAndShow then
		picker:SetupColorPickerAndShow({ r = r, g = g, b = b, opacity = a, hasOpacity = true,
			swatchFunc = Current, opacityFunc = Current, cancelFunc = Cancel })
	else
		picker.func, picker.opacityFunc, picker.cancelFunc = Current, Current, Cancel
		picker.hasOpacity, picker.opacity, picker.previousValues = true, 1 - a, { r, g, b, a }
		picker:SetColorRGB(r, g, b)
		picker:Hide()
		picker:Show()
	end
end

-- A colour swatch with its label; a click opens the colour picker for db[settingKey].
local function AddColorSwatch(parent, labelKey, settingKey, x, y)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	b:SetPoint("TOPLEFT", x, y)
	local edge = b:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.7, 0.7, 0.7, 1)
	local checker = b:CreateTexture(nil, "BORDER") -- dark under the colour, so transparency shows
	checker:SetPoint("TOPLEFT", 2, -2)
	checker:SetPoint("BOTTOMRIGHT", -2, 2)
	checker:SetColorTexture(0.15, 0.15, 0.15, 1)
	local swatch = b:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", b, "RIGHT", 8, 0)
	Loc(label, labelKey)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local function Sync()
		local c = db[settingKey] or DEFAULTS[settingKey]
		swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	end
	b:SetScript("OnClick", function()
		OpenColorPicker(db[settingKey] or DEFAULTS[settingKey], function(color)
			db[settingKey] = color
			Sync()
			ApplySettings()
		end)
	end)
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
	return b, label
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

local function AddDropdown(parent, labelKey, options, labelFor, get, set, x, y, width, fontFor)
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
	if f.SetBackdrop then
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	end
	if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, f:GetName()) end -- Esc closes it
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 20, -18)
	Loc(title, "ICON_STYLE")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	f:Hide()

	local shownCategory = CategoryOf(db.style)
	local categoryButtons, cells = {}, {}

	-- Left: one button per category, with its sample icon.
	for i, category in ipairs(ICON_CATEGORIES) do
		local b = CreateFrame("Button", nil, f, backdrop)
		b:SetSize(190, 44)
		b:SetPoint("TOPLEFT", 18, -48 - (i - 1) * 54)
		if b.SetBackdrop then
			b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		end
		local label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", 12, 0)
		label:SetPoint("RIGHT", -46, 0)
		label:SetJustifyH("LEFT")
		Loc(label, "ICONCAT_" .. category.key)
		local sample = b:CreateTexture(nil, "ARTWORK")
		sample:SetSize(34, 34)
		sample:SetPoint("RIGHT", -6, 0)
		sample:SetTexture(IconPath(category.sample))
		b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
		b:GetHighlightTexture():SetAlpha(0.25)
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
			db.style = self.style
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
		local current = CategoryOf(db.style)
		for _, b in ipairs(categoryButtons) do
			local isShown = b.categoryKey == shownCategory
			if b.SetBackdropColor then
				if isShown then b:SetBackdropColor(0.25, 0.2, 0.05, 0.9) else b:SetBackdropColor(0.05, 0.05, 0.05, 0.9) end
				-- Gold border on the shown category; a dimmer one on the category of the chosen icon.
				if isShown then b:SetBackdropBorderColor(1, 0.82, 0)
				elseif b.categoryKey == current then b:SetBackdropBorderColor(0.7, 0.6, 0.3)
				else b:SetBackdropBorderColor(0.4, 0.4, 0.4) end
			end
		end
		local icons = {}
		for _, category in ipairs(ICON_CATEGORIES) do
			if category.key == shownCategory then icons = category.icons end
		end
		for i, name in ipairs(icons) do
			local c = Cell(i)
			c.style = shownCategory .. "/" .. name
			c.tex:SetTexture(IconPath(c.style))
			c.selected:SetShown(c.style == db.style)
			c:Show()
		end
		for i = #icons + 1, #cells do cells[i]:Hide() end
	end
	f:SetScript("OnShow", function() shownCategory = CategoryOf(db.style); f:Refresh() end)
	panel:HookScript("OnHide", function() f:Hide() end)
	return f
end

-- The button on the panel: current icon, its name and category; a click opens the picker.
local function AddIconPicker(parent, x, y)
	local backdrop = BackdropTemplateMixin and "BackdropTemplate" or nil
	local b = CreateFrame("Button", nil, parent, backdrop)
	b:SetSize(260, 48)
	b:SetPoint("TOPLEFT", x, y)
	if b.SetBackdrop then
		b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		b:SetBackdropColor(0, 0, 0, 0.6)
		b:SetBackdropBorderColor(0.6, 0.5, 0.25)
	end
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
	b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
	b:GetHighlightTexture():SetAlpha(0.2)

	local function Sync()
		icon:SetTexture(IconPath(db.style))
		name:SetText(StyleName(db.style))
		category:SetText(L["ICONCAT_" .. CategoryOf(db.style)])
		if iconPicker and iconPicker:IsShown() then iconPicker:Refresh() end
	end
	b:SetScript("OnClick", function(self)
		iconPicker = iconPicker or BuildIconPicker()
		if iconPicker:IsShown() then iconPicker:Hide() return end
		iconPicker:ClearAllPoints()
		iconPicker:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
		iconPicker:Show()
	end)
	refreshers[#refreshers + 1] = Sync
	parent:HookScript("OnShow", Sync)
	return b
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
	plate.previewBar = bar -- side anchors use the bar, as on real plates
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
			if geom.barTop then
				preview.bar:ClearAllPoints()
				preview.bar:SetPoint("TOP", preview.plate, "TOP", 0, -geom.barTop * ratio)
			end
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
local DISPLAY_KEYS = { "active", "enabled", "objects", "anchor", "scale", "offsetX", "offset",
	"objectAnchor", "objectScale", "objectOffsetX", "objectOffset" }
local ICON_KEYS = { "style", "bounce", "bounceHeight", "bounceSpeed", "glow", "glowAlpha" }
local PROGRESS_KEYS = { "progress", "progressAttach", "progressFloat", "progressSize", "progressFont",
	"progressOutline", "progressColor", "progressFormat", "progressShadow", "progressBadge", "badgeShape", "badgeBorderSize", "badgeColor", "badgeBorderColor",
	"progressX", "progressY" }
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
	b:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -16, TOP + SECTION_HEADER - 6)
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

-- Two columns per section: related groups side by side (mobs | items, float | glow, ...).
local COL1, COL2 = LEFT, LEFT + 290
local COLUMN_DROPDOWN = 200

local function BuildDisplayTab(tab)
	AddResetTabButton(tab, function() ResetKeys(DISPLAY_KEYS) end)
	AddCheck(tab, "ENABLE_ADDON", "ENABLE_ADDON_TIP", "active", COL1, TOP)

	-- Anchor menu: which side of the nameplate the icon sits on. Picking a side starts X/Y from
	-- that side (the defaults for "top", zero for the others), so the icon lands right there.
	local function AnchorMenu(key, xKey, yKey, x, y, gate)
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

	local y = TOP - 58
	GateCheck(AddonOn, AddSectionCheck(tab, "QUEST_MOBS", "enabled", COL1, y))
	AnchorMenu("anchor", "offsetX", "offset", COL1 + 4, y - 26, MobsOn)
	Gate(MobsOn, AddSlider(tab, "ICON_SIZE", "scale", 0.5, 3.0, 0.05, COL1 + 4, y - 80, "%.2f"))
	Gate(MobsOn, AddSlider(tab, "POS_X", "offsetX", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, y - 120, "%d"))
	Gate(MobsOn, AddSlider(tab, "POS_Y", "offset", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, y - 160, "%d"))

	GateCheck(AddonOn, AddSectionCheck(tab, "QUEST_ITEMS", "objects", COL2, y))
	AnchorMenu("objectAnchor", "objectOffsetX", "objectOffset", COL2 + 4, y - 26, ItemsOn)
	Gate(ItemsOn, AddSlider(tab, "ICON_SIZE", "objectScale", 0.5, 3.0, 0.05, COL2 + 4, y - 80, "%.2f"))
	Gate(ItemsOn, AddSlider(tab, "POS_X", "objectOffsetX", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, y - 120, "%d"))
	Gate(ItemsOn, AddSlider(tab, "POS_Y", "objectOffset", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, y - 160, "%d"))
end

-- The objective count ("8/12") next to quest mobs: everything about it is its own.
local function BuildProgressTab(tab)
	AddResetTabButton(tab, function() ResetKeys(PROGRESS_KEYS) end)
	-- Left: what it does. Right: how it looks.
	GateCheck(MobsOn, AddCheck(tab, "PROGRESS", "PROGRESS_TIP", "progress", COL1, TOP))
	GateCheck(ProgressOn, AddCheck(tab, "PROGRESS_ATTACH", "PROGRESS_ATTACH_TIP", "progressAttach", COL1, TOP - 48))
	-- Floating with the icon needs the icon's own Float.
	GateCheck(function() return ProgressOn() and db.bounce end,
		AddCheck(tab, "PROGRESS_FLOAT", "PROGRESS_FLOAT_TIP", "progressFloat", COL1, TOP - 96))
	Gate(ProgressOn, AddSlider(tab, "TEXT_SIZE", "progressSize", 8, 32, 1, COL1 + 4, TOP - 150, "%d"))

	local function Choice(key) return function() return db[key] end end
	local function SetChoice(key) return function(value) db[key] = value; ApplySettings() end end
	Gate(ProgressOn, AddDropdown(tab, "TEXT_FORMAT", PROGRESS_FORMATS,
		function(value) return L["FORMAT_" .. value] end, Choice("progressFormat"), SetChoice("progressFormat"),
		COL2 + 4, TOP, COLUMN_DROPDOWN))
	-- The font menu also lists fonts shared by other addons, each drawn in its own font.
	Gate(ProgressOn, AddDropdown(tab, "TEXT_FONT", FontOptions, FontLabel, Choice("progressFont"), SetChoice("progressFont"),
		COL2 + 4, TOP - 54, COLUMN_DROPDOWN, FontPath))
	Gate(ProgressOn, AddDropdown(tab, "TEXT_OUTLINE", { "none", "thin", "thick" },
		function(value) return L["OUTLINE_" .. value] end, Choice("progressOutline"), SetChoice("progressOutline"),
		COL2 + 4, TOP - 108, COLUMN_DROPDOWN))
	Gate(ProgressOn, AddDropdown(tab, "TEXT_COLOR", { "white", "gold", "green", "kind", "progress" },
		function(value) return L["COLOR_" .. value] end, Choice("progressColor"), SetChoice("progressColor"),
		COL2 + 4, TOP - 162, COLUMN_DROPDOWN))
	GateCheck(ProgressOn, AddCheck(tab, "TEXT_SHADOW", "TEXT_SHADOW_TIP", "progressShadow", COL1, TOP - 214))
	GateCheck(ProgressOn, AddCheck(tab, "PROGRESS_BADGE", "PROGRESS_BADGE_TIP", "progressBadge", COL2, TOP - 214))

	-- Attached, the text is glued to the icon: X/Y only apply when it stands on its own.
	local function FreeTextOn() return ProgressOn() and not db.progressAttach end
	Gate(FreeTextOn, AddSlider(tab, "POS_X", "progressX", -POSITION_RANGE, POSITION_RANGE, 1, COL1 + 4, TOP - 270, "%d"))
	Gate(FreeTextOn, AddSlider(tab, "POS_Y", "progressY", -POSITION_RANGE, POSITION_RANGE, 1, COL2 + 4, TOP - 270, "%d"))

	-- Badge look: shape and border thickness, then fill and border colours (the text colour is above).
	local function BadgeOn() return ProgressOn() and db.progressBadge end
	Gate(BadgeOn, AddDropdown(tab, "BADGE_SHAPE", BADGE_SHAPES,
		function(value) return L["SHAPE_" .. value] end, Choice("badgeShape"), SetChoice("badgeShape"),
		COL1 + 4, TOP - 322, COLUMN_DROPDOWN))
	Gate(BadgeOn, AddSlider(tab, "BADGE_BORDER", "badgeBorderSize", 0, 4, 1, COL2 + 4, TOP - 322, "%d"))
	Gate(BadgeOn, AddColorSwatch(tab, "BADGE_COLOR", "badgeColor", COL1 + 4, TOP - 376))
	Gate(BadgeOn, AddColorSwatch(tab, "BADGE_BORDER_COLOR", "badgeBorderColor", COL2 + 4, TOP - 376))
end

local function BuildIconTab(tab)
	AddResetTabButton(tab, function() ResetKeys(ICON_KEYS) end)
	Gate(AnyIconOn, AddHeading(tab, "ICON_STYLE", COL1, TOP))
	Gate(AnyIconOn, AddIconPicker(tab, COL1 + 4, TOP - 18))

	local y = TOP - 82
	GateCheck(AnyIconOn, AddSectionCheck(tab, "FLOAT", "bounce", COL1, y))
	Gate(FloatOn, AddSlider(tab, "FLOAT_HEIGHT", "bounceHeight", 1, 20, 1, COL1 + 4, y - 22, "%d"))
	Gate(FloatOn, AddSlider(tab, "FLOAT_TIME", "bounceSpeed", 0.3, 2.0, 0.05, COL1 + 4, y - 62, "%.2f"))

	GateCheck(AnyIconOn, AddSectionCheck(tab, "GLOW_SECTION", "glow", COL2, y))
	Gate(GlowOn, AddSlider(tab, "GLOW_INTENSITY", "glowAlpha", 0.1, 1.0, 0.05, COL2 + 4, y - 22, "%.2f"))
end

local function BuildBehaviorTab(tab)
	AddResetTabButton(tab, function()
		ResetKeys(BEHAVIOR_KEYS)
		root.language = "auto"
		L = BuildLocale("auto")
		Relabel()
	end)
	-- Left: how the icons behave. Right: language and sound.
	GateCheck(AnyIconOn, AddCheck(tab, "COLOR_BY_TYPE", "COLOR_BY_TYPE_TIP", "colorByType", COL1, TOP))
	-- The minimap button stays usable with the addon off: it is how you turn it back on.
	AddCheck(tab, "MINIMAP", "MINIMAP_TIP", "minimap", COL1, TOP - 48)
	Gate(AnyIconOn, AddDropdown(tab, "IN_COMBAT", { "show", "fade", "hide" },
		function(value) return L["COMBAT_" .. value:upper()] end,
		function() return db.combat end,
		function(value) db.combat = value; UpdateCombatAlpha() end,
		COL1 + 4, TOP - 100, COLUMN_DROPDOWN))

	local languages = { "auto" }
	for _, code in ipairs(ns.LANGUAGES) do languages[#languages + 1] = code end
	AddDropdown(tab, "LANGUAGE", languages,
		function(code) return code == "auto" and L.LANGUAGE_AUTO or ns.LANGUAGE_NAMES[code] end,
		function() return root.language end,
		function(code) root.language = code; L = BuildLocale(code); Relabel() end,
		COL2 + 4, TOP, COLUMN_DROPDOWN)

	-- Sound when an objective completes: on/off, which sound, and a button to hear it.
	local function SoundOn() return AddonOn() and db.sound end
	GateCheck(AddonOn, AddCheck(tab, "SOUND", "SOUND_TIP", "sound", COL2, TOP - 56))
	Gate(SoundOn, AddDropdown(tab, "SOUND_CHOICE", QUEST_SOUND_ORDER,
		function(value) return L["SOUND_" .. value] end,
		function() return db.soundChoice end,
		function(value) db.soundChoice = value; PlayQuestSound() end,
		COL2 + 4, TOP - 104, 140))
	local test = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
	test:SetSize(70, 22)
	test:SetPoint("TOPLEFT", COL2 + 152, TOP - 123)
	Loc(test, "SOUND_TEST")
	test:SetScript("OnClick", PlayQuestSound)
	Gate(SoundOn, test)
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
	{ key = "TAB_ICON", build = BuildIconTab, height = 184 },
	{ key = "TAB_PROGRESS", build = BuildProgressTab, height = 404 },
	{ key = "TAB_BEHAVIOR", build = BuildBehaviorTab, height = 152 },
}
local SECTION_GAP = 18
local CONTENT_WIDTH = 600 -- until the scroll frame reports its real width

local function BuildSettingsTab(tab, box)
	local scroll = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -8)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)
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
		section:SetPoint("TOPLEFT", content, "TOPLEFT", -12, -(y + SECTION_HEADER) - TOP)
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

local function BuildPanel()
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 16, -16)
	header:SetText(TITLE)
	-- Version next to the title (the packager fills it in; a dev copy shows "dev").
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta(ADDON, "Version")
	if not version or version:find("^@") then version = "dev" end
	local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	versionText:SetPoint("BOTTOMLEFT", header, "BOTTOMRIGHT", 8, 1)
	versionText:SetText(version)
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

-- How far below the top of its plate (or UnitFrame) the bar is anchored, from its anchor points.
local function BarOffsetFromAnchors(bar, plate, frame)
	local ok, count = pcall(bar.GetNumPoints, bar)
	if not ok or type(count) ~= "number" then return end
	for i = 1, count do
		local ok2, _, rel, relPoint, _, y = pcall(bar.GetPoint, bar, i)
		if ok2 and (rel == plate or rel == frame) and type(relPoint) == "string" and relPoint:find("TOP") and type(y) == "number" then
			return -y
		end
	end
end

local function MeasurePlate(unit, force)
	if (plateMeasured and not force) or not (root and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
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
			geom.barTop = BarOffsetFromAnchors(bar, plate, frame) -- positions are restricted here
		end
	end
	root.plateGeom = geom
	plateMeasured = true
	if UpdatePreview then UpdatePreview() end
	return geom
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
				geom.barTop and string.format("%.0f", geom.barTop) or "?") or "not found"))
	else
		OpenPanel()
	end
end
