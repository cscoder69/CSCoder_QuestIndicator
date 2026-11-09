-- Cuts the icon guide sheet (three rows of icons on a transparent background) into one
-- 128x128 TGA per icon, each centred in its square with a small margin.
-- The first set of files was cut on a fixed grid that didn't match the sheet: most icons got a
-- sliver of their left neighbour and lost their right edge. This finds each icon by its shapes.
--
-- Input: the sheet as raw 32-bit BGRA rows (no header), e.g. dumped with System.Drawing LockBits.
-- usage: luajit tools/slice_icons.lua <sheet.raw> <width> <height> <addon dir> [preview]
local bit = require("bit")
local rawPath, W, H, dir = arg[1], tonumber(arg[2]), tonumber(arg[3]), arg[4] or "."
local OUT = 128
local MARGIN = 0.06 -- empty border around the icon, as a share of the square

local ROWS = {
	{ folder = "standard", names = { "yellow", "blue", "red", "green", "purple", "orange", "circle_yellow", "circle_blue",
		"circle_red", "circle_green", "circle_purple", "shield_yellow", "shield_blue", "shield_red" } },
	{ folder = "themed", names = { "laurels", "horde", "alliance", "banner", "scroll", "sign", "gear", "crystal",
		"leaves", "arcane", "stone" } },
	{ folder = "states", names = { "highlight", "ring", "signal", "orbit", "white", "alert", "fire", "bright",
		"inactive", "blocked", "hourglass", "refresh" } },
}

