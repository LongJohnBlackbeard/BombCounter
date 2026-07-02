-- BombCounter_UI.lua

local BC = BombCounter

local function HexToRgb(hex)
    local red = tonumber(hex:sub(1, 2), 16) / 255
    local green = tonumber(hex:sub(3, 4), 16) / 255
    local blue = tonumber(hex:sub(5, 6), 16) / 255
    return red, green, blue
end

function BT_HistoryContainer_MoveStop()
    BC:SaveHistoryPos()
end

function BT_BombPopup_MoveStop()
    BC:SavePopupPos()
end

function BC:InitializeUI()
    local SV = self.SV
    self.historyCtrl = BT_HistoryContainer
    self.historyBG = BT_HistoryContainer_BG
    self.historyTitle = BT_HistoryContainer_Title
    self.historyHint = BT_HistoryContainer_MoveHint
    self.historyRows = BT_HistoryContainer_Rows
    self.historyClear = BT_HistoryContainer_Clear
    self.feedRowPool = {}

    self.popupCtrl = BT_BombPopup
    self.popupBG = BT_BombPopup_BG
    self.popupAccent = BT_BombPopup_Accent
    self.popupTier = BT_BombPopup_Tier
    self.popupCount = BT_BombPopup_Count
    self.popupLabel = BT_BombPopup_Message

    self.historyCtrl:ClearAnchors()
    self.historyCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, SV.historyX, SV.historyY)
    self.popupCtrl:ClearAnchors()
    self.popupCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, SV.popupX, SV.popupY)

    self.historyClear:SetText("Clear")
    self.historyClear:SetHandler("OnClicked", function() self:ClearHistory() end)
    self:ApplyUISettings()
    self:ToggleLock(SV.unlocked)
    self:TogglePopupDrag(SV.popupMovable)
    self:RefreshFeed()
end

function BC:ApplyUISettings()
    local SV = self.SV
    self.popupLabel:SetFont(string.format("%s|%d|soft-shadow-thick", "$(BOLD_FONT)", SV.popupTextSize))
    self.historyBG:SetCenterColor(0.025, 0.025, 0.025, SV.feedOpacity)
    self.popupBG:SetCenterColor(0.025, 0.025, 0.025, SV.popupOpacity)
    self:RefreshFeed()
end

function BC:SaveHistoryPos()
    if not self.historyCtrl then return end
    self.SV.historyX = self.historyCtrl:GetLeft()
    self.SV.historyY = self.historyCtrl:GetTop()
end

function BC:SavePopupPos()
    if not self.popupCtrl then return end
    self.SV.popupX = self.popupCtrl:GetLeft()
    self.SV.popupY = self.popupCtrl:GetTop()
end

function BC:ToggleLock(unlocked)
    if not self.historyCtrl then return end
    self.SV.unlocked = unlocked
    self.historyCtrl:SetMovable(unlocked)
    self.historyCtrl:SetMouseEnabled(unlocked)
    self.historyClear:SetHidden(not unlocked)
    self.historyHint:SetHidden(not unlocked)
    if not unlocked then self:SaveHistoryPos() end
    self:RefreshFeed()
end

function BC:TogglePopupDrag(unlocked)
    if not self.popupCtrl then return end
    self.SV.popupMovable = unlocked
    self.popupCtrl:SetMovable(unlocked)
    self.popupCtrl:SetMouseEnabled(unlocked)

    if unlocked then
        self.popupShowing = false
        if self.popupTimeline and self.popupTimeline:IsPlaying() then self.popupTimeline:Stop() end
        self.popupTier:SetText("POPUP POSITION")
        self.popupCount:SetText("#")
        self.popupLabel:SetText("Drag this card to reposition it")
        self:SetPopupTierColor(5)
        self.popupCtrl:SetAlpha(1)
        self.popupCtrl:SetHidden(false)
    else
        self:SavePopupPos()
        if not self.popupShowing then self.popupCtrl:SetHidden(true) end
    end
end

function BC:ResetPositions()
    self.SV.historyX = self.defaults.historyX
    self.SV.historyY = self.defaults.historyY
    self.SV.popupX = self.defaults.popupX
    self.SV.popupY = self.defaults.popupY

    self.historyCtrl:ClearAnchors()
    self.historyCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.SV.historyX, self.SV.historyY)
    self.popupCtrl:ClearAnchors()
    self.popupCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.SV.popupX, self.SV.popupY)
end

function BC:SetPopupTierColor(tierIndex)
    local red, green, blue = HexToRgb(self:GetTierColor(tierIndex))
    self.popupAccent:SetColor(red, green, blue, 1)
    self.popupBG:SetEdgeColor(red, green, blue, 0.85)
    self.popupTier:SetColor(red, green, blue, 1)
    self.popupCount:SetColor(red, green, blue, 1)
end

function BC:EnqueuePopup(eventData)
    table.insert(self.popupQueue, eventData)
    if not self.popupQueueRunning then self:ProcessPopupQueue() end
