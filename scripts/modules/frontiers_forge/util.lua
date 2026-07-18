local ffi = require("ffi")
local bit = require("bit")

-- pcall because hot reload runs this cdef again, and LuaJIT refuses to
-- redefine structs. The definitions are identical, so a failure is harmless.
pcall(ffi.cdef, [[
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
]])

local CP_UTF8 = 65001


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

--- @return integer base_address The emulated PS2 memory base address in host memory.
function Util.EEmem()
    return ee_mem
end

--- Size of EE main RAM. Offsets at or beyond this are not backed by guest memory,
--- and dereferencing EEmem + offset for them reads unrelated (or unmapped) host memory.
--- In short... trying to read past this will blow up eqoa.
Util.EE_RAM_SIZE = 0x02000000

--- Whether a u32 read from guest memory is a plausible pointer into EE RAM.
--- Null and anything outside main RAM are rejected.
--- @param ptr integer Value to validate.
--- @return boolean valid True when ptr is safe to dereference as an EE address.
function Util.IsValidEEPointer(ptr)
    return ptr ~= nil and ptr > 0 and ptr < Util.EE_RAM_SIZE
end

-- A bad offset here would become a host-side access violation that kills the
-- emulator process, so raise a Lua error naming the caller instead.
local function CheckOffsetBounds(offset, ctype, action)
    if type(offset) ~= "number" or offset < 0
        or offset + ffi.sizeof(ctype) > Util.EE_RAM_SIZE then
        error(("attempt to %s %s at out-of-bounds EE offset %s")
            :format(action, ctype, tostring(offset)), 3)
    end
end

--- Reads a value of the given ctype from EEmem plus offset.
--- Raises a Lua error if the access would fall outside EE RAM.
--- @param offset integer Offset from EEmem to read from.
--- @param ctype string The ctype to read (e.g. "uint32_t").
--- @return any value The value read at that offset.
function Util.ReadFromOffset(offset, ctype)
    CheckOffsetBounds(offset, ctype, "read")
    local ptr = ffi.cast(ctype .. "*", ee_mem + offset)
    return ptr[0]
end

--- Writes a value of the given ctype to EEmem plus offset.
--- Raises a Lua error if the access would fall outside EE RAM.
--- @param offset integer Offset from EEmem to write to.
--- @param ctype string The ctype to write (e.g. "uint32_t").
--- @param value any The value to write.
function Util.WriteToOffset(offset, ctype, value)
    CheckOffsetBounds(offset, ctype, "write")
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
--- If any value in the chain is not a plausible EE pointer we return nil rather than
--- chasing a bogus address. Every read here lands at EEmem + value on the host side,
--- so a garbage u32 (e.g. non-pointer data read through a stale anchor) would become
--- an out-of-bounds host read of up to 4GB past the 32MB of EE RAM and crash the
--- emulator process. Bounding each hop to EE RAM makes that impossible.
--- @param base_offset integer Base offset from EEMem to start traversal from.
--- @param steps integer[] Ordered pointer-chain step values to add between reads.
--- @return integer|nil target_offset Final resolved offset, or nil if the chain hit a null or out-of-range pointer.
function Util.GetOffsetFromPointerChain(base_offset, steps)
    local target_offset = base_offset
    for idx, step in ipairs(steps) do
        local ptr = Util.ReadFromOffset(target_offset, "uint32_t")
        if not Util.IsValidEEPointer(ptr) then
            return nil
        end
        target_offset = ptr + step
        if target_offset < 0 or target_offset >= Util.EE_RAM_SIZE then
            return nil
        end
    end

    return target_offset
end

-- Convenience wrapper to resolve a pointer chain and read the value at the end,
-- returning `default` if the chain hits a null pointer. Saves callers from repeating
-- the nil check required by the updated GetOffsetFromPointerChain now returning nil
-- when encountering a null pointer.
--- @param base_offset integer Base offset from EEMem to start traversal from.
--- @param steps integer[] Ordered pointer-chain step values.
--- @param ctype string The ctype to read at the resolved offset (e.g. "uint32_t").
--- @param default any Value to return if the chain hits a null pointer.
--- @return any value The value read, or `default` if the chain was broken.
function Util.ReadFromPointerChain(base_offset, steps, ctype, default)
    local offset = Util.GetOffsetFromPointerChain(base_offset, steps)
    if offset == nil then
        return default
    end
    return Util.ReadFromOffset(offset, ctype)
