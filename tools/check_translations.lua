-- Lists the panel texts each language still lacks (they fall back to English) and exits with an
-- error when any is missing, so the release check can stop a half-translated version.
-- usage: luajit tools/check_translations.lua <addon dir>
local dir = arg[1] or "."
local ns = {}
assert(loadfile(dir .. "/Locales.lua"))("CSCoder_QuestIndicator", ns)
local en = ns.locales.enUS
-- Same in every language on purpose.
local skip = { POS_X = true, POS_Y = true }
local total = 0
for _, code in ipairs(ns.LANGUAGES) do
	if code ~= "enUS" then
		local missing = {}
		for key in pairs(en) do
			if ns.locales[code][key] == nil and not key:match("^FONT_") and not skip[key] then missing[#missing + 1] = key end
		end
		table.sort(missing)
		total = total + #missing
		print(code, #missing, table.concat(missing, " "))
	end
end
print("missing translations:", total)
os.exit(total > 0 and 1 or 0)
