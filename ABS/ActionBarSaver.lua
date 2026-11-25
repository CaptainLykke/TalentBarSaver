--[[
	Action Bar Saver, Shadowed
	Modified for TalentBarSaver:
	- runs inside the combined addon folder (name comes from "...")
	- fixed: String.format typo, wrong variable in messages, error list not cleared,
	  item name in error message, missing check for empty spellbook tabs
	- profile functions (list, delete, rename) as API for Core\LayoutUI.lua
	- /tbs as additional slash command, without arguments it opens the window
]]
local ADDON_NAME, ns = ...
ActionBarSaver = ns

local ABS = ActionBarSaver
local L = ABS.locals

-- Missing translations must not end in a Lua error
setmetatable(L, {__index = function(t, key) return key end})

local restoreErrors, spellCache, macroCache, macroNameCache = {}, {}, {}, {}
local iconCache, playerClass

local MAX_MACROS = 54
local MAX_CHAR_MACROS = 18
local MAX_GLOBAL_MACROS = 36
local MAX_ACTION_BUTTONS = 144
local POSSESSION_START = 121
local POSSESSION_END = 132

ABS.restoreErrors = restoreErrors

function ABS:OnInitialize()
	local defaults = {
		macro = false,
		checkCount = false,
		restoreRank = true,
		spellSubs = {},
		sets = {}
	}

	ActionBarSaverDB = ActionBarSaverDB or {}

	-- Load defaults in
	for key, value in pairs(defaults) do
		if( ActionBarSaverDB[key] == nil ) then
			ActionBarSaverDB[key] = value
		end
	end

	for classToken in pairs(RAID_CLASS_COLORS) do
		ActionBarSaverDB.sets[classToken] = ActionBarSaverDB.sets[classToken] or {}
	end

	self.db = ActionBarSaverDB

	playerClass = select(2, UnitClass("player"))
	self.playerClass = playerClass

	-- Notify other modules (Bridge, UI)
	if( self.OnDatabaseReady ) then
		self:OnDatabaseReady()
	end
end

-- Normalize profile names (slash commands always used lower case)
function ABS:NormalizeName(name)
	return string.lower(string.trim(name or ""))
end

-- Text "compression" so it can be stored in our format fine
function ABS:CompressText(text)
	text = string.gsub(text, "\n", "/n")
	text = string.gsub(text, "/n$", "")
	text = string.gsub(text, "||", "/124")

	return string.trim(text)
end

function ABS:UncompressText(text)
	text = string.gsub(text, "/n", "\n")
	text = string.gsub(text, "/124", "|")

	return string.trim(text)
end

---------------------------------------------------------------------------
-- Profile API (used by slash commands and the window)
---------------------------------------------------------------------------

-- Sorted list of the profiles of the player class
function ABS:GetProfileList()
	local list = {}
	for name in pairs(self.db.sets[playerClass]) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

function ABS:ProfileExists(name)
	return self.db.sets[playerClass][name] ~= nil
end

function ABS:ProfilesChanged()
	if( self.OnProfilesChanged ) then
		self:OnProfilesChanged()
	end
end

function ABS:DeleteProfile(name)
	if( not self.db.sets[playerClass][name] ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return false
	end

	self.db.sets[playerClass][name] = nil
	self:Print(string.format(L["Deleted saved profile %s."], name))

	if( self.OnProfileDeleted ) then
		self:OnProfileDeleted(name)
	end
	self:ProfilesChanged()
	return true
end

function ABS:RenameProfile(old, new)
	old = self:NormalizeName(old)
	new = self:NormalizeName(new)

	if( new == old ) then
		self:Print(string.format(L["You cannot rename \"%s\" to \"%s\" they are the same profile names."], old, new))
		return false
	elseif( new == "" ) then
		self:Print(string.format(L["No name specified to rename \"%s\" to."], old))
		return false
	elseif( self.db.sets[playerClass][new] ) then
		self:Print(string.format(L["Cannot rename \"%s\" to \"%s\" a profile already exists for %s."], old, new, (UnitClass("player"))))
		return false
	elseif( not self.db.sets[playerClass][old] ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], old))
		return false
	end

	self.db.sets[playerClass][new] = CopyTable(self.db.sets[playerClass][old])
	self.db.sets[playerClass][old] = nil

	self:Print(string.format(L["Renamed \"%s\" to \"%s\""], old, new))

	if( self.OnProfileRenamed ) then
		self:OnProfileRenamed(old, new)
	end
	self:ProfilesChanged()
	return true
