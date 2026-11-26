-- Popup: the small alert near the top of the screen (REQ-019). Silent, with no
-- screen-wide effects. It fades after about 4 seconds, and at once when clicked.
-- Up to three stack downwards; a fourth reuses the oldest.
local _, ns = ...

local Popup = ns.RegisterModule("Popup", {})

local SHOW_FOR = 4          -- seconds at full strength
local FADE_FOR = 0.8        -- seconds to fade out by itself
local FADE_CLICKED = 0.15   -- seconds to fade out when clicked
local WIDTH, HEIGHT, GAP, TOP = 380, 46, 6, -150
local SLOTS = 3

local frames = {}
Popup.frames = frames

local function OnUpdate(frame, elapsed)
    frame.age = frame.age + elapsed
    if not frame.fadeAt and frame.age >= SHOW_FOR then frame.fadeAt, frame.fadeFor = SHOW_FOR, FADE_FOR end
    if frame.fadeAt then
        local alpha = 1 - (frame.age - frame.fadeAt) / frame.fadeFor
        if alpha <= 0 then
            frame:SetAlpha(0)
            frame:Hide()
        else
            frame:SetAlpha(alpha)
        end
    end
end

local function Dismiss(frame)
    if not frame.fadeAt then frame.fadeAt, frame.fadeFor = frame.age, FADE_CLICKED end
end

local function Build(slot)
    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, TOP - (slot - 1) * (HEIGHT + GAP))
    frame:SetFrameStrata("HIGH")
    frame:RegisterForClicks("AnyUp")

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(0.05, 0.05, 0.06, 0.78)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(24, 24)
    frame.icon:SetPoint("LEFT", 10, 0)
    frame.icon:SetTexture(ns.SKULL_TEXTURE)
    frame.icon:SetVertexColor(ns.Colors.you[1], ns.Colors.you[2], ns.Colors.you[3])

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 2)
    frame.title:SetPoint("RIGHT", -10, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.title:SetTextColor(ns.Colors.you[1], ns.Colors.you[2], ns.Colors.you[3])

    frame.detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.detail:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.detail:SetPoint("RIGHT", -10, 0)
    frame.detail:SetJustifyH("LEFT")
    frame.detail:SetWordWrap(false)

    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnClick", Dismiss)
    frame:Hide()
    frame.age = 0
    return frame
end

-- Shows a popup: a title line and an optional detail line.
function Popup.Show(title, detail)
    if not (CreateFrame and UIParent) then return end
    local frame, oldest
    for slot = 1, SLOTS do
        frames[slot] = frames[slot] or Build(slot)
        if not frames[slot]:IsShown() then
            frame = frames[slot]
            break
        end
        if not oldest or frames[slot].age > oldest.age then oldest = frames[slot] end
    end
    frame = frame or oldest
    frame.title:SetText(title)
    frame.detail:SetText(detail or "")
    frame.age, frame.fadeAt = 0, nil
    frame:SetAlpha(1)
    frame:Show()
    return frame
end
