-- ItemRack Forever: the look of the addon, the game's own interface (like ItemRack):
-- dialog and tooltip backdrops, the game's buttons, check boxes, scroll bars and fonts,
-- the action button look for items, and ItemRack's own button textures.
-- The rest of the addon only goes through these functions.
local ADDON, ns = ...

local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local BUTTONS = MEDIA .. "ItemRackButtons"
S.MEDIA = MEDIA
S.WHITE = WHITE
S.BUTTONS = BUTTONS
S.ICON = MEDIA .. "icon"

-- Colours (the game's) ---------------------------------------------------------------
local C = {
  text  = { 1, 1, 1, 1 }, -- GameFontHighlight
  gold  = { 1, 0.82, 0, 1 }, -- GameFontNormal
  title = { 1, 0.82, 0, 1 },
  muted = { 0.65, 0.65, 0.65, 1 },
  dim   = { 0.5, 0.5, 0.5, 1 }, -- GameFontDisable
  good  = { 0.1, 1, 0.1, 1 },
  bad   = { 1, 0.1, 0.1, 1 },
  bank  = { 0.3, 0.5, 1, 1 },
  trim  = { 0.3, 0.3, 0.3, 1 }, -- border grey
  ring  = { 0.5, 0.5, 0.5, 1 },
  well  = { 0, 0, 0, 1 },
}
S.C = C

local function color(t, a) return t[1], t[2], t[3], a or t[4] end
S.Color = color

-- gradient: c1 -> c2, top to bottom (or left to right when horizontal)
local function gradient(tex, c1, c2, horizontal, keepTexture)
  if not keepTexture then tex:SetTexture(WHITE) end
  tex:SetVertexColor(1, 1, 1, 1)
  local o = horizontal and "HORIZONTAL" or "VERTICAL"
  local a, b = c1, c2
  if not horizontal then a, b = c2, c1 end -- VERTICAL runs bottom -> top
  if tex.SetGradient then
    local function col(c) return { r = c[1], g = c[2], b = c[3], a = c[4] or 1 } end
    if pcall(tex.SetGradient, tex, o, col(a), col(b)) then return end
  end
  if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, o,
    a[1], a[2], a[3], a[4] or 1, b[1], b[2], b[3], b[4] or 1) then return end
  tex:SetVertexColor(color(c1))
end
S.Gradient = gradient

-- Tweens (only fades are left: button transparency, the menu) -------------------------
local tweens, running = {}, {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
  wipe(running)
  for key, t in pairs(tweens) do running[key] = t end
  for key, t in pairs(running) do
    if tweens[key] == t then
      t.t = t.t + elapsed
      local p = math.min(1, t.t / t.dur)
      t.set(t.from + (t.to - t.from) * p, p)
      if p >= 1 and tweens[key] == t then
        tweens[key] = nil
        if t.done then t.done() end
      end
    end
  end
  if not next(tweens) then self:Hide() end
end)

-- S.Tween(key, { dur, from, to, set(value, p), done }); same key replaces the running one
function S.Tween(key, a)
  a.t, a.dur = 0, a.dur or 0.25
  tweens[key] = a
  driver:Show()
end
function S.StopTween(key) tweens[key] = nil end
function S.IsTweening(key) return tweens[key] ~= nil end
function S.FadeTo(region, alpha, dur, done)
  S.Tween(region, { dur = dur or 0.15, from = region:GetAlpha(), to = alpha,
    set = function(v) region:SetAlpha(v) end, done = done })
end

-- Fonts: the game's font objects ------------------------------------------------------
function S.Font(size, flags)
  size = size or 12
  if flags and flags:find("OUTLINE") then return NumberFontNormal end
  if size >= 14 then return GameFontNormalLarge end
  if size <= 10 then return GameFontHighlightSmall end
  return GameFontHighlight
end
local font = S.Font

function S.Text(parent, size, col, layer, flags)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(font(size, flags))
  fs:SetTextColor(color(type(col) == "table" and col or C[col or "text"]))
  fs:SetJustifyH("LEFT")
  return fs
end

-- one line of text that fits a width (cut by the game)
function S.FitText(fs, maxWidth)
  fs:SetWordWrap(false)
  fs:SetWidth(0)
  if fs:GetStringWidth() > maxWidth then fs:SetWidth(maxWidth) end