end

-- Save the current action bars as a profile
function ABS:SaveProfile(name)
	name = self:NormalizeName(name)
	if( name == "" ) then return false end

	local isNew = not self.db.sets[playerClass][name]
	self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
	local set = self.db.sets[playerClass][name]

	for actionID=1, MAX_ACTION_BUTTONS do
		set[actionID] = nil

		local type, id, subType, extraID = GetActionInfo(actionID)
		if( type and id and ( actionID < POSSESSION_START or actionID > POSSESSION_END ) ) then
			-- DB Format: <type>|<id>|<binding>|<name>|<extra ...>
			-- Save a companion
			if( type == "companion" ) then
				set[actionID] = string.format("%s|%s|%s|%s|%s|%s", type, id, "", name, subType, extraID)
			-- Save an equipment set
			elseif( type == "equipmentset" ) then
				set[actionID] = string.format("%s|%s|%s", type, id, "")
			-- Save an item
			elseif( type == "item" ) then
				set[actionID] = string.format("%s|%d|%s|%s", type, id, "", (GetItemInfo(id)) or "")
			-- Save a spell
			elseif( type == "spell" and id > 0 ) then
				local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
				if( spell ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, id, "", spell, rank or "", extraID or "")
				end
			-- Save a macro
			elseif( type == "macro" ) then
				local macroName, icon, macro = GetMacroInfo(id)
				if( macroName and icon and macro ) then
					set[actionID] = string.format("%s|%d|%s|%s|%s|%s", type, actionID, "", self:CompressText(macroName), icon, self:CompressText(macro))
				end
			end
		end
	end

	self:Print(string.format(L["Saved profile %s!"], name))

	if( self.OnProfileSaved ) then
		self:OnProfileSaved(name, isNew)
	end
	self:ProfilesChanged()
	return true
end

-- Finds the macroID in case it's changed
function ABS:FindMacro(id, name, data)
	if( macroCache[id] == data ) then
		return id
	end

	-- No such luck, check text
	for macroID, currentMacro in pairs(macroCache) do
		if( currentMacro == data ) then
			return macroID
		end
	end

	-- Still no luck, let us try name
	if( macroNameCache[name] ) then
		return macroNameCache[name]
	end

	return nil
end

local function CacheMacros()
	table.wipe(macroCache)
	table.wipe(macroNameCache)

	local blacklist = {}
	for i=1, MAX_MACROS do
		local name, icon, macro = GetMacroInfo(i)

		if( name ) then
			-- If there are macros with the same name, then blacklist and don't look by name
			if( macroNameCache[name] ) then
				blacklist[name] = true
				macroNameCache[name] = i
			elseif( not blacklist[name] ) then
				macroNameCache[name] = i
			end
		end

		macroCache[i] = macro and ABS:CompressText(macro) or nil
	end
end

