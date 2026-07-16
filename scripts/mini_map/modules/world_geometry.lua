local ffi     = require("ffi")
local Util    = require("frontiers_forge.util")
local Surface = require("surface")

-- Walks the game's live scene in EE memory and yields the world geometry
-- currently streamed in around the player, as textured triangles.
--
-- Each room resolves to its terrain sprite plus the actors placed in it. A
-- sprite carries a render prim buffer (positions, UVs, vertex colors, a
-- material index per strip) and a collision buffer. The render buffer is what
-- the game actually draws, so it is what we decode. Sprites whose prim buffer
-- format is not one of the world formats fall back to their collision buffer,
-- which has no UVs and renders untextured.
--
-- Runtime object graph (all statics relative to the client singleton
-- 0x1FAF730, embedded objects so the addresses never relocate):
--
--   VIScene   0x1FB6CC0 (singleton+0x7590)
--     +0x4C zone count, +0x50 zone array (VIZone, stride 0x250)
--     +0x3EC sprite table (stride 0xC, word 0 = sprite object)
--   VICollide 0x1FB5890 (singleton+0x6160)
--     +0x218 coll buffer table (stride 0xC, word 0 = VICollBuffer)
--   VIRaster  0x1FAFAB0 (singleton+0x380)
--     +0x4B80 prim buffer table (stride 0xC, word 0 = VIPrimBuffer)
--   VIZone: +0x2C bbox, +0x54/+0x58 pre-translation count/array,
--     +0x5C/+0x60 room count/array (VIZoneRoom, stride 0x78)
--   VIZoneRoom: +0x04 bbox, +0x1C terrain sprite id (-1 none),
--     +0x68 actor node chain (node +0x04 actor ptr, +0x10 next, -1 ends)
--   sprite: +0x08 bbox, +0x34 type, and for type 1: +0x40 prim buffer id,
--     +0x44 coll buffer id, +0x48 material palette id
--   VIActor: +0x40 flags, +0x44 pos, +0x50 rot (Euler), +0x5C scale,
--     +0x60 sprite id, +0x64 resource hash, +0x88 world bounding sphere
--   VIPrimBuffer: +0x08 type, +0x30 vertex scale, +0x34 uv scale,
--     +0x40 material count, +0x58 material array (stride 0x10: i32 material
--     index, i32 prim count, i32 first qword), +0x5C prim array (stride 0x1C,
--     word 0 = vertex count), +0x60 vertex data
--   VICollBuffer: +0x08 type, +0x10 vertex scale (1/2^packing),
--     +0x38 prim count, +0x48 prim array (stride 0x1C: u16 mode, u16 verts),
--     +0x4C vertex data

-- MapTri is shared with map_render.lua, tolerate redefinition on reload.
pcall(ffi.cdef, [[
typedef struct {
    float    x0, y0, z0, x1, y1, z1, x2, y2, z2;
    float    u0, v0, u1, v1, u2, v2;
    uint32_t surface;   /* packed material key, 0 = untextured */
    uint32_t color;     /* vertex color modulation, rgba8 */
    uint32_t flags;
} MapTri;
]])

local SCENE   = 0x1FB6CC0
local COLLIDE = 0x1FB5890
local RASTER  = 0x1FAFAB0