end

-- Backdrops ---------------------------------------------------------------------------
local BACKDROPS = {
  -- the options window (ItemRackOptFrame)
  window = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } },
  -- the bind frame, the script editor
  dialog = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } },
  -- the popout menu
  menu = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } },
  -- subframes and the lists inside them: a border, the fill is a gradient texture
  border = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 },
  -- a text box (multi-line edit)
  field = { bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 9, insets = { left = 3, right = 3, top = 6, bottom = 6 } },
  slider = { bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } },
  -- the confirm dialog (StaticPopup)
  popup = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } },
}

function S.Backdrop(f, kind, borderGrey)
  if not f.SetBackdrop and BackdropTemplateMixin then
    Mixin(f, BackdropTemplateMixin)
    if f.OnBackdropSizeChanged then f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged) end
  end
  if not f.SetBackdrop then return f end
  f:SetBackdrop(BACKDROPS[kind] or BACKDROPS.window)
  if borderGrey then f:SetBackdropBorderColor(borderGrey, borderGrey, borderGrey) end
  if kind == "field" then f:SetBackdropColor(.1, .1, .1, 1) end
  f.backdropKind = kind
  return f
end

-- a panel: grey tooltip border, dark gradient inside (ItemRackOptSubFrameTemplate)
function S.Panel(f)
  S.Backdrop(f, "border", 0.3)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetPoint("TOPLEFT", 4, -4)
  fill:SetPoint("BOTTOMRIGHT", -4, 4)
  gradient(fill, { .25, .25, .25, 1 }, { .1, .1, .1, .5 })
  f.fill = fill
  return f
end

-- a list box inside a panel (event list, icons, sort list)
function S.Well(f)
  S.Backdrop(f, "border", 0.3)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetPoint("TOPLEFT", 4, -4)
  fill:SetPoint("BOTTOMRIGHT", -4, 4)
  gradient(fill, { .1, .1, .1, 1 }, { 0, 0, 0, 1 })
  f.fill = fill
  return f
end

-- older names kept for the callers
function S.Rounded(f) return S.Backdrop(f, "window") end
function S.Box(f) return S.Well(f) end
function S.SetRoundedShown(f, shown)
  if not f.SetBackdropColor then return end
  f:SetBackdropColor(1, 1, 1, shown and 1 or 0)
  f:SetBackdropBorderColor(.3, .3, .3, shown and 1 or 0)
end
function S.Shadow() end
function S.EdgeGlow() end
function S.HoverFade() end

