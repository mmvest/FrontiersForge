local ffi     = require("ffi")
local bit     = require("bit")
local Surface = require("surface")

-- Top-down map rasterizer used by mini_map.lua. Renders world triangles into
-- an RGBA texture, z-buffered by height, with a "ceiling cut" that removes
-- geometry starting above a reference height so cave and dungeon interiors
-- render instead of the terrain above them.
--
-- Two modes:
--   textured  samples the triangle's own texture through its UVs and modulates
--             it by the baked vertex color, so the map shows the world's real
--             art from above. The projection is orthographic, so interpolating
--             UVs linearly in screen space is exact, no perspective divide.
--   flat      shades by height alone. Shading is split into two gradients
--             around the reference height (usually the player's y): floor_range
--             below fades toward the low color, above_range above fades toward
--             the high color, which keeps mountains and towers readable.
--
-- Triangles whose texture cannot be read (and every triangle in flat mode) take
-- the height palette, so a map is never blank.
--
-- Cells are supplied by the caller as { tris (MapTri*), count }.

pcall(ffi.cdef, [[
typedef struct {
    float    x0, y0, z0, x1, y1, z1, x2, y2, z2;
    float    u0, v0, u1, v1, u2, v2;
    uint32_t surface;   /* packed material key, 0 = untextured */
    uint32_t color;
    uint32_t flags;
} MapTri;
]])

local MapRender = {}

local ALPHA_TEST = Surface.ALPHA_TEST

-- Textures decoded per Step call, so a zone change never stalls a frame.
local TEX_PER_STEP = 3

local function ColorU32FromTable(c)
    local r = math.floor(c[1] * 255 + 0.5)
    local g = math.floor(c[2] * 255 + 0.5)
    local b = math.floor(c[3] * 255 + 0.5)
    local a = math.floor(c[4] * 255 + 0.5)
    -- Texture memory is R8G8B8A8, little endian word = A<<24 | B<<16 | G<<8 | R
    return bit.bor(r, bit.lshift(g, 8), bit.lshift(b, 16), bit.lshift(a, 24))
end

local function LerpColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        1,
    }
end

-- Palette indexed by height relative to the reference: 0..47 below
-- (low -> mid), 48 at reference, 49..96 above (mid -> high).
local PAL_BELOW = 48
local PAL_ABOVE = 48
local PAL_SIZE = PAL_BELOW + PAL_ABOVE + 1

local function BuildPalette(colors)
    local pal = ffi.new("uint32_t[?]", PAL_SIZE)
    local pal_actor = ffi.new("uint32_t[?]", PAL_SIZE)
    for i = 0, PAL_SIZE - 1 do
        local c
        if i <= PAL_BELOW then
            c = LerpColor(colors.low, colors.mid, i / PAL_BELOW)
        else
            c = LerpColor(colors.mid, colors.high, (i - PAL_BELOW) / PAL_ABOVE)
        end
        pal[i] = ColorU32FromTable(c)
        pal_actor[i] = ColorU32FromTable(LerpColor(c, colors.actor_tint, 0.65))
    end
    return pal, pal_actor
end

--- Starts a render job. opts:
---   center_x, center_z  world center of the square view
---   radius              world half-extent covered by the texture
---   size                texture edge in pixels
---   ref_y               shading reference height (usually player y)
---   cut_y               remove triangles whose lowest point is above this
---   floor_range         shade falloff below ref_y
---   above_range         shade falloff above ref_y
---   textured            sample real textures instead of the height palette
---   lighting            modulate texels by the world's baked vertex lighting.
---                       The engine relights those colors with the time of day,
---                       so at night this renders most of the map black
---   brightness          multiplies the sampled texels, 1.0 leaves them as is
---   colors              { low, mid, high, actor_tint, background } rgba tables
--- Fill job.cells afterwards, then call Step until it returns true.
function MapRender.Start(opts)
    local size = opts.size
    local job = {
        center_x = opts.center_x,
        center_z = opts.center_z,
        ref_y = opts.ref_y,
        cut_y = opts.cut_y,
        radius = opts.radius,
        size = size,
        textured = opts.textured and true or false,
        lighting = opts.lighting and true or false,
        brightness = opts.brightness or 1.0,
        x0 = opts.center_x - opts.radius,
        z0 = opts.center_z - opts.radius,
        pix_per_unit = size / (2 * opts.radius),
        inv_floor = 1.0 / opts.floor_range,
        inv_above = 1.0 / opts.above_range,
        fb = ffi.new("uint32_t[?]", size * size),
        depth = ffi.new("float[?]", size * size),
        cells = {},
        cell_i = 1,
        tri_i = 0,
        tris_done = 0,
        surfaces = nil,     -- material keys still to decode, built on the first Step
        surface_i = 1,
        mat_surf = {},      -- material key -> decoded surface, this job only
    }
    local bg = ColorU32FromTable(opts.colors.background)
    for i = 0, size * size - 1 do
        job.fb[i] = bg
        job.depth[i] = -1e30
    end
    job.palette, job.palette_actor = BuildPalette(opts.colors)
    return job
