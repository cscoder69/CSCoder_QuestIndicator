-- Minimal WoW API mock to smoke-test the addon outside the game.
-- usage: luajit wowmock.lua <addon dir>
local dir = arg[1]
local frames, errors, missing = {}, {}, {}

local function newObject(kind)
	local o = { _scripts = {}, _kind = kind, _text = "", _shown = true, _value = 0 }
	frames[#frames + 1] = o
	return setmetatable(o, { __index = function(_, k)
		if k == "Text" or k == "text" then return nil end
		-- Fields (lower case: f.progressValue, f.completing...) are nil until set, as in the game;
		-- only methods (upper case) are faked.
		if k:match("^%l") or k == "UnitFrame" then return nil end
		return function(self, ...)
			local a = { ... }
			if k == "SetScript" then self._scripts[a[1]] = a[2]
			elseif k == "HookScript" then local old = self._scripts[a[1]]; self._scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
			elseif k == "GetScript" then return self._scripts[a[1]]
			elseif k:match("^Create") or k == "GetHighlightTexture" then return newObject(k)
			elseif k == "SetText" then self._text = a[1]
			elseif k == "GetText" then return self._text
			elseif k == "SetShown" then self._shown = a[1]
			elseif k == "Show" then self._shown = true
			elseif k == "Hide" then self._shown = false
			elseif k == "IsShown" or k == "IsVisible" then return self._shown
			elseif k == "SetValue" then self._value = a[1]; if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, a[1]) end
			elseif k == "GetValue" then return self._value
			elseif k == "SetChecked" then self._checked = a[1]
			elseif k == "GetChecked" then return self._checked
			elseif k == "GetFrameStrata" then return "HIGH"
			elseif k == "GetFrameLevel" then return 1
			elseif k == "GetWidth" then return 140
			elseif k == "GetStringWidth" then return 80
			elseif k == "GetCenter" then return 100, 100
			elseif k == "GetEffectiveScale" then return 1
			elseif k == "IsPlaying" then return false
			elseif k == "GetID" then return 42
			elseif k == "GetName" then return nil
			elseif k == "NumLines" then return 0
			elseif k == "GetParent" then return self._parent or UIParent
			elseif k == "SetParent" then self._parent = a[1]
			end
		end
	end })
end

local env = setmetatable({}, { __index = function(t, k)
	local v = rawget(_G, k)
	if v == nil then missing[k] = true end
	return v
end })

env.CreateFrame = function(kind, name) local f = newObject(kind); if name then rawset(env, name, f) end return f end
env.UIParent, env.WorldFrame, env.Minimap, env.GameTooltip = newObject("UIParent"), newObject("WorldFrame"), newObject("Minimap"), newObject("GameTooltip")
env.GetLocale = function() return rawget(env, "_locale") or "enUS" end
env.UnitName = function() return "Tester" end
env.GetRealmName = function() return "Realm" end
env.UnitExists = function() return false end
env.InCombatLockdown = function() return false end
env.GetCursorPosition = function() return 150, 120 end
env.GetTime = function() return 12.5 end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.print = function(...) end
env.PlaySound = function() end
env.GetBuildInfo = function() return "1.60.1", "12345", "Nov 1 2026", 16001 end
env.date = os.date
-- Error handlers: the addon wraps the current one to keep its own errors for /cqi debug.
local gameHandled = 0
env.geterrorhandler = function() return function() gameHandled = gameHandled + 1 end end
env.seterrorhandler = function(fn) rawset(env, "_handler", fn) end
env.C_Timer = { After = function(_, fn) fn() end }
env.C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return nil end }
env.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, GetInfo = function() return nil end, GetQuestObjectives = function() return {} end }
env.C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end }
env.Settings = {
	RegisterCanvasLayoutCategory = function() return newObject("Category") end,
	RegisterCanvasLayoutSubcategory = function() return newObject("Category") end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}
env.BackdropTemplateMixin = {}
env.Enum = { TooltipDataLineType = { QuestObjective = 8, QuestTitle = 17 } }
env.SlashCmdList = {}
-- Lua builtins the addon uses
for _, k in ipairs({ "pairs", "ipairs", "type", "tostring", "tonumber", "table", "string", "math", "setmetatable", "pcall", "next", "select", "unpack" }) do rawset(env, k, _G[k]) end

