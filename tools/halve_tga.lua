-- Halves 32-bit uncompressed TGA icons (e.g. 256 -> 128 px) in place.
-- Each output pixel is the average of a 2x2 block, colour weighted by alpha so transparent
-- pixels don't darken the edges. Keeps the file's origin (top or bottom row first).
-- usage: luajit tools/halve_tga.lua icons/standard/*.tga ...
local bit = require("bit")

local function halve(path)
	local f = assert(io.open(path, "rb"))
	local data = f:read("*a")
	f:close()
	local h = { data:byte(1, 18) }
	local idLen, imageType, bpp = h[1], h[3], h[17]
	local w, ht = h[13] + h[14] * 256, h[15] + h[16] * 256
	if imageType ~= 2 or bpp ~= 32 or w % 2 ~= 0 or ht % 2 ~= 0 then
		return print("skipped (not 32-bit uncompressed, or odd size): " .. path)
	end
	local base = 18 + idLen
	local nw, nh = w / 2, ht / 2
	local out = {}
	for y = 0, nh - 1 do
		for x = 0, nw - 1 do
			local sb, sg, sr, sa = 0, 0, 0, 0
			for dy = 0, 1 do
				for dx = 0, 1 do
					local i = base + ((y * 2 + dy) * w + (x * 2 + dx)) * 4
					local b, g, r, a = data:byte(i + 1, i + 4)
					sb, sg, sr, sa = sb + b * a, sg + g * a, sr + r * a, sa + a
				end
			end
			local b, g, r = 0, 0, 0
			if sa > 0 then
				b, g, r = math.floor(sb / sa + 0.5), math.floor(sg / sa + 0.5), math.floor(sr / sa + 0.5)
			end
			out[#out + 1] = string.char(b, g, r, math.floor(sa / 4 + 0.5))
		end
	end
	h[1] = 0 -- drop the image ID
	h[13], h[14] = nw % 256, math.floor(nw / 256)
	h[15], h[16] = nh % 256, math.floor(nh / 256)
	local header = {}
	for i = 1, 18 do header[i] = string.char(h[i]) end
	f = assert(io.open(path, "wb"))
	f:write(table.concat(header), table.concat(out))
	f:close()
	print(string.format("%s: %dx%d -> %dx%d", path, w, ht, nw, nh))
end

for _, path in ipairs(arg) do halve(path) end
