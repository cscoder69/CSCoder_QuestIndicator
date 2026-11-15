-- CS.Coder shared minimap button: ONE "CS" button for every CS.Coder addon installed.
-- Every CS.Coder addon ships this same file; the highest VERSION loaded wins and the others
-- only register into it. One addon: left-click opens its options, right-click does its own
-- action. Two or more: a click opens a small menu to pick the addon.
--
-- CSCoderMinimap.Register({
--   name = "Quest Indicator",          -- shown in the menu and the tooltip
--   open = function() end,             -- left-click (its options)
--   rightClick = function() end,       -- optional: right-click (e.g. turn it on/off)
--   leftHint = "...", rightHint = "...", dragHint = "...", -- optional tooltip hints (localized)
--   tooltip = function(tooltip) end,   -- optional: extra tooltip lines
--   shown = function() return true end,  -- does this addon want the button?
--   active = function() return true end, -- is it switched on? (grey "CS" when none is)
--   getAngle = function() end, setAngle = function(degrees) end, -- where the position is saved
-- })
-- CSCoderMinimap.Update() refreshes it (after an option changes).

local VERSION = 1
local lib = _G.CSCoderMinimap
if lib and (lib.version or 0) >= VERSION then return end
lib = lib or {}
lib.addons = lib.addons or {}
lib.version = VERSION
_G.CSCoderMinimap = lib

local DEFAULT_ANGLE = 200

local function Angle()
	for _, entry in ipairs(lib.addons) do
		local angle = entry.getAngle and entry.getAngle()
		if type(angle) == "number" then return angle end
	end
	return DEFAULT_ANGLE
end

function lib.Place()
	local b = lib.button
	if not b then return end
	local angle = math.rad(Angle())
	local radius = (Minimap:GetWidth() / 2) + 6
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function HideMenu() if lib.menu then lib.menu:Hide() end end

local function ShowMenu(anchor)
	local menu = lib.menu
	if not menu then
		menu = CreateFrame("Frame", "CSCoder_MinimapMenu", UIParent)
		menu:SetFrameStrata("DIALOG")
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		local bg = menu:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.07, 0.06, 0.04, 0.97)
		for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
			local e = menu:CreateTexture(nil, "BORDER")
			e:SetColorTexture(1, 0.82, 0, 0.7)
			if side == "TOP" or side == "BOTTOM" then
				e:SetPoint(side .. "LEFT"); e:SetPoint(side .. "RIGHT"); e:SetHeight(1)
			else
				e:SetPoint("TOP" .. side); e:SetPoint("BOTTOM" .. side); e:SetWidth(1)
			end
		end
		menu.title = menu:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		menu.title:SetPoint("TOPLEFT", 10, -8)
		menu.title:SetText("CS.Coder")
		menu.rows = {}
		-- Closes a moment after the mouse leaves it.
		menu:SetScript("OnUpdate", function(self, elapsed)
			if self:IsMouseOver() or (lib.button and lib.button:IsMouseOver()) then
				self.away = 0
			else
				self.away = (self.away or 0) + elapsed
				if self.away > 1.5 then self:Hide() end
			end
		end)
		if UISpecialFrames then table.insert(UISpecialFrames, menu:GetName()) end
		lib.menu = menu
	end
	local width = 160
	for i, entry in ipairs(lib.addons) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, menu)
			row:SetHeight(20)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.82, 0, 0.15)
			row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			row.text:SetPoint("LEFT", 8, 0)
			menu.rows[i] = row
		end
		row:SetPoint("TOPLEFT", 4, -26 - (i - 1) * 20)
		row:SetPoint("RIGHT", -4, 0)
		local on = not entry.active or entry.active()
		row.text:SetText(entry.name)
		row.text:SetTextColor(on and 1 or 0.55, on and 1 or 0.55, on and 1 or 0.55)
		width = math.max(width, row.text:GetStringWidth() + 32)
		row:SetScript("OnClick", function(_, button)
			HideMenu()
			if button == "RightButton" and entry.rightClick then entry.rightClick() else entry.open() end
			lib.Update()
		end)
		row:Show()
	end
	for i = #lib.addons + 1, #menu.rows do menu.rows[i]:Hide() end
	menu:SetSize(width, 32 + #lib.addons * 20)
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 8, 8)
	menu.away = 0
	menu:Show()
end

local function Create()
	local b = CreateFrame("Button", "CSCoder_MinimapButton", Minimap)
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
	local dark = b:CreateTexture(nil, "BORDER")
	dark:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	dark:SetVertexColor(0.1, 0.08, 0.05, 1)
	dark:SetAllPoints(bg)
	b.text = b:CreateFontString(nil, "ARTWORK")
	if not pcall(b.text.SetFont, b.text, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE") then b.text:SetFontObject("GameFontNormalSmall") end
	b.text:SetPoint("CENTER", bg, "CENTER", 0, 0)
	b.text:SetText("CS")
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(self, button)
		GameTooltip:Hide()
		if #lib.addons == 1 then
			local entry = lib.addons[1]
			if button == "RightButton" and entry.rightClick then entry.rightClick() else entry.open() end
			lib.Update()
		elseif lib.menu and lib.menu:IsShown() then
			HideMenu()
		else
			ShowMenu(self)
		end
	end)
	b:SetScript("OnDragStart", function(self)
		HideMenu()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			for _, entry in ipairs(lib.addons) do if entry.setAngle then entry.setAngle(angle) end end
			lib.Place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		if lib.menu and lib.menu:IsShown() then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if #lib.addons == 1 then
			local entry = lib.addons[1]
			GameTooltip:SetText("CS.Coder - " .. entry.name)
			if entry.leftHint then GameTooltip:AddLine(entry.leftHint, 1, 1, 1) end
			if entry.rightHint then GameTooltip:AddLine(entry.rightHint, 1, 1, 1) end
			GameTooltip:AddLine(entry.dragHint or "Drag: move this button", 0.7, 0.7, 0.7)
			if entry.tooltip then pcall(entry.tooltip, GameTooltip) end
		else
			GameTooltip:SetText("CS.Coder")
			GameTooltip:AddLine("Click: choose which addon to open", 1, 1, 1)
			GameTooltip:AddLine("Right-click a name in the menu: its quick action", 0.8, 0.8, 0.8)
			GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
			for _, entry in ipairs(lib.addons) do
				local on = not entry.active or entry.active()
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(entry.name .. (on and "" or " (off)"), 1, 0.82, 0)
				if entry.tooltip then pcall(entry.tooltip, GameTooltip) end
			end
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

function lib.Register(entry)
	for i, old in ipairs(lib.addons) do
		if old.name == entry.name then lib.addons[i] = entry; lib.Update() return end
	end
	table.insert(lib.addons, entry)
	table.sort(lib.addons, function(a, b) return a.name < b.name end)
	lib.Update()
end

function lib.Update()
	if not Minimap then return end
	local wanted, on = false, false
	for _, entry in ipairs(lib.addons) do
		if not entry.shown or entry.shown() then wanted = true end
		if not entry.active or entry.active() then on = true end
	end
	if not wanted then
		if lib.button then lib.button:Hide() end
		HideMenu()
		return
	end
	lib.button = lib.button or Create()
	lib.button.text:SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
	lib.Place()
	lib.button:Show()
end