-- the gold list highlight (ItemRack's lists): shown on hover and while selected
function S.RowHighlight(row)
  local hl = row:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
  gradient(hl, { .75, .63, .1, .5 }, { .75, .75, .75, 1 }, true, true)
  hl:Hide()
  row.highlight = hl
  local function update() hl:SetShown(row.locked or row.hovered) end
  row:HookScript("OnEnter", function() row.hovered = true; update() end)
  row:HookScript("OnLeave", function() row.hovered = nil; update() end)
  function row:SetLocked(on)
    self.locked = on and true or nil
    update()
  end
  return hl
end

-- Windows -----------------------------------------------------------------------------
function S.AnimateOpen(f) f:SetAlpha(1) end
function S.Close(f) f:Hide() end

-- Tooltips ----------------------------------------------------------------------------
function S.Tooltip(frame, title, body, anchor)
  frame:HookScript("OnEnter", function(self)
    if ns.ShowTooltips and not ns.ShowTooltips() then return end
    local t, b = title, body
    if type(t) == "function" then t, b = t(self) end
    if not t then return end
    GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
    GameTooltip:AddLine(t, 1, 1, 1)
    if b then GameTooltip:AddLine(b, 1, 0.82, 0, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Buttons -----------------------------------------------------------------------------
local grayTemplate
local function panelButton(parent)
  if grayTemplate == nil then
    grayTemplate = pcall(CreateFrame, "Button", nil, UIParent, "UIPanelButtonGrayTemplate") and "UIPanelButtonGrayTemplate" or false
  end
  return CreateFrame("Button", nil, parent, grayTemplate or "UIPanelButtonTemplate")
end

-- ItemRackOptButtonTemplate (grey panel button), or the gold one for the main actions
function S.Button(parent, text, width, height, onClick, primary)
  local b = primary and CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") or panelButton(parent)
  b:SetSize(width or 110, height or 22)
  b:SetNormalFontObject(GameFontHighlightSmall)
  b:SetHighlightFontObject(GameFontHighlightSmall)
  b:SetDisabledFontObject(GameFontDisableSmall)
  b:SetText(text or "")
  b.text = b:GetFontString()
  b:SetMotionScriptsWhileDisabled(true)
  b:SetScript("OnClick", function(self, ...)
    PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    if onClick then onClick(self, ...) end
  end)
  return b
end

-- ItemRack's small buttons (ItemRackButtons texture): normal, pushed, disabled coords
local GLYPHS = {
  Lock = { { .75, .875, .125, .25 }, { .875, 1, .125, .25 } },
  Queue = { { 0, .125, .5, .625 }, { .125, .25, .5, .625 } },
  Options = { { .75, .875, .25, .375 }, { .875, 1, .25, .375 } },
  Close = { { .375, .5, .25, .375 }, { .5, .625, .25, .375 } },
  Down = { { .375, .5, .125, .25 }, { .5, .625, .125, .25 }, { .625, .75, .125, .25 } },
  Up = { { 0, .125, .125, .25 }, { .125, .25, .125, .25 }, { .25, .375, .125, .25 } },
  Top = { { .375, .5, 0, .125 }, { .5, .625, 0, .125 }, { .625, .75, 0, .125 } },
  Bottom = { { 0, .125, .25, .375 }, { .125, .25, .25, .375 }, { .25, .375, .25, .375 } },
  Delete = { { 0, .125, .375, .5 }, { .125, .25, .375, .5 }, { .25, .375, .375, .5 } },
  ToggleAll = { { .75, .875, .375, .5 }, { .875, 1, .375, .5 } },
  Grip = { { .75, .875, 0, .125 }, { .75, .875, 0, .125 } },
}
-- the names the rest of the addon used
GLYPHS.Cog, GLYPHS.Sliders, GLYPHS.Cross, GLYPHS.Dot = GLYPHS.Queue, GLYPHS.Options, GLYPHS.Close, GLYPHS.ToggleAll

local function glyphTexture(b, setter, coords)
  if not coords then return end
  b[setter](b, BUTTONS)
  local t = (setter == "SetNormalTexture" and b:GetNormalTexture()) or (setter == "SetPushedTexture" and b:GetPushedTexture())
    or (setter == "SetDisabledTexture" and b:GetDisabledTexture()) or b:GetHighlightTexture()
  t:SetTexCoord(unpack(coords))
  return t
end

-- ItemRackSmallButtonTemplate: glyph = a name above (Arrow + rotation pi = Down,
-- ArrowBar + rotation pi = Bottom)
function S.GlyphButton(parent, glyph, size, onClick, rotation)
  if glyph == "Arrow" then glyph = (rotation and rotation > 1) and "Down" or "Up" end
  if glyph == "ArrowBar" then glyph = (rotation and rotation > 1) and "Bottom" or "Top" end
  local g = GLYPHS[glyph] or GLYPHS.Close
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 16, size or 16)
  b.glyph = glyphTexture(b, "SetNormalTexture", g[1])
  glyphTexture(b, "SetPushedTexture", g[2])
  glyphTexture(b, "SetDisabledTexture", g[3])
  local hl = glyphTexture(b, "SetHighlightTexture", { .25, .375, 0, .125 })
  hl:SetBlendMode("ADD")
  if onClick then
    b:SetScript("OnClick", function(self, ...)
      PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
      onClick(self, ...)
    end)
  end
  b:SetMotionScriptsWhileDisabled(true)
  function b:SetGlyphColor(col) self.glyph:SetVertexColor(color(col)) end
  -- a button without a disabled texture greys out
  if not g[3] then
    hooksecurefunc(b, "Disable", function(self) self.glyph:SetDesaturated(true) end)
    hooksecurefunc(b, "Enable", function(self) self.glyph:SetDesaturated(false) end)
  end
  return b
end

-- the small close button of the windows (ItemRackOptClose)
function S.CloseButton(parent, onClick)
  local b = S.GlyphButton(parent, "Close", 16, onClick or function() parent:Hide() end)
  return b
end

-- Items: the action button look (ActionButtonTemplate) ---------------------------------
-- plain = only the icon and the square highlight (ItemRackOptIconTemplate)
function S.SkinItemButton(b, name, plain)
  local w = b:GetWidth()
  b.icon = b:CreateTexture(name and (name .. "Icon") or nil, "BACKGROUND")
  if plain then
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetHighlightTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
  else
    b.icon:SetAllPoints()
    b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local nt = b:GetNormalTexture()
    nt:ClearAllPoints()
    nt:SetPoint("CENTER", 0, -1)
    nt:SetSize(w * 66 / 36, w * 66 / 36)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if b.SetCheckedTexture then
      b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
      local ct = b:GetCheckedTexture()
      if ct then ct:SetBlendMode("ADD") end
    end
  end
  -- coloured edge: blue = in the bank, red = missing (nil: none)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  border:SetBlendMode("ADD")
  border:SetPoint("CENTER")
  border:SetSize(w * 62 / 36, w * 62 / 36)
  border:Hide()
  b.stateBorder = border
  function b:SetStateBorder(col)
    if col then
      self.stateBorder:SetVertexColor(color(col))
      self.stateBorder:Show()
    else
      self.stateBorder:Hide()
    end
  end
  return b
end

-- Check boxes (UICheckButtonTemplate) -------------------------------------------------
local function setCheckTextures(c)
  c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
end

function S.Check(parent, label, size, onClick)
  size = size or 24
  local c = CreateFrame("CheckButton", nil, parent)
  c:SetSize(size, size)
  setCheckTextures(c)
  c:SetMotionScriptsWhileDisabled(true)
  if onClick then c:SetScript("OnClick", onClick) end
  c:SetScript("PostClick", function(self)
    PlaySound(self:GetChecked() and (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
      or (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857))
  end)
  local setChecked = c.SetChecked
  function c:SetChecked(v) setChecked(self, v and true or false) end
  if label then
    c.text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    c.text:SetPoint("LEFT", c, "RIGHT", 0, 1)
    c.text:SetJustifyH("LEFT")
    function c:SetLabel(t)
      self.text:SetText(t)
      self.text:SetWidth(0)
      self:SetHitRectInsets(0, -self.text:GetStringWidth(), 0, 0)
    end
    function c:FitLabel(maxWidth)
      S.FitText(self.text, maxWidth)
      self:SetHitRectInsets(0, -math.min(self.text:GetStringWidth(), maxWidth), 0, 0)
    end
    c:SetLabel(label)
    hooksecurefunc(c, "Disable", function(self) self.text:SetTextColor(color(C.dim)) end)
    hooksecurefunc(c, "Enable", function(self) self.text:SetTextColor(color(C.text)) end)
  end
  return c
end

-- Slider (ItemRackOptSliderTemplate) --------------------------------------------------
function S.Slider(parent, width, min, max, step, fmt, label, onChange)
  local s = CreateFrame("Slider", nil, parent)
  S.Backdrop(s, "slider", 0.3)
  s:SetOrientation("HORIZONTAL")
  s:SetSize(width, 17)
  s:SetHitRectInsets(0, 0, -5, -5)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = s:GetThumbTexture()
  if thumb then thumb:SetSize(32, 32) end
  s:EnableMouseWheel(true)
  s.step, s.fmt = step, fmt or "%d"
  s.label = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  s.label:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
  s.label:SetText(label or "")
  s.value = s:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  s.value:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 2)
  local function snap(v) return math.floor(v / step + 0.5) * step end
  s:SetScript("OnValueChanged", function(self, value, userInput)
    value = snap(value)
    self.value:SetText(self.fmt:format(value))
    if not self.silent and onChange then onChange(value, userInput) end
  end)
  s:SetScript("OnMouseWheel", function(self, d)
    if not self:IsEnabled() then return end
    self:SetValue(math.max(min, math.min(max, self:GetValue() + d * step)))
  end)
  function s:SetValueSilently(v)
    self.silent = true
    self:SetValue(v)
    self.value:SetText(self.fmt:format(snap(v)))
    self.silent = nil
  end
  return s
end

-- Scroll bars (UIPanelScrollBarTemplate look) -----------------------------------------
local function arrow(parent, dir)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. dir .. "Button-"
  for setter, state in pairs({ SetNormalTexture = "Up", SetPushedTexture = "Down", SetDisabledTexture = "Disabled", SetHighlightTexture = "Highlight" }) do
    b[setter](b, base .. state)
  end
  for _, t in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetDisabledTexture(), b:GetHighlightTexture() }) do
    t:SetTexCoord(.2, .8, .25, .75)
  end
  b:GetHighlightTexture():SetBlendMode("ADD")
  return b
