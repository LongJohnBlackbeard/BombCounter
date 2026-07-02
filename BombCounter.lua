-- BombCounter.lua
-- Core event handling and presentation data. Kill-counting behavior is kept here
-- so UI changes cannot alter the de-duplication or sliding-window algorithm.

local BC = {}
_G.BombCounter = BC

BC.name = "BombCounter"
BC.version = "0.3.0"
BC.streaks = {}
BC.lastEventTimes = {}
BC.history = {}
BC.popupQueue = {}
BC.popupQueueRunning = false

BC.ALLIANCE_COLORS = {
    [1] = "EFD93D",
    [2] = "DE5B4E",
    [3] = "4F81BD",
}

BC.TIER_COLORS = {
    "A8A8A8",
    "62A85B",
    "4F81BD",
    "A66DD4",
    "EFD93D",
}

BC.defaultTiers = {
    { minimum = 1,  label = "Bomb",       template = "{name} made a {count}-kill Bomb!" },
    { minimum = 6,  label = "Detonation", template = "{name} detonated a {count}-kill Bomb!" },
    { minimum = 10, label = "Devastating", template = "{name} unleashed a devastating {count}-kill Bomb!" },
    { minimum = 15, label = "Massive",     template = "{name} obliterated {count} enemies with a massive Bomb!" },
    { minimum = 20, label = "Legendary",   template = "Legendary! {name} erased {count} enemies in one Bomb!" },
}

BC.defaults = {
    unlocked = false,
    bombWindowMs = 2000,
    bombThreshold = 5,
    bombScope = "all",
    historyLimit = 10,
    popupDuration = 3000,
    historyX = 20,
    historyY = 200,
    popupX = 300,
    popupY = 60,
    popupMovable = false,
    popupTextSize = 30,
    feedTextSize = 18,
    popupOpacity = 0.82,
    feedOpacity = 0.72,
    showTimestamps = true,
    nameSource = "character",
    outputPopup = true,
    outputFeed = true,
    outputChat = true,
    popupSound = false,
    tiers = BC.defaultTiers,
}

local function Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

function BC:NormalizeName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name:gsub("%^M[xX]$", ""):gsub("%^F[xX]$", "")
end

function BC:GetSavedVars()
    return self.SV
end