if arg[2] == "old" then env.CSCoderQuestIndicatorDB = { version = 4, scale = 2.0, offset = -12, style = "red", glow = true, savedCVars = { SoftTargetIconGameObject = "0" } } end
-- A fake LibSharedMedia with 30 fonts (another addon's), to exercise the multi-column font menu.
local fakeFonts = {}
for i = 1, 30 do fakeFonts[i] = "Shared Font " .. i end
local fakeLSM = { List = function() return fakeFonts end, Fetch = function(_, _, name) return "Interface\\AddOns\\X\\" .. name .. ".ttf" end }
rawset(_G, "LibStub", function(name) return name == "LibSharedMedia-3.0" and fakeLSM or nil end)

local ns = {}
for _, file in ipairs({ "Locales.lua", "CSCoder_QuestIndicator.lua" }) do
	local chunk = assert(loadfile(dir .. "/" .. file))
	setfenv(chunk, env)
	chunk("CSCoder_QuestIndicator", ns)
end

local function try(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
end

local eventFrame
for _, f in ipairs(frames) do if f._scripts.OnEvent then eventFrame = f end end
try("ADDON_LOADED", eventFrame._scripts.OnEvent, eventFrame, "ADDON_LOADED", "CSCoder_QuestIndicator")
try("PLAYER_LOGIN", eventFrame._scripts.OnEvent, eventFrame, "PLAYER_LOGIN")
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "PLAYER_SOFT_INTERACT_CHANGED" }) do
	try(ev, eventFrame._scripts.OnEvent, eventFrame, ev, "SoftTargetInteract")
end
try("OnUpdate", eventFrame._scripts.OnUpdate, eventFrame, 2)

-- Exercise every control a few times (snapshot: clicks may create frames).
local snapshot = {}
for i, f in ipairs(frames) do snapshot[i] = f end
for _, f in ipairs(snapshot) do if f._kind == "EditBox" then f._text = "Raid" end end
local function clickAll(list, round)
	for i, f in ipairs(list) do
		for _, script in ipairs({ "OnShow", "OnEnter", "OnLeave", "OnClick", "OnDragStart", "OnDragStop", "OnEnterPressed" }) do
			if f._scripts[script] then try(script .. "#" .. i, f._scripts[script], f, round == 2 and "RightButton" or "LeftButton") end
		end
		if f._scripts.OnValueChanged then try("Slider#" .. i, f._scripts.OnValueChanged, f, 0.5 * round) end
		if f._scripts.OnUpdate and f ~= eventFrame then try("OnUpdate#" .. i, f._scripts.OnUpdate, f, 0.1) end
	end
