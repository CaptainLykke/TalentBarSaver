--[[
	TalentBarSaver - Bridge
	Connects Talented templates with ActionBarSaver profiles.

	Flow:
	1. Talented successfully applies a template -> Talented:OnTemplateApplied()
	   -> remember the template for the active talent group, load its linked profile.
	2. Dual spec change (ACTIVE_TALENT_GROUP_CHANGED)
	   -> use the last template applied to that group if its main tree still matches,
	      otherwise fall back to the profile linked to the tree with the most points.
	3. Loading is delayed (the spellbook has to update first) and never happens in combat.

	Stored in ActionBarSaverDB.bridge:
	  auto            = true/false
	  templateLinks   = { [CLASS] = { [templateName] = profile } }
	  treeLinks       = { [CLASS] = { [1] = profile, [2] = profile, [3] = profile } }
	  chars           = { ["Name-Realm"] = { groupTemplate = { [1] = templateName, [2] = ... }, lastProfile = profile } }
	  ui              = window position/size, help seen flag
	  minimap         = { hide = false, angle = 225 }
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Talented = _G.Talented

local Bridge = {}
ABS.Bridge = Bridge

local INITIAL_DELAY = 1.0     -- seconds after a template/spec change
local SPELLS_DELAY = 0.5      -- minimum wait after the last SPELLS_CHANGED
local LOGIN_GRACE = 5         -- seconds after login during which spec events are ignored

local frame = CreateFrame("Frame")
Bridge.frame = frame

local pending, pendingReason, timer
local waitingForCombat = false
local readyTime, lastGroup

local function Print(msg)
	ABS:Print(msg)
end

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
local function InitDB()
	local db = ABS.db
	db.bridge = db.bridge or {}
	local b = db.bridge
	if( b.auto == nil ) then b.auto = true end
	b.templateLinks = b.templateLinks or {}
	b.treeLinks = b.treeLinks or {}
	b.chars = b.chars or {}
	b.ui = b.ui or {}
	b.minimap = b.minimap or {}
	if( b.minimap.hide == nil ) then b.minimap.hide = false end
	b.minimap.angle = b.minimap.angle or 225

	local class = ABS.playerClass
	b.templateLinks[class] = b.templateLinks[class] or {}
	b.treeLinks[class] = b.treeLinks[class] or {}

	local key = CharKey()
	b.chars[key] = b.chars[key] or {}
	local c = b.chars[key]
	c.groupTemplate = c.groupTemplate or {}

	Bridge.db = b
	Bridge.char = c
	Bridge.class = class
end

-- Called from ABS:OnInitialize() (ADDON_LOADED)
function ABS:OnDatabaseReady()
	InitDB()

	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")

	if( ABS.OnBridgeReady ) then
		ABS:OnBridgeReady()
	end
end

local function Refresh()
	if( ABS.RefreshWindow ) then
		ABS:RefreshWindow()
	end
end

---------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------
function Bridge:IsAuto()
	return self.db and self.db.auto
end

function Bridge:SetAuto(value)
	self.db.auto = value and true or false
end

function Bridge:GetTemplateLink(templateName)
	return self.db.templateLinks[self.class][templateName]
end

function Bridge:SetTemplateLink(templateName, profile)
	if( profile == "" ) then profile = nil end
	self.db.templateLinks[self.class][templateName] = profile
end

function Bridge:GetTreeLink(tab)
	return self.db.treeLinks[self.class][tab]
end

function Bridge:SetTreeLink(tab, profile)
	if( profile == "" ) then profile = nil end
	self.db.treeLinks[self.class][tab] = profile
end

function Bridge:GetLastProfile()
	return self.char and self.char.lastProfile
end

function Bridge:GetGroupTemplate(group)
	return self.char.groupTemplate[group]
end

---------------------------------------------------------------------------
-- Reading talents
---------------------------------------------------------------------------

-- Names of the three talent trees of the player class
function Bridge:GetTreeNames()
	local names = {}
	for tab=1, GetNumTalentTabs() do
		names[tab] = (GetTalentTabInfo(tab)) or ("Tree " .. tab)
	end
	return names
end

-- Tree with the most points in a talent group (nil if no points spent)
function Bridge:GetActiveTree(group)
	group = group or GetActiveTalentGroup()
	local best, bestPoints = nil, 0
	for tab=1, GetNumTalentTabs() do
		local _, _, points = GetTalentTabInfo(tab, false, false, group)
		points = points or 0
		if( points > bestPoints ) then
			best, bestPoints = tab, points
		end
	end
	return best, bestPoints
end

-- Talented template object (or nil)
function Bridge:GetTalentedTemplate(name)
	local tdb = Talented and Talented.db
	local templates = tdb and tdb.global and tdb.global.templates
	local template = templates and templates[name]
	if( type(template) == "table" ) then
		return template
	end
	return nil
end

-- Sorted names of all Talented templates of the player class
function Bridge:GetClassTemplates()
	local list = {}
	local tdb = Talented and Talented.db
	local templates = tdb and tdb.global and tdb.global.templates
	if( not templates ) then return list end

	for name, template in pairs(templates) do
		if( type(template) == "table" and template.class == self.class ) then
			table.insert(list, name)
		end
	end
	table.sort(list, function(a, b) return string.lower(a) < string.lower(b) end)
	return list
end

-- Main tree of a Talented template
function Bridge:GetTemplateTree(name)
	local template = self:GetTalentedTemplate(name)
	if( not template ) then return nil end

	local ok, best = pcall(function()
		local copy = {}
		Talented:CopyPackedTemplate(template, copy)
		local bestTab, bestPoints = nil, 0
		for tab, talents in ipairs(copy) do
			local points = 0
			for _, rank in ipairs(talents) do
				points = points + (rank or 0)
			end
			if( points > bestPoints ) then
				bestTab, bestPoints = tab, points
			end
		end
		return bestTab
	end)

	return ok and best or nil
end

---------------------------------------------------------------------------
-- Which profile belongs to a talent group?
-- Returns: profile, reason ("template" | "tree"), templateName/tree
---------------------------------------------------------------------------
function Bridge:ResolveProfile(group)
	group = group or GetActiveTalentGroup()
	local activeTree = self:GetActiveTree(group)
	if( not activeTree ) then
		return nil
	end

	-- 1. Last template applied to this group, if its main tree still matches
	local templateName = self.char.groupTemplate[group]
	if( templateName ) then
		local profile = self:GetTemplateLink(templateName)
		if( profile and self:GetTemplateTree(templateName) == activeTree ) then
			return profile, "template", templateName
		end
	end

	-- 2. Fallback by talent tree
	local profile = self:GetTreeLink(activeTree)
	if( profile ) then
		return profile, "tree", activeTree
	end

	return nil
end

---------------------------------------------------------------------------
-- Delayed loading
---------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
	timer = timer - elapsed
	if( timer > 0 ) then return end

	self:SetScript("OnUpdate", nil)
	timer = nil

	if( InCombatLockdown() ) then
		if( not waitingForCombat ) then
			waitingForCombat = true
			Print(string.format("In combat - |cffffff00%s|r will be loaded after combat.", pending))
		end
		return
	end

	Bridge:RestoreNow()
end

local function StartTimer(seconds)
	if( not timer or timer < seconds ) then
		timer = seconds
	end
	frame:SetScript("OnUpdate", OnUpdate)
end

-- Queue a profile for loading
function Bridge:Queue(profile, reason)
	if( not profile ) then return end
	pending = profile
	pendingReason = reason
	waitingForCombat = false
	StartTimer(INITIAL_DELAY)
end

function Bridge:RestoreNow()
	local profile, reason = pending, pendingReason
	pending, pendingReason = nil, nil
	waitingForCombat = false
	if( not profile ) then return end

	if( not ABS:ProfileExists(profile) ) then
		Print(string.format("Profile |cffffff00%s|r is linked but does not exist (anymore).", profile))
		return
	end

	if( reason ) then
		Print(string.format("Spec detected (%s) - loading profile |cffffff00%s|r.", reason, profile))
	end
	ABS:RestoreProfile(profile)
end

-- For the "Apply now" button in the window
function Bridge:ApplyForActiveGroup()
	local profile, reason, detail = self:ResolveProfile()
	if( not profile ) then
		Print("No profile is linked to your active spec.")
		return
	end
	if( InCombatLockdown() ) then
		self:Queue(profile, self:DescribeReason(reason, detail))
		return
	end
	pending, pendingReason = profile, nil
	self:RestoreNow()
end

function Bridge:DescribeReason(reason, detail)
	if( reason == "template" ) then
		return "template " .. tostring(detail)
	elseif( reason == "tree" ) then
		return "tree " .. tostring(self:GetTreeNames()[detail] or detail)
	end
	return "?"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, ...)
	if( event == "PLAYER_ENTERING_WORLD" ) then
		if( not readyTime ) then
			readyTime = GetTime() + LOGIN_GRACE
		end
		lastGroup = GetActiveTalentGroup()

	elseif( event == "ACTIVE_TALENT_GROUP_CHANGED" ) then
		local newGroup = (...) or GetActiveTalentGroup()
		local oldGroup = lastGroup
		lastGroup = newGroup
		Refresh()
		if( not Bridge:IsAuto() ) then return end
		if( not readyTime or GetTime() < readyTime ) then return end
		if( not oldGroup or newGroup == oldGroup ) then return end

		local profile, reason, detail = Bridge:ResolveProfile(newGroup)
		if( profile ) then
			Bridge:Queue(profile, Bridge:DescribeReason(reason, detail))
		end

	elseif( event == "SPELLS_CHANGED" ) then
		-- Spellbook changed: wait a little longer so new talent spells are available
		if( pending and timer ) then
			StartTimer(SPELLS_DELAY)
		end

	elseif( event == "PLAYER_REGEN_ENABLED" ) then
		if( pending and waitingForCombat ) then
			StartTimer(0.3)
		end
	end
end)

