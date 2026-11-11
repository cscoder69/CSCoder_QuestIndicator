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
			elseif k == "SetVertexColor" then self._color = a
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

	-- Inside a dungeon the mob never gets an icon (the game's limit, not an option).
	related = true
	env.IsInInstance = function() return true, "party" end
	try("plate in dungeon", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("plate in dungeon", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local shownInDungeon = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then shownInDungeon = true end end
	print("quest: icon hidden in a dungeon", not shownInDungeon)
	env.IsInInstance = nil

	-- A forbidden plate (dungeons can hand them out) is never touched, even outside instances.
	rawset(mobPlate, "IsForbidden", function() return true end)
	try("forbidden plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("forbidden plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local onForbidden = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then onForbidden = true end end
	print("quest: forbidden plate left alone", not onForbidden)
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

	-- Same, but quest B asks for an item named nothing like the mob: still marked, no count.
	env.C_QuestLog.GetQuestObjectives = function() return { { text = "Bundle of Hides: 1/5", finished = false } } end
	try("multiquest scan 2", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	try("multiquest plate 2", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("multiquest plate 2", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local marked = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then marked = true end end
	print("quest: mob still marked when no objective names it", marked)

	-- In a group: our objective is done (8/8), a party member's (listed under their QuestPlayer
	-- row) is not. Their progress must not mark the mob for us.
	env.Enum.TooltipDataLineType.QuestPlayer = 18
	env.UnitGUID = function(unit) return unit == "player" and "Player-1" or "Creature-0-1" end
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return nil end
	env.C_QuestLog.GetQuestObjectives = function() return {} end
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = {
			{ type = 17, leftText = "Quest A" },
			{ type = 8, leftText = "Kobold Vermin slain: 8/8", completed = true },
			{ type = 18, leftText = "Friend", guid = "Player-2" },
			{ type = 8, leftText = "Kobold Vermin slain: 1/8", completed = false },
		} }
	end }
	try("party scan", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	try("party plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
	try("party plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local forParty = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then forParty = true end end
	print("quest: party member's objective ignored", not forParty)

	-- Secret values (WoW Forever hides tooltip data, e.g. objects in combat): no error, and an
	-- icon already shown stays as it was.
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = { { type = 17, leftText = "Quest A" }, { type = 8, leftText = "Kobold Vermin slain: 2/8", completed = false } } }
	end }
	try("secret setup", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
	local SECRET = {}
	env.issecretvalue = function(value) return value == SECRET end
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = { { type = 17, leftText = SECRET }, { type = 8, leftText = SECRET, completed = SECRET } } }
	end }
	try("secret refresh", eventFrame._scripts.OnUpdate, eventFrame, 2)
	local kept = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then kept = true end end
	print("quest: icon kept while the data is secret", kept)
	env.issecretvalue = nil

	-- Questie as a helper. The game says the mob matters, the tooltip shows only a finished
	-- quest, and quest B's objective names an item ("Bundle of Hides"), not the mob.
	local function PlateCount()
		try("questie plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
		try("questie plate", eventFrame._scripts.OnEvent, eventFrame, "NAME_PLATE_UNIT_ADDED", "nameplate1")
		for _, f in ipairs(frames) do
			if rawget(f, "unit") == "nameplate1" and f._shown then return true, rawget(f, "progressValue") end
		end
		return false, nil
	end
	local savedGetInfo, savedAddOns = env.C_QuestLog.GetInfo, env.C_AddOns
	env.C_QuestLog.GetInfo = function() return { title = "Quest B", questID = 202, isHeader = false } end
	env.C_QuestLog.GetNumQuestLogEntries = function() return 1 end
	env.C_QuestLog.GetQuestObjectives = function() return { { text = "Bundle of Hides: 1/5", finished = false } } end
	env.UnitGUID = function(unit) return unit == "player" and "Player-1" or "Creature-0-1-2-3-123-0" end
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = { { type = 17, leftText = "Quest A" }, { type = 8, leftText = "Kobold Vermin slain: 3/3", completed = true } } }
	end }
	local questieOn = false
	env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Questie" and questieOn end }
	local fakeQuestie = { lookupByKey = {
		m_123 = { ["202 1"] = { questId = 202, objective = { Completed = false, Collected = 1, Needed = 5, Update = function() end } } },
	} }
	env.QuestieLoader = { ImportModule = function() return fakeQuestie end }
	try("questie log", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	-- Installed but disabled on this character: not used (marked, no count).
	local shownOff, countOff = PlateCount()
	print("questie: disabled -> not used", shownOff and countOff == nil)
	-- Loaded: its count fills the gap.
	questieOn = true
	local shownOn, countOn = PlateCount()
	print("questie: loaded -> count from Questie", shownOn and countOn)
	-- The game says "not related": Questie never overrules it.
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return false end
	local shownNo = PlateCount()
	print("questie: game's no wins", not shownNo)
	env.C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end
	-- A broken Questie (odd entries, an Update that errors) must not break anything.
	fakeQuestie.lookupByKey.m_123 = { odd = "text", ["202 1"] = { questId = 202, objective = {
		Update = function() error("Questie inside changed") end,
		Completed = false, Collected = "?", Needed = setmetatable({}, { __index = function() error("boom") end }) } } }
	local shownBroken = PlateCount()
	print("questie: broken data -> still marked, no error", shownBroken)
	env.QuestieLoader = nil
	env.C_AddOns, env.C_QuestLog.GetInfo = savedAddOns, savedGetInfo

	-- "Hide while fighting it" (off by default): on, the mob fighting you loses its icon; when
	-- the fight ends without a kill (threat gone), the icon comes back.
	env.C_TooltipInfo = { GetUnit = function()
		return { lines = { { type = 17, leftText = "Quest A" }, { type = 8, leftText = "Kobold Vermin slain: 2/8", completed = false } } }
	end }
	local threat = 2
	env.UnitThreatSituation = function() return threat end
	local shownDefault = PlateCount()
	print("fight: default off -> icon stays", shownDefault)
	profile.hideWhileFighting = true
	try("fight threat", eventFrame._scripts.OnEvent, eventFrame, "UNIT_THREAT_LIST_UPDATE", "nameplate1")
	local fightingShown = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then fightingShown = true end end
	print("fight: on -> hidden while fighting", not fightingShown)
	threat = nil
	try("fight over", eventFrame._scripts.OnEvent, eventFrame, "PLAYER_REGEN_ENABLED")
	local back = false
	for _, f in ipairs(frames) do if rawget(f, "unit") == "nameplate1" and f._shown then back = true end end
	print("fight: survived -> icon back", back)
	profile.hideWhileFighting = false
	env.UnitThreatSituation = nil

	-- "Warn about high-level quests" (on by default): quest level 20, player level 10 -> red;
	-- player level 18 (2 below) -> normal colour.
	local playerLevel = 10
	env.UnitLevel = function() return playerLevel end
	env.C_QuestLog.GetInfo = function() return { title = "Quest A", questID = 101, isHeader = false, level = 20 } end
	env.C_QuestLog.GetNumQuestLogEntries = function() return 1 end
	try("high level log", eventFrame._scripts.OnEvent, eventFrame, "QUEST_LOG_UPDATE")
	local function IconGreen()
		PlateCount()
		for _, f in ipairs(frames) do
			if rawget(f, "unit") == "nameplate1" and f._shown then
				local color = rawget(f, "icon") and rawget(rawget(f, "icon"), "_color")
				return color and color[2]
			end
		end
	end
	-- One shade per level: 1 above = normal, 2 = light, 3 = deeper, 4+ = full red.
	local shades = {}
	for _, gap in ipairs({ 1, 2, 3, 4, 10 }) do
		playerLevel = 20 - gap
		try("level up", eventFrame._scripts.OnEvent, eventFrame, "PLAYER_LEVEL_UP")
		shades[#shades + 1] = IconGreen() or 1
	end
	print("level: green per gap 1/2/3/4/10", table.concat(shades, " "))
	print("level: shades step down, full red from 4", shades[1] == 1 and shades[2] < 1 and shades[3] < shades[2]
		and shades[4] < shades[3] and shades[5] == shades[4])

	-- Quest pickup (Gameplay). The pickup block's event frame is the last one with OnEvent
	-- created before the main event frame.
	local pickupFrame
	for _, f in ipairs(frames) do
		if f == eventFrame then break end
		if f._scripts.OnEvent then pickupFrame = f end
	end
	local function Fire(event) try("pickup " .. event, pickupFrame._scripts.OnEvent, pickupFrame, event) end
	-- The talk ends: the NPC's window closes (then opens again for the next case).
	local function Close() env.GossipFrame:Hide(); env.QuestFrame:Hide(); Fire("GOSSIP_CLOSED"); env.GossipFrame:Show(); env.QuestFrame:Show() end
	local available, current, accepted, opened = {}, nil, 0, 0
	local logFull = false
	local function Reset() available = { { questID = 1, title = "A" }, { questID = 2, title = "B" }, { questID = 3, title = "C", frequency = 1 } }; accepted, opened = 0, 0 end
	env.C_GossipInfo = {
		GetAvailableQuests = function() return available end,
		SelectAvailableQuest = function(id) opened = opened + 1; current = id; Fire("QUEST_DETAIL") end,
	}
	env.AcceptQuest = function()
		if logFull then Fire("GOSSIP_SHOW") return end
		accepted = accepted + 1
		for i, q in ipairs(available) do if q.questID == current then table.remove(available, i) break end end
		Fire("GOSSIP_SHOW") -- the game reopens the NPC's window
	end
	env.UnitExists = function(unit) return unit == "npc" or unit == "questnpc" end
	env.UnitGUID = function(unit) return unit == "player" and "Player-1" or "Creature-0-1-2-3-555-0" end
	local shift = false
	env.IsShiftKeyDown = function() return shift end
	env.GossipFrame = env.CreateFrame("Frame")
	env.QuestFrame = env.CreateFrame("Frame")
	env.GetTime = function() return 1000 end

	Reset(); Fire("GOSSIP_SHOW")
	print("pickup: off by default -> nothing", accepted == 0)
	profile.questPickup, profile.questPickupMode, profile.questPickupRepeatable = true, "auto", true -- (the UI clicks above changed them)
	Reset(); Fire("GOSSIP_SHOW")
	print("pickup: auto -> all 3 accepted (daily too)", accepted)
	Close()
	profile.questPickupRepeatable = false
	Reset(); Fire("GOSSIP_SHOW")
	print("pickup: repeatables off -> 2 accepted", accepted)
	Close()
	profile.questPickupRepeatable = true
	shift = true
	Reset(); Fire("GOSSIP_SHOW")
	print("pickup: Shift held -> nothing", accepted == 0)
	shift = false
	Close()
	logFull = true
	Reset(); Fire("GOSSIP_SHOW")
	print("pickup: full quest log -> each opened once, no loop", opened == 3 and accepted == 0)
	logFull = false
	Close()
	profile.questPickupMode = "button"
	Reset(); Fire("GOSSIP_SHOW")
	local pickButton
	for _, f in ipairs(frames) do if rawget(f, "nextQuest") then pickButton = f end end
	print("pickup: button mode -> nothing yet, button shown", accepted == 0 and pickButton ~= nil and pickButton._shown)
	if pickButton then try("pickup click", pickButton._scripts.OnClick, pickButton) end
	print("pickup: button click -> all 3 accepted", accepted)
	-- Button mode, NPC with a single quest (it opens straight away, no list): accepted at once.
	Close(); Reset(); current = 1
	Fire("QUEST_DETAIL")
	print("pickup: button mode, single quest -> accepted at once", accepted == 1)
	-- Button mode, a quest the player picks from a list: theirs to accept.
	Close(); Reset()
	local savedAccept = env.AcceptQuest
	env.AcceptQuest = function() accepted = accepted + 1 end
	Fire("GOSSIP_SHOW"); current = 2; Fire("QUEST_DETAIL")
	print("pickup: button mode, quest picked from a list -> left to the player", accepted == 0)
	env.AcceptQuest = savedAccept
	-- Shift on a single-quest NPC: nothing automatic.
	Close(); Reset(); shift = true; current = 1
	Fire("QUEST_DETAIL")
	print("pickup: Shift on a single quest -> nothing", accepted == 0)
	shift = false
	Close()
	-- A quest shared by a player is never accepted.
	profile.questPickupMode = "auto"
	env.UnitGUID = function() return "Player-2" end
	accepted = 0; Fire("QUEST_DETAIL")
	print("pickup: shared by a player -> left alone", accepted == 0)
	-- Questie's own auto-accept on: we stay out of the way.
	env.UnitGUID = function(unit) return unit == "player" and "Player-1" or "Creature-0-1-2-3-555-0" end
	env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Questie" end }
	env.Questie = { db = { profile = { autoAccept = { enabled = true } } } }
	Close(); Reset(); Fire("GOSSIP_SHOW")
	print("pickup: Questie's auto-accept on -> we do nothing", accepted == 0)
	env.Questie, env.C_AddOns = nil, savedAddOns
	profile.questPickup = false

	-- Auto turn-in (separate switch). Quest 10 is finished, 11 isn't.
	local active, turned, choices = {}, 0, 0
	local function ResetActive() active = { { questID = 10, title = "Done", isComplete = true }, { questID = 11, title = "Open", isComplete = false } }; turned = 0 end
	env.C_GossipInfo = {
		GetAvailableQuests = function() return {} end,
		SelectAvailableQuest = function() end,
		GetActiveQuests = function() return active end,
		SelectActiveQuest = function(id) current = id; Fire("QUEST_PROGRESS") end,
	}
	env.IsQuestCompletable = function() return true end
	env.CompleteQuest = function() Fire("QUEST_COMPLETE") end
	env.GetNumQuestChoices = function() return choices end
	env.GetQuestReward = function()
		turned = turned + 1
		for i, q in ipairs(active) do if q.questID == current then table.remove(active, i) break end end
		Fire("GOSSIP_SHOW")
	end
	Close(); ResetActive(); Fire("GOSSIP_SHOW")
	print("turnin: off by default -> nothing", turned == 0)
	profile.questTurnIn = true
	Close(); ResetActive(); Fire("GOSSIP_SHOW")
	print("turnin: on -> the finished quest handed in (only it)", turned == 1)
	choices = 2
	Close(); ResetActive(); Fire("GOSSIP_SHOW")
	print("turnin: reward to choose -> nothing done, no loop", turned == 0)
	choices = 0
	env.C_AddOns = { IsAddOnLoaded = function(name) return name == "Questie" end }
	env.Questie = { db = { profile = { autocomplete = true } } }
	Close(); ResetActive(); Fire("GOSSIP_SHOW")
	print("turnin: Questie's auto-complete on -> we do nothing", turned == 0)
	env.Questie, env.C_AddOns = nil, savedAddOns
	profile.questTurnIn = false
	profile.questPickup = false
	env.C_GossipInfo, env.AcceptQuest, env.GossipFrame, env.QuestFrame = nil, nil, nil, nil
	rawset(env, "Questie", nil)
	env.C_QuestLog.GetInfo = savedGetInfo
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
local known = { IsMouseButtonDown = 1, IsShiftKeyDown = 1, GetAddOnMetadata = 1, GetQuestLogTitle = 1, GetNumQuestLogEntries = 1, C_TooltipInfo = 1, UnitIsGameObject = 1, C_AddOns = 1, IsAddOnLoaded = 1, InterfaceOptions_AddCategory = 1, InterfaceOptionsFrame_OpenToCategory = 1, CSCoderQuestIndicatorDB = 1, CSCoderOptionsParent = 1, CreateColor = 1, IsInInstance = 1, SettingsPanel = 1, InterfaceOptionsFrame = 1, HideUIPanel = 1, QuestIsDaily = 1, QuestIsWeekly = 1, Questie = 1, issecretvalue = 1, issecrettable = 1, UnitGUID = 1 }
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