end

--- UTF-16 to UTF-8 conversion using WideCharToMultiByte.
--- Assumes a null terminated string. Errors when the conversion fails.
--- @param utf16_ptr cdata Pointer to a null terminated wchar_t string.
--- @return string utf8_str The converted UTF-8 Lua string.
function Util.utf16_to_utf8(utf16_ptr)
    -- Calculate the required buffer size for the UTF-8 string
    local utf8_len = ffi.C.WideCharToMultiByte(
        CP_UTF8, 0,
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
        CP_UTF8, 0,
        utf16_ptr, -1,
        utf8_str, utf8_len,
        nil, nil
    )

    -- Return the resulting UTF-8 string
    return ffi.string(utf8_str)
end

--- UTF-8 to UTF-16 conversion using MultiByteToWideChar.
--- Errors when the conversion fails.
--- @param utf8_str string UTF-8 string to convert. nil becomes an empty string.
--- @return cdata wide_buf Null terminated wchar_t buffer holding the UTF-16 string.
function Util.utf8_to_utf16(utf8_str)
    utf8_str = tostring(utf8_str or "")

    local wide_len = ffi.C.MultiByteToWideChar(
        CP_UTF8, 0,
        utf8_str, -1,
        nil, 0
    )

    if wide_len == 0 then
        error("Failed to calculate UTF-16 length")
    end

    local wide_buf = ffi.new("wchar_t[?]", wide_len)
    local written = ffi.C.MultiByteToWideChar(
        CP_UTF8, 0,
        utf8_str, -1,
        wide_buf, wide_len
    )

    if written == 0 then
        error("Failed to convert UTF-8 to UTF-16")
    end

    return wide_buf
end

--- Total experience required to reach the next level from the given level.
--- @param level integer Character level from 1 to 59.
--- @return integer|nil exp Experience required, or nil for levels outside the table.
function Util.GetExpRequiredForLevel(level)
    return exp_for_levels[level]
end

--- Straight line 3D distance between two world points.
--- @param point_a table Point with x, y, and z fields.
--- @param point_b table Point with x, y, and z fields.
--- @return number distance
function Util.GetDistanceBetween(point_a, point_b)
    local dx = point_a.x - point_b.x
    local dy = point_a.y - point_b.y
    local dz = point_a.z - point_b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Tests whether the bits selected by mask are all zero in value.
--- @param value integer Value to test.
--- @param mask integer Bit mask to apply.
--- @return boolean is_zero True when value AND mask equals zero.
function Util.IsBitZero(value, mask)

    return bit.band(value, mask) == 0
end

--- @param radians number Angle in radians.
--- @return number degrees Angle in degrees.
function Util.RadiansToDegrees(radians)
    return radians * (180 / math.pi)
end

--- Whether the player is currently in the game world.
--- @return integer in_game Nonzero when in game, 0 otherwise.
function Util.IsInGame()
    local is_in_game_offset = 0x1FDB480
    return Util.ReadFromOffset(is_in_game_offset, "uint8_t")
end

--- The index of the world the player is currently in.
--- 0 tunaria, 1 rathe, 2 odus, 3 lavastm, 4 planesky, 5 secrets, and on
--- patched clients 6 underfoot, 7 secrets2. Set when the client loads a
--- world's .esf, so it is only meaningful while in game.
--- @return integer world_id Index into the game's world table.
function Util.GetWorldId()
    local world_index_offset = 0x1FB5D60
    return Util.ReadFromOffset(world_index_offset, "uint32_t")
end

--- Whether the start menu is currently open.
--- @return integer is_open Nonzero when the start menu is open, 0 otherwise or when not in game.
function Util.IsStartMenuOpen()
    return Util.ReadFromPointerChain(0x14E200, {0x15C, 0x53C, 0x8, 0x88, 0x24}, "uint8_t", 0)