local ZONE_STRIDE          = 0x250
local ZONE_BBOX            = 0x2C
local ZONE_PRETRANS_COUNT  = 0x54
local ZONE_PRETRANS_ARRAY  = 0x58
local ZONE_ROOM_COUNT      = 0x5C
local ZONE_ROOM_ARRAY      = 0x60
local ROOM_STRIDE          = 0x78
local ROOM_BBOX            = 0x04
local ROOM_SPRITE_ID       = 0x1C
local ROOM_ACTOR_HEAD      = 0x68
local SPRITE_TYPE          = 0x34   -- 1 = simple/sub sprite, 7 = LOD, 0xB = group
local SPRITE_PRIM_ID       = 0x40
local SPRITE_COLL_ID       = 0x44
local SPRITE_MATPAL_ID     = 0x48
local ACTOR_POS            = 0x44
local ACTOR_ROT            = 0x50
local ACTOR_SCALE          = 0x5C
local ACTOR_SPRITE_ID      = 0x60
local PB_TYPE              = 0x08
local PB_VERT_SCALE        = 0x30
local PB_UV_SCALE          = 0x34
local PB_MAT_COUNT         = 0x40
local PB_MAT_ARRAY         = 0x58
local PB_PRIM_ARRAY        = 0x5C
local PB_VERT_DATA         = 0x60
local CB_TYPE              = 0x08
local CB_SCALE             = 0x10
local CB_PRIM_COUNT        = 0x38
local CB_PRIM_ARRAY        = 0x48
local CB_VERT_ARRAY        = 0x4C

local FLAG_ACTOR = 1

local WorldGeometry = {}

local ee_base = nil

local function host(guest_addr)
    return ee_base + guest_addr
end

local function u32(guest_addr)
    return ffi.cast("uint32_t*", host(guest_addr))[0]
end

local function i32(guest_addr)
    return ffi.cast("int32_t*", host(guest_addr))[0]
end

local function f32ptr(guest_addr)
    return ffi.cast("float*", host(guest_addr))
end

local function valid(guest_addr)
    return guest_addr ~= 0 and guest_addr ~= 0xFFFFFFFF
       and Util.IsValidEEPointer(guest_addr)
end

-- Room decode cache: key -> { tris (MapTri*), count, sprite_id, stamp }.
local room_cache = {}
local room_cache_entries = 0
local ROOM_CACHE_LIMIT = 256
local stamp = 0

local function evict_oldest()
    local oldest_key, oldest = nil, math.huge
    for key, entry in pairs(room_cache) do
        if entry.stamp < oldest then
            oldest_key, oldest = key, entry.stamp
        end
    end
    if oldest_key then
        room_cache[oldest_key] = nil
        room_cache_entries = room_cache_entries - 1
    end
end

-- Triangles carry the material as a packed key rather than a resolved surface
-- pointer. Streaming frees and reuses surface objects, so the pointer is only
-- resolved at draw time, when the material tables reflect what is loaded.
local function material_key(matpal_id, mat_index)
    if matpal_id < 0 or mat_index < 0 then return 0 end
    return matpal_id * 4096 + mat_index + 1
end

-- PS2 vertex colors modulate at 0x80 = 1.0, so an 8 bit channel is the stored
-- byte doubled. Averaged over the triangle, which is all a top-down map needs.
local function tri_color(r, g, b)
    r = math.floor(r * 2); if r > 255 then r = 255 end
    g = math.floor(g * 2); if g > 255 then g = 255 end
    b = math.floor(b * 2); if b > 255 then b = 255 end
    return r + g * 0x100 + b * 0x10000 + 0xFF000000
end