end

-- Sets up the screen-space triangle. Returns nil when the triangle is culled
-- by the ceiling, off the texture, or degenerate, otherwise the pixel bounds
-- and the barycentric setup shared by both raster paths.
local function Setup(job, ax, az, bx, bz, cx, cz)
    local ppu = job.pix_per_unit
    ax = (ax - job.x0) * ppu
    az = (az - job.z0) * ppu
    bx = (bx - job.x0) * ppu
    bz = (bz - job.z0) * ppu
    cx = (cx - job.x0) * ppu
    cz = (cz - job.z0) * ppu

    local size = job.size
    local minx = math.floor(math.min(ax, bx, cx))
    local maxx = math.ceil(math.max(ax, bx, cx))
    local minz = math.floor(math.min(az, bz, cz))
    local maxz = math.ceil(math.max(az, bz, cz))
    if maxx < 0 or maxz < 0 or minx >= size or minz >= size then return nil end
    if minx < 0 then minx = 0 end
    if minz < 0 then minz = 0 end
    if maxx > size - 1 then maxx = size - 1 end
    if maxz > size - 1 then maxz = size - 1 end

    local d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
    if d > -1e-9 and d < 1e-9 then return nil end

    return minx, maxx, minz, maxz, ax, az, bx, bz, cx, cz, 1.0 / d
end

local function ShadeIndex(job, y)
    local rel = y - job.ref_y
    local pi
    if rel <= 0 then
        pi = PAL_BELOW + rel * job.inv_floor * PAL_BELOW
        if pi < 0 then pi = 0 end
    else
        pi = PAL_BELOW + rel * job.inv_above * PAL_ABOVE
        if pi > PAL_SIZE - 1 then pi = PAL_SIZE - 1 end
    end
    return math.floor(pi)
end

--- Rasterizes one triangle with the height palette.
local function RasterFlat(job, t)
    local cut_y = job.cut_y
    local ay, by, cy = t.y0, t.y1, t.y2
    local min_y = ay < by and ay or by
    if cy < min_y then min_y = cy end
    if min_y > cut_y then return end

    local minx, maxx, minz, maxz, ax, az, bx, bz, cx, cz, inv_d =
        Setup(job, t.x0, t.z0, t.x1, t.z1, t.x2, t.z2)
    if minx == nil then return end

    local pal = t.flags ~= 0 and job.palette_actor or job.palette
    local fb, depth, size = job.fb, job.depth, job.size

    for pz_i = minz, maxz do
        local row = pz_i * size
        local pzc = pz_i + 0.5
        for px_i = minx, maxx do
            local pxc = px_i + 0.5
            local l1 = ((bz - cz) * (pxc - cx) + (cx - bx) * (pzc - cz)) * inv_d
            if l1 >= -0.002 then
                local l2 = ((cz - az) * (pxc - cx) + (ax - cx) * (pzc - cz)) * inv_d
                if l2 >= -0.002 and l1 + l2 <= 1.002 then
                    local y = l1 * ay + l2 * by + (1 - l1 - l2) * cy
                    if y <= cut_y then
                        local idx = row + px_i
                        if y > depth[idx] then
                            depth[idx] = y
                            fb[idx] = pal[ShadeIndex(job, y)]
                        end
                    end
                end
            end
        end
    end
end