local data = assert(io.open(rawPath, "rb")):read("*a")
assert(#data == W * H * 4, "size mismatch")
local function A(x, y) return data:byte((y * W + x) * 4 + 4) end
local function BGRA(x, y) return data:byte((y * W + x) * 4 + 1, (y * W + x) * 4 + 4) end

-- 1. Horizontal bands: runs of rows with solid pixels.
local SOLID = 200 -- the opaque body; soft glows (lower alpha) touch between icons
local bands, inBand = {}, false
for y = 0, H - 1 do
	local count = 0
	for x = 0, W - 1 do if A(x, y) > SOLID then count = count + 1 end end
	if count > 0 and not inBand then bands[#bands + 1] = { top = y }; inBand = true
	elseif count == 0 and inBand then bands[#bands].bottom = y - 1; inBand = false end
end
if inBand then bands[#bands].bottom = H - 1 end
-- Drop specks (a band must be tall).
local kept = {}
for _, b in ipairs(bands) do if b.bottom - b.top > 40 then kept[#kept + 1] = b end end
bands = kept
assert(#bands == #ROWS, "expected " .. #ROWS .. " rows, found " .. #bands)

-- 2. In each band, solid connected shapes (8-neighbour), then shapes whose columns overlap
-- are one icon (a "!" inside its ring, laurel leaves, sparkle rays next to their "!").
local function Shapes(band)
	local label, shapes = {}, {}
	for y = band.top, band.bottom do
		for x = 0, W - 1 do
			local key = y * W + x
			if A(x, y) > SOLID and not label[key] then
				local s = { x1 = x, x2 = x, y1 = y, y2 = y, n = 0 }
				local stack = { key }
				label[key] = true
				while #stack > 0 do
					local k = table.remove(stack)
					local px, py = k % W, math.floor(k / W)
					s.n = s.n + 1
					if px < s.x1 then s.x1 = px end
					if px > s.x2 then s.x2 = px end
					if py < s.y1 then s.y1 = py end
					if py > s.y2 then s.y2 = py end
					for dy = -1, 1 do
						for dx = -1, 1 do
							local nx, ny = px + dx, py + dy
							if nx >= 0 and nx < W and ny >= band.top and ny <= band.bottom then
								local nk = ny * W + nx
								if not label[nk] and A(nx, ny) > SOLID then label[nk] = true; stack[#stack + 1] = nk end
							end
						end
					end
				end
				if s.n > 30 then shapes[#shapes + 1] = s end
			end
		end
	end
	return shapes
end

local function Cluster(shapes, expected)
	table.sort(shapes, function(a, b) return a.x1 < b.x1 end)
	-- Join shapes that overlap in x; then, if there are still too many groups, join the pair
	-- with the smallest gap until the count is right (rays a few pixels away from their "!").
	-- Only real overlaps count (a shape mostly inside the group's columns): packed icons touch
	-- at their edges and must stay apart.
	local groups = {}
	for _, s in ipairs(shapes) do
		local g = groups[#groups]
		local overlap = g and (math.min(g.x2, s.x2) - s.x1)
		if g and overlap > 0.5 * math.min(s.x2 - s.x1, g.x2 - g.x1) then
			g.x2 = math.max(g.x2, s.x2); g.y1 = math.min(g.y1, s.y1); g.y2 = math.max(g.y2, s.y2)
		else
			groups[#groups + 1] = { x1 = s.x1, x2 = s.x2, y1 = s.y1, y2 = s.y2 }
		end
	end
	-- Icons that touch come out as one wide group: split the widest at its emptiest column
	-- (fewest solid pixels) near the middle, until the count is right.
	-- A group much wider than tall is a row of touching icons (the five ringed ones): it splits
	-- into width / height parts, each cut at the emptiest column near its share.
	if #groups < expected then
		local split = {}
		for _, g in ipairs(groups) do
			local ww, hh = g.x2 - g.x1, g.y2 - g.y1
			local parts = math.max(1, math.floor(ww / hh + 0.5))
			local x1 = g.x1
			for j = 1, parts - 1 do
				local target = g.x1 + ww * j / parts
				local bestX, bestCount
				for x = math.floor(target - ww / parts * 0.2), math.floor(target + ww / parts * 0.2) do
					local count = 0
					for y = g.y1, g.y2 do if A(x, y) > SOLID then count = count + 1 end end
					if not bestCount or count < bestCount then bestX, bestCount = x, count end
				end
				split[#split + 1] = { x1 = x1, x2 = bestX, y1 = g.y1, y2 = g.y2 }
				x1 = bestX + 1
			end
			split[#split + 1] = { x1 = x1, x2 = g.x2, y1 = g.y1, y2 = g.y2 }
		end
		groups = split
	end
	while #groups > expected do
		local best, bestGap
		for i = 1, #groups - 1 do
			-- Weigh the gap by the narrower group: small bits belong to their neighbour.
			local gap = (groups[i + 1].x1 - groups[i].x2) * math.min(groups[i].x2 - groups[i].x1, groups[i + 1].x2 - groups[i + 1].x1)
			if not bestGap or gap < bestGap then best, bestGap = i, gap end
		end
		local a, b = groups[best], table.remove(groups, best + 1)
		a.x2 = math.max(a.x2, b.x2); a.y1 = math.min(a.y1, b.y1); a.y2 = math.max(a.y2, b.y2)
	end
	return groups
end

-- 3. Cut each icon: columns up to halfway to its neighbours (soft glow included, neighbours
-- not), rows of the band; trim to the visible pixels, centre in a square, shrink to 128.
local function WriteTGA(path, size, pixels)
	local header = string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, size % 256, math.floor(size / 256),
		size % 256, math.floor(size / 256), 32, 0x28)
	local f = assert(io.open(path, "wb"))
	f:write(header, table.concat(pixels))
	f:close()
end

local VISIBLE = 6
for r, row in ipairs(ROWS) do
	local band = bands[r]
	local groups = Cluster(Shapes(band), #row.names)
	assert(#groups == #row.names, string.format("row %d: expected %d icons, found %d", r, #row.names, #groups))
	for i, g in ipairs(groups) do
		local left = (i == 1) and 0 or math.floor((groups[i - 1].x2 + g.x1) / 2) + 1
		local right = (i == #groups) and (W - 1) or math.floor((g.x2 + groups[i + 1].x1) / 2)
		local top, bottom = math.max(0, band.top - 30), math.min(H - 1, band.bottom + 30)
		-- Visible pieces in the strip; a piece whose middle lies outside the icon's own columns is
		-- a neighbour's edge and is left out.
		local keep, seen = {}, {}
		for y = top, bottom do
			for x = left, right do
				local key = y * W + x
				if not seen[key] and A(x, y) > VISIBLE then
					local piece, px1, px2 = {}, x, x
					local stack = { key }
					seen[key] = true
					while #stack > 0 do
						local k = table.remove(stack)
						piece[#piece + 1] = k
						local qx, qy = k % W, math.floor(k / W)
						if qx < px1 then px1 = qx end
						if qx > px2 then px2 = qx end
						for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
							local nx, ny = qx + d[1], qy + d[2]
							if nx >= left and nx <= right and ny >= top and ny <= bottom then
								local nk = ny * W + nx
								if not seen[nk] and A(nx, ny) > VISIBLE then seen[nk] = true; stack[#stack + 1] = nk end
							end
						end
					end
					local middle = (px1 + px2) / 2
					if middle >= g.x1 and middle <= g.x2 then
						for _, k in ipairs(piece) do keep[k] = true end
					end
				end
			end
		end
		-- Trim to what is kept.
		local x1, x2, y1, y2 = right, left, bottom, top
		for y = top, bottom do
			for x = left, right do
				if keep[y * W + x] then
					if x < x1 then x1 = x end
					if x > x2 then x2 = x end
					if y < y1 then y1 = y end
					if y > y2 then y2 = y end
				end
			end
		end
		local w, h = x2 - x1 + 1, y2 - y1 + 1
		local side = math.max(w, h) / (1 - 2 * MARGIN)
		local cx, cy = x1 + w / 2, y1 + h / 2
		local step = side / OUT
		local pixels = {}
		for oy = 0, OUT - 1 do
			for ox = 0, OUT - 1 do
				-- Area average of the source pixels under this output pixel (alpha-weighted colour).
				local sx1, sy1 = cx - side / 2 + ox * step, cy - side / 2 + oy * step
				local rs, gs, bs, as, n = 0, 0, 0, 0, 0
				for sy = math.floor(sy1), math.floor(sy1 + step - 1e-6) do
					for sx = math.floor(sx1), math.floor(sx1 + step - 1e-6) do
						n = n + 1
						if keep[sy * W + sx] then
							local b, gg, rr, a = BGRA(sx, sy)
							rs, gs, bs, as = rs + rr * a, gs + gg * a, bs + b * a, as + a
						end
					end
				end
				local a = n > 0 and as / n or 0
				if as > 0 then
					pixels[#pixels + 1] = string.char(math.floor(bs / as + 0.5), math.floor(gs / as + 0.5), math.floor(rs / as + 0.5), math.floor(a + 0.5))
				else
					pixels[#pixels + 1] = "\0\0\0\0"
				end
			end
		end
		local path = string.format("%s/icons/%s/%s.tga", dir, row.folder, row.names[i])
		WriteTGA(path, OUT, pixels)
		print(string.format("%-30s from x %4d-%4d y %3d-%3d", row.folder .. "/" .. row.names[i], x1, x2, y1, y2))
	end
end
