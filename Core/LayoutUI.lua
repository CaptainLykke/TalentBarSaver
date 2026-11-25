--[[
	TalentBarSaver - Window
	/tbs (or /abs without arguments) opens the window.

	Tabs:
	  Profiles - save, load, rename and delete action bar profiles, link gear sets
	  Links    - Talented template -> profile, fallback per talent tree
	  Options  - automatic switching, gear sets, minimap button, macros, spell rank
	  Help     - short how-to (opened automatically the first time)
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge
local AceGUI = LibStub("AceGUI-3.0")

local window, tabGroup
local currentTab = "profiles"

local NONE_KEY = ""
local NONE_TEXT = "|cff808080- none -|r"
local GREEN = "|cff33ff33"
local YELLOW = "|cffffff00"
local GREY = "|cff9d9d9d"
local RED = "|cffff4040"

-- "<gear set icon> name" for a profile
local function ProfileText(name)
	local GearSets = ABS.GearSets
	if( GearSets ) then
		return GearSets:IconText(GearSets:GetProfileIcon(name)) .. name
	end
	return name
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function AddTooltip(widget, title, text)
	widget:SetCallback("OnEnter", function(w)
		GameTooltip:SetOwner(w.frame, "ANCHOR_TOPRIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if( text ) then
			GameTooltip:AddLine(text, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	widget:SetCallback("OnLeave", function() GameTooltip:Hide() end)
end

local function Label(parent, text, width, fontObject)
	local w = AceGUI:Create("Label")
	w:SetText(text)
	if( width ) then w:SetRelativeWidth(width) else w:SetFullWidth(true) end
	if( fontObject ) then w:SetFontObject(fontObject) end
	parent:AddChild(w)
	return w
end

local function Heading(parent, text)
	local w = AceGUI:Create("Heading")
	w:SetText(text)
	w:SetFullWidth(true)
	parent:AddChild(w)
	return w
end

local function Button(parent, text, width, onClick)
	local w = AceGUI:Create("Button")
	w:SetText(text)
	w:SetRelativeWidth(width)
	w:SetCallback("OnClick", onClick)
	parent:AddChild(w)
	return w
end

local function Row(parent)
	local w = AceGUI:Create("SimpleGroup")
	w:SetFullWidth(true)
	w:SetLayout("Flow")
	parent:AddChild(w)
	return w
end

local function Spacer(parent)
	Label(parent, " ")
end

local function ProfileDropdownList()
	local list = {[NONE_KEY] = NONE_TEXT}
	for _, name in ipairs(ABS:GetProfileList()) do
		list[name] = ProfileText(name)
	end
	return list
end

local function GearDropdown(parent, width, profile)
	local GearSets = ABS.GearSets
	local current = GearSets:GetLink(profile)
	local list = {[NONE_KEY] = NONE_TEXT}
	for _, set in ipairs(GearSets:GetSets()) do
		list[set.name] = GearSets:IconText(set.icon) .. set.name
	end
	if( current and not list[current] ) then
		list[current] = RED .. current .. " (not found)|r"
	end

	local w = AceGUI:Create("Dropdown")
	w:SetList(list)
	w:SetValue(current or NONE_KEY)
	w:SetRelativeWidth(width)
	w:SetCallback("OnValueChanged", function(_, _, key)
		GearSets:SetLink(profile, key ~= NONE_KEY and key or nil)
		ABS:RefreshWindow()
	end)
	parent:AddChild(w)
	return w
end

local function ProfileDropdown(parent, width, value, onChange)
	local w = AceGUI:Create("Dropdown")
	w:SetList(ProfileDropdownList())
	w:SetValue(value or NONE_KEY)
	w:SetRelativeWidth(width)
	w:SetCallback("OnValueChanged", function(_, _, key)
		onChange(key ~= NONE_KEY and key or nil)
	end)
	parent:AddChild(w)
	return w
end

---------------------------------------------------------------------------
-- Dialogs (confirm, rename)
---------------------------------------------------------------------------
local function DialogEditBox(dialog)
	return dialog.editBox or _G[dialog:GetName() .. "EditBox"]
end

StaticPopupDialogs["TALENTBARSAVER_DELETE"] = {
	text = "Delete profile %s?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data) ABS:DeleteProfile(data) end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["TALENTBARSAVER_OVERWRITE"] = {
	text = "Save your current action bars to profile %s?\nThe layout stored in this profile will be overwritten.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data) ABS:SaveProfile(data) end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function RenameAccept(dialog, data)
	local newName = DialogEditBox(dialog):GetText()
	ABS:RenameProfile(data, newName)
end

StaticPopupDialogs["TALENTBARSAVER_RENAME"] = {
	text = "New name for profile %s:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 64,
	OnShow = function(self)
		DialogEditBox(self):SetFocus()
	end,
	OnAccept = RenameAccept,
	EditBoxOnEnterPressed = function(self, data)
		local dialog = self:GetParent()
		RenameAccept(dialog, data or dialog.data)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function Confirm(which, profile)
	local dialog = StaticPopup_Show(which, YELLOW .. profile .. "|r")
	if( dialog ) then
		dialog.data = profile
		if( which == "TALENTBARSAVER_RENAME" ) then
			local box = DialogEditBox(dialog)
			box:SetText(profile)
			box:HighlightText()
		end
	end
end

local function SaveNew(name)
	name = ABS:NormalizeName(name)
	if( name == "" ) then return end
	if( ABS:ProfileExists(name) ) then
		Confirm("TALENTBARSAVER_OVERWRITE", name)
	else
		ABS:SaveProfile(name)
	end
end

---------------------------------------------------------------------------
-- Tab: Profiles
---------------------------------------------------------------------------
local function BuildProfiles(scroll)
	local newRow = Row(scroll)
	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("Save your current action bars as a new profile")
	edit:SetRelativeWidth(0.70)
	edit:DisableButton(true)
	edit:SetCallback("OnEnterPressed", function(w, _, text)
		SaveNew(text)
		w:SetText("")
		w:ClearFocus()
	end)
	newRow:AddChild(edit)

	local saveButton = Button(newRow, "Save", 0.28, function()
		SaveNew(edit:GetText())
		edit:SetText("")
	end)
	AddTooltip(saveButton, "Save", "Saves your current action bars under the name you entered, e.g. ret-pve.")

	Heading(scroll, "Profiles (" .. (UnitClass("player")) .. ")")

	local profiles = ABS:GetProfileList()
	if( #profiles == 0 ) then
		Label(scroll, GREY .. "No profiles yet. Set up your action bars, enter a name above and click Save. See the Help tab for a step-by-step guide.|r")
		return
	end

	local active = Bridge:GetLastProfile()
	local hasSets = #ABS.GearSets:GetSets() > 0
	for _, name in ipairs(profiles) do
		local row = Row(scroll)
		local text = ProfileText(name)
		if( name == active ) then
			text = ABS.GearSets:IconText(ABS.GearSets:GetProfileIcon(name)) .. GREEN .. name .. "|r " .. GREY .. "(loaded)|r"
		end
		Label(row, text, 0.26, GameFontHighlight)

		local load = Button(row, "Load", 0.18, function()
			ABS:RestoreProfile(name)
		end)
		AddTooltip(load, "Load", "Switches your action bars to this profile.")

		local save = Button(row, "Save", 0.18, function()
			Confirm("TALENTBARSAVER_OVERWRITE", name)
		end)
		AddTooltip(save, "Save", "Overwrites this profile with your current action bars.")

		Button(row, "Rename", 0.18, function()
			Confirm("TALENTBARSAVER_RENAME", name)
		end)

		Button(row, "Delete", 0.18, function()
			Confirm("TALENTBARSAVER_DELETE", name)
		end)

		-- Gear set link
		local gearRow = Row(scroll)
		Label(gearRow, GREY .. "   Gear set:|r", 0.26)
		if( hasSets or ABS.GearSets:GetLink(name) ) then
			GearDropdown(gearRow, 0.54, name)
		else
			Label(gearRow, GREY .. "No sets in the Equipment Manager yet.|r", 0.7)
		end
	end
end

---------------------------------------------------------------------------
-- Tab: Links
---------------------------------------------------------------------------
local function StatusText()
	local group = GetActiveTalentGroup()
	local trees = Bridge:GetTreeNames()
	local tree, points = Bridge:GetActiveTree(group)
	local parts = {}

	table.insert(parts, string.format("Active talent group: %s%d|r", YELLOW, group))
	if( tree ) then
		table.insert(parts, string.format("Main tree: %s%s|r (%d points)", YELLOW, trees[tree] or "?", points))
	else
		table.insert(parts, "Main tree: " .. GREY .. "no points spent|r")
	end

	local templateName = Bridge:GetGroupTemplate(group)
	table.insert(parts, "Last applied template: " .. (templateName and (YELLOW .. templateName .. "|r") or (GREY .. "-|r")))

	local profile, reason, detail = Bridge:ResolveProfile(group)
	if( profile ) then
		table.insert(parts, string.format("Matching profile: %s%s%s|r %s(%s)|r", ABS.GearSets:IconText(ABS.GearSets:GetProfileIcon(profile)), GREEN, profile, GREY, Bridge:DescribeReason(reason, detail)))
	else
		table.insert(parts, "Matching profile: " .. GREY .. "none linked|r")
	end

	return table.concat(parts, "\n")
end

local function BuildLinks(scroll)
	Label(scroll, StatusText())

	local actionRow = Row(scroll)
	local apply = Button(actionRow, "Apply now", 0.4, function()
		Bridge:ApplyForActiveGroup()
	end)
	AddTooltip(apply, "Apply now", "Loads the profile that matches your active spec right away.")

	-- Talented templates
	Heading(scroll, "Talented templates")
	local templates = Bridge:GetClassTemplates()
	if( #templates == 0 ) then
		Label(scroll, GREY .. "No Talented templates for your class yet. Press N and use Actions > New Template to create one.|r")
	else
		local groupOf = {}
		for group=1, GetNumTalentGroups() do
			local name = Bridge:GetGroupTemplate(group)
			if( name ) then groupOf[name] = group end
		end

		for _, templateName in ipairs(templates) do
			local row = Row(scroll)
			local text = templateName
			if( groupOf[templateName] ) then
				text = text .. " " .. GREY .. "(group " .. groupOf[templateName] .. ")|r"
			end
			Label(row, text, 0.48, GameFontHighlight)
			ProfileDropdown(row, 0.48, Bridge:GetTemplateLink(templateName), function(profile)
				Bridge:SetTemplateLink(templateName, profile)
				ABS:RefreshWindow()
			end)
		end
	end

	-- Fallback by tree
	Heading(scroll, "Fallback by talent tree")
	Label(scroll, GREY .. "Used when no linked template matches your current spec, e.g. when you spent your talents by hand.|r")
	local trees = Bridge:GetTreeNames()
	for tab, treeName in ipairs(trees) do
		local row = Row(scroll)
		Label(row, treeName, 0.48, GameFontHighlight)
		ProfileDropdown(row, 0.48, Bridge:GetTreeLink(tab), function(profile)
			Bridge:SetTreeLink(tab, profile)
			ABS:RefreshWindow()
		end)
	end
end

---------------------------------------------------------------------------
-- Tab: Options
---------------------------------------------------------------------------
local function CheckBox(parent, label, desc, value, onChange)
	local w = AceGUI:Create("CheckBox")
	w:SetLabel(label)
	if( desc ) then w:SetDescription(desc) end
	w:SetValue(value and true or false)
	w:SetFullWidth(true)
	w:SetCallback("OnValueChanged", function(_, _, v) onChange(v and true or false) end)
	parent:AddChild(w)
	return w
end

local function BuildOptions(scroll)
	CheckBox(scroll, "Switch action bars automatically",
		"Load the linked profile after applying a Talented template and when switching your dual spec.",
		Bridge:IsAuto(), function(v) Bridge:SetAuto(v) end)

	CheckBox(scroll, "Equip gear set on manual load",
		"Also equip the linked gear set when you load a profile by hand (Load, Apply now, /tbs restore). Automatic switches always equip it.",
		ABS.GearSets:IsEquipOnManualLoad(), function(v) ABS.GearSets:SetEquipOnManualLoad(v) end)

	CheckBox(scroll, "Show minimap button",
		"Left-click opens this window, right-click opens Talented. Can also be toggled with /tbs minimap.",
		ABS:IsMinimapButtonShown(), function(v) ABS:SetMinimapButtonShown(v) end)

	CheckBox(scroll, "Recreate missing macros",
		"Macros that are part of a profile but were deleted are created again when the profile is loaded.",
		ABS.db.macro, function(v) ABS.db.macro = v end)

	CheckBox(scroll, "Always load the highest spell rank",
		"If disabled, the rank that was on the bar when the profile was saved is loaded.",
		ABS.db.restoreRank, function(v) ABS.db.restoreRank = v end)

	Heading(scroll, "Errors")
	local errorsButton = Button(scroll, "Show errors in chat", 0.5, function()
		SlashCmdList["TALENTBARSAVER"]("errors")
	end)
	AddTooltip(errorsButton, "Show errors", "Lists the buttons that could not be restored the last time a profile was loaded.")
end

---------------------------------------------------------------------------
-- Tab: Help
---------------------------------------------------------------------------
local function Step(parent, number, title, text)
	Label(parent, YELLOW .. number .. ". " .. title .. "|r", nil, GameFontNormalLarge)
	Label(parent, text, nil, GameFontHighlight)
	Spacer(parent)
end

local function BuildHelp(scroll)
	Heading(scroll, "What does TalentBarSaver do?")
	Label(scroll, "TalentBarSaver stores your action bar layouts as profiles and loads the right one automatically when your talents change: after applying a Talented template or when you switch your dual spec. Each profile can also equip a gear set from the Equipment Manager.", nil, GameFontHighlight)
	Spacer(scroll)

	Heading(scroll, "Setup in 5 steps")
	Step(scroll, 1, "Save a profile for each spec",
		"Arrange your action bars for one spec. Open the Profiles tab, enter a name (e.g. ret-pve) and click Save. Repeat this for every spec you play.")
	Step(scroll, 2, "Create a talent template for each spec",
		"Press N to open Talented. Use Actions > New Template, spend the points and give the template a name (e.g. Ret PvE).")
	Step(scroll, 3, "Link templates to profiles",
		"Open the Links tab and pick a profile for every template. Optional: pick a fallback profile for each talent tree. It is used when no linked template matches your spec, e.g. when you spent your talents by hand.")
	Step(scroll, 4, "Optional: link a gear set",
		"Create gear sets in the Equipment Manager (character window). In the Profiles tab, pick a gear set below each profile. It is equipped whenever that profile is loaded, and its icon is shown next to the profile and on the minimap button.")
	Step(scroll, 5, "Switch your spec",
		"In Talented, open a template and choose Actions > Apply template, or switch your dual spec. About one second later your action bars (and gear) change to the linked profile.")

	Heading(scroll, "Good to know")
	Label(scroll, table.concat({
		"- Nothing is loaded or equipped in combat. The switch happens right after combat ends.",
		"- Missing gear items, or items that are only in your bank, are listed in chat. Everything else is equipped anyway.",
		"- Apply now (Links tab) loads the matching profile immediately.",
		"- Save next to a profile overwrites it with your current bars.",
		"- Disable automatic switching in Options if you only want to load profiles by hand.",
		"- Something missing on your bars? Options > Show errors in chat lists what could not be restored.",
	}, "\n"), nil, GameFontHighlight)
	Spacer(scroll)

	Heading(scroll, "Commands")
	Label(scroll, table.concat({
		"/tbs - open or close this window",
		"/tbs save <name> - save your current bars",
		"/tbs restore <name> - load a profile",
		"/tbs list - list all profiles",
		"/tbs minimap - show or hide the minimap button",
		"/tbs help - all commands (/abs works the same way)",
		"/talented - Talented options",
	}, "\n"), nil, GameFontHighlight)
	Spacer(scroll)

	local row = Row(scroll)
	-- switch on the next frame (via RefreshWindow) so the clicked button is not released in its own callback
	Button(row, "Go to Profiles", 0.32, function() currentTab = "profiles" ABS:RefreshWindow() end)
	Button(row, "Go to Links", 0.32, function() currentTab = "links" ABS:RefreshWindow() end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local builders = {
	profiles = BuildProfiles,
	links = BuildLinks,
	options = BuildOptions,
	help = BuildHelp,
}

local function SelectGroup(container, _, group)
	currentTab = group
	container:ReleaseChildren()

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	container:AddChild(scroll)

	builders[group](scroll)
end

local function UpdateStatusLine()
	if( not window ) then return end
	local last = Bridge:GetLastProfile()
	window:SetStatusText(last and ("Loaded: " .. last) or "")
end

function ABS:ShowWindow(tab)
	if( window ) then
		window:Show()
		if( tab ) then tabGroup:SelectTab(tab) end
		return
	end

	local ui = Bridge.db.ui
	ui.width = ui.width or 560
	ui.height = ui.height or 520

	-- Show the how-to the first time the window is opened
	if( not ui.helpSeen ) then
		ui.helpSeen = true
		tab = tab or "help"
	end
	if( tab ) then currentTab = tab end

	window = AceGUI:Create("Frame")
	window:SetTitle("TalentBarSaver")
	window:SetStatusTable(ui)
	window:SetLayout("Fill")
	window.frame:SetFrameStrata("HIGH") -- confirmation dialogs must stay on top
	window:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		window, tabGroup = nil, nil
	end)

	tabGroup = AceGUI:Create("TabGroup")
	tabGroup:SetLayout("Fill")
	tabGroup:SetTabs({
		{text = "Profiles", value = "profiles"},
		{text = "Links", value = "links"},
		{text = "Options", value = "options"},
		{text = "Help", value = "help"},
	})
	tabGroup:SetCallback("OnGroupSelected", SelectGroup)
	window:AddChild(tabGroup)
	tabGroup:SelectTab(currentTab)

	UpdateStatusLine()

	-- Close with Escape
	_G.TalentBarSaverWindow = window.frame
	local found
	for _, name in ipairs(UISpecialFrames) do
		if( name == "TalentBarSaverWindow" ) then found = true end
	end
	if( not found ) then
		table.insert(UISpecialFrames, "TalentBarSaverWindow")
	end
end

function ABS:HideWindow()
	if( window ) then
		window:Hide()
	end
end

function ABS:ToggleWindow()
	if( window and window.frame:IsShown() ) then
		self:HideWindow()
	else
		self:ShowWindow()
	end
end

-- Rebuild on the next frame so no widget gets released
-- while its own callback (e.g. a dropdown selection) is still running.
local refreshFrame = CreateFrame("Frame")
refreshFrame:Hide()
refreshFrame:SetScript("OnUpdate", function(self)
	self:Hide()
	if( not window or not tabGroup ) then return end
	tabGroup:SelectTab(currentTab)
	UpdateStatusLine()
end)

function ABS:RefreshWindow()
	if( window ) then
		refreshFrame:Show()
	end
end

function ABS:OnProfilesChanged()
	self:RefreshWindow()
end