---------------------------------------------------------------------------
-- Hooks called from Talented (see Talented\Talented.lua)
---------------------------------------------------------------------------
if( Talented ) then
	-- A template was applied successfully
	function Talented:OnTemplateApplied(template)
		if( not Bridge.db or not template or not template.name ) then return end
		if( template.talentGroup ) then return end -- the active specs themselves, not a saved template

		local group = GetActiveTalentGroup()
		Bridge.char.groupTemplate[group] = template.name
		Refresh()

		if( not Bridge:IsAuto() ) then return end

		local profile = Bridge:GetTemplateLink(template.name)
		if( profile ) then
			Bridge:Queue(profile, "template " .. template.name)
		else
			-- No direct link: fall back to the talent tree
			local fallback, reason, detail = Bridge:ResolveProfile(group)
			if( fallback ) then
				Bridge:Queue(fallback, Bridge:DescribeReason(reason, detail))
			end
		end
	end

	-- A template was renamed in Talented
	function Talented:OnTemplateRenamed(oldName, newName, class)
		if( not Bridge.db ) then return end
		local links = Bridge.db.templateLinks[class]
		if( links and links[oldName] ) then
			links[newName] = links[oldName]
			links[oldName] = nil
		end
		for _, char in pairs(Bridge.db.chars) do
			for group, name in pairs(char.groupTemplate or {}) do
				if( name == oldName ) then
					char.groupTemplate[group] = newName
				end
			end
		end
		Refresh()
	end
end

---------------------------------------------------------------------------
-- Hooks called from ActionBarSaver
---------------------------------------------------------------------------
function ABS:OnProfileRestored(name)
	if( Bridge.char ) then
		Bridge.char.lastProfile = name
	end
	Refresh()
end

function ABS:OnProfileRenamed(old, new)
	local b = Bridge.db
	for template, profile in pairs(b.templateLinks[Bridge.class]) do
		if( profile == old ) then b.templateLinks[Bridge.class][template] = new end
	end
	for tab, profile in pairs(b.treeLinks[Bridge.class]) do
		if( profile == old ) then b.treeLinks[Bridge.class][tab] = new end
	end
	if( Bridge.char.lastProfile == old ) then
		Bridge.char.lastProfile = new
	end
end

function ABS:OnProfileDeleted(name)
	local b = Bridge.db
	for template, profile in pairs(b.templateLinks[Bridge.class]) do
		if( profile == name ) then b.templateLinks[Bridge.class][template] = nil end
	end
	for tab, profile in pairs(b.treeLinks[Bridge.class]) do
		if( profile == name ) then b.treeLinks[Bridge.class][tab] = nil end
	end
	if( Bridge.char.lastProfile == name ) then
		Bridge.char.lastProfile = nil
	end
end
