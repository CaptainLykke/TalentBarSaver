--[[
	TalentBarSaver - Bridge
	Verbindet Talented-Templates mit ActionBarSaver-Profilen.

	Ablauf:
	1. Talented wendet ein Template erfolgreich an -> Talented:OnTemplateApplied()
	   -> Template fuer die aktive Talentgruppe merken, zugeordnetes Profil laden.
	2. Dual-Spec-Wechsel (ACTIVE_TALENT_GROUP_CHANGED)
	   -> zuletzt angewendetes Template dieser Gruppe nehmen, sofern der Hauptbaum noch passt,
	      sonst Fallback: Profil des Talentbaums mit den meisten Punkten.
	3. Geladen wird verzoegert (Zauberbuch muss erst aktualisiert sein) und nie im Kampf.

	Gespeichert in ActionBarSaverDB.bridge:
	  auto            = true/false
	  templateLinks   = { [KLASSE] = { [Templatename] = profil } }
	  treeLinks       = { [KLASSE] = { [1] = profil, [2] = profil, [3] = profil } }
	  chars           = { ["Name-Realm"] = { groupTemplate = { [1] = Templatename, [2] = ... }, lastProfile = profil } }
	  ui              = Fensterposition/-groesse
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Talented = _G.Talented

local Bridge = {}
ABS.Bridge = Bridge

local INITIAL_DELAY = 1.0     -- Sekunden nach Template/Spec-Wechsel
local SPELLS_DELAY = 0.5      -- Mindestwartezeit nach dem letzten SPELLS_CHANGED
local LOGIN_GRACE = 5         -- Sekunden nach dem Einloggen, in denen Spec-Events ignoriert werden

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
-- Datenbank
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

-- Wird von ABS:OnInitialize() aufgerufen (ADDON_LOADED)
function ABS:OnDatabaseReady()
	InitDB()

	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	frame:RegisterEvent("SPELLS_CHANGED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function Refresh()
	if( ABS.RefreshWindow ) then
		ABS:RefreshWindow()
	end
end

---------------------------------------------------------------------------
-- Zuordnungen
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
-- Talente auslesen
---------------------------------------------------------------------------

-- Namen der drei Talentbaeume der eigenen Klasse
function Bridge:GetTreeNames()
	local names = {}
	for tab=1, GetNumTalentTabs() do
		names[tab] = (GetTalentTabInfo(tab)) or ("Baum " .. tab)
	end
	return names
end

-- Baum mit den meisten Punkten in einer Talentgruppe (nil, wenn keine Punkte verteilt)
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

-- Talented-Template-Objekt (oder nil)
function Bridge:GetTalentedTemplate(name)
	local tdb = Talented and Talented.db
	local templates = tdb and tdb.global and tdb.global.templates
	local template = templates and templates[name]
	if( type(template) == "table" ) then
		return template
	end
	return nil
end

-- Sortierte Namen aller Talented-Templates der eigenen Klasse
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

-- Hauptbaum eines Talented-Templates
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
-- Welches Profil gehoert zur Talentgruppe?
-- Rueckgabe: profil, grund ("template" | "tree"), templateName/baum
---------------------------------------------------------------------------
function Bridge:ResolveProfile(group)
	group = group or GetActiveTalentGroup()
	local activeTree = self:GetActiveTree(group)
	if( not activeTree ) then
		return nil
	end

	-- 1. Zuletzt angewendetes Template dieser Gruppe, wenn der Hauptbaum noch stimmt
	local templateName = self.char.groupTemplate[group]
	if( templateName ) then
		local profile = self:GetTemplateLink(templateName)
		if( profile and self:GetTemplateTree(templateName) == activeTree ) then
			return profile, "template", templateName
		end
	end

	-- 2. Fallback nach Talentbaum
	local profile = self:GetTreeLink(activeTree)
	if( profile ) then
		return profile, "tree", activeTree
	end

	return nil
end

---------------------------------------------------------------------------
-- Verzoegertes Laden
---------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
	timer = timer - elapsed
	if( timer > 0 ) then return end

	self:SetScript("OnUpdate", nil)
	timer = nil

	if( InCombatLockdown() ) then
		if( not waitingForCombat ) then
			waitingForCombat = true
			Print(string.format("Im Kampf - lade |cffffff00%s|r nach dem Kampf.", pending))
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

-- Profil zum Laden vormerken
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
		Print(string.format("Profil |cffffff00%s|r ist zugeordnet, existiert aber nicht (mehr).", profile))
		return
	end

	if( reason ) then
		Print(string.format("Spec erkannt (%s) - lade Profil |cffffff00%s|r.", reason, profile))
	end
	ABS:RestoreProfile(profile)
end

-- Fuer den Button "Jetzt anwenden" im Fenster
function Bridge:ApplyForActiveGroup()
	local profile, reason, detail = self:ResolveProfile()
	if( not profile ) then
		Print("Fuer den aktiven Spec ist kein Profil zugeordnet.")
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
		return "Template " .. tostring(detail)
	elseif( reason == "tree" ) then
		return "Baum " .. tostring(self:GetTreeNames()[detail] or detail)
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
		-- Zauberbuch hat sich geaendert: noch kurz warten, damit neue Talentzauber da sind
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
-- Hooks aus Talented (siehe Talented\Talented.lua)
---------------------------------------------------------------------------
if( Talented ) then
	-- Template wurde erfolgreich angewendet
	function Talented:OnTemplateApplied(template)
		if( not Bridge.db or not template or not template.name ) then return end
		if( template.talentGroup ) then return end -- aktive Specs selbst, kein gespeichertes Template

		local group = GetActiveTalentGroup()
		Bridge.char.groupTemplate[group] = template.name
		Refresh()

		if( not Bridge:IsAuto() ) then return end

		local profile = Bridge:GetTemplateLink(template.name)
		if( profile ) then
			Bridge:Queue(profile, "Template " .. template.name)
		else
			-- Kein direkter Link: Fallback nach Baum
			local fallback, reason, detail = Bridge:ResolveProfile(group)
			if( fallback ) then
				Bridge:Queue(fallback, Bridge:DescribeReason(reason, detail))
			end
		end
	end

	-- Template wurde in Talented umbenannt
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
-- Hooks aus ActionBarSaver
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