end

--- Whether the battle music is currently playing.
--- Reads the flag byte at offset 0x263 of the player's entity record, which is
--- the same byte the game reads when deciding whether to play battle music. The
--- server sets it a few seconds after combat begins and clears it immediately when
--- combat ends, so it lags behind real combat state a little. Any of you modders
--- that want to determine whether a player is in or out of combat may find this
--- useful but it shouldn't be used on its own for that purpose.
--- @return boolean True when the battle music flag is set.
function Util.IsBattleMusicPlaying()
    local entity_list_offset = 0x1FB6C30
    local player_entity = Util.ReadFromOffset(entity_list_offset, "uint32_t")
    return Util.ReadFromOffset(player_entity + 0x263, "uint8_t") ~= 0
end

--- Retrieve the game's raw facing angle in radians.
--- The raw angle turns opposite to compass degrees, facing at raw angle h
--- points along the world direction (-sin h, -cos h) on the x z plane, so
--- raw east is 270. Use GetCompassDegrees for a real compass reading.
--- @return number radians Raw facing angle in radians.
function Util.GetCompassRadians()
    local compass_heading_offset = 0x1FB66AC
    return Util.ReadFromOffset(compass_heading_offset, "float")
end

--- The compass heading in degrees, north 0, east 90, clockwise.
--- @return number degrees Compass heading in [0, 360).
function Util.GetCompassDegrees()
    return (360 - Util.RadiansToDegrees(Util.GetCompassRadians() or 0)) % 360
end

--- Wraps an angle into [0, 360).
--- @param degrees number
--- @return number degrees
function Util.NormalizeDegrees(degrees)
    return degrees % 360
end

--- Shortest signed difference between two angles, in degrees.
--- @param from_deg number
--- @param to_deg number
--- @return number difference In [-180, 180). Positive means to_deg is ahead of from_deg.
function Util.SignedDegreesBetween(from_deg, to_deg)
    return (to_deg - from_deg + 180) % 360 - 180
end

--- Compass bearing from one world point toward another, in the same convention
--- Util.GetCompassRadians uses. Facing at heading h points along the world
--- direction (sin h, -cos h) on the x z plane, so the bearing of a direction
--- (dx, dz) is atan2(dx, -dz). Verified in game. Height is ignored.
--- @param from table Point with x and z fields.
--- @param to table Point with x and z fields.
--- @return number degrees Bearing in [0, 360).
function Util.GetBearingToPoint(from, to)
    local dx = to.x - from.x
    local dz = to.z - from.z
    return Util.NormalizeDegrees(Util.RadiansToDegrees(math.atan2(dx, -dz)))
end

--- Whether a heading is pointed at a world point, within a tolerance.
--- @param from table Viewer position with x and z fields.
--- @param heading_deg number Compass heading, degrees.
--- @param point table Target point with x and z fields.
--- @param tolerance_deg number|nil Half angle of the acceptance cone, default 10.
--- @return boolean facing
function Util.IsFacingPoint(from, heading_deg, point, tolerance_deg)
    local offset = Util.SignedDegreesBetween(heading_deg, Util.GetBearingToPoint(from, point))
    return math.abs(offset) <= (tolerance_deg or 10)
end

--- Lists files matching a Windows wildcard pattern. Directories are skipped.
--- @param pattern string Windows path pattern (e.g. "scripts\\*.lua").
--- @param options table|nil Optional table with full_path boolean and base_dir string used to prefix results.
--- @return string[] results Array of file names, or full paths when options.full_path is true. Empty when nothing matches.
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

--- Convenience wrapper listing files in a directory that match a glob.
--- @param dir string Directory to search.
--- @param glob string|nil Wildcard to match, defaults to "*".
--- @param options table|nil Same options as ListFiles. full_path uses dir as the prefix when base_dir is not set.
--- @return string[] results Array of file names, or full paths when options.full_path is true. Empty when nothing matches.
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
