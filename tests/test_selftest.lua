-- tests/test_selftest.lua
-- ---------------------------------------------------------------------------
-- Prueft die Attrappe (tests/mock_wow.lua) selbst. Haengt von KEINER Addon-Datei
-- ab: es wird nur die Attrappe installiert, nie die TOC des Addons geladen.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- Hilfsfunktion: Fehlermeldung eines pcall
   local function errOf(fn)
      local ok, err = pcall(fn)
      if ok then return nil end
      return tostring(err)
   end

   -- Temporaeres Addon-Verzeichnis (fuer LoadToc-Tests)
   local function makeTempDir()
      local base = os.tmpname()
      os.remove(base)
      os.execute('mkdir -p "' .. base .. '"')
      return base
   end
   local function writeFile(path, text)
      local f = assert(io.open(path, "wb"))
      f:write(text)
      f:close()
   end
   local function removeDir(dir)
      os.execute('rm -rf "' .. dir .. '"')
   end

   -- ======================================================================
   H.section("Install und Umgebung")
   -- ======================================================================

   H.test("Install entfernt vom Addon angelegte Globals und baut Standard-Frames neu", function()
      _G.Transmog = { x = 1 }
      _G.TransmogDB = {}
      _G.SomeStray = 5
      M.Install()
      H.eq(_G.Transmog, nil)
      H.eq(_G.TransmogDB, nil)
      H.eq(_G.SomeStray, nil)
      H.truthy(_G.UIParent, "UIParent")
      H.truthy(_G.GameTooltip, "GameTooltip")
      H.eq(_G.GameTooltip:GetObjectType(), "GameTooltip")
      H.truthy(_G.GossipFrame, "GossipFrame")
      H.eq(_G.UIParent:GetWidth(), 1365)
      H.eq(_G.UIParent:GetHeight(), 768)
      H.eq(GetScreenWidth(), 1365)
      H.eq(GetScreenHeight(), 768)
   end)

   H.test("Install(opts) mischt world/items/globals", function()
      M.Install({
         world = { locale = "deDE", playerName = "Hans", equipment = { [1] = 100 }, screenWidth = 1920 },
         items = { [100] = { name = "Helm", quality = 4 } },
         globals = { TransmogDB = { a = 1 } },
      })
      H.eq(GetLocale(), "deDE")
      H.eq(UnitName("player"), "Hans")
      H.eq(GetScreenWidth(), 1920)
      H.eq(M.world.equipment[1], 100)
      H.eq(M.items[100].name, "Helm")
      H.eq(TransmogDB.a, 1)
      -- zweites Install setzt alles zurueck
      M.Install()
      H.eq(GetLocale(), "enUS")
      H.eq(TransmogDB, nil)
      H.eq(M.items[100], nil)
   end)

   H.test("nicht in 3.3.5a vorhandene Globals fehlen", function()
      for _, n in ipairs({ "C_Timer", "Mixin", "CreateFromMixins", "GetItemInfoInstant", "tostringall",
                           "BackdropTemplateMixin", "RegisterAddonMessagePrefix", "C_Item", "GetNumFriends" }) do   -- lint:allow(no-api)
         H.eq(_G[n], nil, n)
      end
   end)

   H.test("RegisterAddonMessagePrefix nur mit world.hasRegisterAddonMessagePrefix", function()
      M.Install({ world = { hasRegisterAddonMessagePrefix = true } })
      H.eq(type(RegisterAddonMessagePrefix), "function")
      H.truthy(RegisterAddonMessagePrefix("transmog"))
      H.truthy(M.registeredPrefixes.transmog)
   end)

   H.test("Lua-Aliase und WoW-String-Helfer verhalten sich wie im Client", function()
      -- strsplit: Trennzeichen sind einzelne Zeichen
      H.deepEq({ strsplit(":", "a:b:c") }, { "a", "b", "c" })
      H.deepEq({ strsplit(":", "a::b") }, { "a", "", "b" })
      H.deepEq({ strsplit(":", "a:b:c", 2) }, { "a", "b:c" })
      H.deepEq({ strsplit(",:", "a,b:c") }, { "a", "b", "c" })
      H.deepEq({ strsplit(":", "") }, { "" })
      H.deepEq({ strsplit(":", "abc") }, { "abc" })
      H.eq(strjoin(",", "a", 2, "c"), "a,2,c")
      H.throws(function() strjoin(",", "a", nil) end, "bad argument")
      H.eq(strtrim("  hi \n"), "hi")
      H.eq(strtrim("xxhixx", "x"), "hi")
      H.eq(strconcat("a", 1, "b"), "a1b")
      H.eq(mod(7, 3), 1)
      H.eq(mod(-7, 3), -1)       -- math.fmod: Vorzeichen des Dividenden
      H.eq(floor(2.7), 2)
      H.eq(format("%05.1f", 3.14159), "003.1")
      local t = { 1, 2, 3, x = 1 }
      H.eq(wipe(t), t)
      H.eq(next(t), nil)
      local list = {}
      tinsert(list, "a")
      tinsert(list, 1, "b")
      H.deepEq(list, { "b", "a" })
      H.eq(tremove(list, 1), "b")
      H.eq(date("%Y") ~= nil, true)
      H.eq(type(time()), "number")
      H.eq(getglobal("UIParent"), UIParent)
      setglobal("TransmogProbe", 7)
      H.eq(_G.TransmogProbe, 7)
   end)

   H.test("Zugriffe liefern 1/nil statt true/false (wie 3.3.5a)", function()
      local f = CreateFrame("Frame")
      H.eq(f:IsShown(), 1)
      H.eq(f:IsVisible(), 1)
      f:Hide()
      H.eq(f:IsShown(), nil)
      local b = CreateFrame("Button")
      H.eq(b:IsEnabled(), 1)
      b:Disable()
      H.eq(b:IsEnabled(), nil)
      local c = CreateFrame("CheckButton")
      H.eq(c:GetChecked(), nil)
      c:SetChecked(true)
      H.eq(c:GetChecked(), 1)
      H.eq(IsShiftKeyDown(), nil)
      M.world.shift = true
      H.eq(IsShiftKeyDown(), 1)
   end)

   -- ======================================================================
   H.section("Strenge API")
   -- ======================================================================

   H.test("nur Retail-API wirft 'API not in 3.3.5a: Typ:Methode'", function()
      local f = CreateFrame("Frame")
      local tex = f:CreateTexture()
      local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      local btn = CreateFrame("Button", nil, f)
      local cases = {
         { function() f:SetSize(10, 10) end, "API not in 3.3.5a: Frame:SetSize" },   -- lint:allow(no-api)
         { function() f:SetShown(true) end, "API not in 3.3.5a: Frame:SetShown" },   -- lint:allow(no-api)
         { function() f:GetRect() end, "API not in 3.3.5a: Frame:GetRect" },   -- lint:allow(no-api)
         { function() tex:SetColorTexture(1, 1, 1) end, "API not in 3.3.5a: Texture:SetColorTexture" },   -- lint:allow(no-api)
         { function() fs:SetWordWrap(false) end, "API not in 3.3.5a: FontString:SetWordWrap" },   -- lint:allow(no-api)
         { function() fs:SetMaxLines(1) end, "API not in 3.3.5a: FontString:SetMaxLines" },   -- lint:allow(no-api)
         { function() btn:SetEnabled(true) end, "API not in 3.3.5a: Button:SetEnabled" },
         { function() btn:SetTextColor(1, 1, 1) end, "API not in 3.3.5a: Button:SetTextColor" },
         { function() f:SetIgnoreParentScale(true) end, "API not in 3.3.5a: Frame:SetIgnoreParentScale" },
         { function() tex:SetScript("OnEnter", function() end) end, "API not in 3.3.5a: Texture:SetScript" },
         { function() fs:EnableMouse(true) end, "API not in 3.3.5a: FontString:EnableMouse" },
         { function() f:SetFormattedText() end, "API not in 3.3.5a: Frame:SetFormattedText" },
      }
      for i, c in ipairs(cases) do
         local e = errOf(c[1])
         H.truthy(e and e:find(c[2], 1, true), "case " .. i .. ": " .. tostring(e))
      end
   end)

   H.test("Feldzugriffe (klein) liefern nil, grossgeschriebene unbekannte Namen werfen", function()
      local f = CreateFrame("Frame")
      H.eq(f.label, nil)
      H.eq(f.someField, nil)
      f.label = "x"
      H.eq(f.label, "x")
      -- vom Addon selbst angelegte Methoden funktionieren
      function f:Layout() return 42 end
      H.eq(f:Layout(), 42)
      -- noch nicht gesetztes, grossgeschriebenes Feld wirft (haette im Client nil)
      H.truthy(errOf(function() return f.Refresh end))
      M.AllowField("Refresh")
      H.eq(f.Refresh, nil)
   end)

   H.test("UndressSlot existiert nur mit world.hasUndressSlot", function()
      local m = CreateFrame("DressUpModel")
      H.eq(m.UndressSlot, nil)
      M.world.hasUndressSlot = true
      H.eq(type(m.UndressSlot), "function")
      m:SetUnit("player")
      m:UndressSlot(5)
      H.eq(M.Model(m).count("UndressSlot"), 1)
   end)

   H.test("IsMouseOver existiert (guard-faehig)", function()
      local f = CreateFrame("Frame")
      H.eq(type(f.IsMouseOver), "function")
      H.eq(f:IsMouseOver(), nil)
   end)

   H.test("world.strictApi=false liefert nil statt Fehler", function()
      M.world.strictApi = false
      local f = CreateFrame("Frame")
      H.eq(f.SetSize, nil)   -- lint:allow(no-api)
   end)

   H.test("Whitelist: jede erlaubte Methode existiert und ist aufrufbar (Typen einzeln)", function()
      local function names(str)
         local t = {}
         for n in str:gmatch("%S+") do t[#t + 1] = n end
         return t
      end
      local COMMON = names([[GetName GetObjectType IsObjectType GetParent SetParent GetAlpha SetAlpha
         GetEffectiveAlpha Show Hide IsShown IsVisible SetPoint GetPoint GetNumPoints ClearAllPoints SetAllPoints
         GetLeft GetRight GetTop GetBottom GetCenter GetWidth GetHeight SetWidth SetHeight GetScale SetScale
         GetEffectiveScale GetFrameStrata SetFrameStrata GetFrameLevel SetFrameLevel GetID SetID EnableMouse
         IsMouseEnabled EnableMouseWheel EnableKeyboard IsKeyboardEnabled SetMovable IsMovable SetResizable
         IsResizable SetUserPlaced IsUserPlaced SetClampedToScreen SetClampRectInsets SetMinResize SetMaxResize
         StartMoving StartSizing StopMovingOrSizing SetHitRectInsets RegisterForDrag SetBackdrop GetBackdrop
         SetBackdropColor GetBackdropColor SetBackdropBorderColor GetBackdropBorderColor SetScript GetScript
         HookScript HasScript RegisterEvent UnregisterEvent UnregisterAllEvents IsEventRegistered SetToplevel
         Raise Lower GetChildren GetRegions GetNumChildren GetNumRegions CreateFontString CreateTexture
         SetAttribute GetAttribute IsMouseOver]])
      local PER = {
         Texture = names([[SetTexture GetTexture SetTexCoord GetTexCoord SetVertexColor SetBlendMode
            SetDesaturated SetGradient SetGradientAlpha SetDrawLayer GetDrawLayer SetRotation]]),
         FontString = names([[SetText GetText SetFont GetFont SetFontObject GetFontObject SetTextColor
            GetTextColor SetJustifyH SetJustifyV SetShadowColor SetShadowOffset SetSpacing GetStringWidth
            GetStringHeight SetTextHeight SetNonSpaceWrap SetIndentedWordWrap SetDrawLayer]]),
         Button = names([[SetText GetText SetNormalTexture GetNormalTexture SetPushedTexture GetPushedTexture
            SetHighlightTexture GetHighlightTexture SetDisabledTexture GetDisabledTexture SetNormalFontObject
            SetHighlightFontObject SetDisabledFontObject GetFontString SetFontString Enable Disable IsEnabled
            Click RegisterForClicks SetButtonState GetButtonState LockHighlight UnlockHighlight
            SetPushedTextOffset]]),
         CheckButton = names([[SetChecked GetChecked SetCheckedTexture GetCheckedTexture
            SetDisabledCheckedTexture SetText GetText Enable Disable IsEnabled Click]]),
         EditBox = names([[SetText GetText SetFontObject SetFont SetTextColor SetMaxLetters SetNumeric
            SetAutoFocus SetFocus ClearFocus HasFocus HighlightText Insert SetMultiLine SetTextInsets
            SetJustifyH GetNumber SetCursorPosition GetCursorPosition AddHistoryLine SetPassword
            SetBlinkSpeed]]),
         Slider = names([[SetMinMaxValues GetMinMaxValues SetValue GetValue SetValueStep GetValueStep
            SetOrientation SetThumbTexture GetThumbTexture Enable Disable IsEnabled]]),
         StatusBar = names([[SetStatusBarTexture GetStatusBarTexture SetStatusBarColor GetStatusBarColor
            SetMinMaxValues GetMinMaxValues SetValue GetValue SetOrientation]]),
         ScrollFrame = names([[SetScrollChild GetScrollChild SetVerticalScroll GetVerticalScroll
            GetVerticalScrollRange SetHorizontalScroll GetHorizontalScroll GetHorizontalScrollRange
            UpdateScrollChildRect]]),
         Model = names([[SetModel GetModel SetModelScale GetModelScale SetPosition GetPosition SetFacing
            GetFacing SetRotation SetCamera SetLight ClearModel SetSequence SetSequenceTime]]),
         PlayerModel = names([[SetModel GetModel SetModelScale GetModelScale SetPosition GetPosition
            SetFacing GetFacing SetRotation SetCamera SetLight ClearModel SetSequence SetSequenceTime
            SetUnit SetCreature]]),
         DressUpModel = names([[SetModel GetModel SetModelScale GetModelScale SetPosition GetPosition
            SetFacing GetFacing SetRotation SetCamera SetLight ClearModel SetSequence SetSequenceTime
            SetUnit SetCreature TryOn Dress Undress]]),
         GameTooltip = names([[SetOwner GetOwner IsOwned SetHyperlink SetInventoryItem SetBagItem SetText
            AddLine AddDoubleLine ClearLines NumLines GetItem GetUnit Show Hide FadeOut]]),
      }
      -- 1) jede Methode des Typs (und die gemeinsamen) ist eine Funktion
      for typeName, list in pairs(PER) do
         local o
         if typeName == "Texture" then
            o = CreateFrame("Frame"):CreateTexture()
         elseif typeName == "FontString" then
            o = CreateFrame("Frame"):CreateFontString()
         else
            o = CreateFrame(typeName)
         end
         for _, n in ipairs(list) do
            H.eq(type(o[n]), "function", typeName .. ":" .. n)
         end
         if typeName ~= "Texture" and typeName ~= "FontString" then
            for _, n in ipairs(COMMON) do H.eq(type(o[n]), "function", typeName .. ":" .. n) end
         end
      end
      -- 2) was nur Retail kennt, wirft auf jedem Typ
      local retail = names([[SetSize GetSize SetShown SetColorTexture SetWordWrap GetWordWrap SetMaxLines
         GetRect GetScaledRect SetEnabled SetIgnoreParentScale SetFixedFrameStrata SetFixedFrameLevel
         SetClipsChildren SetPropagateKeyboardInput SetFormattedText ApplyBackdrop SetShadowOffset
         SetColorTexture SetAtlas SetMask SetSnapToPixelGrid GetBoundsRect SetResizeBounds SetHighlightAtlas]])
      local f = CreateFrame("Frame")
      for _, n in ipairs(retail) do
         if n ~= "SetShadowOffset" then
            local e = errOf(function() return f[n] end)
            H.truthy(e and e:find("API not in 3.3.5a: Frame:" .. n, 1, true), "Frame:" .. n .. " -> " .. tostring(e))
         end
      end
   end)

   H.test("Whitelist: Methoden werden mit plausiblen Argumenten gerufen (Rauchtest)", function()
      local p = CreateFrame("Frame", "STSweepParent", UIParent)
      local tex = p:CreateTexture(nil, "ARTWORK")
      local fs = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      local function sweep(o, calls)
         for _, c in ipairs(calls) do
            local name = c[1]
            local args = { unpack(c, 2) }
            local ok, err = pcall(function() return o[name](o, unpack(args)) end)
            H.truthy(ok, tostring(o.__type) .. ":" .. name .. " -> " .. tostring(err))
         end
      end
      local frameCalls = {
         { "GetName" }, { "GetObjectType" }, { "IsObjectType", "Frame" }, { "GetParent" }, { "GetAlpha" },
         { "SetAlpha", 0.5 }, { "GetEffectiveAlpha" }, { "Show" }, { "IsShown" }, { "IsVisible" },
         { "SetPoint", "CENTER" }, { "GetPoint" }, { "GetNumPoints" }, { "SetAllPoints" },
         { "GetLeft" }, { "GetRight" }, { "GetTop" }, { "GetBottom" }, { "GetCenter" },
         { "SetWidth", 100 }, { "SetHeight", 50 }, { "GetWidth" }, { "GetHeight" },
         { "SetScale", 1.5 }, { "GetScale" }, { "GetEffectiveScale" },
         { "SetFrameStrata", "HIGH" }, { "GetFrameStrata" }, { "SetFrameLevel", 5 }, { "GetFrameLevel" },
         { "SetID", 3 }, { "GetID" }, { "EnableMouse", true }, { "IsMouseEnabled" },
         { "EnableMouseWheel", true }, { "EnableKeyboard", true }, { "IsKeyboardEnabled" },
         { "SetMovable", true }, { "IsMovable" }, { "SetResizable", true }, { "IsResizable" },
         { "SetUserPlaced", true }, { "IsUserPlaced" }, { "SetClampedToScreen", true },
         { "SetClampRectInsets", 0, 0, 0, 0 }, { "SetMinResize", 10, 10 }, { "SetMaxResize", 1000, 1000 },
         { "SetHitRectInsets", 1, 1, 1, 1 }, { "StartMoving" }, { "StopMovingOrSizing" },
         { "StartSizing", "BOTTOMRIGHT" }, { "StopMovingOrSizing" }, { "RegisterForDrag", "LeftButton" },
         { "SetBackdrop", { bgFile = "x" } }, { "GetBackdrop" }, { "SetBackdropColor", 0, 0, 0, 1 },
         { "GetBackdropColor" }, { "SetBackdropBorderColor", 1, 1, 1, 1 }, { "GetBackdropBorderColor" },
         { "SetScript", "OnShow", function() end }, { "GetScript", "OnShow" },
         { "HookScript", "OnHide", function() end }, { "HasScript", "OnShow" },
         { "RegisterEvent", "SOME_EVENT" }, { "IsEventRegistered", "SOME_EVENT" },
         { "UnregisterEvent", "SOME_EVENT" }, { "UnregisterAllEvents" }, { "SetToplevel", true },
         { "Raise" }, { "Lower" }, { "GetChildren" }, { "GetRegions" }, { "GetNumChildren" },
         { "GetNumRegions" }, { "SetAttribute", "k", "v" }, { "GetAttribute", "k" }, { "IsMouseOver" },
         { "ClearAllPoints" }, { "Hide" }, { "SetParent", UIParent },
      }
      sweep(p, frameCalls)
      sweep(CreateFrame("Button", nil, p), {
         { "SetNormalFontObject", GameFontNormal }, { "SetText", "x" }, { "GetText" },
         { "SetNormalTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetNormalTexture" },
         { "SetPushedTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetPushedTexture" },
         { "SetHighlightTexture", "Interface\\Buttons\\WHITE8X8", "ADD" }, { "GetHighlightTexture" },
         { "SetDisabledTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetDisabledTexture" },
         { "SetHighlightFontObject", GameFontHighlight }, { "SetDisabledFontObject", GameFontDisable },
         { "GetFontString" }, { "SetFontString", fs }, { "Disable" }, { "IsEnabled" }, { "Enable" },
         { "Click" }, { "RegisterForClicks", "LeftButtonUp", "RightButtonUp" },
         { "SetButtonState", "PUSHED", true }, { "GetButtonState" }, { "LockHighlight" },
         { "UnlockHighlight" }, { "SetPushedTextOffset", 1, -1 },
      })
      sweep(CreateFrame("CheckButton", nil, p), {
         { "SetChecked", true }, { "GetChecked" }, { "SetCheckedTexture", "Interface\\Buttons\\UI-CheckBox-Check" },
         { "GetCheckedTexture" }, { "SetDisabledCheckedTexture", "Interface\\Buttons\\UI-CheckBox-Check" },
      })
      local eb = CreateFrame("EditBox", nil, p)
      sweep(eb, {
         { "SetFontObject", ChatFontNormal }, { "SetFont", STANDARD_TEXT_FONT, 12 },
         { "SetTextColor", 1, 1, 1 }, { "SetText", "abc" }, { "GetText" }, { "SetMaxLetters", 10 },
         { "SetNumeric", false }, { "SetAutoFocus", false }, { "SetFocus" }, { "HasFocus" },
         { "HighlightText" }, { "HighlightText", 0, 2 }, { "Insert", "zz" }, { "SetMultiLine", false },
         { "SetTextInsets", 2, 2, 0, 0 }, { "SetJustifyH", "LEFT" }, { "GetNumber" },
         { "SetCursorPosition", 1 }, { "GetCursorPosition" }, { "AddHistoryLine", "h" },
         { "SetPassword", false }, { "SetBlinkSpeed", 0.5 }, { "ClearFocus" },
      })
      local sl = CreateFrame("Slider", nil, p)
      sweep(sl, {
         { "SetMinMaxValues", 0, 10 }, { "GetMinMaxValues" }, { "SetValueStep", 1 }, { "GetValueStep" },
         { "SetValue", 3 }, { "GetValue" }, { "SetOrientation", "VERTICAL" },
         { "SetThumbTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetThumbTexture" },
         { "Disable" }, { "IsEnabled" }, { "Enable" },
      })
      sweep(CreateFrame("StatusBar", nil, p), {
         { "SetStatusBarTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetStatusBarTexture" },
         { "SetStatusBarColor", 0, 1, 0 }, { "GetStatusBarColor" }, { "SetMinMaxValues", 0, 5 },
         { "GetMinMaxValues" }, { "SetValue", 2 }, { "GetValue" }, { "SetOrientation", "HORIZONTAL" },
      })
      local sf = CreateFrame("ScrollFrame", nil, p)
      sweep(sf, {
         { "SetScrollChild", CreateFrame("Frame") }, { "GetScrollChild" }, { "SetVerticalScroll", 1 },
         { "GetVerticalScroll" }, { "GetVerticalScrollRange" }, { "SetHorizontalScroll", 1 },
         { "GetHorizontalScroll" }, { "GetHorizontalScrollRange" }, { "UpdateScrollChildRect" },
      })
      local modelCalls = {
         { "SetModel", "Interface\\Buttons\\x.m2" }, { "GetModel" }, { "SetModelScale", 2 },
         { "GetModelScale" }, { "SetPosition", 0, 0, 0 }, { "GetPosition" }, { "SetFacing", 1 },
         { "GetFacing" }, { "SetRotation", 1 }, { "SetCamera", 0 },
         { "SetLight", 1, 0, 0, -1, 0, 0.7, 1, 1, 1, 0.8, 1, 1, 1 }, { "SetSequence", 1 },
         { "SetSequenceTime", 1, 0 }, { "ClearModel" },
      }
      sweep(CreateFrame("Model", nil, p), modelCalls)
      local pm = CreateFrame("PlayerModel", nil, p)
      sweep(pm, { { "SetUnit", "player" }, { "SetCreature", 123 } })
      local dm = CreateFrame("DressUpModel", nil, p)
      sweep(dm, { { "SetUnit", "player" }, { "TryOn", 1234 }, { "Dress" }, { "Undress" } })
      sweep(tex, {
         { "SetTexture", "Interface\\Buttons\\WHITE8X8" }, { "GetTexture" }, { "SetTexCoord", 0, 1, 0, 1 },
         { "GetTexCoord" }, { "SetVertexColor", 1, 1, 1, 1 }, { "SetBlendMode", "BLEND" },
         { "SetDesaturated", true }, { "SetGradient", "HORIZONTAL", 0, 0, 0, 1, 1, 1 },
         { "SetGradientAlpha", "VERTICAL", 0, 0, 0, 0, 1, 1, 1, 1 }, { "SetDrawLayer", "BORDER" },
         { "GetDrawLayer" }, { "SetRotation", 1 }, { "GetName" }, { "GetParent" }, { "SetAlpha", 1 },
         { "GetAlpha" }, { "Show" }, { "Hide" }, { "IsShown" }, { "IsVisible" }, { "SetPoint", "CENTER" },
         { "GetPoint" }, { "GetNumPoints" }, { "ClearAllPoints" }, { "SetAllPoints", p },
         { "GetLeft" }, { "GetRight" }, { "GetTop" }, { "GetBottom" }, { "GetCenter" }, { "SetWidth", 4 },
         { "SetHeight", 4 }, { "GetWidth" }, { "GetHeight" }, { "IsObjectType", "Texture" },
         { "GetObjectType" }, { "SetParent", p },
      })
      sweep(fs, {
         { "SetText", "abc" }, { "GetText" }, { "SetFont", STANDARD_TEXT_FONT, 11, "OUTLINE" }, { "GetFont" },
         { "SetFontObject", GameFontHighlight }, { "GetFontObject" }, { "SetTextColor", 1, 0, 0 },
         { "GetTextColor" }, { "SetJustifyH", "LEFT" }, { "SetJustifyV", "TOP" },
         { "SetShadowColor", 0, 0, 0, 1 }, { "SetShadowOffset", 1, -1 }, { "SetSpacing", 2 },
         { "GetStringWidth" }, { "GetStringHeight" }, { "SetTextHeight", 14 }, { "SetNonSpaceWrap", true },
         { "SetIndentedWordWrap", false }, { "SetDrawLayer", "OVERLAY", 1 },
      })
      sweep(GameTooltip, {
         { "SetOwner", UIParent, "ANCHOR_NONE" }, { "GetOwner" }, { "IsOwned", UIParent }, { "ClearLines" },
         { "SetText", "t" }, { "AddLine", "l" }, { "AddDoubleLine", "a", "b" }, { "NumLines" },
         { "GetItem" }, { "GetUnit" }, { "SetHyperlink", "spell:133" }, { "SetInventoryItem", "player", 1 },
         { "SetBagItem", 0, 1 }, { "Show" }, { "FadeOut" }, { "Hide" },
      })
   end)

   -- ======================================================================
   H.section("Frames, Templates, Schriften")
   -- ======================================================================

   H.test("CreateFrame: Typen, Namen, Eltern", function()
      for _, t in ipairs({ "Frame", "Button", "CheckButton", "EditBox", "Slider", "StatusBar", "ScrollFrame",
                           "Model", "PlayerModel", "DressUpModel" }) do
         local f = CreateFrame(t, "SelfTest" .. t, UIParent)
         H.eq(f:GetObjectType(), t)
         H.eq(_G["SelfTest" .. t], f)
         H.eq(f:GetName(), "SelfTest" .. t)
         H.eq(f:GetParent(), UIParent)
      end
      local anon = CreateFrame("Frame")
      H.eq(anon:GetName(), nil)
      H.eq(anon:GetParent(), nil)
      H.truthy(anon:IsObjectType("Frame"))
      H.eq(CreateFrame("Button"):IsObjectType("Frame"), 1)
      H.eq(CreateFrame("Frame"):IsObjectType("Button"), nil)
   end)

   H.test("CreateFrame: Fehler bei unbekanntem Typ, doppeltem Namen, falschem Eltern, unbekanntem Template", function()
      H.throws(function() CreateFrame("Cooldown") end, "unknown frame type")
      H.throws(function() CreateFrame("Frame", "Dup1") CreateFrame("Frame", "Dup1") end, "already exists")
      H.throws(function() CreateFrame("Frame", nil, "UIParent") end, "parent must be a frame")
      local f = CreateFrame("Frame")
      local tex = f:CreateTexture()
      H.throws(function() CreateFrame("Frame", nil, tex) end, "parent must be a frame")
      H.throws(function() CreateFrame("Frame", nil, UIParent, "NoSuchTemplate") end, "unknown template")
      H.throws(function() CreateFrame("Frame", nil, UIParent, "BackdropTemplate") end, "unknown template")   -- lint:allow(no-api)
      H.throws(function() CreateFrame("Frame", nil, UIParent, "UIPanelButtonTemplate") end, "cannot be used")
   end)

   H.test("Templates: UICheckButtonTemplate legt <name>Text an", function()
      local c = CreateFrame("CheckButton", "STCheck", UIParent, "UICheckButtonTemplate")
      H.truthy(STCheckText, "global STCheckText")
      H.eq(STCheckText:GetObjectType(), "FontString")
      H.eq(c:GetFontString(), STCheckText)
      STCheckText:SetText("Label")     -- Schrift vom Template: kein 'Font not set'
      H.eq(STCheckText:GetText(), "Label")
      H.eq(c:GetText(), "Label")
      H.eq(c:GetChecked(), nil)
      H.truthy(c:GetCheckedTexture())
   end)

   H.test("Templates: OptionsSliderTemplate legt Text/Low/High an", function()
      local s = CreateFrame("Slider", "STSlider", UIParent, "OptionsSliderTemplate")
      for _, suffix in ipairs({ "Text", "Low", "High" }) do
         local fs = _G["STSlider" .. suffix]
         H.truthy(fs, suffix)
         H.eq(fs:GetObjectType(), "FontString")
         fs:SetText(suffix)
      end
      H.truthy(s:GetThumbTexture())
      H.eq(s:GetWidth(), 144)
   end)

   H.test("Templates: UIPanelScrollFrameTemplate braucht einen Namen", function()
      local sf = CreateFrame("ScrollFrame", "STScroll", UIParent, "UIPanelScrollFrameTemplate")
      H.truthy(STScrollScrollBar, "ScrollBar")
      H.truthy(STScrollScrollBarScrollUpButton)
      H.truthy(STScrollScrollBarScrollDownButton)
      H.eq(STScrollScrollBar:GetObjectType(), "Slider")
      H.throws(function() CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate") end, "NAMED frame")
      local child = CreateFrame("Frame", nil, sf)
      child:SetWidth(100)
      child:SetHeight(500)
      sf:SetWidth(100)
      sf:SetHeight(100)
      sf:SetScrollChild(child)
      H.eq(sf:GetVerticalScrollRange(), 400)
      local lo, hi = STScrollScrollBar:GetMinMaxValues()
      H.eq(hi, 400)
   end)

   H.test("Templates: InputBoxTemplate hat Schrift, GameTooltipTemplate Zeilen-FontStrings", function()
      local e = CreateFrame("EditBox", "STInput", UIParent, "InputBoxTemplate")
      e:SetText("abc")
      H.eq(e:GetText(), "abc")
      H.eq(e:GetHeight(), 20)
      local t = CreateFrame("GameTooltip", "STTip", UIParent, "GameTooltipTemplate")
      H.truthy(STTipTextLeft1)
      H.truthy(STTipTextRight1)
      H.truthy(STTipTextLeft2)
      H.eq(STTipTextLeft1:GetText(), nil)
      H.eq(t:IsShown(), nil)
   end)

   H.test("UIPanelCloseButton versteckt den Elternframe", function()
      local p = CreateFrame("Frame", nil, UIParent)
      local c = CreateFrame("Button", "STClose", p, "UIPanelCloseButton")
      H.eq(p:IsShown(), 1)
      M.Click(c)
      H.eq(p:IsShown(), nil)
   end)

   H.test("'Font not set' bei FontString und EditBox ohne Schrift", function()
      local f = CreateFrame("Frame")
      local fs = f:CreateFontString()
      H.throws(function() fs:SetText("x") end, "Font not set")
      fs:SetFontObject(GameFontNormal)
      fs:SetText("x")
      H.eq(fs:GetText(), "x")
      local fs2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs2:SetText("ok")
      local fs3 = f:CreateFontString()
      fs3:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
      fs3:SetText("ok")
      local e = CreateFrame("EditBox")
      H.throws(function() e:SetText("x") end, "Font not set")
      e:SetFontObject(ChatFontNormal)
      e:SetText("x")
      H.eq(e:GetText(), "x")
      -- Button ohne FontString
      local b = CreateFrame("Button")
      H.throws(function() b:SetText("x") end, "Font not set")
      b:SetNormalFontObject(GameFontNormal)
      b:SetText("x")
      H.eq(b:GetText(), "x")
   end)

   H.test("CreateFontString: unbekanntes Schriftobjekt und ungueltige Ebene werfen", function()
      local f = CreateFrame("Frame")
      H.throws(function() f:CreateFontString(nil, "OVERLAY", "NoSuchFont") end, "inherited font")
      H.throws(function() f:CreateFontString(nil, "TOP") end, "invalid draw layer")
      H.throws(function() f:CreateTexture(nil, "FOREGROUND") end, "invalid draw layer")
   end)

   H.test("Schriftobjekte: GetFont/SetFont, fest eincodierte Latin-Schrift in CJK-Client ist ein Fehler", function()
      local path, size = GameFontNormal:GetFont()
      H.eq(path, STANDARD_TEXT_FONT)
      H.eq(size, 12)
      local f = CreateFrame("Frame")
      local fs = f:CreateFontString()
      fs:SetFont("Fonts\\FRIZQT__.TTF", 11)     -- enUS: erlaubt
      H.eq(select(2, fs:GetFont()), 11)
      H.throws(function() fs:SetFont("Fonts\\FRIZQT__.TTF", -1) end, "positive")
      H.throws(function() fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "BOLD") end, "invalid font flag")
      M.Install({ world = { locale = "ruRU" } })
      H.eq(STANDARD_TEXT_FONT, "Fonts\\FRIZQT___CYR.TTF")
      local g = CreateFrame("Frame"):CreateFontString()
      H.throws(function() g:SetFont("Fonts\\FRIZQT__.TTF", 10) end, "Latin%-only font")
      g:SetFont(STANDARD_TEXT_FONT, 10)
   end)

   H.test("FontString: Breite aus Text, SetTextColor/Justify-Pruefung", function()
      local f = CreateFrame("Frame")
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      H.eq(fs:GetText(), nil)
      fs:SetText("Hello")
      H.truthy(fs:GetStringWidth() > 0)
      H.eq(fs:GetWidth(), fs:GetStringWidth())
      fs:SetWidth(10)
      H.eq(fs:GetWidth(), 10)
      fs:SetTextColor(0.5, 0.5, 0.5)
      local r, g, b, a = fs:GetTextColor()
      H.deepEq({ r, g, b, a }, { 0.5, 0.5, 0.5, 1 })
      H.throws(function() fs:SetJustifyH("MIDDLE") end, "invalid value")
      H.throws(function() fs:SetText({}) end, "bad argument")
      fs:SetText(12)
      H.eq(fs:GetText(), "12")
      fs:SetText(nil)
      H.eq(fs:GetText(), "")
   end)

   -- ======================================================================
   H.section("Anker, Groessen, Layout")
   -- ======================================================================

   H.test("SetPoint-Varianten, GetPoint, gleicher Anker ersetzt", function()
      local p = CreateFrame("Frame", nil, UIParent)
      p:SetWidth(200)
      p:SetHeight(100)
      p:SetPoint("CENTER")
      local c = CreateFrame("Frame", nil, p)
      c:SetPoint("TOPLEFT", 5, -6)
      H.deepEq({ c:GetPoint() }, { "TOPLEFT", p, "TOPLEFT", 5, -6 })
      c:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 1, 2)
      H.eq(c:GetNumPoints(), 1)
      H.deepEq({ c:GetPoint() }, { "TOPLEFT", p, "BOTTOMLEFT", 1, 2 })
      c:SetPoint("BOTTOMRIGHT", p, -3, 4)
      H.eq(c:GetNumPoints(), 2)
      H.deepEq({ c:GetPoint(2) }, { "BOTTOMRIGHT", p, "BOTTOMRIGHT", -3, 4 })
      c:ClearAllPoints()
      H.eq(c:GetNumPoints(), 0)
      H.eq(c:GetPoint(), nil)
      c:SetPoint("LEFT", "UIParent", "LEFT", 0, 0)
      H.eq(select(2, c:GetPoint()), UIParent)
      c:SetAllPoints()
      H.eq(c:GetNumPoints(), 2)
   end)

   H.test("SetPoint: ungueltige Anker, Selbstbezug, Schleife, unbekannter Name", function()
      local a = CreateFrame("Frame", nil, UIParent)
      local b = CreateFrame("Frame", nil, UIParent)
      H.throws(function() a:SetPoint("MIDDLE") end, "unknown anchor point")
      H.throws(function() a:SetPoint("CENTER", a) end, "itself")
      H.throws(function() a:SetPoint("CENTER", "NoSuchFrameAnywhere") end, "couldn't find")
      H.throws(function() a:SetPoint("CENTER", b, "NOWHERE", 0, 0) end, "relative anchor point")
      a:SetPoint("CENTER", b)
      H.throws(function() b:SetPoint("CENTER", a) end, "loop")
      -- Kind an Eltern verankert, Eltern am Kind: ebenfalls Schleife
      local p = CreateFrame("Frame", nil, UIParent)
      local ch = CreateFrame("Frame", nil, p)
      ch:SetPoint("CENTER")
      H.throws(function() p:SetPoint("TOP", ch, "BOTTOM") end, "loop")
   end)

   H.test("GetWidth/GetHeight: explizit gesetzter Wert oder 0, Fehler bei NaN/negativ/Typ", function()
      local f = CreateFrame("Frame")
      H.eq(f:GetWidth(), 0)
      H.eq(f:GetHeight(), 0)
      f:SetWidth(120)
      f:SetHeight(30)
      H.eq(f:GetWidth(), 120)
      H.eq(f:GetHeight(), 30)
      H.throws(function() f:SetWidth(nil) end, "bad argument")
      H.throws(function() f:SetWidth("10") end, "bad argument")
      H.throws(function() f:SetWidth(0 / 0) end, "NaN")
      H.throws(function() f:SetHeight(-1) end, "negative")
      H.throws(function() f:SetScale(0) end, "greater than 0")
   end)

   H.test("Anker-Aufloesung: GetLeft/GetTop/GetCenter, Scale, Zwei-Punkt-Groesse", function()
      UIParent:SetWidth(1365)
      local w = CreateFrame("Frame", nil, UIParent)
      w:SetWidth(200)
      w:SetHeight(100)
      w:SetPoint("BOTTOMLEFT", 50, 60)
      H.eq(w:GetLeft(), 50)
      H.eq(w:GetBottom(), 60)
      H.eq(w:GetRight(), 250)
      H.eq(w:GetTop(), 160)
      local cx, cy = w:GetCenter()
      H.eq(cx, 150)
      H.eq(cy, 110)
      -- Kind relativ, Zwei-Punkt-Groesse
      local c = CreateFrame("Frame", nil, w)
      c:SetPoint("TOPLEFT", w, "TOPLEFT", 10, -10)
      c:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -10, 10)
      H.eq(c:GetLeft(), 60)
      H.eq(c:GetRight(), 240)
      H.eq(c:GetTop(), 150)
      H.eq(c:GetBottom(), 70)
      H.eq(c:GetWidth(), 0)       -- GetWidth bleibt explizit (nie aus Ankern abgeleitet)
      -- ohne Anker: nicht aufloesbar
      local n = CreateFrame("Frame", nil, UIParent)
      n:SetWidth(10)
      H.eq(n:GetLeft(), nil)
      -- Skalierung: Offsets und Groesse in Einheiten des Frames
      local s = CreateFrame("Frame", nil, UIParent)
      s:SetScale(2)
      s:SetWidth(100)
      s:SetHeight(50)
      s:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 10, 20)
      H.eq(s:GetLeft(), 10)
      H.eq(s:GetRight(), 110)
      H.eq(s:GetEffectiveScale(), 2)
      local t = CreateFrame("Frame", nil, s)
      t:SetWidth(10)
      t:SetHeight(10)
      t:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 0, 0)
      H.eq(t:GetEffectiveScale(), 2)
      H.eq(t:GetLeft(), 110)
   end)

   H.test("OnSizeChanged feuert bei Aenderung mit (self, w, h)", function()
      local f = CreateFrame("Frame")
      local calls = {}
      f:SetScript("OnSizeChanged", function(self, w, h) calls[#calls + 1] = { self, w, h } end)
      f:SetWidth(100)
      f:SetHeight(50)
      f:SetWidth(100)       -- keine Aenderung
      H.eq(#calls, 2)
      H.deepEq(calls[2], { f, 100, 50 })
   end)

   H.test("Strata, Level, Alpha, Scale", function()
      local p = CreateFrame("Frame", nil, UIParent)
      H.eq(p:GetFrameStrata(), "MEDIUM")
      H.eq(p:GetFrameLevel(), 1)
      local c = CreateFrame("Frame", nil, p)
      H.eq(c:GetFrameLevel(), 2)
      p:SetFrameStrata("HIGH")
      H.eq(p:GetFrameStrata(), "HIGH")
      H.eq(c:GetFrameStrata(), "HIGH")
      c:SetFrameStrata("DIALOG")
      p:SetFrameStrata("LOW")
      H.eq(c:GetFrameStrata(), "DIALOG")
      p:SetFrameLevel(10)
      H.eq(c:GetFrameLevel(), 11)
      H.throws(function() p:SetFrameStrata("TOP") end, "invalid strata")
      p:SetAlpha(0.5)
      c:SetAlpha(0.5)
      H.eq(c:GetEffectiveAlpha(), 0.25)
      p:SetAlpha(7)
      H.eq(p:GetAlpha(), 1)
   end)

   H.test("SetParent: Umhaengen, Schleifen, Sichtbarkeit", function()
      local a = CreateFrame("Frame", nil, UIParent)
      local b = CreateFrame("Frame", nil, UIParent)
      local c = CreateFrame("Frame", nil, a)
      H.eq(a:GetNumChildren(), 1)
      c:SetParent(b)
      H.eq(a:GetNumChildren(), 0)
      H.eq(b:GetNumChildren(), 1)
      H.eq(c:GetParent(), b)
      H.throws(function() b:SetParent(c) end, "loop")
      H.throws(function() c:SetParent(b:CreateTexture()) end, "must be a frame")
   end)

   -- ======================================================================
   H.section("Sichtbarkeit, Skripte, Ereignisse")
   -- ======================================================================

   H.test("IsVisible beruecksichtigt alle Eltern, OnShow/OnHide bei echter Aenderung", function()
      local log = {}
      local p = CreateFrame("Frame", nil, UIParent)
      local c = CreateFrame("Frame", nil, p)
      local g = CreateFrame("Frame", nil, c)
      p:SetScript("OnShow", function() log[#log + 1] = "p:show" end)
      p:SetScript("OnHide", function() log[#log + 1] = "p:hide" end)
      c:SetScript("OnShow", function() log[#log + 1] = "c:show" end)
      c:SetScript("OnHide", function() log[#log + 1] = "c:hide" end)
      g:SetScript("OnShow", function() log[#log + 1] = "g:show" end)
      g:SetScript("OnHide", function() log[#log + 1] = "g:hide" end)
      H.eq(g:IsVisible(), 1)
      p:Hide()
      H.eq(g:IsVisible(), nil)
      H.eq(g:IsShown(), 1)         -- eigener Schalter bleibt
      H.deepEq(log, { "p:hide", "c:hide", "g:hide" })
      log = {}
      p:Hide()                     -- keine Aenderung -> kein Ereignis
      H.deepEq(log, {})
      c:Hide()                     -- Eltern versteckt: keine Sichtbarkeitsaenderung
      H.deepEq(log, {})
      p:Show()
      H.deepEq(log, { "p:show" })  -- c ist selbst versteckt, g darunter auch unsichtbar
      log = {}
      c:Show()
      H.deepEq(log, { "c:show", "g:show" })
   end)

   H.test("SetScript/GetScript/HookScript: Reihenfolge, Argumente, ungueltige Namen", function()
      local f = CreateFrame("Frame")
      local log = {}
      f:SetScript("OnShow", function(self, ...) log[#log + 1] = "main" end)
      f:HookScript("OnShow", function(self) log[#log + 1] = "hook1" end)
      f:HookScript("OnShow", function(self) log[#log + 1] = "hook2" end)
      f:Hide()
      f:Show()
      H.deepEq(log, { "main", "hook1", "hook2" })
      H.eq(type(f:GetScript("OnShow")), "function")
      H.eq(f:GetScript("OnHide"), nil)
      H.throws(function() f:SetScript("OnClick", function() end) end, "unknown script")
      H.throws(function() f:SetScript("OnFoo", function() end) end, "unknown script")
      H.throws(function() f:SetScript("OnShow", "nope") end, "bad argument")
      H.eq(f:HasScript("OnUpdate"), 1)
      H.eq(f:HasScript("OnClick"), nil)
      H.eq(CreateFrame("Button"):HasScript("OnClick"), 1)
      -- HookScript auch ohne Hauptskript
      local g = CreateFrame("Frame")
      local n = 0
      g:HookScript("OnHide", function() n = n + 1 end)
      g:Hide()
      H.eq(n, 1)
   end)

   H.test("Fehler in Handlern landen im Fehler-Handler (M.errors) statt den Test abzubrechen", function()
      local f = CreateFrame("Frame")
      local second = false
      f:SetScript("OnEvent", function() error("boom") end)
      f:HookScript("OnEvent", function() second = true end)
      f:RegisterEvent("PLAYER_LOGIN")
      M.Fire("PLAYER_LOGIN")
      H.eq(second, true, "Hook laeuft trotz Fehler")
      H.eq(#M.errors, 1)
      H.truthy(M.errors[1]:find("boom", 1, true))
      H.truthy(M.errorTraces[1])
      local errs = H.takeErrors()
      H.eq(#errs, 1)
      H.eq(#M.errors, 0)
   end)

   H.test("seterrorhandler/geterrorhandler und securecall", function()
      local got = {}
      local old = geterrorhandler()
      seterrorhandler(function(m) got[#got + 1] = m end)
      local f = CreateFrame("Frame")
      f:SetScript("OnShow", function() error("x1") end)
      f:Hide()
      f:Show()
      H.eq(#got, 1)
      H.truthy(got[1]:find("x1", 1, true))
      H.eq(#M.errors, 0)
      seterrorhandler(old)
      H.eq(select("#", securecall(function() return 1, 2, 3 end)), 3)
   end)

   H.test("RegisterEvent: Zustellung in Registrierungsreihenfolge, Unregister, IsEventRegistered", function()
      local log = {}
      local a, b = CreateFrame("Frame"), CreateFrame("Frame")
      b:SetScript("OnEvent", function(self, ev, ...) log[#log + 1] = "b:" .. ev .. ":" .. select("#", ...) end)
      a:SetScript("OnEvent", function(self, ev, x) log[#log + 1] = "a:" .. ev .. ":" .. tostring(x) end)
      b:RegisterEvent("FOO")
      a:RegisterEvent("FOO")
      H.eq(a:IsEventRegistered("FOO"), 1)
      M.Fire("FOO", 7)
      H.deepEq(log, { "b:FOO:1", "a:FOO:7" })
      a:UnregisterEvent("FOO")
      H.eq(a:IsEventRegistered("FOO"), nil)
      log = {}
      M.Fire("FOO", 8)
      H.deepEq(log, { "b:FOO:1" })
      b:UnregisterAllEvents()
      log = {}
      M.Fire("FOO")
      H.deepEq(log, {})
      -- versteckte Frames bekommen Ereignisse trotzdem
      a:RegisterEvent("BAR")
      a:Hide()
      log = {}
      M.Fire("BAR", 1)
      H.deepEq(log, { "a:BAR:1" })
      -- Retail-Ereignis
      H.throws(function() a:RegisterEvent("GET_ITEM_INFO_RECEIVED") end, "API not in 3.3.5a")   -- lint:allow(no-api)
   end)

   H.test("Zeit: Advance ruft OnUpdate nur fuer sichtbare Frames, GetTime ist monoton", function()
      local t0 = GetTime()
      local f = CreateFrame("Frame", nil, UIParent)
      local hiddenParent = CreateFrame("Frame", nil, UIParent)
      local child = CreateFrame("Frame", nil, hiddenParent)
      local hiddenSelf = CreateFrame("Frame", nil, UIParent)
      local n, elapsedSum, nChild, nHidden = 0, 0, 0, 0
      f:SetScript("OnUpdate", function(self, el) n = n + 1 elapsedSum = elapsedSum + el end)
      child:SetScript("OnUpdate", function() nChild = nChild + 1 end)
      hiddenSelf:SetScript("OnUpdate", function() nHidden = nHidden + 1 end)
      hiddenParent:Hide()
      hiddenSelf:Hide()
      M.Advance(1)
      H.eq(n, 20)
      H.near(elapsedSum, 1, 1e-9)
      H.eq(nChild, 0)
      H.eq(nHidden, 0)
      H.near(GetTime() - t0, 1, 1e-9)
      hiddenParent:Show()
      M.Advance(0.1)
      H.eq(nChild, 2)
      -- eigene Schrittweite
      n = 0
      M.Advance(1, 0.25)
      H.eq(n, 4)
      -- Zeit darf nicht zurueckgehen
      M.now = M.now - 5
      H.throws(function() GetTime() end, "went backwards")
      M.now = M.now + 5
   end)

   H.test("Frames, die in OnUpdate Frames verstecken, werden sauber behandelt", function()
      local a = CreateFrame("Frame")
      local b = CreateFrame("Frame")
      local nb = 0
      a:SetScript("OnUpdate", function() b:Hide() end)
      b:SetScript("OnUpdate", function() nb = nb + 1 end)
      M.Advance(0.05)
      H.eq(nb, 0)
   end)

   H.test("Fades: UIFrameFadeIn/Out laufen ueber die Zeit", function()
      local f = CreateFrame("Frame")
      local done = false
      UIFrameFadeOut(f, 1, 1, 0)
      f.fadeInfo.finishedFunc = function() done = true end
      M.Advance(0.5)
      H.near(f:GetAlpha(), 0.5, 0.06)
      M.Advance(0.6)
      H.eq(f:GetAlpha(), 0)
      H.eq(done, true)
      H.eq(f:IsShown(), 1)
   end)

   -- ======================================================================
   H.section("Addon-Nachrichten und Server")
   -- ======================================================================

   H.test("SendAddonMessage: Aufzeichnung, SentCommands, ClearSent, Fehlerfaelle", function()
      SendAddonMessage("transmog", "GetTransmogStatus", "WHISPER", UnitName("player"))
      SendAddonMessage("other", "x", "GUILD")
      SendAddonMessage("transmog", "Apply:0:123", "WHISPER", "Testplayer")
      H.eq(#M.sentAddon, 3)
      H.deepEq(M.sentAddon[1], { prefix = "transmog", msg = "GetTransmogStatus", channel = "WHISPER",
                                  target = "Testplayer" })
      H.deepEq(M.SentCommands(), { "GetTransmogStatus", "Apply:0:123" })
      H.eq(M.CountSent("Apply"), 1)
      M.ClearSent()
      H.deepEq(M.SentCommands(), {})
      H.throws(function() SendAddonMessage("transmog", "x", "WHISPER") end, "needs a target")
      H.throws(function() SendAddonMessage("transmog", "x", "PIGEON", "a") end, "invalid chat type")
      H.throws(function() SendAddonMessage("transmog", ("x"):rep(300), "WHISPER", "a") end, "too long")
      H.throws(function() SendAddonMessage("", "x", "WHISPER", "a") end, "empty prefix")
   end)

   H.test("ServerMessage liefert CHAT_MSG_ADDON(prefix, msg, channel, sender)", function()
      local got
      local f = CreateFrame("Frame")
      f:RegisterEvent("CHAT_MSG_ADDON")
      f:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
         got = { event, prefix, msg, channel, sender }
      end)
      M.ServerMessage("TransmogStatus:0")
      H.deepEq(got, { "CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "Testplayer" })
   end)

   H.test("Gossip: HideUIPanel(GossipFrame) loest GOSSIP_CLOSED synchron aus", function()
      local log = {}
      local addon = CreateFrame("Frame")
      addon:RegisterEvent("GOSSIP_SHOW")
      addon:RegisterEvent("GOSSIP_CLOSED")
      addon:SetScript("OnEvent", function(self, event)
         log[#log + 1] = event
         if event == "GOSSIP_SHOW" then
            log[#log + 1] = "shown=" .. tostring(GossipFrame:IsShown())
            HideUIPanel(GossipFrame)
            log[#log + 1] = "after-hide"
         end
      end)
      M.GossipShow()
      -- Blizzard-GossipFrame wurde VOR dem Addon benachrichtigt und ist sichtbar;
      -- GOSSIP_CLOSED kommt mitten in HideUIPanel, noch vor "after-hide"
      H.deepEq(log, { "GOSSIP_SHOW", "shown=1", "GOSSIP_CLOSED", "after-hide" })
      H.eq(GossipFrame:IsShown(), nil)
      H.eq(M.world.gossipOpen, false)
      -- zweites Schliessen ist wirkungslos
      log = {}
      CloseGossip()
      HideUIPanel(GossipFrame)
      H.deepEq(log, {})
   end)

   H.test("Gossip: CloseGossip versteckt das Fenster per Ereignis; Show/Hide/Toggle", function()
      M.GossipShow()
      H.eq(GossipFrame:IsShown(), 1)
      CloseGossip()
      H.eq(GossipFrame:IsShown(), nil)
      local f = CreateFrame("Frame")
      f:Hide()
      ShowUIPanel(f)
      H.eq(f:IsShown(), 1)
      ToggleFrame(f)
      H.eq(f:IsShown(), nil)
      HideUIPanel(nil)       -- tolerant
      ShowUIPanel(nil)
   end)

   H.test("OpenNpc: 'Open' vom Server, danach GOSSIP_SHOW", function()
      local order = {}
      local f = CreateFrame("Frame")
      f:RegisterEvent("CHAT_MSG_ADDON")
      f:RegisterEvent("GOSSIP_SHOW")
      f:SetScript("OnEvent", function(self, ev, a, b) order[#order + 1] = ev .. (b and (":" .. b) or "") end)
      M.OpenNpc()
      H.deepEq(order, { "CHAT_MSG_ADDON:Open", "GOSSIP_SHOW" })
   end)

   H.test("UISpecialFrames: CloseSpecialWindows / M.Escape", function()
      local w = CreateFrame("Frame", "STWindow", UIParent)
      tinsert(UISpecialFrames, "STWindow")
      H.eq(M.Escape(), true)
      H.eq(w:IsShown(), nil)
      H.eq(M.Escape(), false)
   end)

   -- ======================================================================
   H.section("Items und Cache")
   -- ======================================================================

   H.test("Item-Cache: erst nach SetHyperlink + Verzoegerung; Abfragen werden gezaehlt", function()
      M.items[1001] = { name = "Test Helm", quality = 4, ilvl = 200, minLevel = 80, class = "Armor",
                        subclass = "Plate", equipLoc = "INVTYPE_HEAD", icon = "Interface\\Icons\\INV_Helmet_01",
                        price = 1234 }
      H.eq(GetItemInfo(1001), nil)
      H.eq(select("#", GetItemInfo(1001)), 0)
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetHyperlink("item:1001")
      H.eq(M.itemQueries[1001], 1)
      H.eq(GetItemInfo(1001), nil, "noch nicht gecacht")
      M.Advance(0.2)
      H.eq(GetItemInfo(1001), nil, "0.2 s < 0.3 s")
      M.Advance(0.15)
      local name, link, quality, ilvl, minLevel, class, subclass, maxStack, equipLoc, icon, price =
         GetItemInfo(1001)
      H.eq(name, "Test Helm")
      H.eq(link, "|cffa335ee|Hitem:1001:0:0:0:0:0:0:0:0|h[Test Helm]|h|r")
      H.eq(quality, 4)
      H.eq(ilvl, 200)
      H.eq(minLevel, 80)
      H.eq(class, "Armor")
      H.eq(subclass, "Plate")
      H.eq(maxStack, 1)
      H.eq(equipLoc, "INVTYPE_HEAD")
      H.eq(icon, "Interface\\Icons\\INV_Helmet_01")
      H.eq(price, 1234)
      H.eq(select("#", GetItemInfo(1001)), 11)
      -- Zugriff ueber Link und Name
      H.eq(GetItemInfo(link), "Test Helm")
      H.eq(GetItemInfo("item:1001"), "Test Helm")
      H.eq(GetItemInfo("Test Helm"), "Test Helm")
      H.eq(GetItemInfo("1001"), "Test Helm")
   end)

   H.test("Item-Cache: unbekannte IDs werden nie gecacht, itemCacheDelay konfigurierbar", function()
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetHyperlink("item:424242")
      M.Advance(60)
      H.eq(GetItemInfo(424242), nil)
      H.eq(M.itemQueries[424242], 1)
      M.items[7] = { name = "Quick" }
      M.world.itemCacheDelay = 2
      GameTooltip:SetHyperlink("item:7")
      M.Advance(1.9)
      H.eq(GetItemInfo(7), nil)
      M.Advance(0.2)
      H.eq(GetItemInfo(7), "Quick")
      -- weiterer Aufruf zaehlt, ohne zu verlaengern
      GameTooltip:SetHyperlink("item:7")
      H.eq(M.itemQueries[7], 2)
   end)

   H.test("Item-Cache: CacheItem/CacheAll/UncacheItem; angelegte Gegenstaende sind gecacht", function()
      M.items[1] = { name = "A", quality = 2 }
      M.items[2] = { name = "B", quality = 3 }
      M.items[3] = { name = "C", quality = 1 }
      M.CacheItem(1)
      H.eq(GetItemInfo(1), "A")
      H.eq(GetItemInfo(2), nil)
      H.eq(M.CacheItem(999), false)
      M.CacheAll()
      H.eq(GetItemInfo(2), "B")
      M.UncacheItem(2)
      H.eq(GetItemInfo(2), nil)
      M.world.equipment[1] = 3
      M.UncacheItem(3)
      H.eq(GetItemInfo(3), "C", "angelegt = bekannt")
      M.world.equipmentCached = false
      H.eq(GetItemInfo(3), nil)
   end)

   H.test("GetItemInfo prueft Argumente; Links aus GetInventoryItemLink", function()
      H.throws(function() GetItemInfo(nil) end, "Usage")
      H.throws(function() GetItemInfo({}) end, "Usage")
      M.items[55] = { name = "Rock", quality = 0 }
      M.world.equipment[16] = 55
      local link = GetInventoryItemLink("player", 16)
      H.eq(link, "|cff9d9d9d|Hitem:55:0:0:0:0:0:0:0:0|h[Rock]|h|r")
      H.eq(GetInventoryItemLink("player", 1), nil)
      H.eq(GetInventoryItemLink("target", 16), nil)
      H.eq(GetInventoryItemID("player", 16), 55)
      -- nicht in M.items: Link mit Ersatzname
      M.world.equipment[3] = 9999
      H.eq(GetInventoryItemLink("player", 3), "|cffffffff|Hitem:9999:0:0:0:0:0:0:0:0|h[Item 9999]|h|r")
   end)

   H.test("GetInventorySlotInfo, GetItemQualityColor, ITEM_QUALITY_COLORS", function()
      local id, tex = GetInventorySlotInfo("HeadSlot")
      H.eq(id, 1)
      H.eq(tex, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head")
      H.eq(GetInventorySlotInfo("BackSlot"), 15)
      H.eq(GetInventorySlotInfo("SecondaryHandSlot"), 17)
      H.eq(GetInventorySlotInfo("TabardSlot"), 19)
      H.throws(function() GetInventorySlotInfo("HeadSlott") end, "unknown slot")
      local r, g, b, hex = GetItemQualityColor(4)
      H.near(r, 0.639, 0.01)
      H.eq(hex, "|cffa335ee")
      H.eq(ITEM_QUALITY_COLORS[4].hex, "|cffa335ee")
      H.near(ITEM_QUALITY_COLORS[2].g, 1, 1e-9)
      H.throws(function() GetItemQualityColor(9) end, "invalid quality")
   end)

   H.test("Auktionshaus-Klassen: enUS-Standard, Ueberschreibung durch world.auctionLists", function()
      local classes = { GetAuctionItemClasses() }
      H.eq(#classes, 11)
      H.eq(classes[1], "Weapon")
      H.eq(classes[2], "Armor")
      local weapon = { GetAuctionItemSubClasses(1) }
      H.eq(#weapon, 17)
      H.eq(weapon[1], "One-Handed Axes")
      H.eq(weapon[13], "Daggers")
      local armor = { GetAuctionItemSubClasses(2) }
      H.deepEq(armor, { "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams", "Idols",
                        "Totems", "Sigils" })
      M.world.auctionLists = M.AUCTION_DE
      H.eq((GetAuctionItemClasses()), "Waffe")
      H.eq(select(2, GetAuctionItemSubClasses(2)), "Stoff")
   end)

   H.test("Globalstrings: vorhanden, locale-abhaengig, abschaltbar", function()
      H.eq(HEADSLOT, "Head")
      H.eq(ITEM_QUALITY4_DESC, "Epic")
      H.eq(CLOSE, "Close")
      M.world.locale = "deDE"
      M.ApplyGlobalStrings()
      H.eq(HEADSLOT, "Kopf")
      H.eq(ITEM_QUALITY4_DESC, "Episch")
      M.world.globalStrings = false
      M.ApplyGlobalStrings()
      H.eq(HEADSLOT, nil)
      H.eq(CLOSE, nil)
      M.Install({ world = { globalStrings = false } })
      H.eq(SHOULDERSLOT, nil)
   end)

   H.test("Spielerdaten: UnitRace/UnitClass/UnitFactionGroup/UnitLevel/GetMoney", function()
      M.Install({ world = { race = "NightElf", class = "DEATHKNIGHT", level = 70, money = 12345 } })
      local l, t = UnitRace("player")
      H.eq(l, "Night Elf")
      H.eq(t, "NightElf")
      local cl, ct = UnitClass("player")
      H.eq(cl, "Death Knight")
      H.eq(ct, "DEATHKNIGHT")
      H.eq(select("#", UnitClass("player")), 2)
      H.eq((UnitFactionGroup("player")), "Alliance")
      H.eq(UnitLevel("player"), 70)
      H.eq(GetMoney(), 12345)
      M.Install({ world = { race = "BloodElf", locale = "deDE" } })
      H.eq((UnitRace("player")), "Blutelf")
      H.eq((UnitFactionGroup("player")), "Horde")
      M.Install({ world = { race = { "Draenei!", "Draenei" }, faction = "Horde" } })
      H.eq((UnitRace("player")), "Draenei!")
      H.eq((UnitFactionGroup("player")), "Horde")
   end)

   H.test("M.world: Zuweisung mischt in Standardwerte, Alias-Schluessel wirken", function()
      M.world = { locale = "deDE" }
      H.eq(GetLocale(), "deDE")
      H.eq(M.world.screenWidth, 1365, "Standardwerte bleiben")
      H.eq(UnitName("player"), "Testplayer")
      M.world.shiftDown = true
      H.eq(IsShiftKeyDown(), 1)
      H.eq(M.world.shift, true)
      M.world.screenW = 1920
      M.world.screenH = 1080
      H.eq(GetScreenWidth(), 1920)
      H.eq(UIParent:GetHeight(), 1080)
      M.world.screen = { w = 800, h = 600 }
      H.eq(GetScreenWidth(), 800)
      M.world.cursorX = 10
      M.world.cursorY = 20
      H.deepEq({ GetCursorPosition() }, { 10, 20 })
      M.world.playerRace = "Night Elf"
      M.world.playerClass = "Death Knight"
      H.eq(select(2, UnitRace("player")), "NightElf")
      H.eq(select(2, UnitClass("player")), "DEATHKNIGHT")
      H.eq(UnitClass("player"), "Todesritter")      -- locale deDE
      M.world.race = "undead"
      H.eq(select(2, UnitRace("player")), "Scourge")
      H.eq((UnitFactionGroup("player")), "Horde")
      M.world.faction = "A"
      H.eq((UnitFactionGroup("player")), "Alliance")
   end)

   H.test("AdvanceUntil, Dump", function()
      local n = 0
      local f = CreateFrame("Frame", "STDump", UIParent)
      f:SetScript("OnUpdate", function() n = n + 1 end)
      local took = M.AdvanceUntil(function() return n >= 10 end, 5)
      H.near(took, 0.5, 0.06)
      H.eq(M.AdvanceUntil(function() return false end, 0.5), nil)
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs:SetText("hi")
      f:SetWidth(10)
      local dump = M.Dump(f)
      H.contains(dump, "Frame 'STDump' 10x0")
      H.contains(dump, 'FontString "hi"')
   end)

   -- ======================================================================
   H.section("Modelle")
   -- ======================================================================

   H.test("DressUpModel: SetUnit setzt zurueck, TryOn/Undress, Aufrufprotokoll", function()
      local m = CreateFrame("DressUpModel", nil, UIParent)
      local v = M.Model(m)
      H.deepEq({ m:GetPosition() }, { 0, 0, 0 })
      H.eq(m:GetFacing(), 0)
      H.throws(function() m:TryOn(123) end, "no model loaded")
      m:SetUnit("player")
      m:SetFacing(1.5)
      m:SetPosition(1, 2, 3)
      m:SetRotation(0.61)
      H.eq(m:GetFacing(), 1.5)
      H.deepEq({ m:GetPosition() }, { 1, 2, 3 })
      m:TryOn(111)
      m:TryOn("item:222:0:0:0:0:0:0:0:0")
      H.deepEq(v.tried, { 111, 222 })
      m:Undress()
      H.eq(v.undressed, true)
      H.deepEq(v.tried, {})
      m:TryOn(333)
      H.deepEq(v.tried, { 333 })
      m:SetUnit("player")
      H.eq(m:GetFacing(), 0)
      H.deepEq({ m:GetPosition() }, { 0, 0, 0 })
      H.deepEq(v.tried, {})
      H.eq(v.undressed, false)
      H.eq(v.unit, "player")
      H.eq(v.log(), "SetUnit(player) SetFacing(1.5) SetPosition(1,2,3) SetRotation(0.61) TryOn(111) "
         .. "TryOn(item:222:0:0:0:0:0:0:0:0) Undress() TryOn(333) SetUnit(player)")
      H.eq(v.count("SetUnit"), 2)
      H.deepEq(v.last("TryOn"), { "TryOn", 333 })
      H.eq(v.last("TryOn").name, "TryOn")
      H.deepEq(v.last("TryOn").args, { 333 })
      H.eq(v.last("TryOn").n, 1)
      H.deepEq(v.names(), { "SetUnit", "SetFacing", "SetPosition", "SetRotation", "TryOn", "TryOn", "Undress",
                            "TryOn", "SetUnit" })
      -- reine Arrays: direkt mit deepEq pruefbar
      v.clear()
      H.eq(#v.calls, 0)
      m:SetUnit("player")
      m:Undress()
      m:TryOn(5)
      H.deepEq(v.calls, { { "SetUnit", "player" }, { "Undress" }, { "TryOn", 5 } })
   end)

   H.test("Model: Argumentpruefung, Skalierung, Methoden je Typ", function()
      local p = CreateFrame("PlayerModel")
      p:SetUnit("target")
      H.truthy(errOf(function() return p.TryOn end), "PlayerModel hat kein TryOn")
      local m = CreateFrame("Model")
      H.truthy(errOf(function() m:SetUnit("player") end))
      m:SetModel("Interface\\Foo.m2")
      H.eq(m:GetModel(), "Interface\\Foo.m2")
      m:SetModelScale(2)
      H.eq(m:GetModelScale(), 2)
      H.throws(function() m:SetModelScale(0) end, "greater than 0")
      H.throws(function() m:SetFacing("a") end, "bad argument")
      m:SetCamera(0)
      m:SetSequence(4)
      m:SetLight(1, 0, 0, -1, 0, 0.7, 1, 1, 1, 0.8, 1, 1, 1)
      H.eq(#M.Model(m).calls, 5)
   end)

   -- ======================================================================
   H.section("GameTooltip")
   -- ======================================================================

   H.test("GameTooltip: Owner, Zeilen, FontStrings, ClearLines", function()
      local t = GameTooltip
      H.eq(t:GetOwner(), nil)
      t:SetOwner(UIParent, "ANCHOR_RIGHT")
      H.eq(t:GetOwner(), UIParent)
      H.eq(t:IsOwned(UIParent), 1)
      H.eq(t:IsOwned(GameTooltip), nil)
      H.throws(function() t:SetOwner(UIParent, "ANCHOR_SOMEWHERE") end, "invalid anchor")
      t:AddLine("first", 1, 0, 0)
      t:AddDoubleLine("left", "right", 1, 1, 1, 0, 1, 0)
      H.eq(t:NumLines(), 2)
      H.deepEq({ t.__lines[1].left, t.__lines[1].r }, { "first", 1 })
      H.eq(t.__lines[2].right, "right")
      H.eq(GameTooltipTextLeft1:GetText(), "first")
      H.eq(GameTooltipTextLeft2:GetText(), "left")
      H.eq(GameTooltipTextRight2:GetText(), "right")
      t:AddLine("third")
      H.eq(GameTooltipTextLeft3:GetText(), "third")
      t:Show()
      H.eq(t:IsShown(), 1)
      t:ClearLines()
      H.eq(t:NumLines(), 0)
      H.eq(GameTooltipTextLeft1:GetText(), nil)
      H.eq(GameTooltipTextLeft3:GetText(), nil)
      t:SetText("header")
      H.eq(t:NumLines(), 1)
      H.eq(GameTooltipTextLeft1:GetText(), "header")
      t:Hide()
      H.eq(t:GetOwner(), nil, "Hide gibt den Besitzer frei")
   end)

   H.test("GameTooltip: SetHyperlink ohne Besitzer ist ein Fehler, mit Item zeigt Zeilen + OnTooltipSetItem", function()
      M.items[500] = { name = "Sword", quality = 3, ilvl = 100, minLevel = 60, class = "Weapon",
                       subclass = "One-Handed Swords", equipLoc = "INVTYPE_WEAPON" }
      H.throws(function() GameTooltip:SetHyperlink("item:500") end, "no owner")
      H.throws(function() GameTooltip:SetInventoryItem("player", 1) end, "no owner")
      H.throws(function() GameTooltip:SetBagItem(0, 1) end, "no owner")
      H.eq(GameTooltip:NumLines(), 0)
      H.eq(M.itemQueries[500], nil, "ohne Besitzer keine Abfrage")
      local fired = 0
      GameTooltip:HookScript("OnTooltipSetItem", function() fired = fired + 1 end)
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetHyperlink("item:500")
      H.eq(M.itemQueries[500], 1)
      H.eq(GameTooltip:NumLines(), 0, "noch nicht im Cache")
      H.eq(fired, 0)
      M.Advance(0.4)
      GameTooltip:SetHyperlink("|cff0070dd|Hitem:500:0:0:0:0:0:0:0:0|h[Sword]|h|r")
      H.eq(fired, 1)
      H.eq(GameTooltipTextLeft1:GetText(), "Sword")
      H.truthy(GameTooltip:NumLines() >= 3)
      local name, link = GameTooltip:GetItem()
      H.eq(name, "Sword")
      H.eq(link, "|cff0070dd|Hitem:500:0:0:0:0:0:0:0:0|h[Sword]|h|r")
      H.eq(GameTooltip:IsShown(), 1)
      GameTooltip:AddLine("Appended")
      H.eq(GameTooltipTextLeft1:GetText(), "Sword")
      H.eq(GameTooltip:NumLines() > 3, true)
   end)

   H.test("GameTooltip: SetInventoryItem/SetBagItem und Hook per hooksecurefunc", function()
      M.items[600] = { name = "Cap", quality = 2, equipLoc = "INVTYPE_HEAD" }
      M.world.equipment[1] = 600
      M.world.bags[0] = { [3] = 600 }
      local hooked = {}
      hooksecurefunc(GameTooltip, "SetInventoryItem", function(self, unit, slot)
         hooked[#hooked + 1] = unit .. ":" .. slot
         self:AddLine("extra")
      end)
      GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
      local hasItem = GameTooltip:SetInventoryItem("player", 1)
      H.eq(hasItem, 1)
      H.deepEq(hooked, { "player:1" })
      H.eq(GameTooltipTextLeft1:GetText(), "Cap")
      H.eq(GameTooltip.__lines[GameTooltip:NumLines()].left, "extra")
      H.eq(GameTooltip:SetInventoryItem("player", 2), nil)
      H.eq(GameTooltip:NumLines() >= 1, true)    -- nur 'extra' vom Hook
      GameTooltip:SetBagItem(0, 3)
      H.eq(GameTooltipTextLeft1:GetText(), "Cap")
   end)

   H.test("SetHyperlink prueft den Link-Typ", function()
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      H.throws(function() GameTooltip:SetHyperlink("garbage") end, "unknown link type")
      GameTooltip:SetHyperlink("spell:133")
      H.eq(GameTooltip:NumLines(), 1)
   end)

   -- ======================================================================
   H.section("hooksecurefunc")
   -- ======================================================================

   H.test("hooksecurefunc fuer globale Funktionen und Objekte", function()
      local log = {}
      _G.TransmogHookProbe = function(a, b) log[#log + 1] = "orig" return a + b, "x" end
      hooksecurefunc("TransmogHookProbe", function(a, b) log[#log + 1] = "hook:" .. a .. "," .. b end)
      local r1, r2 = TransmogHookProbe(1, 2)
      H.eq(r1, 3)
      H.eq(r2, "x")
      H.deepEq(log, { "orig", "hook:1,2" })
      -- Tabellenform
      local t = { Do = function(self, v) log[#log + 1] = "do" return v end }
      hooksecurefunc(t, "Do", function(self, v) log[#log + 1] = "hookDo" end)
      H.eq(t:Do(5), 5)
      H.deepEq(log, { "orig", "hook:1,2", "do", "hookDo" })
      -- Objekt (nur dieses Objekt)
      local f1, f2 = CreateFrame("Frame"), CreateFrame("Frame")
      local n = 0
      hooksecurefunc(f1, "Show", function() n = n + 1 end)
      f1:Show()
      f2:Show()
      H.eq(n, 1)
      -- nicht vorhandene Funktion
      H.throws(function() hooksecurefunc("NoSuchGlobalFunctionAnywhere", function() end) end, "non%-existing")
      H.truthy(errOf(function() hooksecurefunc(f1, "SetSize", function() end) end))
      -- Fehler im Hook stoeren den Aufrufer nicht, landen aber im Fehler-Handler
      hooksecurefunc("TransmogHookProbe", function() error("hookerr") end)
      H.eq((TransmogHookProbe(2, 2)), 4)
      H.eq(#M.errors, 1)
      H.takeErrors()
   end)

   -- ======================================================================
   H.section("Buttons, EditBoxen, Slider, Eingabe-Simulation")
   -- ======================================================================

   H.test("Click: nur angemeldete Tasten, CheckButton schaltet um, deaktiviert/versteckt", function()
      local p = CreateFrame("Frame", nil, UIParent)
      local b = CreateFrame("Button", nil, p)
      local log = {}
      b:SetScript("OnClick", function(self, button, down) log[#log + 1] = tostring(button) .. ":" .. tostring(down) end)
      b:SetScript("PreClick", function() log[#log + 1] = "pre" end)
      b:SetScript("PostClick", function() log[#log + 1] = "post" end)
      M.Click(b)
      H.deepEq(log, { "pre", "LeftButton:false", "post" })
      log = {}
      M.Click(b, "RightButton")
      H.deepEq(log, {}, "Rechtsklick ohne RegisterForClicks")
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      M.Click(b, "RightButton")
      H.deepEq(log, { "pre", "RightButton:false", "post" })
      b:RegisterForClicks("AnyUp")
      log = {}
      M.Click(b, "MiddleButton")
      H.eq(#log, 3)
      b:RegisterForClicks("LeftButtonDown")
      log = {}
      M.Click(b)
      H.deepEq(log, { "pre", "LeftButton:true", "post" })
      H.throws(function() b:RegisterForClicks("LeftClick") end, "invalid click type")
      -- deaktiviert
      b:RegisterForClicks("LeftButtonUp")
      b:Disable()
      log = {}
      M.Click(b)
      H.deepEq(log, {})
      b:Enable()
      -- versteckt
      p:Hide()
      H.throws(function() M.Click(b) end, "not visible")
      p:Show()
      -- kein EnableMouse
      local plain = CreateFrame("Frame", nil, UIParent)
      H.throws(function() M.Click(plain) end, "not mouse%-enabled")
      -- CheckButton
      local c = CreateFrame("CheckButton", nil, UIParent)
      local seen
      c:SetScript("OnClick", function(self) seen = self:GetChecked() end)
      M.Click(c)
      H.eq(seen, 1)
      M.Click(c)
      H.eq(seen, nil)
      -- Modifikatoren waehrend des Klicks
      local mod
      b:SetScript("OnClick", function() mod = IsShiftKeyDown() end)
      M.Click(b, "LeftButton", { shift = true })
      H.eq(mod, 1)
      H.eq(IsShiftKeyDown(), nil)
   end)

   H.test("Disable() waehrend die Maus gedrueckt ist verwirft den Klick", function()
      local b = CreateFrame("Button", nil, UIParent)
      local n = 0
      b:SetScript("OnClick", function() n = n + 1 end)
      M.MouseDown(b)
      b:Disable()
      b:Enable()
      M.MouseUp(b)
      H.eq(n, 0)
      M.MouseDown(b)
      M.MouseUp(b)
      H.eq(n, 1)
   end)

   H.test("Enter/Leave/Wheel/Key/Type", function()
      local a = CreateFrame("Button", nil, UIParent)
      local b = CreateFrame("Button", nil, UIParent)
      local log = {}
      a:SetScript("OnEnter", function() log[#log + 1] = "a:enter" end)
      a:SetScript("OnLeave", function() log[#log + 1] = "a:leave" end)
      b:SetScript("OnEnter", function() log[#log + 1] = "b:enter" end)
      b:SetScript("OnLeave", function() log[#log + 1] = "b:leave" end)
      M.Enter(a)
      H.eq(a:IsMouseOver(), 1)
      H.eq(GetMouseFocus(), a)
      M.Enter(b)
      H.deepEq(log, { "a:enter", "a:leave", "b:enter" })
      H.eq(a:IsMouseOver(), nil)
      M.Leave(b)
      M.Leave(b)
      H.deepEq(log, { "a:enter", "a:leave", "b:enter", "b:leave" })
      -- Mausrad
      local w = CreateFrame("Frame", nil, UIParent)
      w:EnableMouse(true)
      local got
      w:SetScript("OnMouseWheel", function(self, d) got = d end)
      H.throws(function() M.Wheel(w, 1) end, "EnableMouseWheel")
      w:EnableMouseWheel(true)
      M.Wheel(w, -1)
      H.eq(got, -1)
      -- Eintippen
      local e = CreateFrame("EditBox", nil, UIParent)
      e:SetFontObject(ChatFontNormal)
      local changes = {}
      e:SetScript("OnTextChanged", function(self, user) changes[#changes + 1] = self:GetText() .. ":" .. tostring(user) end)
      M.Type(e, "abc")
      H.deepEq(changes, { "abc:true" })
      e:SetText("xyz")
      H.deepEq(changes, { "abc:true", "xyz:false" })
      e:SetText("xyz")       -- unveraendert: kein OnTextChanged
      H.eq(#changes, 2)
      e:SetMaxLetters(2)
      e:SetText("qrst")
      H.eq(e:GetText(), "qr")
      e:SetMaxLetters(0)
      e:SetNumeric(true)
      M.Type(e, "a1b2")
      H.eq(e:GetText(), "12")
      H.eq(e:GetNumber(), 12)
      local enter
      e:SetScript("OnEnterPressed", function() enter = true end)
      M.Key(e, "ENTER")
      H.eq(enter, true)
   end)

   H.test("EditBox: AutoFocus beim Anlegen, ClearFocus, Fokuswechsel, Escape", function()
      local lost = {}
      -- Muster CreateFrame + SetAutoFocus(false): kein Fokus, auch nach dem naechsten Frame
      local quiet = CreateFrame("EditBox", nil, UIParent)
      quiet:SetAutoFocus(false)
      M.Advance(0.1)
      H.eq(quiet:HasFocus(), nil)
      -- Standard (AutoFocus an): Fokus im naechsten Frame
      local a = CreateFrame("EditBox", nil, UIParent)
      H.eq(a:HasFocus(), nil, "noch im selben Frame")
      M.Advance(0.1)
      H.eq(a:HasFocus(), 1, "neuer EditBox holt sich den Fokus")
      a:SetScript("OnEditFocusLost", function() lost[#lost + 1] = "a" end)
      local b = CreateFrame("EditBox", nil, UIParent)
      M.Advance(0.1)
      H.eq(a:HasFocus(), nil)
      H.eq(b:HasFocus(), 1)
      H.deepEq(lost, { "a" })
      b:SetAutoFocus(false)
      b:ClearFocus()
      H.eq(b:HasFocus(), nil)
      -- Show() eines EditBox mit AutoFocus: wieder im naechsten Frame
      b:SetAutoFocus(true)
      b:Hide()
      b:Show()
      M.Advance(0.1)
      H.eq(b:HasFocus(), 1)
      b:SetAutoFocus(false)
      b:ClearFocus()
      local c = CreateFrame("EditBox", nil, UIParent)
      c:SetAutoFocus(false)
      c:ClearFocus()
      c:SetFontObject(ChatFontNormal)
      local escaped
      c:SetScript("OnEscapePressed", function(self) escaped = true self:ClearFocus() end)
      c:SetFocus()
      H.eq(c:HasFocus(), 1)
      H.eq(M.Escape(), true)
      H.eq(escaped, true)
      H.eq(c:HasFocus(), nil)
      -- Verstecken verliert den Fokus
      c:SetFocus()
      c:Hide()
      H.eq(c:HasFocus(), nil)
      -- versteckter EditBox bekommt keinen Fokus
      c:SetFocus()
      H.eq(c:HasFocus(), nil)
      -- Standard-Chat-EditBox hat keinen Fokus
      H.eq(ChatFrame1EditBox:HasFocus(), nil)
   end)

   H.test("Slider: Min/Max, Schritt, OnValueChanged nur bei Aenderung", function()
      local s = CreateFrame("Slider", nil, UIParent)
      local vals = {}
      s:SetScript("OnValueChanged", function(self, v) vals[#vals + 1] = v end)
      s:SetMinMaxValues(0, 10)
      s:SetValueStep(2)
      s:SetValue(5)
      H.eq(s:GetValue(), 6)
      s:SetValue(6)
      s:SetValue(50)
      H.eq(s:GetValue(), 10)
      s:SetValue(-3)
      H.eq(s:GetValue(), 0)
      H.deepEq(vals, { 6, 10, 0 })
      H.deepEq({ s:GetMinMaxValues() }, { 0, 10 })
      s:SetMinMaxValues(0, 4)
      s:SetValue(4)
      s:SetMinMaxValues(0, 2)
      H.eq(s:GetValue(), 2)
      H.throws(function() s:SetMinMaxValues(5, 1) end, "greater than max")
      H.throws(function() s:SetOrientation("DIAGONAL") end, "must be")
   end)

   H.test("StatusBar und ScrollFrame", function()
      local sb = CreateFrame("StatusBar", nil, UIParent)
      H.deepEq({ sb:GetMinMaxValues() }, { 0, 1 })
      sb:SetValue(5)
      H.eq(sb:GetValue(), 1)
      sb:SetStatusBarColor(1, 0, 0)
      H.deepEq({ sb:GetStatusBarColor() }, { 1, 0, 0, 1 })
      sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
      H.eq(sb:GetStatusBarTexture():GetTexture(), "Interface\\Buttons\\WHITE8X8")

      local sf = CreateFrame("ScrollFrame", nil, UIParent)
      local content = CreateFrame("Frame", nil, sf)
      local ranges, scrolls = {}, {}
      sf:SetScript("OnScrollRangeChanged", function(self, xr, yr) ranges[#ranges + 1] = yr end)
      sf:SetScript("OnVerticalScroll", function(self, v) scrolls[#scrolls + 1] = v end)
      sf:SetWidth(100)
      sf:SetHeight(100)
      content:SetWidth(100)
      content:SetHeight(300)
      sf:SetScrollChild(content)
      H.eq(sf:GetScrollChild(), content)
      H.eq(sf:GetVerticalScrollRange(), 200)
      H.eq(sf:GetHorizontalScrollRange(), 0)
      H.eq(ranges[#ranges], 200)
      content:SetHeight(500)
      H.eq(ranges[#ranges], 400)
      sf:SetVerticalScroll(50)
      H.eq(sf:GetVerticalScroll(), 50)
      H.deepEq(scrolls, { 50 })
   end)

   H.test("Drag: Fenster verschieben und ueber den Griff in der Groesse aendern", function()
      local win = CreateFrame("Frame", "STDragWin", UIParent)
      win:SetWidth(400)
      win:SetHeight(300)
      win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      win:SetMovable(true)
      win:SetResizable(true)
      win:SetMinResize(200, 150)
      local head = CreateFrame("Frame", nil, win)
      head:EnableMouse(true)
      head:SetWidth(400)
      head:SetHeight(20)
      head:SetPoint("TOP", win, "TOP")
      head:RegisterForDrag("LeftButton")
      head:SetScript("OnDragStart", function() win:StartMoving() end)
      head:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
      M.Drag(head, 30, -10)
      local _, _, _, x, y = win:GetPoint()
      H.eq(x, 30)
      H.eq(y, -10)
      H.eq(win:IsUserPlaced(), 1)
      local grip = CreateFrame("Button", nil, win)
      grip:SetWidth(16)
      grip:SetHeight(16)
      grip:SetPoint("BOTTOMRIGHT")
      local sizes = {}
      win:SetScript("OnSizeChanged", function(self, w, h) sizes[#sizes + 1] = w .. "x" .. h end)
      grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
      grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing() end)
      M.Drag(grip, 100, -50)
      H.eq(win:GetWidth(), 500)
      H.eq(win:GetHeight(), 350)
      M.Drag(grip, -1000, 1000)      -- Mindestgroesse
      H.eq(win:GetWidth(), 200)
      H.eq(win:GetHeight(), 150)
      H.truthy(#sizes >= 2)
      -- ohne SetMovable wirft StartMoving
      local f = CreateFrame("Frame")
      H.throws(function() f:StartMoving() end, "not movable")
      H.throws(function() f:StartSizing() end, "not resizable")
   end)

   H.test("Backdrop und Texturen", function()
      local f = CreateFrame("Frame")
      local bd = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
      f:SetBackdrop(bd)
      H.eq(f:GetBackdrop(), bd)
      f:SetBackdropColor(0.1, 0.2, 0.3, 0.4)
      H.deepEq({ f:GetBackdropColor() }, { 0.1, 0.2, 0.3, 0.4 })
      f:SetBackdropBorderColor(1, 0, 0)
      H.deepEq({ f:GetBackdropBorderColor() }, { 1, 0, 0, 1 })
      H.throws(function() f:SetBackdropColor("a", 1, 1) end, "bad argument")
      local t = f:CreateTexture(nil, "BACKGROUND")
      t:SetTexture("Interface\\Buttons\\WHITE8X8")
      H.eq(t:GetTexture(), "Interface\\Buttons\\WHITE8X8")
      t:SetTexture(1, 0, 0, 1)
      H.eq(t:GetTexture(), nil)
      t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      H.eq(select("#", t:GetTexCoord()), 8)
      t:SetVertexColor(1, 1, 1)
      t:SetBlendMode("ADD")
      H.throws(function() t:SetBlendMode("SCREEN") end, "invalid blend mode")
      t:SetDesaturated(true)
      t:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 1, 1, 1, 1)
      t:SetDrawLayer("OVERLAY", 2)
      H.deepEq({ t:GetDrawLayer() }, { "OVERLAY", 2 })
      t:SetAllPoints(f)
      H.eq(t:GetNumPoints(), 2)
      H.eq(t:GetParent(), f)
      H.eq(f:GetNumRegions(), 1)
      H.eq(f:GetRegions(), t)
      -- Button-Texturen
      local b = CreateFrame("Button")
      b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
      H.eq(b:GetNormalTexture():GetTexture(), "Interface\\Buttons\\UI-CheckBox-Up")
      b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
      H.eq(b:GetHighlightTexture().__blend, "ADD")
      H.eq(b:GetPushedTexture(), nil)
   end)

   H.test("StaticPopup: Show/Accept/Cancel", function()
      local accepted, cancelled
      StaticPopupDialogs["TRANSMOG_SELFTEST"] = {
         text = "Delete %s?", button1 = "Yes", button2 = "No", hasEditBox = 1,
         OnAccept = function(self, data) accepted = { data, self.editBox ~= nil or StaticPopup1EditBox:GetText() } end,
         OnCancel = function(self, data, reason) cancelled = reason end,
         timeout = 0, whileDead = 1, hideOnEscape = 1,
      }
      local d = StaticPopup_Show("TRANSMOG_SELFTEST", "Outfit", nil, { id = 5 })
      H.truthy(d)
      H.eq(M.popup.text, "Delete Outfit?")
      H.eq(d:IsShown(), 1)
      H.truthy(M.PopupAccept("typed"))
      H.eq(accepted[1].id, 5)
      H.eq(d:IsShown(), nil)
      StaticPopup_Show("TRANSMOG_SELFTEST", "X")
      M.PopupCancel()
      H.eq(cancelled, "clicked")
      H.eq(StaticPopup_Show("NO_SUCH_POPUP"), nil)
   end)

   H.test("Slash-Befehle und Sounds, Chat", function()
      local got
      SLASH_TRANSMOGTEST1 = "/stest"
      SlashCmdList["TRANSMOGTEST"] = function(msg) got = msg end
      H.eq(M.Slash("/STEST  hello world"), true)
      H.eq(got, "hello world")
      H.eq(M.Slash("/nope"), false)
      PlaySound("igMainMenuOpen")
      PlaySoundFile("Interface\\AddOns\\Elsewhere\\x.ogg")
      H.eq(#M.sounds, 2)
      H.eq(M.sounds[1].kind, "sound")
      DEFAULT_CHAT_FRAME:AddMessage("hallo")
      H.eq(M.messages[#M.messages], "hallo")
      H.eq(ChatEdit_InsertLink("|cff|Hitem:1|h[X]|h|r"), true)
      H.eq(#M.chatInserts, 1)
      H.eq(IsModifiedClick("CHATLINK"), nil)
      M.world.shift = true
      H.eq(IsModifiedClick("CHATLINK"), 1)
      M.world.modifiedClick.CHATLINK = false
      H.eq(IsModifiedClick("CHATLINK"), nil)
   end)

   -- ======================================================================
   H.section("Randfaelle")
   -- ======================================================================

   H.test("Addon-Dateien: Texturen/Toene mit fehlender Datei werden gemeldet", function()
      local dir = makeTempDir()
      os.execute('mkdir -p "' .. dir .. '/assets"')
      writeFile(dir .. "/assets/exists.ogg", "OggS")
      local oldRoot = M.root
      M.root = dir
      local f = CreateFrame("Frame")
      local t = f:CreateTexture()
      t:SetTexture("Interface\\AddOns\\Transmog\\assets\\exists.ogg")      -- gibt es
      H.eq(#M.missingAssets, 0)
      PlaySoundFile("Interface\\AddOns\\Transmog\\assets\\exists.ogg")
      H.eq(#M.missingAssets, 0)
      t:SetTexture("Interface\\AddOns\\Transmog\\assets\\nope.tga")
      PlaySoundFile("Interface\\AddOns\\Transmog\\assets\\nope.ogg")
      M.root = oldRoot
      removeDir(dir)
      H.eq(#M.missingAssets, 2)
      H.eq(M.missingAssets[1].kind, "texture")
      H.eq(M.missingAssets[2].kind, "sound")
      -- Blizzard-Pfade werden nicht geprueft
      t:SetTexture("Interface\\Buttons\\DoesNotMatter")
      H.eq(#M.missingAssets, 2)
      H.allowMissingAssets()
   end)

   H.test("Textbreite: ASCII, Umlaute und CJK", function()
      local f = CreateFrame("Frame")
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs:SetText("AAAA")
      local ascii = fs:GetStringWidth()
      fs:SetText("\195\164\195\164\195\164\195\164")
      local umlaut = fs:GetStringWidth()
      fs:SetText("\228\184\173\228\184\173\228\184\173\228\184\173")
      local cjk = fs:GetStringWidth()
      H.truthy(ascii > 0 and umlaut >= ascii and cjk > umlaut, ascii .. " " .. umlaut .. " " .. cjk)
      -- Farbcodes und Texturen zaehlen nicht
      fs:SetText("|cffff0000AAAA|r")
      H.eq(fs:GetStringWidth(), ascii)
      -- Mehrzeilig, Umbruch bei fester Breite
      fs:SetText("a\nb\nc")
      H.eq(fs:GetStringHeight(), 36)
      fs:SetText("AAAA AAAA AAAA AAAA")
      fs:SetWidth(30)
      H.truthy(fs:GetStringHeight() > 12)
   end)

   H.test("Fehlerfaelle bei Ankern, Ziehen, Texturen und Schriften", function()
      local f = CreateFrame("Frame", nil, UIParent)
      local tex = f:CreateTexture()
      f:SetAllPoints("UIParent")
      H.eq(f:GetNumPoints(), 2)
      H.throws(function() f:SetAllPoints("NoSuchRegion") end, "couldn't find")
      H.throws(function() f:SetAllPoints(42) end, "invalid argument")
      f:SetResizable(true)
      H.throws(function() f:StartSizing("MIDDLE") end, "unknown anchor point")
      H.throws(function() f:RegisterForDrag("ButtonX") end, "invalid mouse button")
      H.throws(function() tex:SetDrawLayer("FOREGROUND") end, "invalid draw layer")
      H.throws(function() tex:SetGradient("DIAGONAL", 0, 0, 0, 1, 1, 1) end, "orientation")
      H.throws(function() tex:SetGradientAlpha("DIAGONAL", 0, 0, 0, 0, 1, 1, 1, 1) end, "orientation")
      H.throws(function() tex:SetTexCoord(0, 1) end, "4 or 8")
      tex:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
      H.deepEq({ tex:GetTexCoord() }, { 0, 0, 0, 1, 1, 0, 1, 1 })
      tex:SetTexture("Interface\\Buttons\\WHITE8X8")
      tex:SetTexture(nil)
      H.eq(tex:GetTexture(), nil)
      H.throws(function() tex:SetTexture(true) end, "bad argument")
      local fs = f:CreateFontString()
      H.throws(function() fs:SetFontObject("NoSuchFont") end, "unknown font object")
      H.throws(function() fs:SetFontObject(42) end, "expected a font object")
      fs:SetFontObject("GameFontNormal")      -- Name ist erlaubt
      H.eq(fs:GetFontObject(), GameFontNormal)
      H.throws(function() fs:SetJustifyV("CENTER") end, "invalid value")
      local font = CreateFont("STFont")
      font:SetFont(STANDARD_TEXT_FONT, 20)
      font:SetTextColor(1, 0, 0)
      fs:SetFontObject(font)
      H.eq(select(2, fs:GetFont()), 20)
      H.eq(CreateFont("STFont"), font)
      H.throws(function() f:SetPoint("CENTER", {}) end, "relativeTo must be a frame")
      H.throws(function() f:GetScript("OnClick") end, "unknown script")
      H.throws(function() f:HookScript("OnClick", function() end) end, "unknown script")
   end)

   H.test("Button: AnyDown, Zustaende, Texturen als Objekt oder nil", function()
      local b = CreateFrame("Button", nil, UIParent)
      local n = 0
      b:SetScript("OnClick", function(self, btn, down) if down then n = n + 1 end end)
      b:RegisterForClicks("AnyDown")
      M.Click(b, "RightButton")
      H.eq(n, 1)
      H.throws(function() b:SetButtonState("DISABLED") end, "NORMAL or PUSHED")
      b:SetButtonState("PUSHED", true)
      H.eq(b:GetButtonState(), "PUSHED")
      H.throws(function() b:SetHighlightTexture("x", "SCREEN") end, "invalid blend mode")
      local t = b:CreateTexture()
      b:SetNormalTexture(t)
      H.eq(b:GetNormalTexture(), t)
      b:SetNormalTexture(nil)
      H.eq(b:GetNormalTexture(), nil)
      H.throws(function() b:SetNormalTexture(5) end, "texture path")
      local other = CreateFrame("Frame"):CreateFontString(nil, nil, "GameFontNormal")
      b:SetFontString(other)
      H.eq(other:GetParent(), b)
      H.throws(function() b:SetFontString("x") end, "expected a FontString")
      H.throws(function() b:SetNormalFontObject("NoSuchFont") end, "unknown font object")
   end)

   H.test("EditBox: nil/Zahl/falscher Typ, Insert, MaxLetters zaehlt Zeichen", function()
      local e = CreateFrame("EditBox", nil, UIParent)
      e:SetFontObject(ChatFontNormal)
      e:SetText(nil)
      H.eq(e:GetText(), "")
      e:SetText(42)
      H.eq(e:GetText(), "42")
      H.throws(function() e:SetText({}) end, "bad argument")
      e:SetText("ab")
      e:Insert("X")
      H.eq(e:GetText(), "abX")
      e:SetCursorPosition(1)
      e:Insert("Y")
      H.eq(e:GetText(), "aYbX")
      e:SetMaxLetters(3)
      e:SetText("\195\164\195\182\195\188\195\159")      -- 4 Zeichen, 8 Bytes
      H.eq(e:GetText(), "\195\164\195\182\195\188")
      e:HighlightText()
      H.deepEq(e.__highlight, { 0, -1 })
   end)

   H.test("Slider/StatusBar: weitere Fehler, ScrollFrame-Template verdrahtet Leiste und Mausrad", function()
      local sb = CreateFrame("StatusBar")
      H.throws(function() sb:SetOrientation("DIAGONAL") end, "must be")
      H.throws(function() sb:SetMinMaxValues(3, 1) end, "greater than max")
      sb:SetValue(0.5)
      sb:SetMinMaxValues(0, 0.25)
      H.eq(sb:GetValue(), 0.25)
      local sl = CreateFrame("Slider")
      H.throws(function() sl:SetValueStep(-1) end, "negative")
      local sf = CreateFrame("ScrollFrame", "STSF2", UIParent, "UIPanelScrollFrameTemplate")
      local child = CreateFrame("Frame", nil, sf)
      sf:SetWidth(50)
      sf:SetHeight(50)
      child:SetWidth(50)
      child:SetHeight(250)
      sf:SetScrollChild(child)
      local bar = STSF2ScrollBar
      H.deepEq({ bar:GetMinMaxValues() }, { 0, 200 })
      bar:SetValue(40)
      H.eq(sf:GetVerticalScroll(), 40)
      sf:SetVerticalScroll(60)
      H.eq(bar:GetValue(), 60)
      M.Wheel(sf, -1)
      H.eq(sf:GetVerticalScroll(), 80)
   end)

   H.test("Verschiedene Globals: GetItemIcon/Count, CVars, Einheiten, Chatfilter, ModifiedItemClick", function()
      M.items[77] = { name = "Gem", icon = "Interface\\Icons\\INV_Misc_Gem_01" }
      M.world.itemCounts[77] = 5
      H.eq(GetItemIcon(77), "Interface\\Icons\\INV_Misc_Gem_01")
      H.eq(GetItemIcon("item:77:0"), "Interface\\Icons\\INV_Misc_Gem_01")
      H.eq(GetItemIcon(1), nil)
      H.eq(GetItemCount(77), 5)
      H.eq(GetItemCount(78), 0)
      SetCVar("uiScale", 0.8)
      H.eq(GetCVar("uiScale"), "0.8")
      H.eq(GetCVarBool("uiScale"), nil)
      SetCVar("someFlag", 1)
      H.eq(GetCVarBool("someFlag"), 1)
      H.eq(select(4, GetBuildInfo()), 30300)
      H.eq(select("#", GetGameTime()), 2)
      M.world.units.target = { name = "Bob", level = 12, isPlayer = true, guid = "0xAB", sex = 3 }
      H.eq(UnitName("target"), "Bob")
      H.eq(UnitExists("target"), 1)
      H.eq(UnitExists("focus"), nil)
      H.eq(UnitIsPlayer("target"), 1)
      H.eq(UnitLevel("target"), 12)
      H.eq(UnitGUID("target"), "0xAB")
      H.eq(UnitSex("target"), 3)
      H.eq(UnitIsUnit("player", "player"), 1)
      H.eq(UnitIsUnit("player", "target"), nil)
      M.world.dead = true
      M.world.combat = true
      H.eq(UnitIsDeadOrGhost("player"), 1)
      H.eq(UnitAffectingCombat("player"), 1)
      H.eq(InCombatLockdown(), 1)
      -- Chatfilter
      local seen
      ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(frame, event, msg) seen = msg return msg == "hide me" end)
      H.eq(M.Filtered("CHAT_MSG_SYSTEM", "hide me"), true)
      H.eq(M.Filtered("CHAT_MSG_SYSTEM", "keep"), false)
      H.eq(seen, "keep")
      -- HandleModifiedItemClick
      H.eq(HandleModifiedItemClick("|cff|Hitem:77|h[Gem]|h|r"), false)
      M.world.shift = true
      H.eq(HandleModifiedItemClick("|cff|Hitem:77|h[Gem]|h|r"), true)
      H.eq(#M.chatInserts, 1)
      M.world.shift = false
      M.world.ctrl = true
      H.eq(HandleModifiedItemClick("|cff|Hitem:77|h[Gem]|h|r"), true)
      H.eq(#M.dressUps, 1)
      SetItemRef("item:77", "x", "LeftButton")
      H.eq(M.itemRefs[1].link, "item:77")
      -- Tooltip-Helfer
      GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
      H.eq(GameTooltip:GetOwner(), UIParent)
      GameTooltip:Show()
      GameTooltip_Hide()
      H.eq(GameTooltip:IsShown(), nil)
      -- Chat-EditBox
      H.eq(ChatEdit_GetActiveWindow(), nil)
      M.world.chatOpen = true
      H.eq(ChatEdit_GetActiveWindow(), ChatFrame1EditBox)
      M.world.combat = false
      H.eq(InCombatLockdown(), nil)
   end)

   H.test("StaticPopup_Hide, UIFrameFadeIn, M.Key/M.Type Fehlerfaelle", function()
      StaticPopupDialogs["TRANSMOG_STH"] = { text = "x", button1 = "ok" }
      local d = StaticPopup_Show("TRANSMOG_STH")
      H.eq(d:IsShown(), 1)
      StaticPopup_Hide("TRANSMOG_STH")
      H.eq(d:IsShown(), nil)
      local f = CreateFrame("Frame")
      UIFrameFadeIn(f, 1, 0, 1)
      H.eq(f:GetAlpha(), 0)
      M.Advance(1.1)
      H.eq(f:GetAlpha(), 1)
      local kf = CreateFrame("Frame", nil, UIParent)
      H.throws(function() M.Key(kf, "A") end, "EnableKeyboard")
      kf:EnableKeyboard(true)
      local keys = {}
      kf:SetScript("OnKeyDown", function(self, k) keys[#keys + 1] = k end)
      M.Key(kf, "A")
      H.deepEq(keys, { "A" })
      local e = CreateFrame("EditBox", nil, UIParent)
      e:SetFontObject(ChatFontNormal)
      e:Hide()
      H.throws(function() M.Type(e, "x") end, "not visible")
      H.throws(function() M.Model(kf) end, "not a Model")
      H.throws(function() M.Slash("transmog") end, "expected")
      H.throws(function() M.RunBinding("NOPE") end, "unknown binding")
      H.throws(function() M.Fire(5) end, "event name")
      H.throws(function() M.Advance(-1) end, ">= 0")
   end)

   H.test("Rest: GlobalMisses, SetScreen, ItemDueAt, Unhandled, Inventar-Texturen, MouseIsOver", function()
      local dir = makeTempDir()
      writeFile(dir .. "/M.lua", "TransmogProbeValue = NeverDefinedA or NeverDefinedB\n"
         .. "TransmogProbeValue2 = NeverDefinedA\n")
      M.LoadFiles({ dir .. "/M.lua" })
      removeDir(dir)
      local misses = M.GlobalMisses()
      H.eq(#misses, 2)
      H.eq(misses[1].name, "NeverDefinedA")
      H.eq(misses[1].count, 2)
      H.truthy(misses[1].where:find("M.lua", 1, true))
      _G.NeverDefinedB = 1       -- inzwischen definiert: kein Fehlgriff mehr
      H.eq(#M.GlobalMisses(), 1)
      M.SetScreen(1024, 768)
      H.eq(GetScreenWidth(), 1024)
      M.items[9] = { name = "Nine", icon = "Interface\\Icons\\INV_Misc_Gem_02", quality = 3 }
      H.eq(M.ItemDueAt(9), nil)
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetHyperlink("item:9")
      H.near(M.ItemDueAt(9), M.now + 0.3, 1e-9)
      M.CacheItem(9)
      H.eq(M.ItemDueAt(9), M.now)
      M.world.equipment[2] = 9
      H.eq(GetInventoryItemTexture("player", 2), "Interface\\Icons\\INV_Misc_Gem_02")
      H.eq(GetInventoryItemQuality("player", 2), 3)
      H.eq(GetInventoryItemTexture("player", 3), nil)
      local b = CreateFrame("Button", nil, UIParent)
      H.eq(MouseIsOver(b), nil)
      M.Enter(b)
      H.eq(MouseIsOver(b), 1)
      H.eq(MouseIsOver(UIParent), 1, "Eltern enthalten das Kind unter der Maus")
      H.throws(function() GameTooltip:SetOwner(5, "ANCHOR_NONE") end, "owner must be a frame")
      M.errors[#M.errors + 1] = "synthetic"
      H.eq(#M.Unhandled(), 1)
      M.ClearErrors()
      H.eq(#M.errors, 0)
   end)

   H.test("XML: <Script file> und <Include file> werden ausgefuehrt", function()
      local dir = makeTempDir()
      writeFile(dir .. "/X.toc", "## Interface: 30300\nMain.xml\n")
      writeFile(dir .. "/Main.xml", '<Ui>\n<Script file="One.lua"/>\n<Include file="Sub.xml"/>\n</Ui>\n')
      writeFile(dir .. "/Sub.xml", '<Ui>\n<Script file="Two.lua"/>\n'
         .. '<Frame name="SubVirtual" virtual="true"/>\n</Ui>\n')
      writeFile(dir .. "/One.lua", "TransmogProbeOrder = { 'one' }\n")
      writeFile(dir .. "/Two.lua", "TransmogProbeOrder[#TransmogProbeOrder + 1] = 'two'\n")
      local loaded = M.LoadToc(dir, "X.toc")
      removeDir(dir)
      H.deepEq(TransmogProbeOrder, { "one", "two" })
      H.truthy(#loaded >= 3)
      H.truthy(CreateFrame("Frame", nil, UIParent, "SubVirtual"))
   end)

   -- ======================================================================
   H.section("Laden: LoadFiles / LoadToc / XML / Umgebung")
   -- ======================================================================

   H.test("LoadToc: Reihenfolge, gemeinsame Addon-Tabelle, XML-Templates, Bindings, Metadaten", function()
      local dir = makeTempDir()
      writeFile(dir .. "/Probe.toc", table.concat({
         "## Interface: 30300",
         "## Title: Probe",
         "## Title-deDE: Probe DE",
         "## Version: 1.5",
         "## SavedVariables: ProbeDB",
         "A.lua",
         "sub\\B.lua",
         "T.xml",
         "Bindings.xml",
         "Missing.lua",
      }, "\r\n") .. "\r\n")
      writeFile(dir .. "/A.lua", [[
local name, addon = ...
ProbeOrder = { name }
ProbeAddon = addon
addon.fromA = true
]])
      os.execute('mkdir -p "' .. dir .. '/sub"')
      writeFile(dir .. "/sub/B.lua", [[
local name, addon = ...
ProbeOrder[#ProbeOrder + 1] = "B"
ProbeShared = (addon == ProbeAddon) and addon.fromA
ProbeIo = (io == nil) and (os == nil) and (debug == nil)
ProbeUndefined = SomeNeverDefinedGlobal
]])
      writeFile(dir .. "/T.xml", [[
<Ui xmlns="http://www.blizzard.com/wow/ui/">
   <!-- <Frame name="Commented" virtual="true"/> -->
   <DressUpModel name="ProbeCellTemplate" virtual="true" scale="4.0">
      <Size><AbsDimension x="80" y="107"/></Size>
   </DressUpModel>
   <Button name="ProbeButtonTemplate" inherits="UIPanelButtonTemplate" virtual="true" enableMouse="false" hidden="true">
      <Size><AbsDimension x="120" y="30"/></Size>
   </Button>
</Ui>
]])
      writeFile(dir .. "/Bindings.xml", [[
<Bindings>
   <Binding name="PROBE_TOGGLE" header="PROBE">ProbeBound = (ProbeBound or 0) + 1</Binding>
</Bindings>
]])
      local loaded, info = M.LoadToc(dir, "Probe.toc", { skipMissing = true })
      removeDir(dir)
      H.deepEq(loaded, { "A.lua", "sub/B.lua", "T.xml", "Bindings.xml" })
      H.deepEq(info.missing, { "Missing.lua" })
      H.deepEq(ProbeOrder, { "Probe", "B" })
      H.eq(ProbeShared, true)
      H.eq(ProbeIo, true)
      H.eq(ProbeUndefined, nil)
      H.truthy(M.globalMisses.SomeNeverDefinedGlobal)
      H.truthy(M.globalMisses.SomeNeverDefinedGlobal.where:find("B.lua", 1, true))
      H.truthy(M.globalWrites.ProbeOrder)
      H.eq(GetAddOnMetadata("Probe", "Version"), "1.5")
      H.eq(GetAddOnMetadata("Probe", "Title"), "Probe")
      H.eq(GetAddOnMetadata("Nope", "Title"), nil)
      -- Templates aus dem XML
      local m = CreateFrame("DressUpModel", nil, UIParent, "ProbeCellTemplate")
      H.eq(m:GetWidth(), 80)
      H.eq(m:GetHeight(), 107)
      H.eq(m:GetModelScale(), 4)
      H.eq(m:GetScale(), 1)
      local b = CreateFrame("Button", nil, UIParent, "ProbeButtonTemplate")
      H.eq(b:GetWidth(), 120)
      H.eq(b:IsShown(), nil)
      H.eq(b:IsMouseEnabled(), nil)
      H.truthy(b:GetFontString(), "geerbtes Template")
      -- Binding ausfuehren
      M.RunBinding("PROBE_TOGGLE")
      H.eq(ProbeBound, 1)
      -- ungueltige Template-Kombination
      H.throws(function() CreateFrame("Frame", nil, UIParent, "ProbeCellTemplate") end, "cannot be used")
      H.allowStrays()
   end)

   H.test("LoadToc: upTo, skip, Interface-Pruefung, Fehlermeldungen mit Dateiname", function()
      local dir = makeTempDir()
      writeFile(dir .. "/P.toc", "## Interface: 30300\nA.lua\nB.lua\nC.lua\n")
      writeFile(dir .. "/A.lua", "PA = 1\n")
      writeFile(dir .. "/B.lua", "PB = 1\n")
      writeFile(dir .. "/C.lua", "PC = 1\n")
      local loaded = M.LoadToc(dir, "P.toc", { upTo = "B.lua" })
      H.deepEq(loaded, { "A.lua", "B.lua" })
      H.eq(PC, nil)
      M.Install()
      H.throws(function() M.LoadToc(dir, "P.toc", { upTo = "Nope.lua" }) end, "not listed")
      M.Install()
      loaded = M.LoadToc(dir, "P.toc", { skip = { ["B.lua"] = true } })
      H.deepEq(loaded, { "A.lua", "C.lua" })
      H.eq(PB, nil)
      M.Install()
      -- Syntaxfehler nennt die Datei
      writeFile(dir .. "/B.lua", "local x = = 1\n")
      local e = errOf(function() M.LoadToc(dir, "P.toc") end)
      H.truthy(e and e:find("B.lua", 1, true) and e:find("Syntax error", 1, true), e)
      M.Install()
      -- Laufzeitfehler beim Laden nennt die Datei
      writeFile(dir .. "/B.lua", "local t = nil\nt.x = 1\n")
      e = errOf(function() M.LoadToc(dir, "P.toc") end)
      H.truthy(e and e:find("B.lua", 1, true) and e:find("Error while loading", 1, true), e)
      M.Install()
      -- fehlende Datei ohne skipMissing
      writeFile(dir .. "/P.toc", "## Interface: 30300\nA.lua\nGone.lua\n")
      e = errOf(function() M.LoadToc(dir, "P.toc") end)
      H.truthy(e and e:find("Gone.lua", 1, true), e)
      -- falsche Interface-Nummer
      writeFile(dir .. "/P.toc", "## Interface: 40200\nA.lua\n")
      e = errOf(function() M.LoadToc(dir, "P.toc") end)
      H.truthy(e and e:find("30300", 1, true), e)
      removeDir(dir)
      H.allowStrays()
   end)

   H.test("LoadFiles: Lua-5.1-Pruefungen (goto, BOM), xpcall-Argumente, load(String)", function()
      local dir = makeTempDir()
      writeFile(dir .. "/G.lua", "for i = 1, 3 do\n   if i == 2 then goto continue end\n   ::continue::\nend\n")
      local e = errOf(function() M.LoadFiles({ dir .. "/G.lua" }) end)
      H.truthy(e and e:find("goto", 1, true), e)
      -- goto/:: in Strings und Kommentaren ist harmlos
      writeFile(dir .. "/H.lua", "-- goto x\nlocal s = 'goto y ::z::'\nlocal t = [[goto q]]\nPH = 1\n")
      M.LoadFiles({ dir .. "/H.lua" })
      H.eq(PH, 1)
      writeFile(dir .. "/BOM.lua", "\239\187\191PB = 1\n")
      e = errOf(function() M.LoadFiles({ dir .. "/BOM.lua" }) end)
      H.truthy(e and e:find("BOM", 1, true), e)
      writeFile(dir .. "/X.lua", "XR = select('#', pcall(xpcall, function() end, print, 1))\n"
         .. "XE = select(2, pcall(function() return xpcall(function() end, print, 1) end))\n"
         .. "XL = select(2, pcall(function() return load('return 1') end))\n"
         .. "XP = print\nprint('from addon')\n")
      M.LoadFiles({ dir .. "/X.lua" })
      H.truthy(tostring(XE):find("extra arguments", 1, true), XE)
      H.truthy(tostring(XL):find("loadstring", 1, true), XL)
      H.eq(M.messages[#M.messages], "from addon")
      removeDir(dir)
      H.allowStrays()
   end)

   H.test("StrayGlobals meldet Globals ausserhalb des erlaubten Namensraums", function()
      local dir = makeTempDir()
      writeFile(dir .. "/S.lua", "TransmogDB = {}\ntransmogOutfits = {}\nSLASH_TRANSMOG1 = '/t'\n"
         .. "BINDING_NAME_TRANSMOG_TOGGLE = 'x'\nLeakedHelper = 1\nfunction leakedFn() end\n")
      M.LoadFiles({ dir .. "/S.lua" })
      removeDir(dir)
      local stray = M.StrayGlobals()
      H.eq(#stray, 2)
      H.truthy(stray[1]:find("LeakedHelper", 1, true) or stray[2]:find("LeakedHelper", 1, true))
      H.truthy(stray[1]:find("leakedFn", 1, true) or stray[2]:find("leakedFn", 1, true))
      H.allowStrays()
   end)

   H.test("SavedVariables: nur einfache Daten ueberleben die Abmeldung", function()
      local dir = makeTempDir()
      writeFile(dir .. "/SV.toc", "## Interface: 30300\n## SavedVariables: TransmogGlobalDB\n"
         .. "## SavedVariablesPerCharacter: TransmogDB, transmogOutfits\nA.lua\n")
      writeFile(dir .. "/A.lua", "TransmogGlobalDB = TransmogGlobalDB or { count = 0 }\n"
         .. "TransmogGlobalDB.count = TransmogGlobalDB.count + 1\n"
         .. "TransmogGlobalDB.fn = function() end\n"
         .. "TransmogGlobalDB.list = { 'a', 'b', n = 2 }\n")
      M.LoadToc(dir, "SV.toc")
      H.eq(TransmogGlobalDB.count, 1)
      local sv = M.SavedVariables()
      H.eq(sv.TransmogDB, nil)
      H.eq(sv.TransmogGlobalDB.count, 1)
      H.eq(sv.TransmogGlobalDB.fn, nil, "Funktionen werden nicht gespeichert")
      H.deepEq(sv.TransmogGlobalDB.list, { "a", "b", n = 2 })
      M.Install({ globals = sv })
      M.LoadToc(dir, "SV.toc")
      H.eq(TransmogGlobalDB.count, 2, "zweite Sitzung sieht die Daten der ersten")
      removeDir(dir)
   end)

   H.test("ImplicitGlobalReads meldet this/event/arg1; UpdateFrames listet laufende OnUpdate-Frames", function()
      local dir = makeTempDir()
      writeFile(dir .. "/I.lua", "function ProbeOldHandler() return this, arg1, event end\n"
         .. "TransmogProbeFn = function(self, event) return event end\n")
      M.LoadFiles({ dir .. "/I.lua" })
      removeDir(dir)
      H.eq(#M.ImplicitGlobalReads(), 0, "noch nicht gelesen")
      ProbeOldHandler()
      TransmogProbeFn(nil, "x")
      local reads = M.ImplicitGlobalReads()
      H.eq(#reads, 3)
      H.truthy(reads[1]:find("arg1", 1, true))
      H.allowImplicit()
      H.allowStrays()

      local f = CreateFrame("Frame")
      H.eq(#M.UpdateFrames(), 0)
      f:SetScript("OnUpdate", function() end)
      H.deepEq(M.UpdateFrames(), { f })
      f:Hide()
      H.eq(#M.UpdateFrames(), 0)
   end)

   H.test("StrayFrameNames meldet benannte Frames ausserhalb von Transmog*", function()
      CreateFrame("Frame", "TransmogOk", UIParent)
      CreateFrame("Frame", "SomethingElse", UIParent)
      local names = M.StrayFrameNames()
      H.deepEq(names, { "SomethingElse" })
   end)

   H.test("Walk, Texts, HasText, Find", function()
      local root = CreateFrame("Frame", nil, UIParent)
      local fs1 = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs1:SetText("one")
      local child = CreateFrame("Frame", nil, root)
      local fs2 = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs2:SetText("two")
      local fs3 = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      fs3:SetText("hidden")
      fs3:Hide()
      local empty = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      empty:SetText("")
      H.deepEq(M.Texts(root), { "one", "two" })
      H.deepEq(M.Texts(root, true), { "one", "two", "hidden" })
      child:Hide()
      H.deepEq(M.Texts(root), { "one" })
      H.eq(M.HasText(root, "on"), true)
      H.eq(M.HasText(root, "two"), false)
      H.eq(#M.Find(root, "FontString"), 4)
      local n = 0
      M.Walk(root, function() n = n + 1 end)
      H.eq(n, 6)
      H.eq(M.FindFrame("nope"), nil)
   end)

   H.test("H.boot: Welt/Items vor dem Laden, Ereignisreihenfolge, login/enterWorld, Rueckgabe", function()
      local dir = makeTempDir()
      writeFile(dir .. "/Transmog.toc", "## Interface: 30300\n## SavedVariables: TransmogGlobalDB\n"
         .. "Init.lua\nMissing.lua\nBoot.lua\n")
      writeFile(dir .. "/Init.lua", [[
Transmog = Transmog or {}
local T = Transmog
T.log = {}
T.localeAtLoad = GetLocale()
T.itemAtLoad = M_ITEMS_PROBE
T.dbAtLoad = TransmogGlobalDB and TransmogGlobalDB.preset
local f = CreateFrame("Frame", "TransmogProbeFrame")
for _, ev in ipairs({ "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
   f:RegisterEvent(ev)
end
f:SetScript("OnEvent", function(self, event, arg)
   T.log[#T.log + 1] = event .. (arg and (":" .. tostring(arg)) or "")
end)
]])
      writeFile(dir .. "/Boot.lua", "Transmog.bootLoaded = true\n")
      local oldRoot = M.root
      M.root = dir
      local ok, T = pcall(H.boot, {
         world = { locale = "frFR" }, items = { [1] = { name = "X" } },
         globals = { TransmogGlobalDB = { preset = 5 } },
      })
      M.root = oldRoot
      H.truthy(ok, tostring(T))
      H.eq(T.localeAtLoad, "frFR")
      H.eq(T.dbAtLoad, 5)
      H.eq(T.bootLoaded, true)
      H.deepEq(T.log, { "ADDON_LOADED:Transmog", "VARIABLES_LOADED", "PLAYER_LOGIN" })
      H.deepEq(H.loadInfo.missing, { "Missing.lua" })
      H.eq(IsLoggedIn(), 1)
      -- login = false, enterWorld = true
      M.root = dir
      ok, T = pcall(H.boot, { login = false })
      M.root = oldRoot
      H.deepEq(T.log, { "ADDON_LOADED:Transmog" })
      H.eq(IsLoggedIn(), nil)
      M.root = dir
      ok, T = pcall(H.boot, { enterWorld = true })
      M.root = oldRoot
      H.deepEq(T.log, { "ADDON_LOADED:Transmog", "VARIABLES_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })
      -- skipMissing = false meldet die fehlende Datei
      M.root = dir
      local ok2, e = pcall(H.boot, { skipMissing = false })
      M.root = oldRoot
      H.eq(ok2, false)
      H.truthy(tostring(e):find("Missing.lua", 1, true), e)
      removeDir(dir)
   end)

   -- H.beforeEach: laeuft vor jedem Test der Datei, nach dem automatischen Zuruecksetzen
   local ran = 0
   H.beforeEach(function()
      ran = ran + 1
      _G.TransmogBeforeEachProbe = ran
   end)
   H.test("beforeEach: erster Test", function() H.eq(TransmogBeforeEachProbe, 1) H.allowStrays() end)
   H.test("beforeEach: zweiter Test (Install hat dazwischen alles geloescht)", function()
      H.eq(TransmogBeforeEachProbe, 2)
      H.allowStrays()
   end)
   H.beforeEach(nil)
   H.test("beforeEach: abgeschaltet", function() H.eq(TransmogBeforeEachProbe, nil) end)

end
