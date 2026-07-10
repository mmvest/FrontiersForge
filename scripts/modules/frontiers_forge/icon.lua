local ffi = require("ffi")
local bit = require("bit")
local Util = require("frontiers_forge.util")

-- Decodes game icon textures straight out of emulated PS2 memory so they can be
-- drawn with ImGui.Image. The game keys its UI art by 32 bit resource hashes (the
-- values in ability records at +0x3C and +0x40), looked up through the UI object at
-- [0x4E37F0] into a dictionary and surface table. Decoded pixels are uploaded once
-- through UiForge.CreateTextureFromMemory and cached by hash, so calling GetTexture
-- every frame is cheap.

local Icon = {}

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0
local RASTER_OFFSET          = 0x48
local DICTIONARY_OFFSET      = 0x50
local SURFACE_TABLE_OFFSET   = 0x4BBC
local DICT_NODE_STRIDE       = 0x1C

-- One cache table per trim variant (keyed by a short variant string), since the
-- same hash can be requested with different trim flags. Entries are
-- hash -> { texture = userdata, width = n, height = n } on success, false on failure.
local texture_cache = {}

local function read_u32(offset)
    return Util.ReadFromOffset(offset, "uint32_t")
end

-- PS2 alpha runs 0x00 to 0x80 where 0x80 is fully opaque, so double it for standard alpha.
local function scale_alpha(a)
    a = a * 2
    return a > 255 and 255 or a
end

--- Finds the VISurface offset for a resource hash by scanning the UI texture dictionary.
--- @param hash integer 32 bit resource hash.
--- @return integer|nil surface_offset EE offset of the VISurface, or nil when not found.
local function FindSurface(hash)
    local ui = read_u32(GUI_CONTEXT_PTR_OFFSET)
    if ui == 0 then return nil end

    local raster = read_u32(ui + RASTER_OFFSET)
    local dictionary = read_u32(ui + DICTIONARY_OFFSET)
    if raster == 0 or dictionary == 0 then return nil end

    local node_count = read_u32(dictionary)
    local node_base = read_u32(dictionary + 0x8)
    if node_base == 0 or node_count == 0 or node_count > 0x10000 then return nil end

    -- Node 0 is the tree sentinel. A linear scan is fine since results are cached.
    local handle = nil
    for i = 1, node_count - 1 do
        local node = node_base + i * DICT_NODE_STRIDE
        if read_u32(node + 0x10) == hash then
            handle = read_u32(node + 0x18)
            break
        end
    end
    if handle == nil then return nil end

    local surf_table = read_u32(raster + SURFACE_TABLE_OFFSET)
    if surf_table == 0 then return nil end

    local surface = read_u32(surf_table + handle * 0xC)
    if surface == 0 then return nil end
    return surface
end

--- Decodes a palette from the surface pixel buffer into an array of RGBA entries.
--- CLUT8 palettes are stored GS swizzled (CSM1) in memory, so within every 32
--- entries the blocks 8 to 15 and 16 to 23 are swapped back.
local function DecodePalette(buf, pal_off, pal_count, pal_fmt)
    if pal_count <= 0 or pal_count > 256 then return nil end

    local pal = {}
    if pal_fmt == 2 then      -- RGBA32
        for i = 0, pal_count - 1 do
            local o = pal_off + i * 4
            pal[i] = { buf[o], buf[o + 1], buf[o + 2], scale_alpha(buf[o + 3]) }
        end
    elseif pal_fmt == 5 then  -- RGB16, A1B5G5R5 packed low byte first
        for i = 0, pal_count - 1 do
            local o = pal_off + i * 2
            local v = buf[o] + buf[o + 1] * 256
            pal[i] = {
                bit.lshift(bit.band(v, 0x1F), 3),
                bit.lshift(bit.band(bit.rshift(v, 5), 0x1F), 3),
                bit.lshift(bit.band(bit.rshift(v, 10), 0x1F), 3),
                bit.band(v, 0x8000) ~= 0 and 255 or 0
            }
        end
    else
        return nil
    end

    if pal_count >= 0x20 and pal_count % 0x20 == 0 then
        for base = 0, pal_count - 1, 0x20 do
            for i = 0, 7 do
                local lo = base + 8 + i
                local hi = base + 16 + i
                pal[lo], pal[hi] = pal[hi], pal[lo]
            end
        end
    end
    return pal
end