-- Restore any macros that don't exist
function ABS:RestoreMacros(set)
	local perCharacter = true
	for _, data in pairs(set) do
		local type, id, binding, macroName, macroIcon, macroData = string.split("|", data)
		if( type == "macro" ) then
			-- Do we already have a macro?
			local macroID = self:FindMacro(tonumber(id), macroName, macroData)
			if( not macroID ) then
				local globalNum, charNum = GetNumMacros()
				-- Make sure we aren't at the limit
				if( globalNum == MAX_GLOBAL_MACROS and charNum == MAX_CHAR_MACROS ) then
					table.insert(restoreErrors, L["Unable to restore macros, you already have 18 global and 18 per character ones created."])
					break

				-- We ran out of space for per character, so use global
				elseif( charNum == MAX_CHAR_MACROS ) then
					perCharacter = false
				end

				-- When creating a macro, we have to pass the icon id not the icon path
				if( not iconCache ) then
					iconCache = {}
					for i=1, GetNumMacroIcons() do
						iconCache[(GetMacroIconInfo(i))] = i
					end
				end

				macroName = self:UncompressText(macroName)

				-- No macro name means a space has to be used or else it won't be created and saved
				CreateMacro(macroName == "" and " " or macroName, iconCache[macroIcon] or 1, self:UncompressText(macroData), nil, perCharacter)
			end
		end
	end

	-- Recache macros due to any additions
	CacheMacros()
end