--- Decodes one VIPrimBuffer (the render mesh) into out. Returns false when the
--- buffer format is not one the world uses, so the caller can fall back.
--- pretrans is the owning zone's translation table (nil for local space).
local function decode_prim_buffer(pb, matpal_id, out, pretrans, flags)
    local ptype = i32(pb + PB_TYPE)
    local vstride
    if ptype == 2 or ptype == 4 then
        vstride = 0x20
    elseif ptype == 8 then
        vstride = 0x10
    else
        return false
    end

    local vscale  = f32ptr(pb + PB_VERT_SCALE)[0]
    local uvscale = f32ptr(pb + PB_UV_SCALE)[0]
    local mat_count = i32(pb + PB_MAT_COUNT)
    local mats  = u32(pb + PB_MAT_ARRAY)
    local prims = u32(pb + PB_PRIM_ARRAY)
    local data  = u32(pb + PB_VERT_DATA)
    if mat_count <= 0 or mat_count > 0x400
       or not valid(mats) or not valid(prims) or not valid(data) then
        return false
    end

    -- UVs land at +0x0C/+0x0E on the two qword formats and at +0x0A/+0x0C on
    -- the packed one, where the vertex group short takes the +0x0A slot.
    local uv_offset = (vstride == 0x20) and 0x0C or 0x0A

    local prim_i = 0
    for m = 0, mat_count - 1 do
        local entry = mats + m * 0x10
        local surface   = material_key(matpal_id, i32(entry))
        local prim_n    = i32(entry + 4)
        local first_qw  = i32(entry + 8)
        if prim_n < 0 or prim_n > 0x4000 or first_qw < 0 then return false end

        local block = data + first_qw * 0x10
        for _ = 1, prim_n do
            local vcount = i32(prims + prim_i * 0x1C)
            if vcount < 0 or vcount > 0x2000 then return false end
            prim_i = prim_i + 1

            if vcount >= 3 then
                local verts = block + 0x20
                if not valid(verts) then return false end
                local s = ffi.cast("int16_t*", host(verts))
                local c = ffi.cast("uint8_t*", host(verts))
                local shorts = vstride / 2
                local uv_slot = uv_offset / 2

                local px, py, pz, pu, pv, pc = {}, {}, {}, {}, {}, {}
                for i = 0, vcount - 1 do
                    local o = i * shorts
                    local tx, ty, tz = 0, 0, 0
                    if ptype == 4 and pretrans then
                        local t = pretrans[s[o + 5]]
                        if t then tx, ty, tz = t[1], t[2], t[3] end
                    end
                    px[i] = s[o + 2] * vscale + tx
                    py[i] = s[o + 3] * vscale + ty
                    pz[i] = s[o + 4] * vscale + tz

                    pu[i] = s[o + uv_slot] * uvscale
                    pv[i] = s[o + uv_slot + 1] * uvscale

                    if vstride == 0x20 then
                        local b = i * vstride + 0x1C
                        pc[i] = { c[b], c[b + 1], c[b + 2] }
                    else
                        pc[i] = { 0x80, 0x80, 0x80 }
                    end
                end

                -- Triangle strip. Winding is irrelevant to a top-down raster,
                -- so emit the vertices in order.
                for i = 0, vcount - 3 do
                    local a, b, c = pc[i], pc[i + 1], pc[i + 2]
                    out[#out + 1] = {
                        px[i], py[i], pz[i],
                        px[i + 1], py[i + 1], pz[i + 1],
                        px[i + 2], py[i + 2], pz[i + 2],
                        pu[i], pv[i], pu[i + 1], pv[i + 1], pu[i + 2], pv[i + 2],
                        surface,
                        tri_color((a[1] + b[1] + c[1]) / 3,
                                  (a[2] + b[2] + c[2]) / 3,
                                  (a[3] + b[3] + c[3]) / 3),
                        flags,
                    }
                end
            end
            block = block + 0x30 + vcount * vstride
        end
    end
    return true
end