--- Decodes a VISurface into a raw RGBA8 pixel buffer.
--- @param surface integer EE offset of the VISurface.
--- @return ffi.cdata*|nil rgba uint8_t buffer of RGBA bytes, plus width and height, or nil on failure.
--- @return integer|nil width
--- @return integer|nil height
local function DecodeSurface(surface)
    local w = read_u32(surface + 0x08)
    local h = read_u32(surface + 0x0C)
    local fmt = read_u32(surface + 0x10)
    local pal_count = read_u32(surface + 0x28)
    local pal_off = read_u32(surface + 0x2C)
    local pal_fmt = read_u32(surface + 0x34)
    local mip0_off = read_u32(surface + 0x4C)
    local mip0_stride = read_u32(surface + 0x50)
    local buf_size = read_u32(surface + 0x134)
    local buf_ptr = read_u32(surface + 0x138)

    if w == 0 or w > 2048 or h == 0 or h > 2048 then return nil end
    if buf_ptr == 0 or buf_size == 0 or buf_size > 0x800000 then return nil end

    -- The pixel buffer lives in EE RAM. Index it directly as bytes.
    local buf = ffi.cast("uint8_t*", Util.EEmem() + buf_ptr)

    local pal = nil
    if fmt == 0 or fmt == 1 then
        pal = DecodePalette(buf, pal_off, pal_count, pal_fmt)
        if pal == nil then return nil end
    end

    local rgba = ffi.new("uint8_t[?]", w * h * 4)
    for y = 0, h - 1 do
        local row = mip0_off + y * mip0_stride
        local out = y * w * 4
        for x = 0, w - 1 do
            local r, g, b, a
            if fmt == 0 then      -- CLUT4, low nibble first
                local byte = buf[row + bit.rshift(x, 1)]
                local idx = bit.band(x, 1) == 0 and bit.band(byte, 0x0F) or bit.rshift(byte, 4)
                local e = pal[idx]
                r, g, b, a = e[1], e[2], e[3], e[4]
            elseif fmt == 1 then  -- CLUT8
                local e = pal[buf[row + x]]
                r, g, b, a = e[1], e[2], e[3], e[4]
            elseif fmt == 2 then  -- RGBA32
                local o = row + x * 4
                r, g, b, a = buf[o], buf[o + 1], buf[o + 2], scale_alpha(buf[o + 3])
            elseif fmt == 5 then  -- RGB16, A1B5G5R5
                local o = row + x * 2
                local v = buf[o] + buf[o + 1] * 256
                r = bit.lshift(bit.band(v, 0x1F), 3)
                g = bit.lshift(bit.band(bit.rshift(v, 5), 0x1F), 3)
                b = bit.lshift(bit.band(bit.rshift(v, 10), 0x1F), 3)
                a = bit.band(v, 0x8000) ~= 0 and 255 or 0
            else
                return nil
            end
            rgba[out] = r
            rgba[out + 1] = g
            rgba[out + 2] = b
            rgba[out + 3] = a
            out = out + 4
        end
    end
    return rgba, w, h
end

--- Finds the dominant color of the outermost one pixel border ring of the image.
--- Padding around an icon is a flat fill, so if one color makes up at least half
--- of the ring we treat that color as the padding color. Transparent ring pixels
--- are ignored since transparent padding is handled separately.
--- @param rgba ffi.cdata* uint8_t buffer of width * height * 4 RGBA bytes.
--- @param w integer Buffer width in pixels.
--- @param h integer Buffer height in pixels.
--- @return integer|nil color Packed RGBA of the padding color, or nil when no color dominates.
local function DetectPaddingColor(rgba, w, h)
    local counts = {}
    local ring_total = 0

    local function tally(x, y)
        local o = (y * w + x) * 4
        if rgba[o + 3] == 0 then return end
        local key = rgba[o] * 16777216 + rgba[o + 1] * 65536 + rgba[o + 2] * 256 + rgba[o + 3]
        counts[key] = (counts[key] or 0) + 1
        ring_total = ring_total + 1
    end

    for x = 0, w - 1 do
        tally(x, 0)
        if h > 1 then tally(x, h - 1) end
    end
    for y = 1, h - 2 do
        tally(0, y)
        if w > 1 then tally(w - 1, y) end
    end

    if ring_total == 0 then return nil end

    local best_key, best_count = nil, 0
    for key, count in pairs(counts) do
        if count > best_count then
            best_key, best_count = key, count
        end
    end

    if best_count * 2 < ring_total then
        return nil
    end
    return best_key
end