--- Rasterizes one triangle by sampling its texture. Texels under the alpha test
--- are left untouched.
local function RasterTextured(job, t, surf)
    local cut_y = job.cut_y
    local ay, by, cy = t.y0, t.y1, t.y2
    local min_y = ay < by and ay or by
    if cy < min_y then min_y = cy end
    if min_y > cut_y then return end

    local minx, maxx, minz, maxz, ax, az, bx, bz, cx, cz, inv_d =
        Setup(job, t.x0, t.z0, t.x1, t.z1, t.x2, t.z2)
    if minx == nil then return end

    local u0, v0, u1, v1, u2, v2 = t.u0, t.v0, t.u1, t.v1, t.u2, t.v2
    local pixels, tw, th = surf.pixels, surf.w, surf.h

    local scale = job.brightness
    local mr, mg, mb = scale, scale, scale
    if job.lighting then
        local color = t.color
        mr = mr * bit.band(color, 0xFF) / 255
        mg = mg * bit.band(bit.rshift(color, 8), 0xFF) / 255
        mb = mb * bit.band(bit.rshift(color, 16), 0xFF) / 255
    end
    local plain = mr > 0.99 and mr < 1.01 and mg > 0.99 and mg < 1.01
                  and mb > 0.99 and mb < 1.01

    local fb, depth, size = job.fb, job.depth, job.size
    local floor = math.floor

    for pz_i = minz, maxz do
        local row = pz_i * size
        local pzc = pz_i + 0.5
        for px_i = minx, maxx do
            local pxc = px_i + 0.5
            local l1 = ((bz - cz) * (pxc - cx) + (cx - bx) * (pzc - cz)) * inv_d
            if l1 >= -0.002 then
                local l2 = ((cz - az) * (pxc - cx) + (ax - cx) * (pzc - cz)) * inv_d
                if l2 >= -0.002 and l1 + l2 <= 1.002 then
                    local l3 = 1 - l1 - l2
                    local y = l1 * ay + l2 * by + l3 * cy
                    if y <= cut_y then
                        local idx = row + px_i
                        if y > depth[idx] then
                            local u = l1 * u0 + l2 * u1 + l3 * u2
                            local v = l1 * v0 + l2 * v1 + l3 * v2
                            local tx = floor((u - floor(u)) * tw)
                            local ty = floor((v - floor(v)) * th)
                            if tx >= tw then tx = tw - 1 end
                            if ty >= th then ty = th - 1 end
                            local texel = pixels[ty * tw + tx]
                            if bit.rshift(texel, 24) >= ALPHA_TEST then
                                depth[idx] = y
                                if plain then
                                    fb[idx] = bit.bor(texel, 0xFF000000)
                                else
                                    local r = bit.band(texel, 0xFF) * mr
                                    local g = bit.band(bit.rshift(texel, 8), 0xFF) * mg
                                    local b = bit.band(bit.rshift(texel, 16), 0xFF) * mb
                                    if r > 255 then r = 255 end
                                    if g > 255 then g = 255 end
                                    if b > 255 then b = 255 end
                                    fb[idx] = bit.bor(floor(r),
                                        bit.lshift(floor(g), 8),
                                        bit.lshift(floor(b), 16), 0xFF000000)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Collects the distinct material keys the job's triangles reference, so their
-- textures can be decoded a few per frame instead of stalling on the first
-- zone build.
local function CollectSurfaces(job)
    local seen, list = {}, {}
    for _, cell in ipairs(job.cells) do
        local tris, count = cell.tris, cell.count
        for i = 0, count - 1 do
            local s = tris[i].surface
            if s ~= 0 and not seen[s] then
                seen[s] = true
                list[#list + 1] = s
            end
        end
    end
    job.surfaces = list
end

-- Resolves a packed material key to its decoded texture. Resolved per job
-- rather than baked into the cached geometry, so streaming replacing a surface
-- object corrects itself on the next rebuild.
local function SurfaceFromKey(key)
    local k = key - 1
    local matpal = math.floor(k / 4096)
    return Surface.Get(Surface.FromMaterial(matpal, k % 4096))
end

--- Processes up to budget triangles, decoding a few textures first. Returns
--- true when the job is complete.
function MapRender.Step(job, budget)
    if job.textured then
        if job.surfaces == nil then
            CollectSurfaces(job)
            return false
        end
        local decoded = 0
        while job.surface_i <= #job.surfaces and decoded < TEX_PER_STEP do
            local key = job.surfaces[job.surface_i]
            local ok, surf = pcall(SurfaceFromKey, key)
            if ok then
                job.mat_surf[key] = surf
            end
            job.surface_i = job.surface_i + 1
            decoded = decoded + 1
        end
        if job.surface_i <= #job.surfaces then return false end
    end

    local textured = job.textured
    local last_key, last_surf = 0, nil

    while budget > 0 do
        local cell = job.cells[job.cell_i]
        if cell == nil then break end

        local tris, count = cell.tris, cell.count
        local i = job.tri_i
        local n = math.min(count - i, budget)
        for k = i, i + n - 1 do
            local t = tris[k]
            -- Triangles come out grouped by material, so the same texture
            -- repeats for long runs.
            if textured and t.surface ~= last_key then
                last_key = t.surface
                last_surf = job.mat_surf[last_key]
            end
            if textured and last_surf ~= nil then
                RasterTextured(job, t, last_surf)
            else
                RasterFlat(job, t)
            end
        end
        job.tri_i = i + n
        job.tris_done = job.tris_done + n
        budget = budget - n
        if job.tri_i >= count then
            job.cell_i = job.cell_i + 1
            job.tri_i = 0
        end
    end
    return job.cells[job.cell_i] == nil
end

--- Uploads the finished framebuffer as a texture. Caller owns the handle.
function MapRender.Upload(job)
    return UiForge.CreateTextureFromMemory(
        ffi.string(job.fb, job.size * job.size * 4), job.size, job.size)
end

return MapRender