end
for round = 1, 3 do clickAll(snapshot, round) end
-- Dropdown rows are made when a list opens: click everything once more, new frames included.
local later = {}
for i, f in ipairs(frames) do later[i] = f end
for _, f in ipairs(later) do if f._kind == "EditBox" then f._text = "Solo" end end
clickAll(later, 1)
try("slash", env.SlashCmdList.CSCODERQUESTINDICATOR, "toggle")
try("slash open", env.SlashCmdList.CSCODERQUESTINDICATOR, "")
try("slash setup", env.SlashCmdList.CSCODERQUESTINDICATOR, "setup")
try("slash news", env.SlashCmdList.CSCODERQUESTINDICATOR, "news")
try("slash debug", env.SlashCmdList.CSCODERQUESTINDICATOR, "debug")
-- An error from this addon is kept for /cqi debug and still reaches the game's handler.
if rawget(env, "_handler") then
	try("error handler", env._handler, "Interface/AddOns/CSCoder_QuestIndicator/CSCoder_QuestIndicator.lua:1: test error")
	try("error handler", env._handler, "Interface/AddOns/OtherAddon/x.lua:1: not ours")
	local kept = env.CSCoderQuestIndicatorDB.lastErrors or {}
	print("errors kept for debug:", #kept, "| passed on to the game:", gameHandled)
	try("slash debug with errors", env.SlashCmdList.CSCODERQUESTINDICATOR, "debug")
end
print("setup seen:", env.CSCoderQuestIndicatorDB.setupSeen["Tester - Realm"])

-- /cqi plate on a fake target plate drawn at 0.8 distance scale: the saved size must be the
-- close-range one (base scale 1, bar 100x10 at 10 from the top).
env.UnitExists = function() return true end
local fakeBar = { GetTop = function() return 90 end, GetSize = function() return 100, 10 end, GetEffectiveScale = function() return 0.8 end }
local fakePlate = { GetSize = function() return 120, 40 end, GetEffectiveScale = function() return 0.8 end, GetScale = function() return 0.8 end,
	GetTop = function() return 100 end, UnitFrame = { GetScale = function() return 1 end, healthBar = fakeBar } }
env.C_NamePlate.GetNamePlateForUnit = function() return fakePlate end
try("slash plate", env.SlashCmdList.CSCODERQUESTINDICATOR, "plate")
local g = env.CSCoderQuestIndicatorDB.plateGeom or {}
print("plate:", g.w, g.h, "base scale", g.eff, "bar", g.barW, g.barH, "top", g.barTop)
env.UnitExists = function() return false end

-- Quest log: one quest whose last objective finishes between two scans -> the sound plays, the
-- quest is announced as ready, and the summary lists open objectives only.
do
	local finished = false
	env.C_QuestLog.GetNumQuestLogEntries = function() return 1 end
	env.C_QuestLog.GetQuestIDForLogIndex = function() return 101 end
	env.C_QuestLog.GetTitleForQuestID = function() return "The Kobold Threat" end
	env.C_QuestLog.GetQuestObjectives = function()
		return { { text = "Kobold Vermin slain: " .. (finished and "10/10" or "9/10"), finished = finished } }
	end
	local saved = env.CSCoderQuestIndicatorDB
	local profile = saved.profiles[saved.chars["Tester - Realm"]]
	profile.active, profile.sound, profile.readyAlert = true, true, true -- "/cqi toggle" above turned it off
	local printed, sounds = {}, 0
	env.print = function(text) printed[#printed + 1] = tostring(text) end
	env.PlaySound = function() sounds = sounds + 1 end
	try("quest scan 1", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	-- At 50% the sound plays on the Dialog channel, whose volume is set and then put back.
	profile.soundVolume = 50
	local cvars, channel = { Sound_EnableDialog = "1", Sound_DialogVolume = "0.8" }, nil
	local getCVar, setCVar = env.C_CVar.GetCVar, env.C_CVar.SetCVar
	env.C_CVar.GetCVar = function(name) return cvars[name] or "0" end
	env.C_CVar.SetCVar = function(name, value) cvars[name] = tostring(value) end
	env.PlaySound = function(_, ch) sounds = sounds + 1; channel = ch end
	finished = true
	try("quest scan 2", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	local ready = false
	for _, line in ipairs(printed) do if line:find("The Kobold Threat", 1, true) then ready = true end end
	print("quest: sound played", sounds > 0, "| ready announced", ready)
	print("quest: volume 50% on", channel, "| dialog volume back to", cvars.Sound_DialogVolume, "| pending", saved.dialogVolume)
	env.C_CVar.GetCVar, env.C_CVar.SetCVar = getCVar, setCVar
	profile.soundVolume = 100

	-- A quest mob on a nameplate: needed (icon), then not needed right after the objective
	-- finished -> its icon turns into the check mark instead of vanishing.
	local related = true
	local mobPlate = newObject("NamePlate")
	mobPlate.namePlateUnitToken = "nameplate1"
	env.UnitExists = function() return true end
	env.UnitIsPlayer = function() return false end
	env.UnitIsDead = function() return false end
	env.UnitIsFriend = function() return false end
	env.UnitCanAttack = function() return true end
	env.UnitName = function() return "Kobold Vermin" end
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return related end
	env.C_NamePlate.GetNamePlates = function() return { mobPlate } end
	env.C_NamePlate.GetNamePlateForUnit = function(unit) return unit == "nameplate1" and mobPlate or nil end
	try("plate added", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	related = false
	try("refresh after done", eventFrame._scripts.OnUpdate, eventFrame, 2)
	local completing = false
	for _, f in ipairs(frames) do if rawget(f, "completing") then completing = true end end
	print("quest: check mark shown", completing)

	-- Inside a dungeon (hideInInstances is on by default) the mob gets no icon.
	related = true
	env.IsInInstance = function() return true, "party" end
	try("plate in dungeon", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("plate in dungeon", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local shownInDungeon = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then shownInDungeon = true end end
	print("quest: icon hidden in a dungeon", not shownInDungeon)
	env.IsInInstance = nil

	-- A forbidden plate (dungeons can hand them out) is never touched, even with the option off.
	profile.hideInInstances = false
	rawset(mobPlate, "IsForbidden", function() return true end)
	try("forbidden plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("forbidden plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local onForbidden = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then onForbidden = true end end
	print("quest: forbidden plate left alone", not onForbidden)
	profile.hideInInstances = true
	rawset(mobPlate, "IsForbidden", nil)

	-- Two quests, same mob: the tooltip lists only quest A, already done (3/3); quest B still
	-- needs the mob (2/8) but isn't in the tooltip. The icon must show, with B's count.
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = {
			{ type = 17, leftText = "Quest A" },
			{ type = 8, leftText = "Kobold Vermin slain: 3/3", completed = true },
		} }
	end }
	env.C_QuestLog.GetNumQuestLogEntries = function() return 1 end
	env.C_QuestLog.GetQuestIDForLogIndex = function() return 202 end
	env.C_QuestLog.GetTitleForQuestID = function() return "Quest B" end
	env.C_QuestLog.GetQuestObjectives = function() return { { text = "Kobold Vermin slain: 2/8", finished = false } } end
	try("multiquest scan", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	try("multiquest plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("multiquest plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local multiCount
	for _, f in ipairs(frames) do
		if rawget(f, "unit") == "nameplate1" and f._shown then multiCount = rawget(f, "progressValue") end
	end
	print("quest: second quest on the same mob shows", multiCount)
	env.C_TooltipInfo = nil
	env.C_QuestLog.GetNumQuestLogEntries = function() return 0 end
	env.UnitExists = function() return false end
	env.C_NamePlate.GetNamePlates = function() return {} end
	env.C_NamePlate.GetNamePlateForUnit = function() return nil end
	env.print = function() end
	env.PlaySound = function() end
	env.C_QuestLog.GetNumQuestLogEntries = function() return 0 end
end

local db = env.CSCoderQuestIndicatorDB
local names = {}
for name in pairs(db.profiles) do names[#names + 1] = name end
print("profiles:", table.concat(names, ", "), "| char ->", db.chars["Tester - Realm"], "| language:", db.language)
local known = { IsMouseButtonDown = 1, IsShiftKeyDown = 1, GetAddOnMetadata = 1, GetQuestLogTitle = 1, GetNumQuestLogEntries = 1, C_TooltipInfo = 1, UnitIsGameObject = 1, C_AddOns = 1, IsAddOnLoaded = 1, InterfaceOptions_AddCategory = 1, InterfaceOptionsFrame_OpenToCategory = 1, CSCoderQuestIndicatorDB = 1, CSCoderOptionsParent = 1, CreateColor = 1, IsInInstance = 1, SettingsPanel = 1, InterfaceOptionsFrame = 1, HideUIPanel = 1 }
local unexpected = {}
for k in pairs(missing) do if not known[k] then unexpected[#unexpected + 1] = k end end
print("unexpected nil globals:", #unexpected == 0 and "none" or table.concat(unexpected, ", "))
print("errors:", #errors)
for _, e in ipairs(errors) do print("  " .. e) end
local pname = db.profiles.Default and "Default" or db.chars["Tester - Realm"]
local p = db.profiles[pname]
print(pname .. ": scale", p.scale, "offset", p.offset, "style", p.style, "glow", p.glow, "| root.scale", db.scale, "| savedCVars", db.savedCVars and db.savedCVars.SoftTargetIconGameObject)

-- Exit code for the release check: any error or unexpected global fails it.
os.exit((#errors > 0 or #unexpected > 0) and 1 or 0)