end

-- a bar: up button, slider, down button; bar.slider moves 0..max
local function scrollBar(parent)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(16)
  local up, down = arrow(bar, "Up"), arrow(bar, "Down")
  up:SetPoint("TOP")
  down:SetPoint("BOTTOM")
  local s = CreateFrame("Slider", nil, bar)
  s:SetOrientation("VERTICAL")
  s:SetPoint("TOP", up, "BOTTOM")
  s:SetPoint("BOTTOM", down, "TOP")
  s:SetWidth(16)
  s:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(16, 24)
  thumb:SetTexCoord(.2, .8, .125, .875)
  s:SetMinMaxValues(0, 0)
  s:SetValue(0)
  bar.slider, bar.up, bar.down = s, up, down
  local function refresh()
    local v = s:GetValue()
    local lo, hi = s:GetMinMaxValues()
    up:SetEnabled(v > lo)
    down:SetEnabled(v < hi)
  end
  bar.Refresh = refresh
  s:HookScript("OnValueChanged", refresh)
  return bar
end

-- faux scrolling of a list of rows: SetCount(n), GetOffset(), SetOffset(v); .bar to place
function S.FauxScroll(holder, visible, update, step)
  local o = { count = 0, visible = visible, offset = 0 }
  local bar = scrollBar(holder)
  local s = bar.slider
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    bar.Refresh()
    if v ~= o.offset then o.offset = v; update() end
  end)
  local function scrollBy(d)
    local _, hi = s:GetMinMaxValues()
    s:SetValue(math.max(0, math.min(hi, o.offset + d)))
  end
  bar.up:SetScript("OnClick", function() PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115); scrollBy(-(step or 1)) end)
  bar.down:SetScript("OnClick", function() PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115); scrollBy(step or 1) end)
  holder:EnableMouseWheel(true)
  holder:SetScript("OnMouseWheel", function(_, d) scrollBy(-d * (step or 1)) end)
  o.bar = bar
  function o:SetCount(n)
    self.count = n
    local hi = math.max(0, n - self.visible)
    s:SetMinMaxValues(0, hi)
    bar:SetShown(hi > 0)
    if self.offset > hi then self.offset = hi end
    s:SetValue(self.offset)
    bar.Refresh()
  end
  function o:GetOffset() return self.offset end
  function o:SetOffset(v)
    local _, hi = s:GetMinMaxValues()
    v = math.max(0, math.min(hi, v))
    self.offset = v
    s:SetValue(v)
  end
  return o
