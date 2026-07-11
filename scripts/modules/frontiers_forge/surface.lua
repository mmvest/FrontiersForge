local ffi  = require("ffi")
local bit  = require("bit")
local Util = require("frontiers_forge.util")

-- Decodes VISurface texture data out of EE memory into RGBA8 buffers the map
-- rasterizer can sample. Surfaces are reached by handle through the VIRaster
-- surface table, and every decode is cached by surface pointer.
--
-- Pixels are packed the same way the map framebuffer packs them, little endian
-- R | G<<8 | B<<16 | A<<24, so a sampled texel can be written straight out.

local RASTER          = 0x1FAFAB0
local SURFACE_TABLE   = 0x4BBC
local MATPAL_TABLE    = 0x4BEC

local SURF_WIDTH      = 0x08
local SURF_HEIGHT     = 0x0C
local SURF_FORMAT     = 0x10
local SURF_PAL_COUNT  = 0x28
local SURF_PAL_OFFSET = 0x2C
local SURF_PAL_FORMAT = 0x34
local SURF_MIP_COUNT  = 0x40
local SURF_MIPS       = 0x44   -- stride 0x18: w, h, data offset, row stride
local SURF_BUF_SIZE   = 0x134
local SURF_BUF        = 0x138

local MAT_LAYER_STRIDE = 0x90
local MAT_LAYER0_TEX   = 0x30

-- Cap the decoded size. A minimap never resolves more than a few pixels per
-- world unit, so a smaller mip is both sharper than it needs to be and cheap.
local MAX_TEX = 128

-- Texels below this alpha count as cut out (foliage, fences, grates).
local ALPHA_TEST = 0x60

local Surface = {}

Surface.ALPHA_TEST = ALPHA_TEST

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

local function valid(guest_addr)
    return guest_addr ~= 0 and guest_addr ~= 0xFFFFFFFF
       and Util.IsValidEEPointer(guest_addr)
end

-- surface pointer -> { surf = { w, h, pixels } or false, sig... }. Streaming
-- reuses addresses for new surfaces, so each hit is checked against the header.
local cache = {}
local cache_entries = 0
local CACHE_LIMIT = 512

-- PS2 alpha runs 0x00-0x80, so double it for an 8 bit channel.
local function alpha8(a)
    a = a * 2
    if a > 255 then a = 255 end
    return a
end

local function read_palette(buf, offset, count, format)
    local pal = ffi.new("uint32_t[?]", count)
    if format == 2 then           -- RGBA32
        for i = 0, count - 1 do
            local o = offset + i * 4
            pal[i] = bit.bor(buf[o], bit.lshift(buf[o + 1], 8),
                             bit.lshift(buf[o + 2], 16),
                             bit.lshift(alpha8(buf[o + 3]), 24))
        end
    elseif format == 5 then       -- RGB16, A1B5G5R5 packed low to high
        for i = 0, count - 1 do
            local o = offset + i * 2
            local v = bit.bor(buf[o], bit.lshift(buf[o + 1], 8))
            local r = bit.lshift(bit.band(v, 0x1F), 3)
            local g = bit.lshift(bit.band(bit.rshift(v, 5), 0x1F), 3)
            local b = bit.lshift(bit.band(bit.rshift(v, 10), 0x1F), 3)
            local a = bit.band(v, 0x8000) ~= 0 and 255 or 0
            pal[i] = bit.bor(r, bit.lshift(g, 8), bit.lshift(b, 16), bit.lshift(a, 24))
        end
    else
        return nil
    end

    -- 256 color palettes are held GS swizzled (CSM1): inside every block of 32
    -- entries, 8-15 are swapped with 16-23.
    if count >= 0x20 and count % 0x20 == 0 then
        for base = 0, count - 1, 0x20 do
            for i = 0, 7 do
                local lo, hi = base + 8 + i, base + 16 + i
                pal[lo], pal[hi] = pal[hi], pal[lo]
            end
        end
    end
    return pal
end

--- Picks the largest mip that fits inside MAX_TEX, so big textures cost a
--- fraction of a full decode. Returns w, h, data offset, row stride.
local function pick_mip(surface)
    local mips = i32(surface + SURF_MIP_COUNT)
    if mips <= 0 or mips > 12 then
        return nil
    end
    local chosen = 0
    for i = 0, mips - 1 do
        local m = surface + SURF_MIPS + i * 0x18
        local w = i32(m + 0)
        local h = i32(m + 4)
        if w <= 0 or h <= 0 then break end
        chosen = i
        if w <= MAX_TEX and h <= MAX_TEX then break end
    end
    local m = surface + SURF_MIPS + chosen * 0x18
    return i32(m + 0), i32(m + 4), u32(m + 8), i32(m + 12)
end

