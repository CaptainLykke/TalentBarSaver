--[[
	TalentBarSaver - Gear sets
	Links an action bar profile to an Equipment Manager set.
	When the profile is loaded, the linked set is equipped as well.

	- Automatic switches (template applied, dual spec change) always equip the linked set.
	- Manual loads (Load button, Apply now, /tbs restore) equip it if the option is enabled.
	- Never in combat (UseEquipmentSet is protected in combat): the set is queued
	  and equipped right after combat. Same while dead or a ghost.
	- Before equipping, every slot of the set is checked. Missing items and items
	  that are only in the bank are reported in chat. Available items are equipped anyway.

	Stored in ActionBarSaverDB.bridge:
	  gearLinks         = { [CLASS] = { [profile] = setName } }
	  equipOnManualLoad = true/false
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local GearSets = {}
ABS.GearSets = GearSets

local YELLOW = "|cffffff00"
local RED = "|cffff4040"

local FIRST_SLOT, LAST_SLOT = 1, 19 -- 0 (ammo) is skipped on purpose
local NUM_BAGS = 4

local frame = CreateFrame("Frame")
local pendingSet

local function Print(msg)
	ABS:Print(msg)
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
function GearSets:InitDB()
	local b = Bridge.db
	b.gearLinks = b.gearLinks or {}
	b.gearLinks[Bridge.class] = b.gearLinks[Bridge.class] or {}
	if( b.equipOnManualLoad == nil ) then b.equipOnManualLoad = true end
	self.links = b.gearLinks[Bridge.class]

	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:RegisterEvent("PLAYER_UNGHOST")
	frame:RegisterEvent("PLAYER_ALIVE")
	frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function GearSets:GetLink(profile)
	return self.links and self.links[profile]
end

function GearSets:SetLink(profile, setName)
	if( setName == "" ) then setName = nil end
	self.links[profile] = setName
	if( ABS.UpdateMinimapIcon ) then ABS:UpdateMinimapIcon() end
end

function GearSets:IsEquipOnManualLoad()
	return Bridge.db.equipOnManualLoad
end

function GearSets:SetEquipOnManualLoad(value)
	Bridge.db.equipOnManualLoad = value and true or false
end

---------------------------------------------------------------------------
-- Equipment Manager sets
---------------------------------------------------------------------------
local function NormalizeIcon(icon)
	if( not icon or icon == "" ) then return nil end
	if( type(icon) == "string" and not string.find(icon, "\\", 1, true) ) then
		return "Interface\\Icons\\" .. icon
	end
	return icon
end

-- List of { name = ..., icon = ... }, sorted by name
function GearSets:GetSets()
	local sets = {}
	for i=1, (GetNumEquipmentSets() or 0) do
		local name, icon = GetEquipmentSetInfo(i)
		if( name ) then
			table.insert(sets, {name = name, icon = NormalizeIcon(icon)})
		end
	end
	table.sort(sets, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
	return sets
end

function GearSets:SetExists(setName)
	for i=1, (GetNumEquipmentSets() or 0) do
		if( GetEquipmentSetInfo(i) == setName ) then
			return true
		end
	end
	return false
end

function GearSets:GetSetIcon(setName)
	if( not setName ) then return nil end
	for i=1, (GetNumEquipmentSets() or 0) do
		local name, icon = GetEquipmentSetInfo(i)
		if( name == setName ) then
			return NormalizeIcon(icon)
		end
	end
	return nil
end

-- Inline texture for labels, dropdowns and chat
function GearSets:IconText(icon, size)
	if( not icon ) then return "" end
	return "|T" .. icon .. ":" .. (size or 16) .. "|t "
end

-- Icon of the gear set linked to a profile (or nil)
function GearSets:GetProfileIcon(profile)
	return self:GetSetIcon(self:GetLink(profile))
end

---------------------------------------------------------------------------
-- Missing item check
---------------------------------------------------------------------------
local function ItemIDFromLink(link)
	return link and tonumber(string.match(link, "item:(%d+)"))
end

local function ItemText(itemID)
	local _, link = GetItemInfo(itemID)
	return link or ("item #" .. itemID)
end

-- Returns two lists of item IDs: missing (not owned) and inBank (only in the bank)
function GearSets:CheckItems(setName)
	local needed = {}
	local itemIDs = GetEquipmentSetItemIDs(setName) or {}
	for slot=FIRST_SLOT, LAST_SLOT do
		local id = itemIDs[slot]
		-- nil / 0 = empty slot, 1 = ignored slot
		if( id and id > 1 ) then
			needed[id] = (needed[id] or 0) + 1
		end
	end

	-- What do we have equipped or in our bags?
	local have = {}
	for slot=FIRST_SLOT, LAST_SLOT do
		local id = ItemIDFromLink(GetInventoryItemLink("player", slot))
		if( id ) then have[id] = (have[id] or 0) + 1 end
	end
	for bag=0, NUM_BAGS do
		for slot=1, (GetContainerNumSlots(bag) or 0) do
			local id = ItemIDFromLink(GetContainerItemLink(bag, slot))
			if( id ) then have[id] = (have[id] or 0) + 1 end
		end
	end

	local missing, inBank = {}, {}
	for id, count in pairs(needed) do
		local lacking = count - (have[id] or 0)
		if( lacking > 0 ) then
			local bank = math.max(0, (GetItemCount(id, true) or 0) - (GetItemCount(id) or 0))
			for n=1, lacking do
				if( n <= bank ) then
					table.insert(inBank, id)
				else
					table.insert(missing, id)
				end
			end
		end
	end
	return missing, inBank
end

local function JoinItems(list)
	local parts = {}
	for _, id in ipairs(list) do
		table.insert(parts, ItemText(id))
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Equipping
---------------------------------------------------------------------------
local function CanEquipNow()
	return not InCombatLockdown() and not UnitIsDeadOrGhost("player")
end

function GearSets:Equip(setName)
	if( not setName ) then return end

	if( not self:SetExists(setName) ) then
		Print(string.format(RED .. "Linked gear set|r %s%s|r " .. RED .. "not found.|r Check the Equipment Manager or the link in the Profiles tab.", YELLOW, setName))
		return
	end

	if( not CanEquipNow() ) then
		if( pendingSet ~= setName ) then
			pendingSet = setName
			local why = InCombatLockdown() and "In combat" or "You are dead"
			Print(string.format("%s - gear set %s%s%s|r will be equipped afterwards.", why, self:IconText(self:GetSetIcon(setName)), YELLOW, setName))
		end
		return
	end
	pendingSet = nil

	local missing, inBank = self:CheckItems(setName)
	local icon = self:IconText(self:GetSetIcon(setName))

	if( #missing > 0 ) then
		Print(string.format("Gear set %s%s%s|r: %s%d item(s) missing:|r %s", icon, YELLOW, setName, RED, #missing, JoinItems(missing)))
	end
	if( #inBank > 0 ) then
		Print(string.format("Gear set %s%s%s|r: %d item(s) are in your bank: %s", icon, YELLOW, setName, #inBank, JoinItems(inBank)))
	end

	if( UseEquipmentSet(setName) ) then
		Print(string.format("Equipped gear set %s%s%s|r.", icon, YELLOW, setName))
	else
		Print(string.format(RED .. "Could not equip gear set|r %s%s|r.", YELLOW, setName))
	end
end

-- Called after a profile was loaded (see Bridge: ABS:OnProfileRestored)
function GearSets:OnProfileLoaded(profile, isAutomatic)
	local setName = self:GetLink(profile)
	if( not setName ) then return end
	if( not isAutomatic and not self:IsEquipOnManualLoad() ) then return end
	self:Equip(setName)
end

---------------------------------------------------------------------------
-- Profile renamed / deleted
---------------------------------------------------------------------------
function GearSets:OnProfileRenamed(old, new)
	if( self.links and self.links[old] ) then
		self.links[new] = self.links[old]
		self.links[old] = nil
	end
end

function GearSets:OnProfileDeleted(name)
	if( self.links ) then
		self.links[name] = nil
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event)
	if( event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_ENTERING_WORLD" ) then
		if( ABS.RefreshWindow ) then ABS:RefreshWindow() end
		if( ABS.UpdateMinimapIcon ) then ABS:UpdateMinimapIcon() end
		return
	end

	-- PLAYER_REGEN_ENABLED, PLAYER_UNGHOST, PLAYER_ALIVE
	if( pendingSet and CanEquipNow() ) then
		local setName = pendingSet
		pendingSet = nil
		GearSets:Equip(setName)
	end
end)
