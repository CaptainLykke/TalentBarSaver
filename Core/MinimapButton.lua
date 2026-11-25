--[[
	TalentBarSaver - Minimap button
	Left-click:  open/close the TalentBarSaver window
	Right-click: open Talented
	Drag:        move the button around the minimap

	Settings in ActionBarSaverDB.bridge.minimap: hide (true/false), angle (degrees)
	Toggle via Options tab or /tbs minimap
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge

local ICON = "Interface\\Icons\\Ability_DualWield"
local RADIUS = 80

local button

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
	end
	GameTooltip:AddLine("|cffffff00Left-click|r to open the window", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffff00Right-click|r to open Talented", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffff00Drag|r to move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function OnClick(self, mouseButton)
	GameTooltip:Hide()
	if( mouseButton == "RightButton" ) then
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

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetWidth(17)
	icon:SetHeight(17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)

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
	return button
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
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
