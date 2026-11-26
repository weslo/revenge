-- ListPanel: the "Recent killers" list on Revenge's settings page, as one element of
-- the game's own settings list (so it scrolls with the page and uses its look):
--
--   Recent killers (5)
--   Add by name [First Last        ] [Add]
--   <status line>
--   | Gorvak Ashmane    (5) You, Mira, Tavish, +1 more    2h ago [Remove] |
--   | Level 41 Rogue                                                     |
--
-- The rows scroll inside the element. The element is built from addon-owned XML
-- templates (Templates.xml) so the settings list never reuses its frames for
-- Blizzard's own controls, or theirs for this.
local _, ns = ...

local ListPanel = ns.RegisterModule("ListPanel", {})
local L = ns.L
local List = ns.List

local TEMPLATE = "RevengeTrackerListTemplate"
local ROW_TEMPLATE = "RevengeTrackerListRowTemplate"
local ROW_HEIGHT = 38
local VISIBLE_ROWS = 6
local LIST_TOP = 86                 -- title, add row and status line above the rows
local EXTENT = LIST_TOP + ROW_HEIGHT * VISIBLE_ROWS + 14
local CONTENT_LEFT = 37             -- lines up with the labels of the game's own controls
local NAME_WIDTH = 172
local NAME_R, NAME_G, NAME_B = 1, 0.55, 0.43
local OK_R, OK_G, OK_B = 0.55, 0.9, 0.55
local BAD_R, BAD_G, BAD_B = 1, 0.45, 0.4

local current  -- the element frame on screen, if any

local function SetStatus(frame, text, good)
    frame.statusText:SetText(text or "")
    if good then
        frame.statusText:SetTextColor(OK_R, OK_G, OK_B)
    else
        frame.statusText:SetTextColor(BAD_R, BAD_G, BAD_B)
    end
end

local function Refresh(frame)
    local now = ns.Now()
    local items = {}
    for i, row in ipairs(List.Rows(now)) do items[i] = List.Describe(row, now) end
    frame.titleText:SetText(L.LIST_TITLE:format(#items))
    frame.emptyText:SetText(L.LIST_EMPTY:format(ns.DaysText(ns.Store.Setting("expiryDays"))))
    frame.emptyText:SetShown(#items == 0)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    frame.scrollBox:SetDataProvider(CreateDataProvider(items), retain)
end

local function Add(frame)
    local added, message = List.AddByName(frame.editBox:GetText())
    SetStatus(frame, message, added)
    if added then
        frame.editBox:SetText("")
        frame.editBox:ClearFocus()
    end
    Refresh(frame)
end

local function RemoveItem(item)
    local name = List.Remove(item.row)
    if current then
        SetStatus(current, L.REMOVED:format(name), true)
        Refresh(current)
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function BuildRow(row)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("TOPLEFT", 6, -4)
    row.nameText:SetWidth(NAME_WIDTH)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)
    row.nameText:SetTextColor(NAME_R, NAME_G, NAME_B)

    row.whoText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.whoText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -3)
    row.whoText:SetWidth(NAME_WIDTH)
    row.whoText:SetJustifyH("LEFT")
    row.whoText:SetWordWrap(false)

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(80, 22)
    row.removeButton:SetPoint("RIGHT", -4, 0)
    row.removeButton:SetText(L.REMOVE_BUTTON)

    row.whenText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.whenText:SetPoint("RIGHT", row.removeButton, "LEFT", -10, 0)
    row.whenText:SetWidth(56)
    row.whenText:SetJustifyH("RIGHT")

    row.whatText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.whatText:SetPoint("LEFT", NAME_WIDTH + 14, 0)
    row.whatText:SetPoint("RIGHT", row.whenText, "LEFT", -8, 0)
    row.whatText:SetJustifyH("LEFT")
    row.whatText:SetMaxLines(2)

    row.separator = row:CreateTexture(nil, "BACKGROUND")
    row.separator:SetColorTexture(1, 1, 1, 0.06)
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT", 0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", 0, 0)

    row.built = true
end

local function InitRow(row, item)
    if not row.built then BuildRow(row) end
    row.nameText:SetText(item.name)
    row.whoText:SetText(item.who)
    row.whatText:SetText(item.what)
    row.whenText:SetText(item.when)
    row.removeButton:SetScript("OnClick", function()
        local ok, err = pcall(RemoveItem, item)
        if not ok then ns.Debug("remove error: %s", tostring(err)) end
    end)
end

---------------------------------------------------------------------------
-- The element
---------------------------------------------------------------------------
local function Build(frame)
    frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.titleText:SetPoint("TOPLEFT", 7, -6)

    frame.addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.addLabel:SetPoint("TOPLEFT", CONTENT_LEFT, -42)
    frame.addLabel:SetText(L.ADD_LABEL)

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxInstructionsTemplate")
    editBox:SetSize(220, 22)
    editBox:SetPoint("LEFT", frame.addLabel, "RIGHT", 16, 0)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(48)
    if editBox.Instructions then editBox.Instructions:SetText(L.ADD_PLACEHOLDER) end
    editBox:SetScript("OnEnterPressed", function() Add(frame) end)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.editBox = editBox

    local addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addButton:SetSize(80, 22)
    addButton:SetPoint("LEFT", editBox, "RIGHT", 8, 0)
    addButton:SetText(L.ADD_BUTTON)
    addButton:SetScript("OnClick", function() Add(frame) end)
    frame.addButton = addButton

    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.statusText:SetPoint("TOPLEFT", frame.addLabel, "BOTTOMLEFT", 0, -10)
    frame.statusText:SetPoint("RIGHT", -28, 0)
    frame.statusText:SetJustifyH("LEFT")

    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", CONTENT_LEFT, -LIST_TOP)
    scrollBox:SetPoint("BOTTOMRIGHT", -28, 8)
    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer(ROW_TEMPLATE, InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    frame.scrollBox = scrollBox

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetColorTexture(0, 0, 0, 0.25)
    frame.background:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", -4, 4)
    frame.background:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 4, -4)

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.emptyText:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 8, -12)
    frame.emptyText:SetPoint("RIGHT", scrollBox, "RIGHT", -8, 0)
    frame.emptyText:SetJustifyH("LEFT")

    frame.revengeBuilt = true
end

local function Available()
    return Settings and Settings.CreateElementInitializer and CreateFrame and CreateScrollBoxListLinearView
        and CreateDataProvider and ScrollUtil and ScrollUtil.InitScrollBoxListWithScrollBar
end

-- Adds the list to a vertical settings layout. Returns true if it was added.
function ListPanel.AddTo(layout)
    if not (layout and layout.AddInitializer and Available()) then return false end
    local initializer = Settings.CreateElementInitializer(TEMPLATE, { name = L.LIST_HEADER })
    initializer.GetExtent = function() return EXTENT end
    initializer.InitFrame = function(_, frame)
        if not frame.revengeBuilt then Build(frame) end
        current = frame
        SetStatus(frame, "")
        Refresh(frame)
    end
    initializer.Resetter = function(_, frame)
        if current == frame then current = nil end
    end
    if initializer.AddSearchTags then initializer:AddSearchTags(L.LIST_HEADER, L.ADD_LABEL) end
    layout:AddInitializer(initializer)
    return true
end

-- Keep the list current while it's on screen (a death or an addition elsewhere).
ns.OnChange(function()
    if current and current:IsVisible() then Refresh(current) end
end)