--- Decodes one VICollBuffer. Used only for sprites whose render mesh we cannot
--- read, so these triangles carry no UVs and draw untextured.
local function decode_coll_buffer(cb, out, pretrans, flags)
    local ctype = i32(cb + CB_TYPE)
    local scale = f32ptr(cb + CB_SCALE)[0]
    local prim_count = i32(cb + CB_PRIM_COUNT)
    local prims = u32(cb + CB_PRIM_ARRAY)
    local verts = u32(cb + CB_VERT_ARRAY)
    if prim_count <= 0 or prim_count > 0x4000
       or not valid(prims) or not valid(verts) then
        return
    end

    local white = tri_color(0x80, 0x80, 0x80)
    local prim = ffi.cast("uint16_t*", host(prims))
    local vert_index = 0
    for p = 0, prim_count - 1 do
        -- prim entry stride 0x1C = 14 uint16 slots: [0] mode, [1] vertex count
        local vcount = prim[p * 14 + 1]
        if vcount > 0x2000 then return end
        local px, py, pz = {}, {}, {}
        if ctype == 3 then
            local v = ffi.cast("int16_t*", host(verts + vert_index * 8))
            local g = ffi.cast("int8_t*", host(verts + vert_index * 8))
            for i = 0, vcount - 1 do
                local tx, ty, tz = 0, 0, 0
                if pretrans then
                    local t = pretrans[g[i * 8 + 6]]
                    if t then tx, ty, tz = t[1], t[2], t[3] end
                end
                px[i] = v[i * 4] * scale + tx
                py[i] = v[i * 4 + 1] * scale + ty
                pz[i] = v[i * 4 + 2] * scale + tz
            end
        elseif ctype == 1 then
            local v = ffi.cast("int16_t*", host(verts + vert_index * 6))
            for i = 0, vcount - 1 do
                px[i] = v[i * 3] * scale
                py[i] = v[i * 3 + 1] * scale
                pz[i] = v[i * 3 + 2] * scale
            end
        elseif ctype == 0 then
            local v = f32ptr(verts + vert_index * 12)
            for i = 0, vcount - 1 do
                px[i] = v[i * 3]
                py[i] = v[i * 3 + 1]
                pz[i] = v[i * 3 + 2]
            end
        else
            return
        end

        for i = 0, vcount - 3 do
            out[#out + 1] = { px[i], py[i], pz[i],
                              px[i + 1], py[i + 1], pz[i + 1],
                              px[i + 2], py[i + 2], pz[i + 2],
                              0, 0, 0, 0, 0, 0,
                              0, white, flags }
        end
        vert_index = vert_index + vcount
    end
end

local function sprite_object(sprite_id)
    if sprite_id < 0 or sprite_id > 0x40000 then return nil end
    local table_ptr = u32(SCENE + 0x3EC)
    if not valid(table_ptr) then return nil end
    local sprite = u32(table_ptr + sprite_id * 0xC)
    if not valid(sprite) then return nil end
    return sprite
end

local function prim_buffer_by_id(prim_id)
    if prim_id < 0 or prim_id > 0x40000 then return nil end
    local pb_table = u32(RASTER + 0x4B80)
    if not valid(pb_table) then return nil end
    local pb = u32(pb_table + prim_id * 0xC)
    if not valid(pb) then return nil end
    return pb
end

local function coll_buffer_by_id(coll_id)
    if coll_id < 0 or coll_id > 0x40000 then return nil end
    local cb_table = u32(COLLIDE + 0x218)
    if not valid(cb_table) then return nil end
    local cb = u32(cb_table + coll_id * 0xC)
    if not valid(cb) then return nil end
    return cb
end

local function quat_rotate(x, y, z, qx, qy, qz, qw)
    -- v + 2*q x (q x v + w*v)
    local ux = qy * z - qz * y + qw * x
    local uy = qz * x - qx * z + qw * y
    local uz = qx * y - qy * x + qw * z
    return x + 2 * (qy * uz - qz * uy),
           y + 2 * (qz * ux - qx * uz),
           z + 2 * (qx * uy - qy * ux)
end