--- Crops a decoded RGBA buffer down to the bounding box of its meaningful pixels.
--- A pixel counts as padding when it is fully transparent (when trim_transparent
--- is set) or matches the detected flat padding color of the border ring (when
--- trim_color is set). Game icons often sit inside a much larger surface padded
--- with transparent or flat colored rows and columns.
--- @param rgba ffi.cdata* uint8_t buffer of width * height * 4 RGBA bytes.
--- @param w integer Buffer width in pixels.
--- @param h integer Buffer height in pixels.
--- @param trim_transparent boolean Treat fully transparent pixels as padding.
--- @param trim_color boolean Treat pixels matching the border ring's dominant color as padding.
--- @return ffi.cdata*|nil cropped Cropped buffer, or nil when every pixel is padding.
--- @return integer|nil width Cropped width.
--- @return integer|nil height Cropped height.
local function Trim(rgba, w, h, trim_transparent, trim_color)
    local pad_color = nil
    if trim_color then
        pad_color = DetectPaddingColor(rgba, w, h)
    end

    local min_x, min_y, max_x, max_y = w, h, -1, -1
    for y = 0, h - 1 do
        local row = y * w * 4
        for x = 0, w - 1 do
            local o = row + x * 4
            local is_padding = false
            if trim_transparent and rgba[o + 3] == 0 then
                is_padding = true
            elseif pad_color ~= nil then
                local key = rgba[o] * 16777216 + rgba[o + 1] * 65536 + rgba[o + 2] * 256 + rgba[o + 3]
                is_padding = (key == pad_color)
            end
            if not is_padding then
                if x < min_x then min_x = x end
                if x > max_x then max_x = x end
                if y < min_y then min_y = y end
                if y > max_y then max_y = y end
            end
        end
    end

    if max_x < 0 then
        return nil
    end
    if min_x == 0 and min_y == 0 and max_x == w - 1 and max_y == h - 1 then
        return rgba, w, h
    end

    local tw = max_x - min_x + 1
    local th = max_y - min_y + 1
    local cropped = ffi.new("uint8_t[?]", tw * th * 4)
    for y = 0, th - 1 do
        ffi.copy(cropped + y * tw * 4,
                 rgba + ((min_y + y) * w + min_x) * 4,
                 tw * 4)
    end
    return cropped, tw, th
end

--- Gets an ImGui compatible texture for a resource hash, decoding and uploading
--- it on first use and returning the cached copy afterwards. Failures are cached
--- too so a missing icon does not rescan the dictionary every frame.
--- @param hash integer 32 bit resource hash, for example ability GetIconForegroundRef.
--- @param options table|nil Optional table with these flags
---   trim_transparent crops away fully transparent padding
---   trim_color also crops away flat colored padding, detected as the dominant
---   color of the image's outer border ring
---   trim is an alias for trim_transparent
--- @return userdata|nil texture Texture usable with ImGui.Image, or nil when unavailable.
--- @return integer|nil width Texture width in pixels.
--- @return integer|nil height Texture height in pixels.
function Icon.GetTexture(hash, options)
    if hash == nil then return nil end
    hash = tonumber(hash)
    if hash == nil or hash == 0 or hash == 0xFFFFFFFF then return nil end

    local trim_transparent = options ~= nil and (options.trim_transparent == true or options.trim == true)
    local trim_color = options ~= nil and options.trim_color == true

    -- One cache per trim variant so the same hash can be requested every way.
    local variant = (trim_transparent and "t" or "") .. (trim_color and "c" or "")
    local cache = texture_cache[variant]
    if cache == nil then
        cache = {}
        texture_cache[variant] = cache
    end

    local cached = cache[hash]
    if cached == false then return nil end
    if cached ~= nil then return cached.texture, cached.width, cached.height end

    local surface = FindSurface(hash)
    if surface == nil then
        cache[hash] = false
        return nil
    end

    local rgba, w, h = DecodeSurface(surface)
    if rgba == nil then
        cache[hash] = false
        return nil
    end

    if trim_transparent or trim_color then
        rgba, w, h = Trim(rgba, w, h, trim_transparent, trim_color)
        if rgba == nil then
            -- Every pixel was padding so there is nothing to draw.
            cache[hash] = false
            return nil
        end
    end

    local texture = UiForge.CreateTextureFromMemory(ffi.string(rgba, w * h * 4), w, h)
    if texture == nil then
        cache[hash] = false
        return nil
    end

    cache[hash] = { texture = texture, width = w, height = h }
    return texture, w, h
end

-- Built-in UI textures (bar frames, hotbar slot glyphs, ...) are keyed by small
-- texture ids instead of hashes.
local UI_TEX_REGISTRY_OFFSET = 0x4EDAF8   -- static registry, stride 0x24
local UI_TEX_COUNT           = 0xFC
local UI_NAME_TEMPLATE       = "P:\\studio\\eqps2\\Game_Assets\\UI\\%s.tga"

local ui_texture_cache = {}

