-- BombCounter.lua

-- Global MoveStop handlers for XML
function BT_HistoryContainer_MoveStop() BombCounter:SaveHistoryPos() end
function BT_BombPopup_MoveStop()    BombCounter:SavePopupPos()    end

local BC = {}
_G.BombCounter = BC

-- alias for SavedVars
local SV

-- In-memory state
BC.streaks           = {}   -- srcName → { timestamps }
BC.lastEventTimes    = {}   -- "src:tgt" → timestamp of last counted event
BC.history           = {}   -- history lines
BC.popupQueue        = {}   -- queued popups
BC.popupQueueRunning = false
BC._savedPopupText   = nil

-- SavedVars defaults (now includes bombScope)
local defaults = {
  unlocked        = false,
  bombWindowMs    = 2000,
  bombThreshold   = 5,
  bombScope       = "all",    -- "self", "party", or "all"
  historyLimit    = 10,
  popupDuration   = 3000,
  historyX        = 20,
  historyY        = 200,
  popupX          = 300,
  popupY          = 60,
  popupMovable    = false,
}

-- Utility: strip trailing ^Mx/^Fx color codes
local function NormalizeName(name)
  if type(name) ~= "string" or name == "" then return nil end
  return name:gsub("%^M[xX]$", ""):gsub("%^F[xX]$", "")
end

-- Enqueue / process popups
function BC:EnqueuePopup(msg)
  table.insert(self.popupQueue, msg)
  if not self.popupQueueRunning then
    self:ProcessPopupQueue()
  end
end

function BC:ProcessPopupQueue()
  if #self.popupQueue == 0 then
    self.popupQueueRunning = false
    return
  end
  self.popupQueueRunning = true
  local msg = table.remove(self.popupQueue, 1)
  self:ShowPopup(msg)
  zo_callLater(function() self:ProcessPopupQueue() end, SV.popupDuration)
end

-- Persist panel positions
function BC:SaveHistoryPos()
  if not self.historyCtrl then return end
  SV.historyX = self.historyCtrl:GetLeft()
  SV.historyY = self.historyCtrl:GetTop()
end

function BC:SavePopupPos()
  if not self.popupCtrl then return end
  SV.popupX = self.popupCtrl:GetLeft()
  SV.popupY = self.popupCtrl:GetTop()
end

-- Toggle history panel drag mode
function BC:ToggleLock(on)
  self.historyBG:SetHidden(not on)
  self.historyCtrl:SetMovable(on)
  self.historyCtrl:SetMouseEnabled(on)
  if not on then BC:SaveHistoryPos() end
  SV.unlocked = on
end

-- Toggle popup panel drag mode
function BC:TogglePopupDrag(on)
  self.popupCtrl:SetMovable(on)
  self.popupCtrl:SetMouseEnabled(on)
  self.popupBG:SetHidden(not on)
  self.popupCtrl:SetHidden(not on)
  self.popupLabel:SetMouseEnabled(false)

  if on then
    BC._savedPopupText = self.popupLabel:GetText()
    self.popupLabel:SetText("Click and drag me to reposition!")
  else
    if BC._savedPopupText then
      self.popupLabel:SetText(BC._savedPopupText)
      BC._savedPopupText = nil
    end
    BC:SavePopupPos()
  end
  SV.popupMovable = on
end

-- Initialization on addon load
function BC:OnAddOnLoaded(_, addonName)
  if addonName ~= "BombCounter" then return end
  EVENT_MANAGER:UnregisterForEvent("BombCounter", EVENT_ADD_ON_LOADED)

  -- 1) Load SavedVars
  SV = ZO_SavedVars:NewAccountWide("BombCounterSV", 1, nil, defaults)
  SV.bombThreshold = tonumber(SV.bombThreshold) or defaults.bombThreshold
  SV.bombWindowMs  = tonumber(SV.bombWindowMs)  or defaults.bombWindowMs
  SV.bombScope     = SV.bombScope or "all"

  -- 2) Grab XML controls
  BC.historyCtrl  = BT_HistoryContainer
  BC.historyBG    = BT_HistoryContainer_BG
  BC.historyLabel = BT_HistoryContainer_HistoryLabel
  BC.popupCtrl    = BT_BombPopup
  BC.popupBG      = BT_BombPopup_BG
  BC.popupLabel   = BT_BombPopupLabel

  -- 3) Restore anchors & states
  BC.historyCtrl:ClearAnchors()
  BC.historyCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, SV.historyX, SV.historyY)
  BC.popupCtrl:ClearAnchors()
  BC.popupCtrl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, SV.popupX, SV.popupY)
  BC:ToggleLock(SV.unlocked)
  BC:TogglePopupDrag(SV.popupMovable)

  -- 4) Slash commands
  SLASH_COMMANDS["/bombtest"] = function() BC:TestBomb() end
  SLASH_COMMANDS["/bombmenu"] = function()
    InterfaceOptionsFrame_OpenToCategory("BombCounter")
  end

  -- 5) Register kill-feed handler
  EVENT_MANAGER:RegisterForEvent(
    "BombCounter",
    EVENT_PVP_KILL_FEED_DEATH,
    function(...) BC:OnKillFeed(...) end
  )

  -- 6) Settings menu
  if LibAddonMenu2 then BC:CreateSettingsMenu(LibAddonMenu2) end