function BC:SanitizeSavedVars()
    local SV = self.SV
    SV.bombThreshold = Clamp(SV.bombThreshold, 2, 20)
    SV.bombWindowMs = Clamp(SV.bombWindowMs, 500, 10000)
    SV.historyLimit = Clamp(SV.historyLimit, 1, 30)
    SV.popupDuration = Clamp(SV.popupDuration, 750, 10000)
    SV.popupTextSize = Clamp(SV.popupTextSize, 22, 42)
    SV.feedTextSize = Clamp(SV.feedTextSize, 14, 24)
    SV.popupOpacity = Clamp(SV.popupOpacity, 0.1, 1)
    SV.feedOpacity = Clamp(SV.feedOpacity, 0.1, 1)

    if SV.nameSource ~= "character" and SV.nameSource ~= "account" and SV.nameSource ~= "both" then
        SV.nameSource = self.defaults.nameSource
    end
    if SV.bombScope ~= "self" and SV.bombScope ~= "party" and SV.bombScope ~= "all" then
        SV.bombScope = self.defaults.bombScope
    end

    if type(SV.tiers) ~= "table" then SV.tiers = {} end
    for index = #self.defaultTiers + 1, #SV.tiers do
        SV.tiers[index] = nil
    end
    local previousMinimum = 0
    for index, tierDefault in ipairs(self.defaultTiers) do
        local tier = SV.tiers[index]
        if type(tier) ~= "table" then
            tier = {}
            SV.tiers[index] = tier
        end

        local maximum = 50 - (#self.defaultTiers - index)
        local minimum = index == 1 and 1 or Clamp(tier.minimum or tierDefault.minimum, previousMinimum + 1, maximum)
        tier.minimum = minimum
        tier.label = tierDefault.label
        if type(tier.template) ~= "string" or tier.template == "" then
            tier.template = tierDefault.template
        end
        previousMinimum = minimum
    end
end

function BC:GetTier(count)
    for index = #self.SV.tiers, 1, -1 do
        if count >= self.SV.tiers[index].minimum then
            return index, self.SV.tiers[index]
        end
    end
    return 1, self.SV.tiers[1]
end

function BC:GetTierColor(index)
    return self.TIER_COLORS[index] or "FFFFFF"
end

function BC:FormatPlayerName(characterName, accountName, alliance)
    local character = self:NormalizeName(characterName) or self:NormalizeName(accountName) or "<unknown>"
    local account = self:NormalizeName(accountName) or self:NormalizeName(characterName) or "<unknown>"
    local allianceHex = self.ALLIANCE_COLORS[alliance] or "FFFFFF"

    if self.SV.nameSource == "account" then
        return string.format("|c%s%s|r", allianceHex, account)
    elseif self.SV.nameSource == "both" then
        return string.format("|c%s%s|r |cA8A8A8(%s)|r", allianceHex, character, account)
    end
    return string.format("|c%s%s|r", allianceHex, character)
end

function BC:BuildBombEvent(count, alliance, characterName, accountName)
    local tierIndex, tier = self:GetTier(count)
    local formattedName = self:FormatPlayerName(characterName, accountName, alliance)
    local message = tier.template
    message = message:gsub("{name}", function() return formattedName end)
    message = message:gsub("{count}", function() return tostring(count) end)

    return {
        count = count,
        alliance = alliance,
        characterName = characterName,
        accountName = accountName,
        tierIndex = tierIndex,
        tierLabel = tier.label,
        tierColor = self:GetTierColor(tierIndex),
        message = message,
        time = GetTimeString and GetTimeString() or "",
    }
end

function BC:DispatchBomb(eventData)
    if self.SV.outputFeed then self:AddHistory(eventData) end
    if self.SV.outputChat then CHAT_SYSTEM:AddMessage(eventData.message) end
    if self.SV.outputPopup then self:EnqueuePopup(eventData) end
end

-- Kill-feed handling. Scope filtering, de-duplication, sliding-window counting,
-- delayed finalization, and streak reset intentionally match the previous code.
function BC:OnKillFeed(_, killLocation,
                       srcDisp, srcChar, srcAlliance, srcRank,
                       tgtDisp, tgtChar, tgtAlliance, tgtRank)
    local charSrc = (srcChar ~= "" and self:NormalizeName(srcChar)) or srcDisp or "<unknown>"
    local accSrc = self:NormalizeName(srcDisp) or srcDisp or "<unknown>"
    local trackingNameSource = self.SV.nameSource == "account" and "account" or "character"
    local src = trackingNameSource == "account" and accSrc or charSrc

    local charTgt = (tgtChar ~= "" and self:NormalizeName(tgtChar)) or tgtDisp or "<unknown>"
    local accTgt = self:NormalizeName(tgtDisp) or tgtDisp or "<unknown>"
    local tgt = trackingNameSource == "account" and accTgt or charTgt

    -- 1) scope filtering
    if self.SV.bombScope == "self" then
        if src ~= self:NormalizeName(GetUnitName("player")) then return end
    elseif self.SV.bombScope == "party" then
        local inParty = false
        for i = 1, GetGroupSize() do
            local tag = GetGroupUnitTagByIndex(i)
            if self:NormalizeName(GetUnitName(tag)) == src then
                inParty = true
                break
            end
        end
        if not inParty then return end
    end

    -- 2) de-duplicate same source-to-target within window
    local now = GetGameTimeMilliseconds()
    local key = src .. ":" .. tgt
    if self.lastEventTimes[key] and now - self.lastEventTimes[key] < self.SV.bombWindowMs then
        return
    end
    self.lastEventTimes[key] = now

    -- 3) record timestamp and purge expired entries
    local list = self.streaks[src] or {}
    table.insert(list, now)
    local cutoff = now - self.SV.bombWindowMs
    while list[1] and list[1] < cutoff do
        table.remove(list, 1)
    end
    self.streaks[src] = list

    -- 4) threshold hit: cancel and reschedule via EventManager
    if #list >= self.SV.bombThreshold then
        local updateName = "BombCounter_Update_" .. src
        EVENT_MANAGER:UnregisterForUpdate(updateName)
        local captured = #list
        local eventData = self:BuildBombEvent(captured, srcAlliance, charSrc, accSrc)
        EVENT_MANAGER:RegisterForUpdate(
            updateName,
            self.SV.bombWindowMs,
            function()
                BC:DispatchBomb(eventData)
                BC.streaks[src] = {}
                EVENT_MANAGER:UnregisterForUpdate(updateName)
            end
        )
    end
end

function BC:TestBomb(count)
    count = Clamp(count or self.SV.bombThreshold, 1, 99)
    local eventData = self:BuildBombEvent(
        count,
        GetUnitAlliance("player"),
        self:NormalizeName(GetUnitName("player")) or "You",
        self:NormalizeName(GetUnitDisplayName("player")) or "@You"
    )
    self:DispatchBomb(eventData)
end

function BC:PreviewBomb(count)
    count = Clamp(count or self.SV.bombThreshold, 1, 99)
    local eventData = self:BuildBombEvent(
        count,
        GetUnitAlliance("player"),
        self:NormalizeName(GetUnitName("player")) or "You",
        self:NormalizeName(GetUnitDisplayName("player")) or "@You"
    )
    self:EnqueuePopup(eventData)
end

function BC:OnAddOnLoaded(_, addonName)
    if addonName ~= self.name then return end
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_ADD_ON_LOADED)

    self.SV = ZO_SavedVars:NewAccountWide("BombCounterSV", 1, nil, self.defaults)
    self:SanitizeSavedVars()
    self:InitializeUI()

    SLASH_COMMANDS["/bombtest"] = function(argument)
        self:TestBomb(tonumber(argument))
    end
    SLASH_COMMANDS["/bombclear"] = function()
        self:ClearHistory()
    end
    SLASH_COMMANDS["/bombmenu"] = function()
        if self.settingsPanel and LibAddonMenu2 then
            LibAddonMenu2:OpenToPanel(self.settingsPanel)
        else
            InterfaceOptionsFrame_OpenToCategory("BombCounter")
        end
    end

    EVENT_MANAGER:RegisterForEvent(self.name, EVENT_PVP_KILL_FEED_DEATH, function(...)
        self:OnKillFeed(...)
    end)

    if LibAddonMenu2 then self:CreateSettingsMenu(LibAddonMenu2) end
end

EVENT_MANAGER:RegisterForEvent(BC.name, EVENT_ADD_ON_LOADED, function(...)
    BC:OnAddOnLoaded(...)
end)
