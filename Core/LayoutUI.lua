--[[
	TalentBarSaver - Fenster
	/tbs (oder /abs ohne Argument) oeffnet das Fenster.

	Reiter:
	  Profile    - Leisten speichern, laden, umbenennen, loeschen
	  Zuordnung  - Talented-Template -> Profil, Fallback je Talentbaum
	  Optionen   - Automatik, Makros, Zauberrang
]]
local ADDON_NAME, ns = ...
local ABS = ns
local Bridge = ABS.Bridge
local AceGUI = LibStub("AceGUI-3.0")

local window, tabGroup
local currentTab = "profiles"

local NONE_KEY = ""
local NONE_TEXT = "|cff808080- keins -|r"
local GREEN = "|cff33ff33"
local YELLOW = "|cffffff00"
local GREY = "|cff9d9d9d"

---------------------------------------------------------------------------
-- Hilfsfunktionen
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

local function ProfileDropdownList()
	local list = {[NONE_KEY] = NONE_TEXT}
	for _, name in ipairs(ABS:GetProfileList()) do
		list[name] = name
	end
	return list
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
-- Dialoge (Bestaetigen, Umbenennen)
---------------------------------------------------------------------------
local function DialogEditBox(dialog)
	return dialog.editBox or _G[dialog:GetName() .. "EditBox"]
end

