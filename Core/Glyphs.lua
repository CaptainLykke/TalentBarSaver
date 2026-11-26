--[[
	TalentBarSaver - Glyph reminder
	Remembers your glyphs when a profile is saved and tells you in chat when
	the glyphs of your active spec do not match after loading that profile.
	Nothing is changed automatically (glyphs cost reagents).

	Profiles saved before this feature have no glyph data: save them once
	("..." > Save current bars) to start the check.

	Stored in ActionBarSaverDB.bridge.glyphs = { [CLASS] = { [profile] = { spellID, ... } } }
	Option: ActionBarSaverDB.bridge.checkGlyphs (default on)
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local Glyphs = {}
ABS.Glyphs = Glyphs
ABS:RegisterModule(Glyphs)

local NUM_SOCKETS = 6
local YELLOW = "|cffffff00"
local ORANGE = "|cffff9900"

-- Glyph spell IDs of the active talent group
local function CurrentGlyphs()
	local list = {}
	local group = GetActiveTalentGroup()
	for socket=1, NUM_SOCKETS do
		local enabled, _, spell = GetGlyphSocketInfo(socket, group)
		if( enabled and spell ) then
			table.insert(list, spell)
		end
	end
	return list
end

local function GlyphName(spell)
	return (GetSpellInfo(spell)) or ("spell #" .. spell)
end

function Glyphs:InitDB()
	local b = Bridge.db
	b.glyphs = b.glyphs or {}
	b.glyphs[Bridge.class] = b.glyphs[Bridge.class] or {}
	if( b.checkGlyphs == nil ) then b.checkGlyphs = true end
	self.store = b.glyphs[Bridge.class]
end

function Glyphs:IsEnabled()
	return Bridge.db.checkGlyphs
end

function Glyphs:SetEnabled(value)
	Bridge.db.checkGlyphs = value and true or false
end

function Glyphs:HasData(profile)
	return self.store and self.store[profile] ~= nil
end

-- Compare stored and current glyphs. Returns lists of glyph names: missing, extra
function Glyphs:Compare(profile)
	local stored = self.store[profile]
	if( not stored ) then return nil end

	local current = CurrentGlyphs()
	local have, want = {}, {}
	for _, spell in ipairs(current) do have[spell] = true end
	for _, spell in ipairs(stored) do want[spell] = true end

	local missing, extra = {}, {}
	for _, spell in ipairs(stored) do
		if( not have[spell] ) then table.insert(missing, GlyphName(spell)) end
	end
	for _, spell in ipairs(current) do
		if( not want[spell] ) then table.insert(extra, GlyphName(spell)) end
	end
	return missing, extra
end

---------------------------------------------------------------------------
-- Module hooks
---------------------------------------------------------------------------
function Glyphs:OnProfileSaved(profile)
	self.store[profile] = CurrentGlyphs()
end

function Glyphs:OnProfileLoaded(profile)
	if( not self:IsEnabled() ) then return end
	local missing, extra = self:Compare(profile)
	if( not missing or #missing == 0 ) then return end

	ABS:Print(string.format("%sGlyphs do not match profile|r %s%s|r. Missing: %s", ORANGE, YELLOW, profile, table.concat(missing, ", ")))
	if( #extra > 0 ) then
		ABS:Print("Currently inscribed instead: " .. table.concat(extra, ", "))
	end
end

function Glyphs:OnProfileRenamed(old, new)
	if( self.store and self.store[old] ) then
		self.store[new] = self.store[old]
		self.store[old] = nil
	end
end

function Glyphs:OnProfileDeleted(name)
	if( self.store ) then
		self.store[name] = nil
	end
end