end

-- a real scroll frame with the bar; returns the scroll frame and its child
function S.Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)
  local bar = scrollBar(parent)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
  local s = bar.slider
  s:SetScript("OnValueChanged", function(_, v)
    sf:SetVerticalScroll(v)
    bar.Refresh()
  end)
  local function sync()
    local range = sf:GetVerticalScrollRange() or 0
    s:SetMinMaxValues(0, range)
    s:SetValue(math.min(sf:GetVerticalScroll() or 0, range))
    bar:SetShown(range > 0)
    bar.Refresh()
  end
  sf:SetScript("OnScrollRangeChanged", sync)
  sf:SetScript("OnVerticalScroll", function(_, v) s:SetValue(v) end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, d)
    local _, hi = s:GetMinMaxValues()
    s:SetValue(math.max(0, math.min(hi, s:GetValue() - d * 20)))
  end)
  bar.up:SetScript("OnClick", function() s:SetValue(s:GetValue() - 14) end)
  bar.down:SetScript("OnClick", function() s:SetValue(s:GetValue() + 14) end)
  sf.bar = bar
  sf.Sync = sync
  return sf, content
end

-- Edit boxes --------------------------------------------------------------------------
-- style: nil = the game's input box, "number" = ItemRackNumberEditBoxTemplate,
-- "big" = ItemRackOptBigEditBoxTemplate
local function threePart(e, file, lw, h, lx, ly, rx, l1, l2, r1, r2)
  local left = e:CreateTexture(nil, "BACKGROUND")
  left:SetTexture(file)
  left:SetSize(lw, h)
  left:SetPoint("TOPLEFT", lx, ly)
  left:SetTexCoord(0, l1, 0, 1)
  local right = e:CreateTexture(nil, "BACKGROUND")
  right:SetTexture(file)
  right:SetSize(lw, h)
  right:SetPoint("TOPRIGHT", rx, ly)
  right:SetTexCoord(r1, 1, 0, 1)
  local mid = e:CreateTexture(nil, "BACKGROUND")
  mid:SetTexture(file)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
  mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
  mid:SetTexCoord(l2 or l1, r1, 0, 1)
