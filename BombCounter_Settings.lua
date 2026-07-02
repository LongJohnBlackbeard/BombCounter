-- BombCounter_Settings.lua

local BC = BombCounter

local function NameChoice(value)
    return ({ character = "Character", account = "Account", both = "Character (@Account)" })[value] or "Character"
end

local function ScopeChoice(value)
    return ({ self = "Self", party = "Party", all = "All" })[value] or "All"
end

function BC:SetTierMinimum(index, value)
    if index == 1 then return end
    local tiers = self.SV.tiers
    local minimum = index
    local maximum = 50 - (#tiers - index)
    tiers[index].minimum = math.max(minimum, math.min(maximum, tonumber(value) or minimum))

    for tierIndex = index - 1, 2, -1 do
        if tiers[tierIndex].minimum >= tiers[tierIndex + 1].minimum then
            tiers[tierIndex].minimum = tiers[tierIndex + 1].minimum - 1
        end
    end
    for tierIndex = index + 1, #tiers do
        if tiers[tierIndex].minimum <= tiers[tierIndex - 1].minimum then
            tiers[tierIndex].minimum = tiers[tierIndex - 1].minimum + 1
        end
    end
end

function BC:CreateSettingsMenu(LAM)
    local panelId = "BC_Panel"
    self.settingsPanel = LAM:RegisterAddonPanel(panelId, {
        type = "panel",
        name = "BombCounter",
        displayName = "|cEFD93DBomb|rCounter",
        author = "Alphatrazz",
        version = self.version,
        registerForRefresh = true,
        registerForDefaults = true,
    })

    local controls = {
        {
            type = "description",
            title = "Bomb alerts without the clutter",
            text = "Configure who is tracked and how detected bombs appear. Display settings never alter kill counting.",
        },
        { type = "header", name = "General" },
        {
            type = "dropdown", name = "Kill scope",
            tooltip = "Choose whose bombs are tracked.",
            choices = { "Self", "Party", "All" },
            getFunc = function() return ScopeChoice(self.SV.bombScope) end,
            setFunc = function(value)
                self.SV.bombScope = ({ Self = "self", Party = "party", All = "all" })[value]
            end,
            default = "All", width = "half",
        },
        {
            type = "dropdown", name = "Displayed name",
            tooltip = "Show character name, account name, or both. Both uses Character (@Account).",
            choices = { "Character", "Account", "Character (@Account)" },
            getFunc = function() return NameChoice(self.SV.nameSource) end,
            setFunc = function(value)
                self.SV.nameSource = ({
                    Character = "character",
                    Account = "account",
                    ["Character (@Account)"] = "both",
                })[value]
            end,
            default = "Character", width = "half",
        },
        {
            type = "slider", name = "Detection window (ms)",
            tooltip = "Kills within this sliding window are grouped into one bomb.",
            min = 500, max = 10000, step = 100, clampInput = true,
            getFunc = function() return self.SV.bombWindowMs end,
            setFunc = function(value) self.SV.bombWindowMs = value end,
            default = self.defaults.bombWindowMs, width = "half",
        },
        {
            type = "slider", name = "Bomb threshold",
            tooltip = "Minimum kills required before an alert is scheduled.",
            min = 2, max = 20, step = 1, clampInput = true,
            getFunc = function() return self.SV.bombThreshold end,
            setFunc = function(value) self.SV.bombThreshold = value end,
            default = self.defaults.bombThreshold, width = "half",
        },
        { type = "header", name = "Outputs" },
        {
            type = "checkbox", name = "HUD popup",
            getFunc = function() return self.SV.outputPopup end,
            setFunc = function(value) self.SV.outputPopup = value end,
            default = self.defaults.outputPopup, width = "half",
        },
        {
            type = "checkbox", name = "On-screen feed",
            getFunc = function() return self.SV.outputFeed end,
            setFunc = function(value)
                self.SV.outputFeed = value
                self:RefreshFeed()
            end,
            default = self.defaults.outputFeed, width = "half",
        },
        {
            type = "checkbox", name = "Chat message",
            getFunc = function() return self.SV.outputChat end,
            setFunc = function(value) self.SV.outputChat = value end,
            default = self.defaults.outputChat, width = "half",
        },
        { type = "header", name = "Popup" },
        {
            type = "slider", name = "Duration (ms)",
            min = 750, max = 10000, step = 250, clampInput = true,
            getFunc = function() return self.SV.popupDuration end,
            setFunc = function(value) self.SV.popupDuration = value end,
            default = self.defaults.popupDuration, width = "half",
        },
        {
            type = "slider", name = "Text size",
            min = 22, max = 42, step = 1, clampInput = true,
            getFunc = function() return self.SV.popupTextSize end,
            setFunc = function(value)
                self.SV.popupTextSize = value
                self:ApplyUISettings()
            end,
            default = self.defaults.popupTextSize, width = "half",
        },
        {
            type = "slider", name = "Background opacity",
            min = 0.1, max = 1, step = 0.05, decimals = 2, clampInput = true,
            getFunc = function() return self.SV.popupOpacity end,
            setFunc = function(value)
                self.SV.popupOpacity = value
                self:ApplyUISettings()
            end,
            default = self.defaults.popupOpacity, width = "half",
        },
        {
            type = "checkbox", name = "Alert sound",
            tooltip = "Play the ESO level-up sound with each popup.",
            getFunc = function() return self.SV.popupSound end,
            setFunc = function(value) self.SV.popupSound = value end,
            default = self.defaults.popupSound, width = "half",
        },
        {
            type = "checkbox", name = "Move popup",
            tooltip = "Show a draggable popup placeholder.",
            getFunc = function() return self.SV.popupMovable end,
            setFunc = function(value) self:TogglePopupDrag(value) end,
            default = self.defaults.popupMovable, width = "half",
        },
        {
            type = "button", name = "Preview popup",
            func = function() self:PreviewBomb(self.SV.bombThreshold) end,
            width = "half",
        },
        { type = "header", name = "Feed" },
        {
            type = "slider", name = "Maximum rows",
            min = 1, max = 30, step = 1, clampInput = true,
            getFunc = function() return self.SV.historyLimit end,
            setFunc = function(value)
                self.SV.historyLimit = value
                while #self.history > value do table.remove(self.history) end
                self:RefreshFeed()
            end,
            default = self.defaults.historyLimit, width = "half",
        },
        {
            type = "slider", name = "Text size",
            min = 14, max = 24, step = 1, clampInput = true,
            getFunc = function() return self.SV.feedTextSize end,
            setFunc = function(value)
                self.SV.feedTextSize = value
                self:ApplyUISettings()
            end,
            default = self.defaults.feedTextSize, width = "half",
        },
        {
            type = "slider", name = "Background opacity",
            min = 0.1, max = 1, step = 0.05, decimals = 2, clampInput = true,
            getFunc = function() return self.SV.feedOpacity end,
            setFunc = function(value)
                self.SV.feedOpacity = value
                self:ApplyUISettings()
            end,
            default = self.defaults.feedOpacity, width = "half",
        },
        {
            type = "checkbox", name = "Show timestamps",
            getFunc = function() return self.SV.showTimestamps end,
            setFunc = function(value)
                self.SV.showTimestamps = value
                self:RefreshFeed()
            end,
            default = self.defaults.showTimestamps, width = "half",
        },
        {
            type = "checkbox", name = "Move feed",
            tooltip = "Unlock the feed and show its clear button.",
            getFunc = function() return self.SV.unlocked end,
            setFunc = function(value) self:ToggleLock(value) end,
            default = self.defaults.unlocked, width = "half",
        },
        {
            type = "button", name = "Clear feed",
            func = function() self:ClearHistory() end,
            width = "half",
        },
        {
            type = "button", name = "Reset HUD positions",
            func = function() self:ResetPositions() end,
            width = "full",
        },
        { type = "header", name = "Message Tiers" },
        {
            type = "description",
            text = "The highest matching minimum wins. Templates support {name} and {count}.",
        },
    }

    for index, tierDefault in ipairs(self.defaultTiers) do
        local tierIndex = index
        local defaultTier = tierDefault
        local tierControls = {}
        if tierIndex == 1 then
            table.insert(tierControls, {
                type = "description",
                text = "Minimum count: 1 (base tier)",
            })
        else
            table.insert(tierControls, {
                type = "slider", name = "Minimum kills",
                min = 2, max = 50, step = 1, clampInput = true,
                getFunc = function() return self.SV.tiers[tierIndex].minimum end,
                setFunc = function(value) self:SetTierMinimum(tierIndex, value) end,
                default = defaultTier.minimum,
            })
        end
        table.insert(tierControls, {
            type = "editbox", name = "Message template",
            tooltip = "Available tokens: {name} and {count}.",
            isMultiline = false,
            getFunc = function() return self.SV.tiers[tierIndex].template end,
            setFunc = function(value)
                self.SV.tiers[tierIndex].template = value ~= "" and value or defaultTier.template
            end,
            default = defaultTier.template,
            width = "full",
        })
        table.insert(tierControls, {
            type = "button", name = "Preview this tier",
            func = function() self:PreviewBomb(self.SV.tiers[tierIndex].minimum) end,
            width = "half",
        })
        table.insert(controls, {
            type = "submenu",
            name = string.format("Tier %d — %s", tierIndex, defaultTier.label),
            controls = tierControls,
        })
    end

    LAM:RegisterOptionControls(panelId, controls)
end
