local ffi = require("ffi")
local Util = require("frontiers_forge.util")

-- Group information lives in the client-state singleton, reached the same way
-- ability_list.lua does it: the static pointer at 0x4E37F0 points at
-- singleton + 4, so each singleton-relative offset below is resolved with a
-- single pointer-chain step of (offset - 4).
--
-- Singleton-relative offsets:
--   +0x2BD74 = in-group flag
--   +0x2BD78 = self-is-leader flag
--   +0x2BD7C = member record array (stride 0x34)
--   +0x2BE4C = member count
--
-- Note the member array includes the local player as one of its entries.
ffi.cdef[[
    typedef struct {
        uint32_t entity_id;         // +0x00
        uint32_t unknown_04;        // +0x04
        uint8_t  percent_hp;        // +0x08  health percent, 0-255
        uint8_t  hp_known;          // +0x09  nonzero when percent_hp is valid
        uint8_t  active;            // +0x0A  nonzero when this slot is shown in the group panel
        uint8_t  unknown_0B;        // +0x0B
        uint32_t unknown_0C;        // +0x0C
        float    x;                 // +0x10  cached position, used by the game when
        float    y;                 // +0x14  the member's entity isn't loaded
        float    z;                 // +0x18
        char     name[24];          // +0x1C  inline string
    } GroupMember;
]]

local GUI_CONTEXT_PTR_OFFSET = 0x4E37F0

local IN_GROUP_STEP     = 0x2BD70
local IS_LEADER_STEP    = 0x2BD74
local MEMBERS_STEP      = 0x2BD78
local MEMBER_COUNT_STEP = 0x2BE48

local MEMBER_SIZE = 0x34

local GroupMember = {}
GroupMember.__index = GroupMember

function GroupMember.new(address)
    if type(address) == "number" then
        address = ffi.cast("GroupMember*", address)
    elseif not ffi.istype("GroupMember*", address) then
        error("Invalid pointer type for GroupMember")
    end

    local self = setmetatable({}, GroupMember)
    self.ptr = address  -- Store the FFI pointer
    return self
end

function GroupMember:GetEntityId()
    return self.ptr.entity_id
end

function GroupMember:GetName()
    return ffi.string(self.ptr.name)
end

-- Health percent as 0-255, matching how the game stores it. Returns nil when
-- the game doesn't currently know this member's health.
function GroupMember:GetHealthPercent255()
    if self.ptr.hp_known == 0 then
        return nil
    end
    return self.ptr.percent_hp
end

-- Convenience wrapper returning 0-100
function GroupMember:GetHealthPercent()
    local hp = self:GetHealthPercent255()
    if hp == nil then
        return nil
    end
    return (hp / 255) * 100
end

function GroupMember:IsActive()
    return self.ptr.active ~= 0
end

-- Last known position the server sent for this member.
function GroupMember:GetCoordinates()
    return { x = self.ptr.x, y = self.ptr.y, z = self.ptr.z }
end

local Group = {}

local function ResolveOffset(step)
    return Util.GetOffsetFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {step})
end

function Group.IsInGroup()
    return Util.ReadFromOffset(ResolveOffset(IN_GROUP_STEP), "uint32_t") ~= 0
end

function Group.IsSelfLeader()
    return Util.ReadFromOffset(ResolveOffset(IS_LEADER_STEP), "uint32_t") ~= 0
end

-- Number of member records, INCLUDING the local player. Returns 0 when not
-- in a group.
function Group.GetMemberCount()
    if not Group.IsInGroup() then
        return 0
    end
    return Util.ReadFromOffset(ResolveOffset(MEMBER_COUNT_STEP), "uint32_t")
end

-- Get a member record by index (0 .. GetMemberCount()-1), or nil.
function Group.GetMemberByIndex(index)
    if index < 0 or index >= Group.GetMemberCount() then
        return nil
    end
    local address = Util.EEmem() + ResolveOffset(MEMBERS_STEP) + (index * MEMBER_SIZE)
    return GroupMember.new(address)
end

-- Iterator over all members:
--   for index, member in Group.Members() do ... end
function Group.Members()
    local index = -1
    return function()
        index = index + 1
        local member = Group.GetMemberByIndex(index)
        if member == nil then
            return nil
        end
        return index, member
    end
end

return Group
