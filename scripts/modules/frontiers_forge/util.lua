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

    int MultiByteToWideChar(
        unsigned int CodePage,
        unsigned long dwFlags,
        const char* lpMultiByteStr,
        int cbMultiByte,
        wchar_t* lpWideCharStr,
        int cchWideChar
    );

    enum {
        CP_UTF8 = 65001
    };

    typedef void* HANDLE;
    typedef unsigned long DWORD;
    typedef int BOOL;

    typedef struct _FILETIME {
        DWORD dwLowDateTime;
        DWORD dwHighDateTime;
    } FILETIME;

    typedef struct _WIN32_FIND_DATAW {
        DWORD dwFileAttributes;
        FILETIME ftCreationTime;
        FILETIME ftLastAccessTime;
        FILETIME ftLastWriteTime;
        DWORD nFileSizeHigh;
        DWORD nFileSizeLow;
        DWORD dwReserved0;
        DWORD dwReserved1;
        wchar_t cFileName[260];
        wchar_t cAlternateFileName[14];
    } WIN32_FIND_DATAW;

    HANDLE FindFirstFileW(const wchar_t* lpFileName, WIN32_FIND_DATAW* lpFindFileData);
    BOOL FindNextFileW(HANDLE hFindFile, WIN32_FIND_DATAW* lpFindFileData);
    BOOL FindClose(HANDLE hFindFile);
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

-- This function traverses through a pointer chain and returns the final offset.
-- It works by taking a base_offset, reading the value at that offset, then using
-- each step value to move to the next address in the chain. It is a bit confusing,
-- but hopefully the following example helps.
-- Example chain: 4FA500 -> 25C -> 684 -> 1F8 -> target offset
--   Read 4FA500         -> 01FF6860
--   01FF6860 + 25C      = 01FF6ABC
--   Read 01FF6ABC       -> 00268970
--   00268970 + 684      = 00268FF4
--   Read 00268FF4       -> 0026CC40
--   0026CC40 + 1F8      = 0026CE38
--   0026CE38 is the target offset
--   We return 0026CE38
-- base_offset in this case is 0x4FA500
-- steps is { 0x25C, 0x684, 0x1F8 }
--- @param base_offset integer Base offset from EEMem to start traversal from.
--- @param steps integer[] Ordered pointer-chain step values to add between reads.
--- @return integer target_offset Final resolved offset after all chain steps.
function Util.GetOffsetFromPointerChain(base_offset, steps)
    local target_offset = base_offset
    for idx, step in ipairs(steps) do
        target_offset = Util.ReadFromOffset(target_offset, "uint32_t") + step
    end

    return target_offset
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

function Util.utf8_to_utf16(utf8_str)
    utf8_str = tostring(utf8_str or "")

    local wide_len = ffi.C.MultiByteToWideChar(
        ffi.C.CP_UTF8, 0,
        utf8_str, -1,
        nil, 0
    )

    if wide_len == 0 then
        error("Failed to calculate UTF-16 length")
    end

    local wide_buf = ffi.new("wchar_t[?]", wide_len)
    local written = ffi.C.MultiByteToWideChar(
        ffi.C.CP_UTF8, 0,
        utf8_str, -1,
        wide_buf, wide_len
    )

    if written == 0 then
        error("Failed to convert UTF-8 to UTF-16")
    end

    return wide_buf
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
    local is_start_menu_open_offset = Util.GetOffsetFromPointerChain(0x14E200, {0x15C, 0x53C, 0x8, 0x88, 0x24})
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

function Util.ListFiles(pattern, options)
    options = options or {}

    local FILE_ATTRIBUTE_DIRECTORY = 0x10
    local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", -1)
    local base_dir = tostring(options.base_dir or "")
    if base_dir ~= "" and not base_dir:match("[\\\\/]$") then
        base_dir = base_dir .. "\\"
    end

    local wide_pattern = Util.utf8_to_utf16(pattern)
    local find_data = ffi.new("WIN32_FIND_DATAW[1]")
    local h = ffi.C.FindFirstFileW(wide_pattern, find_data)

    if h == INVALID_HANDLE_VALUE then
        return {}
    end

    local results = {}
    while true do
        local data = find_data[0]

        if bit.band(tonumber(data.dwFileAttributes), FILE_ATTRIBUTE_DIRECTORY) == 0 then
            local name = Util.utf16_to_utf8(data.cFileName)
            if name ~= "" and name ~= "." and name ~= ".." then
                if options.full_path == true then
                    results[#results + 1] = base_dir .. name
                else
                    results[#results + 1] = name
                end
            end
        end

        if ffi.C.FindNextFileW(h, find_data) == 0 then
            break
        end
    end

    ffi.C.FindClose(h)
    return results
end

function Util.ListFilesInDir(dir, glob, options)
    dir = tostring(dir or "")
    glob = tostring(glob or "*")
    options = options or {}

    if options.full_path == true and options.base_dir == nil then
        options.base_dir = dir
    end

    return Util.ListFiles(dir .. "\\" .. glob, options)
end

return Util