end

function S.EditBox(parent, width, height, style)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, height or 20)
  e:SetAutoFocus(false)
  e:SetMaxLetters(255)
  if style == "number" then
    e:SetFontObject(GameFontHighlightSmall)
    threePart(e, "Interface\\ClassTrainerFrame\\UI-ClassTrainer-FilterBorder", 12, 29, -11, 2, 4, 0.09375, nil, 0.90625)
  elseif style == "big" then
    e:SetFontObject(GameFontHighlight)
    threePart(e, "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame", 25, 64, -26, 21, 22, 0.1953125, nil, 0.8046875)
  else
    e:SetFontObject(ChatFontNormal or GameFontHighlight)
    e:SetTextInsets(0, 0, 0, 0)
    local left = e:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\Common\\Common-Input-Border")
    left:SetSize(8, 20)
    left:SetPoint("LEFT", -5, 0)
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    local right = e:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\Common\\Common-Input-Border")
    right:SetSize(8, 20)
    right:SetPoint("RIGHT", 0, 0)
    right:SetTexCoord(0.9375, 1, 0, 0.625)
    local mid = e:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture("Interface\\Common\\Common-Input-Border")
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetTexCoord(0.0625, 0.9375, 0, 0.625)
  end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  hooksecurefunc(e, "Disable", function(self) self:SetTextColor(color(C.dim)) end)
  hooksecurefunc(e, "Enable", function(self) self:SetTextColor(color(C.text)) end)
  return e
end

-- multi-line edit box in a scroll frame, in a dark box; returns holder, editbox
function S.MultiEdit(parent)
  local holder = CreateFrame("Frame", nil, parent)
  S.Backdrop(holder, "field", 0.3)
  local sf, content = S.Scroll(holder)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -24, 6)
  sf.bar:ClearAllPoints()
  sf.bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -4, -5)
  sf.bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4, 5)
  local e = CreateFrame("EditBox", nil, content)
  e:SetMultiLine(true)
  e:SetAutoFocus(false)
  e:SetFontObject(GameFontHighlight)
  e:SetPoint("TOPLEFT")
  e:SetMaxLetters(0)
  sf:SetScrollChild(e)
  content:Hide()
  local function fitWidth() e:SetWidth(math.max(10, sf:GetWidth() - 2)) end
  sf:HookScript("OnSizeChanged", fitWidth)
  fitWidth()
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnCursorChanged", function(self, _, y, _, h)
    y = -y
    local top = sf:GetVerticalScroll()
    local view = sf:GetHeight()
    if y < top then sf:SetVerticalScroll(y)
    elseif y + h > top + view then sf:SetVerticalScroll(math.max(0, y + h - view)) end
  end)
  e:SetScript("OnTextChanged", function(self)
    sf:UpdateScrollChildRect()
    if self.onChange then self.onChange(self) end
  end)
  holder:EnableMouse(true)
  holder:SetScript("OnMouseDown", function() e:SetFocus() end)
  holder.edit = e
  holder.scroll = sf
  return holder, e
end

