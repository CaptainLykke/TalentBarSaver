--[[
	TalentBarSaver - Key bindings per profile (optional, off by default)
	Turn it on per profile in the "..." menu of the Profiles tab.

	- When turned on, your current key bindings are stored in the profile.
	- "Save current bars" stores them again.
	- Loading the profile restores them (never in combat, the game blocks it).
	- Before bindings are replaced, the previous ones are kept: /tbs undobinds brings them back.

	Stored in ActionBarSaverDB.bridge.keybinds = { [CLASS] = { [profile] = { [command] = {key1, key2} } } }
	Undo data per character in ActionBarSaverDB.bridge.chars[...].bindingsUndo
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local Keybinds = {}
ABS.Keybinds = Keybinds
ABS:RegisterModule(Keybinds)

local YELLOW = "|cffffff00"

local function Print(msg)
	ABS:Print(msg)
end

---------------------------------------------------------------------------
-- Reading and writing bindings
---------------------------------------------------------------------------

-- All commands that have at least one key: { [command] = {key1, key2, ...} }, count
local function Capture()
	local binds, count = {}, 0
	for i=1, GetNumBindings() do
		local info = {GetBinding(i)}
		local command = info[1]
		local keys = {}
		for n=2, table.maxn(info) do
			if( info[n] ) then
				table.insert(keys, info[n])
			end
		end
		if( command and #keys > 0 ) then
			binds[command] = keys
			count = count + #keys
		end
	end
	return binds, count
end

-- Replace all bindings with the given ones. Returns true on success.
local function Apply(binds)
	if( InCombatLockdown() ) then
		Print("Key bindings cannot be changed in combat.")
		return false
	end
	if( not binds or not next(binds) ) then
		return false
	end

	-- keep the current bindings for /tbs undobinds
	Bridge.char.bindingsUndo = (Capture())

	-- remove every key that is bound right now
	for i=1, GetNumBindings() do
		local info = {GetBinding(i)}
		for n=2, table.maxn(info) do
			if( info[n] ) then
				SetBinding(info[n])
			end
		end
	end

	-- set the stored ones
	for command, keys in pairs(binds) do
		for _, key in ipairs(keys) do
			SetBinding(key, command)
		end
	end

	SaveBindings(GetCurrentBindingSet())
	return true
end

---------------------------------------------------------------------------
-- Per profile
---------------------------------------------------------------------------
function Keybinds:InitDB()
	local b = Bridge.db
	b.keybinds = b.keybinds or {}
	b.keybinds[Bridge.class] = b.keybinds[Bridge.class] or {}
	self.store = b.keybinds[Bridge.class]
end

function Keybinds:IsEnabled(profile)
	return self.store and self.store[profile] ~= nil
end

function Keybinds:Enable(profile)
	local binds, count = Capture()
	self.store[profile] = binds
	Print(string.format("Key bindings are now saved with profile %s%s|r (%d keys).", YELLOW, profile, count))
end

function Keybinds:Disable(profile)
	self.store[profile] = nil
	Print(string.format("Profile %s%s|r no longer changes your key bindings.", YELLOW, profile))
end

function Keybinds:Toggle(profile)
	if( self:IsEnabled(profile) ) then
		self:Disable(profile)
	else
		self:Enable(profile)
	end
	if( ABS.RefreshWindow ) then ABS:RefreshWindow() end
end

-- Bring back the bindings from before the last profile load
function Keybinds:Undo()
	local undo = Bridge.char.bindingsUndo
	if( not undo or not next(undo) ) then
		Print("There are no previous key bindings to restore.")
		return
	end
	local previous = undo
	if( Apply(previous) ) then
		Print("Your previous key bindings have been restored.")
	end
end

---------------------------------------------------------------------------
-- Module hooks
---------------------------------------------------------------------------
function Keybinds:OnProfileLoaded(profile)
	local binds = self.store and self.store[profile]
	if( binds and Apply(binds) ) then
		Print(string.format("Key bindings loaded from profile %s%s|r. Type /tbs undobinds to go back.", YELLOW, profile))
	end
end

function Keybinds:OnProfileSaved(profile)
	if( self:IsEnabled(profile) ) then
		self.store[profile] = (Capture())
	end
end

function Keybinds:OnProfileRenamed(old, new)
	if( self.store and self.store[old] ) then
		self.store[new] = self.store[old]
		self.store[old] = nil
	end
end

function Keybinds:OnProfileDeleted(name)
	if( self.store ) then
		self.store[name] = nil
	end
end