end

function BC:ProcessPopupQueue()
    if #self.popupQueue == 0 then
        self.popupQueueRunning = false
        return
    end

    self.popupQueueRunning = true
    local eventData = table.remove(self.popupQueue, 1)
    self:ShowPopup(eventData)
    zo_callLater(function() self:ProcessPopupQueue() end, self.SV.popupDuration)
end

function BC:ShowPopup(eventData)
    if self.SV.popupMovable then return end
    if self.popupTimeline and self.popupTimeline:IsPlaying() then self.popupTimeline:Stop() end

    self.popupShowing = true
    self.popupTier:SetText(string.upper(eventData.tierLabel))
    self.popupCount:SetText(tostring(eventData.count))
    self.popupLabel:SetText(eventData.message)
    self:SetPopupTierColor(eventData.tierIndex)
    self.popupCtrl:SetHidden(false)

    local duration = self.SV.popupDuration
    local timeline = ANIMATION_MANAGER:CreateTimeline()
    local fadeIn = timeline:InsertAnimation(ANIMATION_ALPHA, self.popupCtrl, 0)
    fadeIn:SetDuration(150)
    fadeIn:SetAlphaValues(0, 1)
    fadeIn:SetEasingFunction(ZO_EaseOutQuadratic)

    local scaleIn = timeline:InsertAnimation(ANIMATION_SCALE, self.popupCtrl, 0)
    scaleIn:SetDuration(180)
    scaleIn:SetScaleValues(0.94, 1)
    scaleIn:SetEasingFunction(ZO_EaseOutQuadratic)

    local fadeOut = timeline:InsertAnimation(ANIMATION_ALPHA, self.popupCtrl, math.max(300, duration - 220))
    fadeOut:SetDuration(220)
    fadeOut:SetAlphaValues(1, 0)
    fadeOut:SetEasingFunction(ZO_EaseInQuadratic)

    timeline:SetHandler("OnStop", function()
        self.popupShowing = false
        self.popupCtrl:SetAlpha(1)
        self.popupCtrl:SetScale(1)
        if not self.SV.popupMovable then self.popupCtrl:SetHidden(true) end
    end)
    self.popupTimeline = timeline
    timeline:PlayFromStart()

    if self.SV.popupSound then PlaySound(SOUNDS.LEVEL_UP) end
end

function BC:AddHistory(eventData)
    table.insert(self.history, 1, eventData)
    while #self.history > self.SV.historyLimit do table.remove(self.history) end
    self:RefreshFeed()
end

function BC:ClearHistory()
    ZO_ClearNumericallyIndexedTable(self.history)
    self:RefreshFeed()
end

function BC:GetFeedRow(index)
    if self.feedRowPool[index] then return self.feedRowPool[index] end

    local row = WINDOW_MANAGER:CreateControlFromVirtual(
        "BT_HistoryContainer_Row" .. index,
        self.historyRows,
        "BT_HistoryRow"
    )
    if index == 1 then
        row:SetAnchor(TOPLEFT, self.historyRows, TOPLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, self.historyRows, TOPRIGHT, 0, 0)
    else
        row:SetAnchor(TOPLEFT, self.feedRowPool[index - 1], BOTTOMLEFT, 0, 3)
        row:SetAnchor(TOPRIGHT, self.feedRowPool[index - 1], BOTTOMRIGHT, 0, 3)
    end
    self.feedRowPool[index] = row
    return row
end

function BC:RefreshFeed()
    if not self.historyCtrl or not self.SV then return end
    local visibleCount = math.min(#self.history, self.SV.historyLimit)

    for index = 1, math.max(visibleCount, #self.feedRowPool) do
        local row = self:GetFeedRow(index)
        local eventData = self.history[index]
        if index <= visibleCount and eventData then
            local red, green, blue = HexToRgb(eventData.tierColor)
            row:GetNamedChild("_Accent"):SetColor(red, green, blue, 1)
            row:GetNamedChild("_Count"):SetText(tostring(eventData.count))
            row:GetNamedChild("_Count"):SetColor(red, green, blue, 1)
            row:GetNamedChild("_Time"):SetText(self.SV.showTimestamps and eventData.time or "")
            row:GetNamedChild("_Message"):SetText(eventData.message)
            row:GetNamedChild("_Message"):SetFont(string.format("%s|%d|soft-shadow-thin", "$(CHAT_FONT)", self.SV.feedTextSize))
            row:GetNamedChild("_BG"):SetCenterColor(0.02, 0.02, 0.02, math.min(0.8, self.SV.feedOpacity + 0.08))
            row:SetHidden(false)
        else
            row:SetHidden(true)
        end
    end

    local height = 42 + (visibleCount * 47) + 8
    self.historyCtrl:SetHeight(math.max(64, height))
    local hiddenByOutput = not self.SV.outputFeed and not self.SV.unlocked
    self.historyCtrl:SetHidden(hiddenByOutput or (visibleCount == 0 and not self.SV.unlocked))
end