StaticPopupDialogs["TALENTBARSAVER_DELETE"] = {
	text = "Profil %s wirklich loeschen?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, data) ABS:DeleteProfile(data) end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

StaticPopupDialogs["TALENTBARSAVER_OVERWRITE"] = {
	text = "Aktuelle Leisten im Profil %s speichern?\nDas bisherige Layout wird ueberschrieben.",
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
	text = "Neuer Name fuer Profil %s:",
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
-- Reiter: Profile
---------------------------------------------------------------------------
local function BuildProfiles(scroll)
	local newRow = Row(scroll)
	local edit = AceGUI:Create("EditBox")
	edit:SetLabel("Aktuelle Leisten als neues Profil speichern")
	edit:SetRelativeWidth(0.70)
	edit:DisableButton(true)
	edit:SetCallback("OnEnterPressed", function(w, _, text)
		SaveNew(text)
		w:SetText("")
		w:ClearFocus()
	end)
	newRow:AddChild(edit)

	local saveButton = Button(newRow, "Speichern", 0.28, function()
		SaveNew(edit:GetText())
		edit:SetText("")
	end)
	AddTooltip(saveButton, "Speichern", "Speichert deine aktuellen Aktionsleisten unter dem eingegebenen Namen.")

	Heading(scroll, "Profile (" .. (UnitClass("player")) .. ")")

	local profiles = ABS:GetProfileList()
	if( #profiles == 0 ) then
		Label(scroll, GREY .. "Noch keine Profile. Leisten einrichten, Namen eingeben, Speichern.|r")
		return
	end

	local active = Bridge:GetLastProfile()
	for _, name in ipairs(profiles) do
		local row = Row(scroll)
		local text = name
		if( name == active ) then
			text = GREEN .. name .. "|r " .. GREY .. "(geladen)|r"
		end
		Label(row, text, 0.26, GameFontHighlight)

		local load = Button(row, "Laden", 0.18, function()
			ABS:RestoreProfile(name)
		end)
		AddTooltip(load, "Laden", "Stellt deine Aktionsleisten auf dieses Profil um.")

		local save = Button(row, "Speichern", 0.18, function()
			Confirm("TALENTBARSAVER_OVERWRITE", name)
		end)
		AddTooltip(save, "Speichern", "Ueberschreibt dieses Profil mit deinen aktuellen Leisten.")

		Button(row, "Umbenennen", 0.18, function()
			Confirm("TALENTBARSAVER_RENAME", name)
		end)

		Button(row, "Loeschen", 0.18, function()
			Confirm("TALENTBARSAVER_DELETE", name)
		end)
	end
end

---------------------------------------------------------------------------
-- Reiter: Zuordnung
---------------------------------------------------------------------------
local function StatusText()
	local group = GetActiveTalentGroup()
	local trees = Bridge:GetTreeNames()
	local tree, points = Bridge:GetActiveTree(group)
	local parts = {}

	table.insert(parts, string.format("Aktive Talentgruppe: %s%d|r", YELLOW, group))
	if( tree ) then
		table.insert(parts, string.format("Hauptbaum: %s%s|r (%d Punkte)", YELLOW, trees[tree] or "?", points))
	else
		table.insert(parts, "Hauptbaum: " .. GREY .. "keine Punkte verteilt|r")
	end

	local templateName = Bridge:GetGroupTemplate(group)
	table.insert(parts, "Zuletzt angewendetes Template: " .. (templateName and (YELLOW .. templateName .. "|r") or (GREY .. "-|r")))

	local profile, reason, detail = Bridge:ResolveProfile(group)
	if( profile ) then
		table.insert(parts, string.format("Passendes Profil: %s%s|r %s(%s)|r", GREEN, profile, GREY, Bridge:DescribeReason(reason, detail)))
	else
		table.insert(parts, "Passendes Profil: " .. GREY .. "keins zugeordnet|r")
	end

	return table.concat(parts, "\n")
end

local function BuildLinks(scroll)
	Label(scroll, StatusText())

	local actionRow = Row(scroll)
	local apply = Button(actionRow, "Jetzt anwenden", 0.4, function()
		Bridge:ApplyForActiveGroup()
	end)
	AddTooltip(apply, "Jetzt anwenden", "Laedt sofort das Profil, das zu deinem aktiven Spec passt.")

	-- Talented-Templates
	Heading(scroll, "Talented-Templates")
	local templates = Bridge:GetClassTemplates()
	if( #templates == 0 ) then
		Label(scroll, GREY .. "Keine Talented-Templates fuer deine Klasse. Lege sie im Talentfenster (Taste N) an.|r")
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
				text = text .. " " .. GREY .. "(Gruppe " .. groupOf[templateName] .. ")|r"
			end
			Label(row, text, 0.48, GameFontHighlight)
			ProfileDropdown(row, 0.48, Bridge:GetTemplateLink(templateName), function(profile)
				Bridge:SetTemplateLink(templateName, profile)
				ABS:RefreshWindow()
			end)
		end
	end

	-- Fallback nach Baum
	Heading(scroll, "Fallback nach Talentbaum")
	Label(scroll, GREY .. "Greift, wenn kein zugeordnetes Template zum aktuellen Spec passt (z. B. von Hand geskillt).|r")
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
-- Reiter: Optionen
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
	CheckBox(scroll, "Leisten automatisch wechseln",
		"Nach dem Anwenden eines Talented-Templates und beim Dual-Spec-Wechsel das zugeordnete Profil laden.",
		Bridge:IsAuto(), function(v) Bridge:SetAuto(v) end)

	CheckBox(scroll, "Fehlende Makros neu anlegen",
		"Makros, die im Profil stehen, aber geloescht wurden, beim Laden neu erstellen.",
		ABS.db.macro, function(v) ABS.db.macro = v end)

	CheckBox(scroll, "Immer hoechsten Zauberrang laden",
		"Aus: Es wird der Rang geladen, der beim Speichern auf der Leiste lag.",
		ABS.db.restoreRank, function(v) ABS.db.restoreRank = v end)

	Heading(scroll, "Fehler")
	local errorsButton = Button(scroll, "Fehler im Chat anzeigen", 0.5, function()
		SlashCmdList["TALENTBARSAVER"]("errors")
	end)
	AddTooltip(errorsButton, "Fehler anzeigen", "Zeigt im Chat, welche Buttons beim letzten Laden nicht wiederhergestellt werden konnten.")

	Heading(scroll, "Befehle")
	Label(scroll, "/tbs - dieses Fenster\n/tbs save <name>, /tbs restore <name>, /tbs list, /tbs help\n/abs funktioniert weiterhin genauso.\n/talented - Talented-Optionen")
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local builders = {
	profiles = BuildProfiles,
	links = BuildLinks,
	options = BuildOptions,
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
	window:SetStatusText(last and ("Geladen: " .. last) or "")
end

function ABS:ShowWindow()
	if( window ) then
		window:Show()
		return
	end

	local ui = Bridge.db.ui
	ui.width = ui.width or 560
	ui.height = ui.height or 520

	window = AceGUI:Create("Frame")
	window:SetTitle("TalentBarSaver")
	window:SetStatusTable(ui)
	window:SetLayout("Fill")
	window.frame:SetFrameStrata("HIGH") -- Bestaetigungsdialoge muessen darueber liegen
	window:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		window, tabGroup = nil, nil
	end)

	tabGroup = AceGUI:Create("TabGroup")
	tabGroup:SetLayout("Fill")
	tabGroup:SetTabs({
		{text = "Profile", value = "profiles"},
		{text = "Zuordnung", value = "links"},
		{text = "Optionen", value = "options"},
	})
	tabGroup:SetCallback("OnGroupSelected", SelectGroup)
	window:AddChild(tabGroup)
	tabGroup:SelectTab(currentTab)

	UpdateStatusLine()

	-- Mit Escape schliessen
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

-- Neu aufbauen erst im naechsten Frame: so wird kein Widget waehrend
-- seines eigenen Callbacks (z. B. Dropdown-Auswahl) freigegeben.
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