-- Restore a saved profile. Returns true if it was loaded.
function ABS:RestoreProfile(name, overrideClass)
	name = self:NormalizeName(name)
	local set = self.db.sets[overrideClass or playerClass][name]
	if( not set ) then
		self:Print(string.format(L["No profile with the name \"%s\" exists."], name))
		return false
	elseif( InCombatLockdown() ) then
		self:Print(string.format(L["Unable to restore profile \"%s\", you are in combat."], name))
		return false
	end

	table.wipe(restoreErrors)
	table.wipe(spellCache)

	-- Cache spells
	for book=1, MAX_SKILLLINE_TABS do
		local _, _, offset, numSpells = GetSpellTabInfo(book)

		for i=1, (numSpells or 0) do
			local index = offset + i
			local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)

			if( spell ) then
				-- This way we restore the max rank of spells
				spellCache[spell] = index
				spellCache[string.lower(spell)] = index

				if( rank and rank ~= "" ) then
					spellCache[spell .. rank] = index
				end
			end
		end
	end

	-- Cache macros
	CacheMacros()

	-- Check if we need to restore any missing macros
	if( self.db.macro ) then
		self:RestoreMacros(set)
	end

	-- Start fresh with nothing on the cursor
	ClearCursor()

	-- Save current sound setting
	local soundToggle = GetCVar("Sound_EnableAllSound")
	-- Turn sound off
	SetCVar("Sound_EnableAllSound", 0)

	for i=1, MAX_ACTION_BUTTONS do
		if( i < POSSESSION_START or i > POSSESSION_END ) then
			local type, id = GetActionInfo(i)

			-- Clear the current spot
			if( id or type ) then
				PickupAction(i)
				ClearCursor()
			end

			-- Restore this spot
			if( set[i] ) then
				self:RestoreAction(i, string.split("|", set[i]))
			end
		end
	end

	-- Restore old sound setting
	SetCVar("Sound_EnableAllSound", soundToggle)

	-- Done!
	if( #(restoreErrors) == 0 ) then
		self:Print(string.format(L["Restored profile %s!"], name))
	else
		self:Print(string.format(L["Restored profile %s, failed to restore %d buttons type /abs errors for more information."], name, #(restoreErrors)))
	end

	if( self.OnProfileRestored ) then
		self:OnProfileRestored(name)
	end
	return true
end

function ABS:RestoreAction(i, type, actionID, binding, ...)
	-- Restore a spell
	if( type == "spell" ) then
		local spellName, spellRank = ...
		spellRank = spellRank or ""
		if( ( self.db.restoreRank or spellRank == "" ) and spellCache[spellName] ) then
			PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
		elseif( spellRank ~= "" and spellCache[spellName .. spellRank] ) then
			PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
		end

		if( GetCursorInfo() ~= type ) then
			-- Bad restore, check if we should link at all
			local lowerSpell = string.lower(spellName)
			for spell, linked in pairs(self.db.spellSubs) do
				if( lowerSpell == spell and spellCache[linked] ) then
					self:RestoreAction(i, type, actionID, binding, linked, "")
					return
				elseif( lowerSpell == linked and spellCache[spell] ) then
					self:RestoreAction(i, type, actionID, binding, spell, "")
					return
				end
			end

			table.insert(restoreErrors, string.format(L["Unable to restore spell \"%s\" to slot #%d, it does not appear to have been learned yet."], spellName, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	-- Restore an equipment set button
	elseif( type == "equipmentset" ) then
		local slotID = -1
		for setIndex=1, GetNumEquipmentSets() do
			if( GetEquipmentSetInfo(setIndex) == actionID ) then
				slotID = setIndex
				break
			end
		end

		PickupEquipmentSet(slotID)
		if( GetCursorInfo() ~= "equipmentset" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore equipment set \"%s\" to slot #%d, it does not appear to exist anymore."], actionID, i))
			ClearCursor()
			return
		end

		PlaceAction(i)

	-- Restore a 3.1 saved companion
	elseif( type == "companion" ) then
		local critterName, critterType = ...
		PickupCompanion(critterType, actionID)
		if( GetCursorInfo() ~= "companion" ) then
			table.insert(restoreErrors, string.format(L["Unable to restore companion \"%s\" to slot #%d, it does not appear to exist yet."], critterName, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	-- Restore an item
	elseif( type == "item" ) then
		PickupItem(actionID)

		if( GetCursorInfo() ~= type ) then
			local itemName = ...
			table.insert(restoreErrors, string.format(L["Unable to restore item \"%s\" to slot #%d, cannot be found in inventory."], itemName and itemName ~= "" and itemName or actionID, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	-- Restore a macro
	elseif( type == "macro" ) then
		local name, _, content = ...
		local macroID = self:FindMacro(tonumber(actionID), name, content or -1)
		if( macroID ) then
			PickupMacro(macroID)
		end
		if( GetCursorInfo() ~= type ) then
			table.insert(restoreErrors, string.format(L["Unable to restore macro id #%d to slot #%d, it appears to have been deleted."], tonumber(actionID) or 0, i))
			ClearCursor()
			return
		end

		PlaceAction(i)
	end
end

function ABS:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TalentBarSaver|r: " .. msg)
end

---------------------------------------------------------------------------
-- Slash commands: /tbs, /abs, /actionbarsaver
---------------------------------------------------------------------------
local function PrintHelp(self)
	self:Print(L["Slash commands"])
	DEFAULT_CHAT_FRAME:AddMessage("/tbs - Opens the TalentBarSaver window (/tbs minimap toggles the minimap button)")
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs save <profile> - Saves your current action bar setup under the given profile."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs restore <profile> - Changes your action bars to the passed profile."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs delete <profile> - Deletes the saved profile."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs rename <oldProfile> <newProfile> - Renames a saved profile from oldProfile to newProfile."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs link \"<spell 1>\" \"<spell 2>\" - Links a spell with another, INCLUDE QUOTES for example you can use \"Shadowmeld\" \"War Stomp\" so if War Stomp can't be found, it'll use Shadowmeld and vica versa."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs count - Toggles checking if you have the item in your inventory before restoring it, use if you have disconnect issues when restoring."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs macro - Attempts to restore macros that have been deleted for a profile."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs rank - Toggles if ABS should restore the highest rank of the spell, or the one saved originally."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs list - Lists all saved profiles."])
	DEFAULT_CHAT_FRAME:AddMessage(L["/abs errors - Lists the errors that happened on the last restore (if any)."])
end

SLASH_ACTIONBARSAVER1 = nil
SlashCmdList["ACTIONBARSAVER"] = nil

SLASH_TALENTBARSAVER1 = "/tbs"
SLASH_TALENTBARSAVER2 = "/abs"
SLASH_TALENTBARSAVER3 = "/actionbarsaver"
SlashCmdList["TALENTBARSAVER"] = function(msg)
	msg = msg or ""

	local cmd, arg = string.split(" ", msg, 2)
	cmd = string.lower(cmd or "")
	arg = string.lower(string.trim(arg or ""))

	local self = ABS

	-- Window
	if( cmd == "" or cmd == "ui" or cmd == "show" ) then
		if( self.ToggleWindow ) then
			self:ToggleWindow()
		else
			PrintHelp(self)
		end

	-- Profile saving
	elseif( cmd == "save" and arg ~= "" ) then
		self:SaveProfile(arg)

	-- Spell sub
	elseif( cmd == "link" and arg ~= "" ) then
		local first, second = string.match(arg, "\"(.+)\" \"(.+)\"")
		first = string.trim(first or "")
		second = string.trim(second or "")

		if( first == "" or second == "" ) then
			self:Print(L["Invalid spells passed, remember you must put quotes around both of them."])
			return
		end

		self.db.spellSubs[first] = second

		self:Print(string.format(L["Spells \"%s\" and \"%s\" are now linked."], first, second))

	-- Profile restoring
	elseif( cmd == "restore" and arg ~= "" ) then
		if( not self.db.sets[playerClass][arg] ) then
			self:Print(string.format(L["Cannot restore profile \"%s\", you can only restore profiles saved to your class."], arg))
			return
		end

		self:RestoreProfile(arg, playerClass)

	-- Profile renaming
	elseif( cmd == "rename" and arg ~= "" ) then
		local old, new = string.split(" ", arg, 2)
		self:RenameProfile(old, new)

	-- Restore errors
	elseif( cmd == "errors" ) then
		if( #(restoreErrors) == 0 ) then
			self:Print(L["No errors found!"])
			return
		end

		self:Print(string.format(L["Errors found: %d"], #(restoreErrors)))
		for _, text in pairs(restoreErrors) do
			DEFAULT_CHAT_FRAME:AddMessage(text)
		end

	-- Delete profile
	elseif( cmd == "delete" and arg ~= "" ) then
		self:DeleteProfile(arg)

	-- List profiles
	elseif( cmd == "list" ) then
		local classes = {}

		for class in pairs(self.db.sets) do
			table.insert(classes, class)
		end
		table.sort(classes)

		for _, class in pairs(classes) do
			local setList = {}
			for setName in pairs(self.db.sets[class]) do
				table.insert(setList, setName)
			end
			table.sort(setList)

			if( #(setList) > 0 ) then
				DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99%s|r: %s", L[class] or "???", table.concat(setList, ", ")))
			end
		end

	-- Macro restoring
	elseif( cmd == "macro" ) then
		self.db.macro = not self.db.macro

		if( self.db.macro ) then
			self:Print(L["Auto macro restoration is now enabled!"])
		else
			self:Print(L["Auto macro restoration is now disabled!"])
		end
		self:ProfilesChanged()

	-- Item counts
	elseif( cmd == "count" ) then
		self.db.checkCount = not self.db.checkCount

		if( self.db.checkCount ) then
			self:Print(L["Checking item count is now enabled!"])
		else
			self:Print(L["Checking item count is now disabled!"])
		end

	-- Rank restore
	elseif( cmd == "rank" ) then
		self.db.restoreRank = not self.db.restoreRank

		if( self.db.restoreRank ) then
			self:Print(L["Auto restoring highest spell rank is now enabled!"])
		else
			self:Print(L["Auto restoring highest spell rank is now disabled!"])
		end
		self:ProfilesChanged()

	-- Minimap button
	elseif( cmd == "minimap" ) then
		if( self.ToggleMinimapButton ) then
			self:ToggleMinimapButton()
		end

	-- Halp
	else
		PrintHelp(self)
	end
end

-- Check if we need to load
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
	if( addon == ADDON_NAME ) then
		ABS:OnInitialize()
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
