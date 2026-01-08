local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
    extern uintptr_t EEmem;
    int WideCharToMultiByte(
        unsigned int CodePage,
        unsigned int dwFlags,
        const wchar_t* lpWideCharStr,
        int cchWideChar,
        char* lpMultiByteStr,
        int cbMultiByte,
        const char* lpDefaultChar,
        int* lpUsedDefaultChar
    );

    enum {
        CP_UTF8 = 65001
    };
]]


-- Define experience needed for each level
local exp_for_levels = {
    [1] = 424, [2] = 2187, [3] = 6976, [4] = 17125, [5] = 35640, [6] = 66199, 
    [7] = 113152, [8] = 181521, [9] = 277000, [10] = 405955, [11] = 575424, 
    [12] = 793117, [13] = 1067416, [14] = 1407375, [15] = 1822720, [16] = 2323849, 
    [17] = 2921832, [18] = 3628411, [19] = 4456000, [20] = 5417685, [21] = 6527224, 
    [22] = 7799047, [23] = 9248256, [24] = 10890625, [25] = 12742600, [26] = 14821299, 
    [27] = 17144512, [28] = 19730701, [29] = 22599000, [30] = 25769215, [31] = 29261824, 
    [32] = 33097977, [33] = 37299496, [34] = 41888875, [35] = 46889280, [36] = 52324549, 
    [37] = 58219192, [38] = 64598391, [39] = 71488000, [40] = 78914545, [41] = 86905224, 
    [42] = 95487907, [43] = 104691136, [44] = 114544125, [45] = 125076760, 
    [46] = 136319599, [47] = 148303872, [48] = 161061481, [49] = 174625000, 
    [50] = 189027675, [51] = 204303424, [52] = 220486837, [53] = 237613176, 
    [54] = 255718375, [55] = 274839040, [56] = 295012449, [57] = 316276552, 
    [58] = 338669971, [59] = 362232000
}

-- Dereference EEmem to get the base address
local ee_mem = tonumber(ffi.C.EEmem)


local Util = {}

function Util.EEmem()
    return ee_mem
end

-- Function to read a value from EEmem + offset
function Util.ReadFromOffset(offset, ctype)
    local ptr = ffi.cast(ctype .. "*", ee_mem + offset)
    return ptr[0]
end

function Util.WriteToOffset(offset, ctype, value)
    local ptr = ffi.cast(ctype .. "*", Util.EEmem() + offset)
    ptr[0] = value
end

-- UTF-16 to UTF-8 conversion using WideCharToMultiByte
-- Assumes null-terminated string
function Util.utf16_to_utf8(utf16_ptr)
    -- Calculate the required buffer size for the UTF-8 string
    local utf8_len = ffi.C.WideCharToMultiByte(
        ffi.C.CP_UTF8, 0,
        utf16_ptr, -1,
        nil, 0,
        nil, nil
    )

    if utf8_len == 0 then
        error("Failed to calculate UTF-8 length")
    end

    -- Allocate the buffer for the UTF-8 string
    local utf8_str = ffi.new("char[?]", utf8_len)

    -- Perform the conversion
    ffi.C.WideCharToMultiByte(
        ffi.C.CP_UTF8, 0,
        utf16_ptr, -1,
        utf8_str, utf8_len,
        nil, nil
    )

    -- Return the resulting UTF-8 string
    return ffi.string(utf8_str)
end

function Util.GetExpRequiredForLevel(level)
    return exp_for_levels[level]
end

function Util.IsBitZero(value, mask)
    
    return bit.band(value, mask) == 0
end

function Util.RadiansToDegrees(radians)
    return radians * (180 / math.pi)
end

function Util.IsInGame()
    local is_in_game_offset = 0x1FDB480
    return Util.ReadFromOffset(is_in_game_offset, "uint8_t")
end

function Util.IsStartMenuOpen()
    local is_start_menu_open_offset = 0x26CC44
    return Util.ReadFromOffset(is_start_menu_open_offset, "uint8_t")
end

-- Retrieve the player's compass heading in radians
function Util.GetCompassRadians()
    local compass_heading_offset = 0x1FB66AC
    return Util.ReadFromOffset(compass_heading_offset, "float")
end

-- Convenience wrapper to get compass heading in degrees
function Util.GetCompassDegrees()
    return Util.RadiansToDegrees(Util.GetCompassRadians())
end

return Util