-- The game's resource id hash: h = h * 0x83 + byte over the full asset path.
local function HashResourceID(str)
    local h = 0
    for i = 1, #str do
        h = bit.tobit(h * 0x83 + str:byte(i))
    end
    if h < 0 then h = h + 4294967296 end
    return h
end

-- Reads an entry (1-based index) from the UI string table, narrowed to ASCII.
local function ReadUIString(index)
    local ui = read_u32(GUI_CONTEXT_PTR_OFFSET)
    if not Util.IsValidEEPointer(ui) then return nil end

    local count = read_u32(ui + 0x10)
    local langs = read_u32(ui + 0x14)
    local base = read_u32(ui + 0x1C)
    local lang = read_u32(ui + 0x30)
    index = index - 1
    if not Util.IsValidEEPointer(base) or index < 0 or index >= count or lang >= langs then
        return nil
    end

    local str_offset = read_u32(base + (index * langs + lang) * 4)
    if not Util.IsValidEEPointer(str_offset) then return nil end

    local out = {}
    for i = 0, 63 do
        local ch = Util.ReadFromOffset(str_offset + i * 2, "uint16_t")
        if ch == 0 then break end
        out[#out + 1] = string.char(bit.band(ch, 0xFF))
    end
    return table.concat(out)
end

--- Gets an ImGui compatible texture for a built-in UI texture id (the id space used
--- by the HUD's own frames and hotbar slot glyphs, 0 to 0xFB). Cached like GetTexture.
--- @param tex_id integer UI texture id, for example AbilityBar.GetSlotUITexId(slot).
--- @return userdata|nil texture Texture usable with ImGui.Image, or nil when unavailable.
--- @return integer|nil width
--- @return integer|nil height
function Icon.GetUITexture(tex_id)
    tex_id = tonumber(tex_id)
    if tex_id == nil or tex_id < 0 or tex_id >= UI_TEX_COUNT then return nil end

    local cached = ui_texture_cache[tex_id]
    if cached == false then return nil end
    if cached ~= nil then return cached.texture, cached.width, cached.height end

    local function fail()
        ui_texture_cache[tex_id] = false
        return nil
    end

    local entry = UI_TEX_REGISTRY_OFFSET + tex_id * 0x24
    local name_index = read_u32(entry + 0x4)
    local src_x = read_u32(entry + 0x8)
    local src_y = read_u32(entry + 0xC)
    local w = read_u32(entry + 0x10)
    local h = read_u32(entry + 0x14)

    local name = ReadUIString(name_index)
    if name == nil or name == "" or name == "_null_" then return fail() end

    local surface = FindSurface(HashResourceID(string.format(UI_NAME_TEMPLATE, name)))
    if surface == nil then return fail() end

    local rgba, full_w, full_h = DecodeSurface(surface)
    if rgba == nil then return fail() end
    if w <= 0 or h <= 0 or src_x + w > full_w or src_y + h > full_h then return fail() end

    local cropped = ffi.new("uint8_t[?]", w * h * 4)
    for y = 0, h - 1 do
        ffi.copy(cropped + y * w * 4, rgba + ((src_y + y) * full_w + src_x) * 4, w * 4)
    end

    local texture = UiForge.CreateTextureFromMemory(ffi.string(cropped, w * h * 4), w, h)
    if texture == nil then return fail() end

    ui_texture_cache[tex_id] = { texture = texture, width = w, height = h }
    return texture, w, h
end

--- Looks up a resource hash and reports its raw surface properties without decoding.
--- Useful for diagnosing icons that fail to decode (e.g. an unsupported pixel format).
--- @param hash integer 32 bit resource hash.
--- @return table|nil info { width, height, format, palette_count, palette_format }, or nil when not in the dictionary.
function Icon.GetSurfaceInfo(hash)
    hash = tonumber(hash)
    if hash == nil or hash == 0 or hash == 0xFFFFFFFF then return nil end

    local surface = FindSurface(hash)
    if surface == nil then return nil end

    return {
        width          = read_u32(surface + 0x08),
        height         = read_u32(surface + 0x0C),
        format         = read_u32(surface + 0x10),
        palette_count  = read_u32(surface + 0x28),
        palette_format = read_u32(surface + 0x34),
    }
end

--- Releases every cached texture and empties all caches. Call from a script
--- disable callback so textures are not leaked across reloads.
function Icon.ReleaseAll()
    for _, cache in pairs(texture_cache) do
        for _, entry in pairs(cache) do
            if entry and entry.texture then
                UiForge.ReleaseTexture(entry.texture)
            end
        end
    end
    texture_cache = {}
    for _, entry in pairs(ui_texture_cache) do
        if entry and entry.texture then
            UiForge.ReleaseTexture(entry.texture)
        end
    end
    ui_texture_cache = {}
end

return Icon