-- Drop-down (ItemRackOptDropDownTemplate): a label frame, ItemRack's arrow, a list --------
function S.Dropdown(parent, width, getOptions, getValue, onSelect)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
  threePart(b, "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame", 25, 64, -26, 21, 22, 0.1953125, nil, 0.8046875)
  b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  b.text:SetPoint("LEFT", 2, 0)
  b.text:SetPoint("RIGHT", -20, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  function b:SetText(t) self.text:SetText(t) end
  local arrowButton = S.GlyphButton(b, "Down", 18)
  arrowButton:SetPoint("RIGHT", 2, 0)
  b.arrow = arrowButton

  local menu
  local rows = {}
  local function close()
    if menu then menu:Hide() end
  end
  local function refreshLabel()
    local v = getValue()
    local text = ""
    for _, o in ipairs(getOptions()) do if o[1] == v then text = o[2] end end
    b:SetText(text)
  end
  local function open()
    if menu and menu:IsShown() then close() return end
    if not menu then
      menu = CreateFrame("Frame", nil, b)
      S.Backdrop(menu, "menu", 0.3)
      menu:SetFrameStrata("FULLSCREEN_DIALOG")
      menu:SetClampedToScreen(true)
      menu:EnableMouse(true)
      menu:Hide()
    end
    local options = getOptions()
    local menuWidth = width
    menu:SetSize(menuWidth, #options * 18 + 12)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", -6, -2)
    for i, o in ipairs(options) do
      local row = rows[i]
      if not row then
        row = CreateFrame("Button", nil, menu)
        row:SetHeight(18)
        S.RowHighlight(row)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row:SetScript("OnClick", function(self)
          PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
          close()
          onSelect(self.value)
          refreshLabel()
        end)
        rows[i] = row
      end
      row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
      row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 18)
      row.value = o[1]
      row.text:SetText(o[2])
      row:SetLocked(o[1] == getValue())
      row:Show()
      menuWidth = math.max(menuWidth, row.text:GetStringWidth() + 24)
    end
    menu:SetWidth(menuWidth)
    for i = #options + 1, #rows do rows[i]:Hide() end
    menu:Show()
  end
  b:SetScript("OnClick", open)
  arrowButton:SetScript("OnClick", open)
  b:SetScript("OnEnter", function() arrowButton:LockHighlight() end)
  b:SetScript("OnLeave", function() arrowButton:UnlockHighlight() end)
  b:HookScript("OnHide", close)
  function b:SetDropEnabled(on)
    self:SetEnabled(on)
    arrowButton:SetEnabled(on)
    self.text:SetTextColor(color(on and C.text or C.dim))
    if not on then close() end
  end
  b.Refresh = refreshLabel
  b.Close = close
  refreshLabel()
  return b
end

-- Confirm dialog (the game's popup) ---------------------------------------------------
-- S.Confirm(text, { {label, fn}, ... }); Escape = the last button
local dialog
function S.Confirm(text, buttons)
  if not dialog then
    dialog = CreateFrame("Frame", "ItemRackForeverConfirm", UIParent)
    dialog:SetSize(320, 100)
    dialog:SetPoint("TOP", UIParent, "TOP", 0, -135)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    S.Backdrop(dialog, "popup")
    dialog.text = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dialog.text:SetPoint("TOP", 0, -16)
    dialog.text:SetWidth(290)
    dialog.buttons = {}
    tinsert(UISpecialFrames, "ItemRackForeverConfirm")
    dialog:SetScript("OnHide", function(self) -- a button, or Escape (= the last button)
      local fn = self.pending or self.cancel
      self.pending, self.cancel = nil, nil
      if fn then fn() end
    end)
  end
  dialog.text:SetText(text)
  local n = #buttons
  local bw = n >= 3 and 90 or 128
  dialog:SetWidth(math.max(320, n * (bw + 12) + 30))
  dialog:SetHeight(dialog.text:GetStringHeight() + 62)
  for _, b in ipairs(dialog.buttons) do b:Hide() end
  for i, def in ipairs(buttons) do
    local b = dialog.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
      b:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857)
        dialog.pending = self.fn
        dialog:Hide()
      end)
      dialog.buttons[i] = b
    end
    b:SetSize(bw, 21)
    b:SetText(def[1])
    b.fn = def[2] or function() end
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", dialog, "BOTTOM", (i - (n + 1) / 2) * (bw + 12), 16)
    b:Show()
  end
  dialog.cancel = buttons[n][2] or function() end
  dialog.pending = nil
  dialog:Show()
  PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850)
end
