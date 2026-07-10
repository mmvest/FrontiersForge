local ffi = require("ffi")
local Util = require("frontiers_forge.util")

-- Group information lives in the client-state singleton, resolved through the
-- static pointer at 0x4E37F0 which points at singleton + 4 (so each chain step is
-- offset - 4). The member array includes the local player as one of its entries.
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

--- @return integer entity_id The member's entity id.
function GroupMember:GetEntityId()
    return self.ptr.entity_id
end

--- @return string name The member's character name.
function GroupMember:GetName()
    return ffi.string(self.ptr.name)
end

--- Health percent as 0-255, matching how the game stores it.
--- @return integer|nil percent_hp Health from 0 to 255, or nil when the game does not currently know this member's health.
function GroupMember:GetHealthPercent255()
    if self.ptr.hp_known == 0 then
        return nil
    end
    return self.ptr.percent_hp
end

--- Convenience wrapper returning health on a 0 to 100 scale.
--- @return number|nil percent_hp Health from 0 to 100, or nil when the game does not currently know this member's health.
function GroupMember:GetHealthPercent()
    local hp = self:GetHealthPercent255()
    if hp == nil then
        return nil
    end
    return (hp / 255) * 100
end

--- @return boolean active True when this slot is shown in the group panel.
function GroupMember:IsActive()
    return self.ptr.active ~= 0
end

--- Last known position the server sent for this member.
--- @return table coordinates Table with fields x, y, and z.
function GroupMember:GetCoordinates()
    return { x = self.ptr.x, y = self.ptr.y, z = self.ptr.z }
end

local Group = {}

-- Reads a group field via the pointer chain, returning `default` when the
-- chain can't be resolved (e.g. not in game).
local function ReadGroupField(step, default)
    return Util.ReadFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {step}, "uint32_t", default)
end

--- @return boolean in_group True when the player is currently in a group.
function Group.IsInGroup()
    return ReadGroupField(IN_GROUP_STEP, 0) ~= 0
end

--- @return boolean is_leader True when the player is the group leader.
function Group.IsSelfLeader()
    return ReadGroupField(IS_LEADER_STEP, 0) ~= 0
end

--- Number of member records, INCLUDING the local player.
--- @return integer count Member count, or 0 when not in a group or not in game.
function Group.GetMemberCount()
    if not Group.IsInGroup() then
        return 0
    end
    return ReadGroupField(MEMBER_COUNT_STEP, 0)
end

--- Get a member record by index.
--- @param index integer Member index from 0 to GetMemberCount() - 1.
--- @return table|nil member GroupMember object, or nil when the index is out of range or the group data is not loaded.
function Group.GetMemberByIndex(index)
    if index < 0 or index >= Group.GetMemberCount() then
        return nil
    end
    local members_offset = Util.GetOffsetFromPointerChain(GUI_CONTEXT_PTR_OFFSET, {MEMBERS_STEP})
    if members_offset == nil then
        return nil
    end
    local address = Util.EEmem() + members_offset + (index * MEMBER_SIZE)
    return GroupMember.new(address)
end

--- Iterator over all members.
--- Usage looks like `for index, member in Group.Members() do ... end`.
--- @return function iterator Iterator producing member index and GroupMember object pairs.
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