local function decode(surface)
    local format  = i32(surface + SURF_FORMAT)
    local buf_ptr = u32(surface + SURF_BUF)
    local buf_len = u32(surface + SURF_BUF_SIZE)
    if not valid(buf_ptr) or buf_len == 0 or buf_len > 0x800000 then return nil end

    local w, h, data_off, stride = pick_mip(surface)
    if w == nil or w <= 0 or h <= 0 or w > 2048 or h > 2048 then return nil end
    if data_off + h * stride > buf_len then return nil end

    local buf = ffi.cast("uint8_t*", host(buf_ptr))

    local pal = nil
    if format == 0 or format == 1 then
        local count  = i32(surface + SURF_PAL_COUNT)
        local offset = u32(surface + SURF_PAL_OFFSET)
        local pformat = i32(surface + SURF_PAL_FORMAT)
        if count <= 0 or count > 256 then return nil end
        pal = read_palette(buf, offset, count, pformat)
        if pal == nil then return nil end
    end

    local pixels = ffi.new("uint32_t[?]", w * h)
    for y = 0, h - 1 do
        local row = data_off + y * stride
        local out = y * w
        if format == 1 then           -- CLUT8
            for x = 0, w - 1 do
                pixels[out + x] = pal[buf[row + x]]
            end
        elseif format == 0 then       -- CLUT4, low nibble first
            for x = 0, w - 1 do
                local b = buf[row + bit.rshift(x, 1)]
                local idx = bit.band(x, 1) == 0 and bit.band(b, 0x0F) or bit.rshift(b, 4)
                pixels[out + x] = pal[idx]
            end
        elseif format == 2 then       -- RGBA32
            for x = 0, w - 1 do
                local o = row + x * 4
                pixels[out + x] = bit.bor(buf[o], bit.lshift(buf[o + 1], 8),
                                          bit.lshift(buf[o + 2], 16),
                                          bit.lshift(alpha8(buf[o + 3]), 24))
            end
        elseif format == 5 then       -- RGB16
            for x = 0, w - 1 do
                local o = row + x * 2
                local v = bit.bor(buf[o], bit.lshift(buf[o + 1], 8))
                local r = bit.lshift(bit.band(v, 0x1F), 3)
                local g = bit.lshift(bit.band(bit.rshift(v, 5), 0x1F), 3)
                local b = bit.lshift(bit.band(bit.rshift(v, 10), 0x1F), 3)
                local a = bit.band(v, 0x8000) ~= 0 and 255 or 0
                pixels[out + x] = bit.bor(r, bit.lshift(g, 8), bit.lshift(b, 16),
                                          bit.lshift(a, 24))
            end
        else
            return nil
        end
    end

    -- A surface with nothing solid in it would rasterize to nothing, which is
    -- worse than falling back to flat shading.
    local opaque = false
    for i = 0, w * h - 1 do
        if bit.rshift(pixels[i], 24) >= ALPHA_TEST then
            opaque = true
            break
        end
    end
    if not opaque then return nil end

    return { w = w, h = h, pixels = pixels }
end

--- Resolves a raster texture handle to its VISurface pointer, 0 when unset.
function Surface.FromHandle(handle)
    if ee_base == nil then ee_base = Util.EEmem() end
    if handle < 0 or handle > 0x10000 then return 0 end
    local table_ptr = u32(RASTER + SURFACE_TABLE)
    if not valid(table_ptr) then return 0 end
    local surface = u32(table_ptr + handle * 0xC)
    if not valid(surface) then return 0 end
    return surface
end

--- Resolves entry index of a material palette to the VISurface of its first
--- texture layer. Returns 0 when the material has no texture.
function Surface.FromMaterial(matpal_id, mat_index)
    if ee_base == nil then ee_base = Util.EEmem() end
    if matpal_id < 0 or matpal_id > 0x40000 then return 0 end
    local table_ptr = u32(RASTER + MATPAL_TABLE)
    if not valid(table_ptr) then return 0 end
    local pal = u32(table_ptr + matpal_id * 0xC)
    if not valid(pal) then return 0 end

    local count = i32(pal + 8)
    local materials = u32(pal + 0xC)
    if mat_index < 0 or mat_index >= count or not valid(materials) then return 0 end

    local material = u32(materials + mat_index * 4)
    if not valid(material) then return 0 end

    local handle = i32(material + MAT_LAYER0_TEX)
    if handle < 0 then return 0 end
    return Surface.FromHandle(handle)
end

-- Header fields that change when a new surface lands at a reused address.
local function header(surface)
    return u32(surface + SURF_BUF), u32(surface + SURF_BUF_SIZE),
           i32(surface + SURF_FORMAT), i32(surface + SURF_WIDTH),
           i32(surface + SURF_HEIGHT)
end

--- Decodes (or returns the cached decode of) a surface. nil when unreadable.
function Surface.Get(surface_ptr)
    if surface_ptr == nil or surface_ptr == 0 then return nil end
    if ee_base == nil then ee_base = Util.EEmem() end
    if not valid(surface_ptr) then return nil end

    local buf, len, fmt, w, h = header(surface_ptr)
    local entry = cache[surface_ptr]
    if entry ~= nil and entry.buf == buf and entry.len == len
       and entry.fmt == fmt and entry.w == w and entry.h == h then
        return entry.surf or nil
    end

    local ok, decoded = pcall(decode, surface_ptr)
    if not ok then decoded = nil end

    if entry == nil then
        if cache_entries >= CACHE_LIMIT then
            Surface.ClearCache()
        end
        cache_entries = cache_entries + 1
    end
    cache[surface_ptr] = { surf = decoded or false,
                           buf = buf, len = len, fmt = fmt, w = w, h = h }
    return decoded
end

function Surface.ClearCache()
    cache = {}
    cache_entries = 0
end

return Surface