end
EVENT_MANAGER:RegisterForEvent(
  "BombCounter",
  EVENT_ADD_ON_LOADED,
  function(...) BC:OnAddOnLoaded(...) end
)

-- Refactored OnKillFeed: scope filter, de-dupe, sliding window, EventManager scheduling
function BC:OnKillFeed(_, killLocation,
                      srcDisp, srcChar, srcAlliance, srcRank,
                      tgtDisp, tgtChar, tgtAlliance, tgtRank)
  -- normalize
  local src = (srcChar ~= "" and NormalizeName(srcChar)) or srcDisp or "<unknown>"
  local tgt = (tgtChar ~= "" and NormalizeName(tgtChar)) or tgtDisp or "<unknown>"

  -- 1) scope filtering
  if SV.bombScope == "self" then
    if src ~= NormalizeName(GetUnitName("player")) then return end
  elseif SV.bombScope == "party" then
    local inParty = false
    for i = 1, GetGroupSize() do
      local tag = GetGroupUnitTagByIndex(i)
      if NormalizeName(GetUnitName(tag)) == src then
        inParty = true break
      end
    end
    if not inParty then return end
  end

  -- 2) de-duplicate same src→tgt within window
  local now = GetGameTimeMilliseconds()
  local key = src .. ":" .. tgt
  if self.lastEventTimes[key] and now - self.lastEventTimes[key] < SV.bombWindowMs then
    return
  end
  self.lastEventTimes[key] = now

  -- 3) record timestamp
  local list = self.streaks[src] or {}
  table.insert(list, now)
  -- purge old
  local cutoff = now - SV.bombWindowMs
  while list[1] and list[1] < cutoff do
    table.remove(list, 1)
  end
  self.streaks[src] = list

  -- 4) threshold hit: cancel & reschedule via EventManager
  if #list >= SV.bombThreshold then
    local updateName = "BombCounter_Update_" .. src
    EVENT_MANAGER:UnregisterForUpdate(updateName)
    local hex      = ({ [1]="EFD93D",[2]="DE5B4E",[3]="4F81BD" })[srcAlliance] or "FFFFFF"
    local captured = #list
    local msg      = string.format("|c%s%s|r made a %d-kill Bomb!", hex, src, captured)
    EVENT_MANAGER:RegisterForUpdate(
      updateName,
      SV.bombWindowMs,
      function()
        BC:AddHistory(msg)
        CHAT_SYSTEM:AddMessage(msg)
        BC:EnqueuePopup(msg)
        BC.streaks[src] = {}
        EVENT_MANAGER:UnregisterForUpdate(updateName)
      end
    )
  end
end

-- Manual test
function BC:TestBomb()
  local name   = NormalizeName(GetUnitName("player")) or "You"
  local all    = GetUnitAlliance("player")
  local hex    = ({ [1]="EFD93D",[2]="DE5B4E",[3]="4F81BD" })[all] or "FFFFFF"
  local msg    = string.format("|c%s%s|r made a %d-kill Bomb!", hex, name, SV.bombThreshold)
  BC:AddHistory(msg)
  CHAT_SYSTEM:AddMessage(msg)
  BC:EnqueuePopup(msg)
end

-- Show popup
function BC:ShowPopup(text)
  self.popupLabel:SetText(text)
  self.popupCtrl:SetHidden(false)
  zo_callLater(function() self.popupCtrl:SetHidden(true) end, SV.popupDuration)
end

-- Add to history
function BC:AddHistory(text)
  table.insert(self.history, 1, text)
  if #self.history > SV.historyLimit then table.remove(self.history) end
  self.historyLabel:SetText(table.concat(self.history, "\n"))
  self.historyCtrl:SetHeight(SV.historyLimit * 20 + 20)
end

-- Settings menu
function BC:CreateSettingsMenu(LAM)
  local panel = {
    type               = "panel",
    name               = "BombCounter",
    displayName        = "Bomb Counter",
    author             = "Alphatrazz",
    version            = "0.1.0",
    registerForRefresh = true,
  }
  LAM:RegisterAddonPanel("BC_Panel", panel)
  LAM:RegisterOptionControls("BC_Panel", {
    {
      type="dropdown", name="Kill Scope",
      choices  = {"Self","Party","All"},
      getFunc  = function()
        return ({ self="Self", party="Party", all="All" })[SV.bombScope]
      end,
      setFunc  = function(v)
        SV.bombScope = ({ Self="self", Party="party", All="all" })[v]
      end,
      width    = "half",
    },
    {
      type="checkbox", name="Unlock History Panel",
      getFunc = function() return SV.unlocked end,
      setFunc = function(v) BC:ToggleLock(v) end,
    },
    {
      type="button", name="Toggle Popup Move",
      func    = function() BC:TogglePopupDrag(not SV.popupMovable) end,
    },
    {
      type="slider", name="Bomb Popup window (ms)", min=500, max=10000, step=100,
      getFunc = function() return SV.bombWindowMs end,
      setFunc = function(v) SV.bombWindowMs = v end,
    },
    {
      type="slider", name="Bomb threshold", min=2, max=20, step=1,
      getFunc = function() return SV.bombThreshold end,
      setFunc = function(v) SV.bombThreshold = v end,
    },
    {
      type="slider", name="History size", min=1, max=50, step=1,
      getFunc = function() return SV.historyLimit end,
      setFunc = function(v) SV.historyLimit = v; BC:AddHistory("") end,
    },
  })
end