--- Resolves a sprite to its drawable buffers, following LOD levels and group
--- members. Appends { pb, matpal, cb, xform } rows to out.
--- Only type 1 sprites store buffer ids at +0x40..+0x48 — other classes keep
--- unrelated data there, which is why blindly reading them draws garbage.
local function resolve_sprite(sprite_id, out, depth)
    if depth > 4 then return end
    local sprite = sprite_object(sprite_id)
    if sprite == nil then return end
    local stype = i32(sprite + SPRITE_TYPE)

    if stype == 1 then
        out[#out + 1] = {
            pb     = prim_buffer_by_id(i32(sprite + SPRITE_PRIM_ID)),
            matpal = i32(sprite + SPRITE_MATPAL_ID),
            cb     = coll_buffer_by_id(i32(sprite + SPRITE_COLL_ID)),
        }
    elseif stype == 7 then
        -- LOD sprite: +0x44 level count, +0x48 {sprite id, f32 dist} pairs.
        -- Use the coarsest level, plenty for a map.
        local levels = i32(sprite + 0x44)
        if levels > 0 and levels <= 8 then
            resolve_sprite(i32(sprite + 0x48 + (levels - 1) * 8), out, depth + 1)
        end
    elseif stype == 0xB then
        -- Group sprite: +0x40 member count, stride 0x20 members at +0x44:
        -- {sprite id, f32 quat xyzw, f32 pos xyz}.
        local members = i32(sprite + 0x40)
        if members > 0 and members <= 5 then
            for m = 0, members - 1 do
                local base = sprite + 0x44 + m * 0x20
                local child = {}
                resolve_sprite(i32(base), child, depth + 1)
                local q = f32ptr(base + 4)
                for _, row in ipairs(child) do
                    row.xform = { q[0], q[1], q[2], q[3], q[4], q[5], q[6] }
                    out[#out + 1] = row
                end
            end
        end
    end
end

--- Decodes one resolved buffer row, preferring the render mesh. The render mesh
--- decodes into a scratch table so a buffer that turns out to be unreadable
--- part way through leaves nothing behind for the collision fallback.
local function decode_buffer_row(row, out, pretrans, flags)
    if row.pb ~= nil then
        local scratch = {}
        local ok, decoded = pcall(decode_prim_buffer, row.pb, row.matpal, scratch,
                                  pretrans, flags)
        if ok and decoded then
            for _, tri in ipairs(scratch) do
                out[#out + 1] = tri
            end
            return
        end
    end
    if row.cb ~= nil then
        decode_coll_buffer(row.cb, out, pretrans, flags)
    end
end

local function euler_rotate(x, y, z, rx, ry, rz)
    -- Ry*Rx*Rz, the order the engine builds actor rotations in.
    local sx, cx = math.sin(rx), math.cos(rx)
    local sy, cy = math.sin(ry), math.cos(ry)
    local sz, cz = math.sin(rz), math.cos(rz)
    local m00 = cy * cz + sy * sx * sz
    local m01 = -cy * sz + sy * sx * cz
    local m02 = sy * cx
    local m10 = cx * sz
    local m11 = cx * cz
    local m12 = -sx
    local m20 = -sy * cz + cy * sx * sz
    local m21 = sy * sz + cy * sx * cz
    local m22 = cy * cx
    return m00 * x + m01 * y + m02 * z,
           m10 * x + m11 * y + m12 * z,
           m20 * x + m21 * y + m22 * z
end

--- Decodes a room's terrain and actor geometry into a MapTri FFI array.
local function decode_room(zone, room, pretrans)
    local rows = {}

    local sprite_id = i32(room + ROOM_SPRITE_ID)
    if sprite_id >= 0 then
        local buffers = {}
        resolve_sprite(sprite_id, buffers, 0)
        for _, row in ipairs(buffers) do
            decode_buffer_row(row, rows, pretrans, 0)
        end
    end

    local node = u32(room + ROOM_ACTOR_HEAD)
    local guard = 0
    while node ~= 0xFFFFFFFF and valid(node) and guard < 4096 do
        guard = guard + 1
        local actor = u32(node + 4)
        if valid(actor) then
            local actor_sprite = i32(actor + ACTOR_SPRITE_ID)
            if actor_sprite >= 0 then
                local buffers = {}
                resolve_sprite(actor_sprite, buffers, 0)
                if #buffers > 0 then
                    local pos = f32ptr(actor + ACTOR_POS)
                    local rot = f32ptr(actor + ACTOR_ROT)
                    local sc = f32ptr(actor + ACTOR_SCALE)[0]
                    for _, buf in ipairs(buffers) do
                        local local_rows = {}
                        decode_buffer_row(buf, local_rows, nil, FLAG_ACTOR)
                        local xf = buf.xform
                        for _, row in ipairs(local_rows) do
                            for c = 0, 2 do
                                local x = row[c * 3 + 1]
                                local y = row[c * 3 + 2]
                                local z = row[c * 3 + 3]
                                if xf then
                                    x, y, z = quat_rotate(x, y, z, xf[1], xf[2], xf[3], xf[4])
                                    x, y, z = x + xf[5], y + xf[6], z + xf[7]
                                end
                                x, y, z = x * sc, y * sc, z * sc
                                x, y, z = euler_rotate(x, y, z, rot[0], rot[1], rot[2])
                                row[c * 3 + 1] = x + pos[0]
                                row[c * 3 + 2] = y + pos[1]
                                row[c * 3 + 3] = z + pos[2]
                            end
                            rows[#rows + 1] = row
                        end
                    end
                end
            end
        end
        node = u32(node + 0x10)
    end

    local count = #rows
    local tris = ffi.new("MapTri[?]", count)
    for i = 1, count do
        local row = rows[i]
        local t = tris[i - 1]
        t.x0, t.y0, t.z0 = row[1], row[2], row[3]
        t.x1, t.y1, t.z1 = row[4], row[5], row[6]
        t.x2, t.y2, t.z2 = row[7], row[8], row[9]
        t.u0, t.v0 = row[10], row[11]
        t.u1, t.v1 = row[12], row[13]
        t.u2, t.v2 = row[14], row[15]
        t.surface = row[16]
        t.color = row[17]
        t.flags = row[18]
    end
    return tris, count
end

local function read_pretrans(zone)
    local count = i32(zone + ZONE_PRETRANS_COUNT)
    local arr = u32(zone + ZONE_PRETRANS_ARRAY)
    if count <= 0 or count > 64 or not valid(arr) then return nil end
    local v = f32ptr(arr)
    local out = {}
    for i = 0, count - 1 do
        out[i] = { v[i * 3], v[i * 3 + 1], v[i * 3 + 2] }
    end
    return out
end

local function bbox_overlaps(bbox_ptr, x0, z0, x1, z1)
    local b = f32ptr(bbox_ptr)
    return b[0] <= x1 and b[3] >= x0 and b[2] <= z1 and b[5] >= z0
end

--- True when the live scene looks walkable (in game, pointers sane).
function WorldGeometry.IsAvailable()
    if Util.IsInGame() == 0 then return false end
    if ee_base == nil then ee_base = Util.EEmem() end
    local zone_count = i32(SCENE + 0x4C)
    local zones = u32(SCENE + 0x50)
    return zone_count > 0 and zone_count < 2048 and valid(zones)
end

--- Iterates every loaded room whose bbox intersects the square around (x, z),
--- invoking callback({ tris, count }) with cached MapTri arrays.
function WorldGeometry.EachRoomInRadius(x, z, radius, callback)
    if not WorldGeometry.IsAvailable() then return end
    stamp = stamp + 1

    local x0, x1 = x - radius, x + radius
    local z0, z1 = z - radius, z + radius
    local zone_count = i32(SCENE + 0x4C)
    local zones = u32(SCENE + 0x50)

    for zi = 0, zone_count - 1 do
        local zone = zones + zi * ZONE_STRIDE
        if bbox_overlaps(zone + ZONE_BBOX, x0, z0, x1, z1) then
            local room_count = i32(zone + ZONE_ROOM_COUNT)
            local rooms = u32(zone + ZONE_ROOM_ARRAY)
            if room_count > 0 and room_count < 0x8000 and valid(rooms) then
                local pretrans = nil
                local pretrans_read = false
                for ri = 0, room_count - 1 do
                    local room = rooms + ri * ROOM_STRIDE
                    if bbox_overlaps(room + ROOM_BBOX, x0, z0, x1, z1) then
                        local key = zi .. ":" .. ri
                        local sprite_id = i32(room + ROOM_SPRITE_ID)
                        local entry = room_cache[key]
                        if entry == nil or entry.sprite_id ~= sprite_id then
                            if not pretrans_read then
                                pretrans = read_pretrans(zone)
                                pretrans_read = true
                            end
                            local ok, tris, count = pcall(decode_room, zone, room, pretrans)
                            if not ok then tris, count = nil, 0 end
                            if entry == nil then
                                if room_cache_entries >= ROOM_CACHE_LIMIT then
                                    evict_oldest()
                                end
                                room_cache_entries = room_cache_entries + 1
                            end
                            entry = { tris = tris, count = count,
                                      sprite_id = sprite_id, stamp = stamp }
                            room_cache[key] = entry
                        end
                        entry.stamp = stamp
                        if entry.count > 0 then
                            callback(entry)
                        end
                    end
                end
            end
        end
    end
end

-- Probe columns for the ceiling test: the player's own column plus four around
-- it, so a doorway or a gap in the roof does not read as open sky.
local PROBE_OFFSETS = { {0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1} }

--- Finds the ceiling over the player, meaning the lowest geometry above head
--- height in every probe column. Returns the highest of those (so a low beam in
--- one column does not slice the whole room away) or nil when any column is
--- open to the sky, which is what standing outdoors looks like.
---   min_clearance  ignore geometry closer than this above the player
---   max_search     stop looking this far above the player
---   probe_radius   how far out the surrounding columns sit
function WorldGeometry.CeilingAbove(x, y, z, min_clearance, max_search, probe_radius)
    if not WorldGeometry.IsAvailable() then return nil end

    local lo, hi = y + min_clearance, y + max_search
    local sx, sz, best = {}, {}, {}
    for i, offset in ipairs(PROBE_OFFSETS) do
        sx[i] = x + offset[1] * probe_radius
        sz[i] = z + offset[2] * probe_radius
    end

    WorldGeometry.EachRoomInRadius(x, z, probe_radius + 1, function(room)
        local tris, count = room.tris, room.count
        for i = 0, count - 1 do
            local t = tris[i]
            local ay, by, cy = t.y0, t.y1, t.y2
            local min_y = math.min(ay, by, cy)
            local max_y = math.max(ay, by, cy)
            if max_y >= lo and min_y <= hi then
                local ax, az = t.x0, t.z0
                local bx, bz = t.x1, t.z1
                local cx, cz = t.x2, t.z2
                local d = (bz - cz) * (ax - cx) + (cx - bx) * (az - cz)
                if d < -1e-9 or d > 1e-9 then
                    local inv_d = 1.0 / d
                    for s = 1, #sx do
                        local px, pz = sx[s], sz[s]
                        local l1 = ((bz - cz) * (px - cx) + (cx - bx) * (pz - cz)) * inv_d
                        if l1 >= 0 and l1 <= 1 then
                            local l2 = ((cz - az) * (px - cx) + (ax - cx) * (pz - cz)) * inv_d
                            if l2 >= 0 and l1 + l2 <= 1 then
                                local hit = l1 * ay + l2 * by + (1 - l1 - l2) * cy
                                if hit >= lo and hit <= hi
                                   and (best[s] == nil or hit < best[s]) then
                                    best[s] = hit
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    local ceiling = nil
    for s = 1, #sx do
        if best[s] == nil then return nil end
        if ceiling == nil or best[s] > ceiling then ceiling = best[s] end
    end
    return ceiling
end

--- Drops all cached geometry and textures (call on zone change or reload).
function WorldGeometry.ClearCache()
    room_cache = {}
    room_cache_entries = 0
    Surface.ClearCache()
end

return WorldGeometry
