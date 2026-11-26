-- Settings: the "Revenge" category in Options > AddOns, built from the game's own
-- controls, with the "Recent killers" list (ListPanel.lua) at the end. Controls for
-- later features are added as those features land.
local addonName, ns = ...

local Settings_ = ns.RegisterModule("Settings", {})
local L = ns.L

local category, layout

local function Register(key, varType, label, default)
    return Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
        ns.db.settings, varType, label, default)
end

local function AddSectionHeader(name)
    if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end
end

local function AddExpirySlider()
    if not (Settings.CreateSlider and Settings.CreateSliderOptions) then return end
    local setting = Register("expiryDays", Settings.VarType.Number, L.SETTING_EXPIRY, ns.Store.DEFAULTS.expiryDays)
    local options = Settings.CreateSliderOptions(1, 30, 1)
    if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, ns.DaysText)
    end
    Settings.CreateSlider(category, setting, options, L.SETTING_EXPIRY_TOOLTIP)
    -- Tooltips read the setting live; the list (and later the skulls and pins) redraw.
    if Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback(addonName .. "_expiryDays", function() ns.Changed() end)
    end
end

local function AddModifierDropdown()
    if not (Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
    local setting = Register("detailsModifier", Settings.VarType.String, L.SETTING_MODIFIER, ns.Store.DEFAULTS.detailsModifier)
    local function Options()
        local container = Settings.CreateControlTextContainer()
        container:Add("SHIFT", L.MODIFIER_SHIFT)
        container:Add("CTRL", L.MODIFIER_CTRL)
        container:Add("ALT", L.MODIFIER_ALT)
        container:Add("OFF", L.MODIFIER_OFF)
        return container:GetData()
    end
    Settings.CreateDropdown(category, setting, Options, L.SETTING_MODIFIER_TOOLTIP)
end

local function AddShareGuild()
    if not Settings.CreateCheckbox then return end
    local setting = Register("shareGuild", Settings.VarType.Boolean, L.SETTING_SHARE_GUILD, ns.Store.DEFAULTS.shareGuild)
    Settings.CreateCheckbox(category, setting, L.SETTING_SHARE_GUILD_TOOLTIP)
end

function Settings_:OnLogin()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.RegisterAddOnCategory and Settings.VarType) then
        ns.Print(L.SETTINGS_UNAVAILABLE)
        return
    end
    category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
    AddSectionHeader(L.SECTION_KILLS)
    AddExpirySlider()
    AddModifierDropdown()
    AddSectionHeader(L.SECTION_SHARING)
    AddShareGuild()
    -- The list is the only custom element; if it can't be built, the rest still works.
    local ok, err = pcall(ns.ListPanel.AddTo, layout)
    if not ok then ns.Debug("list error: %s", tostring(err)) end
    Settings.RegisterAddOnCategory(category)
    Settings_.category = category
end

function Settings_.Open()
    if InCombatLockdown() then
        ns.Print(L.CANNOT_OPEN_IN_COMBAT)
        return
    end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end
