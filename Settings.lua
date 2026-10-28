local _, NS = ...

function NS.CreateSettings()
    local root = CreateFrame("Frame")
    root.name = "MessageSplitter"
    local scroll = CreateFrame("ScrollFrame", nil, root, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -28, 0)
    local panel = CreateFrame("Frame", nil, scroll)
    panel:SetSize(760, 900)
    scroll:SetScrollChild(panel)
    scroll:SetScript("OnSizeChanged", function(_, width) panel:SetWidth(width) end)
    local title = NS.Label(panel, "MessageSplitter", 22)
    title:SetPoint("TOPLEFT", 20, -20)
    local description = NS.Label(panel, "Long-form chat. Drag the title area; resize from the bottom-right corner.", 13)
    description:SetPoint("TOPLEFT", 20, -52)
    local y = -88
    local checks = {}
    local function check(key, label)
        local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        button:SetPoint("TOPLEFT", 20, y)
        local text = NS.Label(button, label)
        text:SetPoint("LEFT", button, "RIGHT", 4, 0)
        button:SetChecked(NS.db[key])
        button:SetScript("OnClick", function(self)
            if key == "enabled" then NS.SetEnabled(self:GetChecked())
            else NS.db[key] = self:GetChecked() and true or false end
            NS.CancelQueue(); NS.ApplyStyle(); NS.RefreshPreview(); NS.SaveDraft()
        end)
        checks[key] = button
        y = y - 33
    end
    check("enabled", "Open composer when the native chat box gains focus outside lockdown")
    check("locked", "Lock position and size")
    check("rpColors", "Color emotes, speech and OOC (use TRP3 settings when available)")
    check("markers", "Append >> when a message continues")
    check("emoteContinuation", "Prefix continued emotes with ...")
    check("automatic", "Pace group / guild / whisper parts automatically (local chat stays manual)")
    check("closeAfterSend", "Close after all parts are submitted")
    check("rememberDraft", "Save unsent draft across logout (stored locally in SavedVariables)")
    root:SetScript("OnShow", function()
        for key, button in pairs(checks) do button:SetChecked(NS.db[key]) end
    end)
    local growth = NS.Button(panel, "", 180, function()
        NS.db.growth = NS.db.growth == "UP" and "DOWN" or "UP"
        NS.AnchorGrowth()
    end)
    growth:SetPoint("TOPLEFT", 24, y)
    growth:HookScript("OnClick", function(self) self.label:SetText("Grow: " .. (NS.db.growth == "UP" and "Up" or "Down")) end)
    growth.label:SetText("Grow: " .. (NS.db.growth == "UP" and "Up" or "Down"))
    y = y - 40
    local sliders = {}
    local function slider(key, label, low, high, step, format)
        local s = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 28, y - 20)
        s:SetSize(280, 16)
        s:SetMinMaxValues(low, high)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
        s.Low:SetText(tostring(low)); s.High:SetText(tostring(high))
        local function caption(value) s.Text:SetText(label .. ": " .. string.format(format, value)) end
        s:SetValue(NS.db[key]); caption(NS.db[key])
        s:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / step + 0.5) * step
            NS.db[key] = value; caption(value)
            NS.CancelQueue(); NS.ApplyStyle(); NS.RefreshPreview()
        end)
        sliders[key] = s
        y = y - 66
    end
    slider("maxHeight", "Maximum typing height", 64, 600, 1, "%d")
    slider("fontSize", "Font size", 12, 24, 1, "%d")
    slider("opacity", "Panel opacity", 0.4, 1, 0.05, "%.2f")
    slider("limit", "Wire byte limit (10 bytes reserved)", 64, 255, 1, "%d")
    slider("delay", "Send interval (seconds)", 0.5, 3, 0.1, "%.1f")
    local reset = NS.Button(panel, "Reset position / size", 180, function()
        NS.db.point, NS.db.x, NS.db.y = nil, nil, nil
        NS.db.width, NS.db.height = NS.defaults.width, NS.defaults.height
        NS.ApplyStyle()
    end)
    reset:SetPoint("TOPLEFT", 24, y - 6)
    local help = NS.Label(panel, "Combat and Midnight chat lockdown pause sends. Resume manually when safe.\nDefault chat opens Blizzard's editor with your draft retained here.\n/msplit opens the composer; /msplit reset restores its position.\n/mse on enables MessageSplitter; /mse off disables it.", 12)
    help:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -15)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(root, root.name)
        Settings.RegisterAddOnCategory(category)
        NS.category = category
    end
    NS.settingsPanel = root
end

function NS.OpenSettings()
    if NS.category then Settings.OpenToCategory(NS.category:GetID())
    else NS.Notify("The Retail Settings API is unavailable on this client.") end
end
