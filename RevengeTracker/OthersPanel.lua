-- OthersPanel: how each other addon's support is doing, under the "Other addons"
-- switches on Revenge's settings page:
--
--   Revenge Book: listening · 3 this session
--   Grudgekeeper: listening
--   HeadHunter: paused: the other addon may have changed. It tries again next session.
--   Kill on Sight: not loaded
--
-- Plain text in an element of the game's own settings list, like the Recent killers
-- list, built from an addon-owned template (Templates.xml).
local _, ns = ...

local OthersPanel = ns.RegisterModule("OthersPanel", {})

local TEMPLATE = "RevengeTrackerOthersTemplate"
local CONTENT_LEFT = 37             -- lines up with the labels of the game's own controls
local LINE_HEIGHT = 16
local EXTENT = 12 + LINE_HEIGHT * 4

local current  -- the element frame on screen, if any

local function Refresh(frame)
    local lines = ns.Foreign.StatusLines()
    frame.statusText:SetText(table.concat(lines, "\n"))
end

local function Build(frame)
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.statusText:SetPoint("TOPLEFT", CONTENT_LEFT, -4)
    frame.statusText:SetPoint("RIGHT", -28, 0)
    frame.statusText:SetJustifyH("LEFT")
    frame.statusText:SetSpacing(4)
    frame.statusText:SetTextColor(0.79, 0.81, 0.84)
    frame.revengeBuilt = true
end

-- Adds the status lines to a vertical settings layout. Returns true if they were added.
function OthersPanel.AddTo(layout)
    if not (layout and layout.AddInitializer and Settings and Settings.CreateElementInitializer and CreateFrame) then
        return false
    end
    local initializer = Settings.CreateElementInitializer(TEMPLATE, { name = ns.L.SECTION_OTHERS })
    initializer.GetExtent = function() return EXTENT end
    initializer.InitFrame = function(_, frame)
        if not frame.revengeBuilt then Build(frame) end
        current = frame
        Refresh(frame)
    end
    initializer.Resetter = function(_, frame)
        if current == frame then current = nil end
    end
    layout:AddInitializer(initializer)
    return true
end

-- The lines on screen, for tests.
function OthersPanel.Text()
    return current and current.statusText:GetText() or nil
end

-- Keep the lines current while they're on screen.
function OthersPanel.Refresh()
    if current and current:IsVisible() then Refresh(current) end
end

ns.OnChange(OthersPanel.Refresh)
