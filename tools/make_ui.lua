-- Makes the UI art the options window draws with: a white circle with smooth (4x4
-- supersampled) edges, tinted in game. Switch knobs and slider thumbs use it whole; switch
-- tracks use its left and right halves as round ends and its middle column stretched.
--   icons/ui/circle.tga  64x64
-- usage: luajit tools/make_ui.lua <addon dir>
local dir = arg[1] or "."
local SIZE = 64

local pixels = {}
local r = SIZE / 2
for y = 0, SIZE - 1 do
	for x = 0, SIZE - 1 do
		local hits = 0
		for sy = 0, 3 do
			for sx = 0, 3 do
				local dx, dy = x + (sx + 0.5) / 4 - r, y + (sy + 0.5) / 4 - r
				if dx * dx + dy * dy <= r * r then hits = hits + 1 end
			end
		end
		pixels[#pixels + 1] = string.char(255, 255, 255, math.floor(hits / 16 * 255 + 0.5)) -- BGRA
	end
end
-- 32-bit uncompressed TGA, top-left origin (descriptor 0x28).
local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, SIZE, 0, SIZE, 0, 32, 0x28)
os.execute('mkdir "' .. dir .. '/icons/ui" 2>nul')
local f = assert(io.open(dir .. "/icons/ui/circle.tga", "wb"))
f:write(header, table.concat(pixels))
f:close()
print(dir .. "/icons/ui/circle.tga", SIZE .. "x" .. SIZE)
