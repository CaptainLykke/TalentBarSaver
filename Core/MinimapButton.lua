--[[
	TalentBarSaver - Minimap button
	Shows the icon of the gear set linked to the loaded profile (default icon otherwise).
	A small dot appears when your bars changed since the profile was loaded or saved.
	Left-click:       open/close the TalentBarSaver window
	Shift-left-click: quick menu (load a profile, save changes)
	Right-click:      open Talented
	Drag:             move the button around the minimap

	Settings in ActionBarSaverDB.bridge.minimap: hide (true/false), angle (degrees)
	Toggle via Options tab or /tbs minimap
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local ICON = "Interface\\Icons\\Ability_DualWield"
local RADIUS = 80

local button, iconTexture, dirtyDot, quickMenuFrame
local ORANGE = "|cffff9900"

local function Settings()
	return Bridge.db.minimap
end

local function UpdatePosition()
	if( not button ) then return end
	local angle = math.rad(Settings().angle or 225)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	Settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	UpdatePosition()
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("TalentBarSaver", 1, 1, 1)
	local last = Bridge:GetLastProfile()
	if( last ) then
		GameTooltip:AddLine("Loaded profile: |cff33ff33" .. last .. "|r")
		local GearSets = ABS.GearSets
		local setName = GearSets and GearSets:GetLink(last)
		if( setName ) then
			GameTooltip:AddLine("Gear set: " .. GearSets:IconText(GearSets:GetSetIcon(setName), 14) .. "|cff33ff33" .. setName .. "|r")
		end
		if( ABS.HasUnsavedChanges and ABS:HasUnsavedChanges() ) then
			GameTooltip:AddLine(ORANGE .. "Your bars changed since this profile was loaded.|r")
			GameTooltip:AddLine(ORANGE .. "Shift-click to save the changes.|r")
		end
	end
	GameTooltip:AddLine("|cffffff00Left-click|r to open the window", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffff00Shift-click|r for the quick menu", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffff00Right-click|r to open Talented", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffff00Drag|r to move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

-- Quick menu: load a profile with one click, save unsaved changes
local function ShowQuickMenu(anchor)
	local GearSets = ABS.GearSets
	local last = Bridge:GetLastProfile()
	local items = {{text = "TalentBarSaver", isTitle = true, notCheckable = true}}

	if( ABS:HasUnsavedChanges() ) then
		table.insert(items, {text = ORANGE .. "Save changes to " .. last .. "|r", notCheckable = true, func = function() ABS:SaveChanges() end})
	end

	local profiles = ABS:GetProfileList()
	for _, name in ipairs(profiles) do
		local profile = name
		table.insert(items, {
			text = GearSets:IconText(GearSets:GetProfileIcon(profile)) .. profile,
			checked = profile == last,
			func = function() ABS:RestoreProfile(profile) end,
		})
	end
	if( #profiles == 0 ) then
		table.insert(items, {text = "|cff9d9d9dNo profiles yet|r", disabled = true, notCheckable = true})
	end

	table.insert(items, {text = "Open window", notCheckable = true, func = function() ABS:ShowWindow() end})
	table.insert(items, {text = "Cancel", notCheckable = true, func = function() CloseDropDownMenus() end})

	if( not quickMenuFrame ) then
		quickMenuFrame = CreateFrame("Frame", "TalentBarSaverQuickMenu", UIParent, "UIDropDownMenuTemplate")
	end
	EasyMenu(items, quickMenuFrame, anchor, 0, 0, "MENU")
end

local function OnClick(self, mouseButton)
	GameTooltip:Hide()
	if( mouseButton == "LeftButton" and IsShiftKeyDown() ) then
		ShowQuickMenu(self)
	elseif( mouseButton == "RightButton" ) then
		local Talented = _G.Talented
		if( Talented and Talented.ToggleTalentFrame ) then
			Talented:ToggleTalentFrame()
		end
	else
		ABS:ToggleWindow()
	end
end

local function CreateButton()
	if( button ) then return button end

	button = CreateFrame("Button", "TalentBarSaverMinimapButton", Minimap)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetWidth(31)
	button:SetHeight(31)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetWidth(53)
	overlay:SetHeight(53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetWidth(20)
	background:SetHeight(20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	iconTexture = button:CreateTexture(nil, "ARTWORK")
	iconTexture:SetWidth(17)
	iconTexture:SetHeight(17)
	iconTexture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	iconTexture:SetPoint("TOPLEFT", 7, -6)

	-- small dot for unsaved changes (own frame so it is drawn above the border)
	local dotFrame = CreateFrame("Frame", nil, button)
	dotFrame:SetFrameLevel(button:GetFrameLevel() + 2)
	dotFrame:SetWidth(12)
	dotFrame:SetHeight(12)
	dotFrame:SetPoint("TOPRIGHT", -1, -1)
	dirtyDot = dotFrame:CreateTexture(nil, "OVERLAY")
	dirtyDot:SetAllPoints(dotFrame)
	dirtyDot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	dirtyDot:Hide()

	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)

	UpdatePosition()
	ABS:UpdateMinimapIcon()
	return button
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

-- Icon of the gear set linked to the loaded profile, default icon otherwise
function ABS:UpdateMinimapIcon()
	if( not iconTexture ) then return end
	local GearSets = self.GearSets
	local last = Bridge:GetLastProfile()
	local icon = GearSets and last and GearSets:GetProfileIcon(last)
	iconTexture:SetTexture(icon or ICON)
	if( dirtyDot ) then
		if( self.HasUnsavedChanges and self:HasUnsavedChanges() ) then
			dirtyDot:Show()
		else
			dirtyDot:Hide()
		end
	end
end
function ABS:IsMinimapButtonShown()
	return not Settings().hide
end

function ABS:SetMinimapButtonShown(show)
	Settings().hide = not show
	if( show ) then
		CreateButton():Show()
		UpdatePosition()
	elseif( button ) then
		button:Hide()
	end
end

function ABS:ToggleMinimapButton()
	local show = not self:IsMinimapButtonShown()
	self:SetMinimapButtonShown(show)
	self:Print(show and "Minimap button shown." or "Minimap button hidden. Type /tbs minimap to show it again.")
	if( self.RefreshWindow ) then
		self:RefreshWindow()
	end
end

-- Called from Bridge once the database is ready
function ABS:OnBridgeReady()
	if( self:IsMinimapButtonShown() ) then
		CreateButton():Show()
	end
end
