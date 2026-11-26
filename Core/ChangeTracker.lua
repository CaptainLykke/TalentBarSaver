--[[
	TalentBarSaver - Change tracker
	Notices when you change your action bars after a profile was loaded or saved,
	so you do not forget to save the changes.

	- A snapshot of the bars is taken shortly after a profile is loaded or saved
	  (and after a dual spec change, because the game swaps the bars itself).
	- Every ACTIONBAR_SLOT_CHANGED compares the bars with that snapshot.
	- Spells are compared by name, so rank upgrades and spellbook shifts do not count as changes.

	API: ABS:HasUnsavedChanges(), ABS:SaveChanges()
	Shown in: Profiles tab, minimap tooltip, small dot on the minimap button, quick menu.
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local ChangeTracker = {}
ABS.ChangeTracker = ChangeTracker
ABS:RegisterModule(ChangeTracker)

local MAX_ACTION_BUTTONS = 144
local POSSESSION_START, POSSESSION_END = 121, 132
local BASELINE_DELAY = 1.5  -- wait until all slot updates of a restore/swap have arrived
local CHECK_DELAY = 0.5     -- debounce for slot changes

local frame = CreateFrame("Frame")
local baseline
local dirty = false
local baselineTimer, checkTimer

---------------------------------------------------------------------------
-- Snapshot of the current bars: slot -> comparable key
---------------------------------------------------------------------------
local function ActionKey(slot)
	local actionType, id, subType = GetActionInfo(slot)
	if( not actionType ) then return nil end

	if( actionType == "spell" ) then
		local name = id and GetSpellName(id, BOOKTYPE_SPELL)
		return "spell|" .. tostring(name or id)
	elseif( actionType == "macro" ) then
		local name, _, body = GetMacroInfo(id)
		return "macro|" .. tostring(name) .. "|" .. tostring(body)
	elseif( actionType == "companion" ) then
		return "companion|" .. tostring(subType) .. "|" .. tostring(id)
	end
	return actionType .. "|" .. tostring(id)
end

local function Snapshot()
	local snap = {}
	for slot=1, MAX_ACTION_BUTTONS do
		if( slot < POSSESSION_START or slot > POSSESSION_END ) then
			snap[slot] = ActionKey(slot)
		end
	end
	return snap
end

local function SameSnapshot(a, b)
	for slot=1, MAX_ACTION_BUTTONS do
		if( a[slot] ~= b[slot] ) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local function SetDirty(value)
	if( dirty == value ) then return end
	dirty = value
	if( ABS.UpdateMinimapIcon ) then ABS:UpdateMinimapIcon() end
	if( ABS.RefreshWindow ) then ABS:RefreshWindow() end
end

local function OnUpdate(self, elapsed)
	if( baselineTimer ) then
		baselineTimer = baselineTimer - elapsed
		if( baselineTimer <= 0 ) then
			baselineTimer = nil
			checkTimer = nil
			baseline = Snapshot()
			SetDirty(false)
		end
	elseif( checkTimer ) then
		checkTimer = checkTimer - elapsed
		if( checkTimer <= 0 ) then
			checkTimer = nil
			if( baseline and Bridge:GetLastProfile() ) then
				SetDirty(not SameSnapshot(baseline, Snapshot()))
			end
		end
	end

	if( not baselineTimer and not checkTimer ) then
		self:SetScript("OnUpdate", nil)
	end
end

-- Take a new snapshot a little later (after a load, save or spec swap)
function ChangeTracker:ScheduleBaseline()
	baselineTimer = BASELINE_DELAY
	frame:SetScript("OnUpdate", OnUpdate)
end

function ChangeTracker:ScheduleCheck()
	if( baselineTimer ) then return end -- a new snapshot is coming anyway
	checkTimer = CHECK_DELAY
	frame:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Module hooks
---------------------------------------------------------------------------
function ChangeTracker:InitDB()
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
end

function ChangeTracker:OnProfileLoaded()
	self:ScheduleBaseline()
end

function ChangeTracker:OnProfileSaved()
	self:ScheduleBaseline()
end

function ChangeTracker:OnProfileDeleted()
	if( not Bridge:GetLastProfile() ) then
		SetDirty(false)
	end
end

frame:SetScript("OnEvent", function(self, event)
	if( event == "ACTIONBAR_SLOT_CHANGED" ) then
		ChangeTracker:ScheduleCheck()
	elseif( event == "PLAYER_ENTERING_WORLD" ) then
		-- only on login; loading screens must not reset unsaved changes
		if( not baseline and not baselineTimer ) then
			ChangeTracker:ScheduleBaseline()
		end
	else
		-- ACTIVE_TALENT_GROUP_CHANGED: the game swaps the bars itself
		ChangeTracker:ScheduleBaseline()
	end
end)

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function ABS:HasUnsavedChanges()
	return dirty and Bridge:GetLastProfile() ~= nil
end

function ABS:SaveChanges()
	local profile = Bridge:GetLastProfile()
	if( profile and ABS:ProfileExists(profile) ) then
		ABS:SaveProfile(profile)
	end
end
