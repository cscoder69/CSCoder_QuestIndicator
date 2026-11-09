-- Makes the badge end caps: white shapes with smooth (4x4 supersampled) alpha edges, tinted in
-- game. Each cap is the left end of a rounded rectangle 64 px tall; the right end is the same
-- texture mirrored.
--   icons/badge/pill.tga     32x64, radius 32 (a half circle)
--   icons/badge/rounded.tga  16x64, radius 12 (rounded corners)
-- usage: luajit tools/make_badge.lua <addon dir>
local dir = arg[1] or "."
local H = 64

local function inside(x, y, r)
	-- Corner circles sit at (r, r) and (r, H - r); right of them the shape is solid.
	if x >= r then return true end
	local cy = (y < r) and r or ((y > H - r) and (H - r) or nil)
	if not cy then return true end
	local dx, dy = x - r, y - cy
	return dx * dx + dy * dy <= r * r
end

local function cap(path, width, radius)
	local pixels = {}
	for y = 0, H - 1 do
		for x = 0, width - 1 do
			local hits = 0
			for sy = 0, 3 do
				for sx = 0, 3 do
					if inside(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4, radius) then hits = hits + 1 end
				end
			end
			local a = math.floor(hits / 16 * 255 + 0.5)
			pixels[#pixels + 1] = string.char(255, 255, 255, a) -- BGRA
		end
	end
	-- 32-bit uncompressed TGA, top-left origin (descriptor 0x28: 8 alpha bits + top origin).
	local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		width % 256, math.floor(width / 256), H % 256, math.floor(H / 256), 32, 0x28)
	local f = assert(io.open(path, "wb"))
	f:write(header, table.concat(pixels))
	f:close()
	print(path, width .. "x" .. H)
end

os.execute('mkdir "' .. dir .. '/icons/badge" 2>nul')
cap(dir .. "/icons/badge/pill.tga", 32, 32)
cap(dir .. "/icons/badge/rounded.tga", 16, 12)
