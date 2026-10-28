local _, NS = ...
local backdrop = {bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1}
local gold = {0.77, 0.61, 0.33}

function NS.Label(parent, text, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size or 13, "")
    label:SetText(text)
    label:SetTextColor(0.87, 0.85, 0.79)
    label:SetJustifyH("LEFT")
    return label
end

function NS.Button(parent, text, width, action)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, 26)
    button:SetBackdrop(backdrop)
    NS.Skin(button, {0.26, 0.21, 0.12, 0.32}, {0.62, 0.48, 0.25, 0.28})
    button:SetBackdropBorderColor(0.36, 0.31, 0.22, 1)
    button.label = NS.Label(button, text)
    button.label:SetPoint("CENTER")
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function(self) self.wmRoundedBorder:SetColor({1, 0.82, 0.30, 0.8}); self.wmRoundedFill:SetColor({0.26, 0.21, 0.12, 0.65}) end)
    button:SetScript("OnLeave", function(self) self.wmRoundedBorder:SetColor({0.62, 0.48, 0.25, 0.28}); self.wmRoundedFill:SetColor({0.26, 0.21, 0.12, 0.32}) end)
    return button
end

-- Small toolbar controls keep labels and instructions in hover tooltips.
function NS.Tooltip(control, title, detail)
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(type(detail) == "function" and detail() or detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", function() GameTooltip:Hide() end)
    control:HookScript("OnHide", function() GameTooltip:Hide() end)
end

function NS.Icon(parent, texture, title, detail, action)
    local button = NS.Button(parent, "", 18, action)
    button:SetHeight(18)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(texture)
    icon:SetVertexColor(0.88, 0.79, 0.59)
    button:HookScript("OnEnter", function() icon:SetVertexColor(1, 0.9, 0.65) end)
    button:HookScript("OnLeave", function() icon:SetVertexColor(0.88, 0.79, 0.59) end)
    button:SetScript("OnMouseDown", function() icon:SetAlpha(0.55) end)
    button:SetScript("OnMouseUp", function() icon:SetAlpha(1) end)
    NS.Tooltip(button, title, detail)
    return button
end

function NS.SetStatus(text)
    if NS.status then NS.status:SetText(text or "") end
end

function NS.PaintChannel(route)
    route = route or NS.route
    local key = route.type == "CHANNEL" and "CHANNEL" .. tostring(route.target or 1) or route.type
    local color = ChatTypeInfo[key] or ChatTypeInfo[route.type] or ChatTypeInfo.SAY
    local title = _G[route.type] or route.type:gsub("_", " ")
    if route.type == "CHANNEL" then
        local id, name = GetChannelName(route.target or 0)
        title = tostring(id or route.target or "?") .. ". " .. (name or "Channel")
    elseif route.type == "WHISPER" then title = "Whisper" end
    NS.channel.label:SetText(title .. ":")
    NS.channel:SetWidth(math.min(110, math.max(60, NS.channel.label:GetStringWidth() + 26)))
    NS.channel.label:SetTextColor(0.55 + color.r * 0.45, 0.55 + color.g * 0.45, 0.55 + color.b * 0.45)
    NS.Skin(NS.frame, {0.025 + color.r * 0.065, 0.025 + color.g * 0.065,
        0.025 + color.b * 0.065, NS.db.opacity}, {color.r, color.g, color.b, 0.48})
    NS.Skin(NS.well, {color.r * 0.16, color.g * 0.16, color.b * 0.16, 0.35},
        {color.r, color.g, color.b, 0.30})
    local fill = {color.r * 0.22, color.g * 0.22, color.b * 0.22, 0.65}
    local border = {color.r, color.g, color.b, 0.40}
    NS.Skin(NS.channel, fill, border)
    NS.channel:SetScript("OnEnter", function(self)
        self.wmRoundedFill:SetColor({color.r * 0.32, color.g * 0.32, color.b * 0.32, 0.8})
        self.wmRoundedBorder:SetColor({color.r, color.g, color.b, 0.75})
    end)
    NS.channel:SetScript("OnLeave", function(self)
        self.wmRoundedFill:SetColor(fill)
        self.wmRoundedBorder:SetColor(border)
    end)
    if NS.scroll then
        NS.scroll:SetPoint("TOPLEFT", NS.well, "TOPLEFT", NS.channel:GetWidth() + 14, -4)
    end
    NS.rail:SetColorTexture(color.r, color.g, color.b, 0.8)
    NS.editor:SetTextColor(color.r, color.g, color.b, NS.db.rpColors and 0 or 1)
    if NS.coloredText then NS.coloredText:SetTextColor(color.r, color.g, color.b) end
end

function NS.RefreshPreview()
    if not NS.composerReady then return end
    NS.UpdateEditorLayout()
    local queue, err = NS.queue
    if not queue then queue, err = NS.Prepare() end
    if not queue then NS.counter:SetText("Check channel / text"); NS.SetStatus(err); return end
    local progress = NS.queue and (queue.index - 1) .. "/" .. #queue.parts or #queue.parts
    NS.counter:SetText(#NS.GetDraftText() .. "B / " .. progress .. "p")
    NS.PaintChannel(queue.route)
    NS.UpdateEditorLayout()
    if not NS.queue then NS.SetStatus("Enter: send") end
end

function NS.SaveGeometry(saveSize)
    local point, _, relativePoint, x, y = NS.frame:GetPoint(1)
    NS.db.point, NS.db.relativePoint, NS.db.x, NS.db.y = point, relativePoint, x, y
    -- Moving a grown window must not turn its temporary height into a minimum.
    if saveSize then
        NS.db.width, NS.db.height = NS.frame:GetWidth(), NS.frame:GetHeight()
    end
    NS.AnchorGrowth()
end

function NS.ApplyStyle()
    local f, db = NS.frame, NS.db
    NS.Skin(f, {0.085, 0.075, 0.060, db.opacity}, {0.62, 0.48, 0.25, 0.48})
    if NS.well then NS.Skin(NS.well, {0.16, 0.135, 0.095, 0.20}, {0.62, 0.48, 0.25, 0.30}) end
    f:SetSize(db.width, db.height)
    f:ClearAllPoints()
    local valid = {CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    local point = valid[db.point] and db.point or "CENTER"
    local relativePoint = valid[db.relativePoint] and db.relativePoint or point
    f:SetPoint(point, UIParent, relativePoint, tonumber(db.x) or 0, tonumber(db.y) or -160)
    NS.editor:SetFont(STANDARD_TEXT_FONT, db.fontSize, "")
    NS.resize:SetShown(not db.locked)
    if NS.composerReady then NS.PaintChannel() end
    NS.AnchorGrowth()
    NS.UpdateEditorLayout()
end

-- Anchor the stationary edge before changing height; growth never saves a new base size.
function NS.AnchorGrowth()
    local f = NS.frame
    local left, bottom, top = f:GetLeft(), f:GetBottom(), f:GetTop()
    if not left or not bottom or not top then return end
    f:ClearAllPoints()
    if NS.db.growth == "UP" then f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    else f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
end

function NS.UpdateEditorLayout(grow)
    if not NS.coloredText or NS.layoutBusy then return end
    NS.layoutBusy = true
    local text = NS.editor:GetText()
    local display = text
    if NS.db.rpColors then
        local formatter = TRP3_API and TRP3_API.chat and TRP3_API.chat.detectEmoteAndOOC
        if formatter then
            local ok, result = pcall(formatter, text, NS.route.type == "EMOTE")
            if ok and type(result) == "string" then display = result end
        else
            local function hex(c)
                return string.format("|cff%02x%02x%02x", math.floor(c.r*255), math.floor(c.g*255), math.floor(c.b*255))
            end
            -- Protect hyperlinks rather than editing their contents.
            local saved = {}
            display = display:gsub("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", function(link)
                saved[#saved+1] = link; return "\001" .. #saved .. "\002"
            end):gsub("|H.-|h.-|h", function(link)
                saved[#saved+1] = link; return "\001" .. #saved .. "\002"
            end)
            display = display:gsub("(%*[^%*|]+%*)", function(t) return hex(ChatTypeInfo.EMOTE) .. t .. "|r" end)
            display = display:gsub('("[^"|]+")', function(t) return hex(ChatTypeInfo.SAY) .. t .. "|r" end)
            display = display:gsub("(%b())", function(t) return "|cff888888" .. t .. "|r" end)
            display = display:gsub("\001(%d+)\002", function(i) return saved[tonumber(i)] end)
        end
    end
    NS.coloredText:SetFont(STANDARD_TEXT_FONT, NS.db.fontSize, "")
    NS.coloredText:SetWidth(math.max(100, NS.editor:GetWidth() - 4))
    -- Clear the previous measured height before layout, otherwise FontString
    -- truncates the new content to its old height and appends an ellipsis.
    NS.coloredText:SetHeight(0)
    NS.coloredText:SetText(display)
    NS.coloredText:SetShown(NS.db.rpColors)
    -- Reserve a full line even for an empty draft, using the same font metrics
    -- and padding as the growing text. The first character must not resize us.
    NS.lineMeasure:SetFont(STANDARD_TEXT_FONT, NS.db.fontSize, "")
    local lineHeight = NS.lineMeasure:GetStringHeight()
    local base = math.max(NS.db.height, lineHeight + 44)
    -- The viewport has 36 pixels of frame/toolbar padding. Center the first
    -- line in the baseline height, and keep that inset as multiline text grows.
    local padding = math.max(0, (base - 36 - lineHeight) / 2)
    NS.editor:SetTextInsets(0, 4, padding, padding)
    NS.coloredText:ClearAllPoints()
    NS.coloredText:SetPoint("TOPLEFT", NS.editor, "TOPLEFT", 0, -padding)
    local contentHeight = NS.coloredText:GetStringHeight() + padding * 2
    if not NS.resizing then
        if grow then
            NS.frame:SetHeight(math.max(base, math.min(math.max(base, NS.db.maxHeight), contentHeight + 36)))
        elseif NS.frame:GetHeight() < base then
            NS.frame:SetHeight(base)
        end
    end
    NS.layoutBusy = nil
end

function NS.Open()
    if not NS.db.enabled then
        NS.Notify("Disabled. Use /mse on to re-enable.")
        return
    end
    if not NS.composerReady then
        NS.Notify("Composer setup failed: " .. tostring(NS.composerError or "reload the UI to see the setup error."))
        return
    end
    NS.frame:Show()
    NS.recipient:SetShown(NS.route.type == "WHISPER")
    NS.syncRecipient = true
    NS.recipient:SetText(NS.route.type == "WHISPER" and NS.route.target or "")
    NS.syncRecipient = nil
    NS.RefreshPreview()
    if NS.Restricted() then NS.SetStatus("Draft mode during lockdown. Default chat opens native messaging.") end
    NS.editor:SetFocus()
end

function NS.ShowChannels()
    if NS.menu:IsShown() then NS.menu:Hide(); return end
    local choices = {{"Say","SAY"},{"Party","PARTY"},{"Raid","RAID"},{"Raid warning","RAID_WARNING"},
        {"Instance","INSTANCE_CHAT"},{"Guild","GUILD"},{"Officer","OFFICER"},{"Whisper","WHISPER"},
        {"Emote","EMOTE"},{"Yell","YELL"}}
    local channels = {GetChannelList()}
    for i = 1, #channels, 3 do
        if channels[i + 1] then choices[#choices + 1] = {channels[i] .. ". " .. channels[i + 1], "CHANNEL", channels[i]} end
    end
    for _, row in ipairs(NS.menu.rows) do row:Hide() end
    for i, choice in ipairs(choices) do
        local kind, target = choice[2], choice[3]
        local row = NS.menu.rows[i]
        if not row then row = NS.Button(NS.menu, "", 186, nil); NS.menu.rows[i] = row end
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 27)
        row.label:SetText(choice[1])
        local c = ChatTypeInfo[kind == "CHANNEL" and "CHANNEL" .. target or kind] or ChatTypeInfo.SAY
        row.label:SetTextColor(c.r, c.g, c.b)
        row:SetScript("OnClick", function()
            NS.CancelQueue()
            NS.route = {type=kind, target=target}
            NS.recipient:SetShown(kind == "WHISPER")
            NS.menu:Hide()
            NS.RefreshPreview()
            if kind == "WHISPER" then NS.recipient:SetFocus() else NS.editor:SetFocus() end
        end)
        row:Show()
    end
    NS.menu:SetHeight(#choices * 27 + 12)
    NS.menu:Show()
end

function NS.CreateComposer()
    local f = CreateFrame("Frame", "MessageSplitterComposer", UIParent, "BackdropTemplate")
    NS.frame = f
    f:Hide()
    f:SetBackdrop(backdrop)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetResizeBounds(260, 64, 1200, 800)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if not NS.db.locked and not InCombatLockdown() then f:StartMoving() end end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing(); NS.SaveGeometry() end)
    f:SetScript("OnHide", function()
        if NS.resizing then
            f:StopMovingOrSizing()
            NS.SaveGeometry(true)
            NS.resizing = nil
        end
        if NS.editor then NS.editor:ClearFocus() end
        if NS.timer then NS.timer:Cancel(); NS.timer = nil end
        if NS.menu then NS.menu:Hide() end
        NS.SaveDraft()
    end)
    local close = NS.Icon(f, "Interface\\AddOns\\MessageSplitter\\Media\\Close.tga",
        "Close", "Keep draft; Escape also closes.", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -3)
    local settings = NS.Icon(f, "Interface\\AddOns\\MessageSplitter\\Media\\Settings.tga",
        "Settings", nil, NS.OpenSettings)
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local disable = NS.Icon(f, "Interface\\AddOns\\MessageSplitter\\Media\\Power.tga",
        "Disable MessageSplitter", "Re-enable with /mse on", function() NS.SetEnabled(false) end)
    disable:SetPoint("RIGHT", settings, "LEFT", -2, 0)
    local native = NS.Icon(f, "Interface\\AddOns\\MessageSplitter\\Media\\Chat.tga",
        "Default chat", "Open Blizzard's chat box; keep this draft.", NS.DefaultChat)
    native:SetPoint("RIGHT", disable, "LEFT", -2, 0)
    local send = NS.Icon(f, "Interface\\AddOns\\MessageSplitter\\Media\\Send.tga",
        "Send / next part", "Enter: send | Shift+Enter: new line", function()
            NS.SendNext()
            if f:IsShown() then NS.editor:SetFocus() end
        end)
    send:SetPoint("RIGHT", native, "LEFT", -2, 0)

    NS.channel = NS.Button(f, "Say:", 76, NS.ShowChannels)
    NS.channel:SetHeight(30)
    NS.channel.label:SetFont(STANDARD_TEXT_FONT, 16, "")
    NS.channel.label:ClearAllPoints()
    NS.channel.label:SetPoint("TOPLEFT", 8, -1)
    NS.channel.label:SetPoint("BOTTOMRIGHT", -18, 1)
    NS.channel.label:SetJustifyH("LEFT")
    NS.channel.label:SetJustifyV("MIDDLE")
    -- Draw a centered chevron independently of the font's baseline.
    for i = 1, 2 do
        local stroke = NS.channel:CreateTexture(nil, "OVERLAY")
        stroke:SetColorTexture(0.85, 0.85, 0.85, 1)
        stroke:SetSize(6, 1.5)
        stroke:SetPoint("CENTER", NS.channel, "RIGHT", i == 1 and -12 or -8, 0)
        stroke:SetRotation(i == 1 and -math.pi / 4 or math.pi / 4)
    end
    NS.channel.label:SetWordWrap(false)
    NS.Tooltip(NS.channel, "MessageSplitter: channel", "Choose the channel for this message.")
    NS.recipient = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    NS.recipient:SetHeight(18)
    NS.recipient:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -3)
    NS.recipient:SetPoint("RIGHT", send, "LEFT", -6, 0)
    NS.recipient:SetAutoFocus(false)
    NS.recipient:SetMaxLetters(80)
    NS.recipient:SetScript("OnTextChanged", function(self)
        if NS.syncRecipient then return end
        if NS.route.type == "WHISPER" then
            NS.CancelQueue(); NS.route.target = self:GetText():match("^%s*(.-)%s*$"); NS.RefreshPreview()
        end
    end)
    NS.recipient:SetScript("OnEnterPressed", function(self) self:ClearFocus(); NS.editor:SetFocus() end)
    NS.recipient:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    NS.recipient:Hide()

    local well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    NS.well = well
    well:SetPoint("TOPLEFT", 4, -24)
    well:SetPoint("BOTTOMRIGHT", -4, 4)
    well:SetBackdrop(backdrop)
    well:SetBackdropColor(0.025, 0.03, 0.04, 0.9)
    well:SetBackdropBorderColor(0.19, 0.2, 0.23, 1)
    NS.channel:SetParent(well)
    NS.channel:SetPoint("LEFT", well, "LEFT", 8, 0)
    NS.rail = well:CreateTexture(nil, "OVERLAY")
    NS.rail:SetPoint("TOPLEFT")
    NS.rail:SetPoint("BOTTOMLEFT")
    NS.rail:SetWidth(4)

    local scroll = CreateFrame("ScrollFrame", nil, well)
    NS.scroll = scroll
    scroll:SetPoint("TOPLEFT", NS.channel:GetWidth() + 14, -4)
    scroll:SetPoint("BOTTOMRIGHT", -5, 4)
    local editor = CreateFrame("EditBox", "MessageSplitterEditor", scroll)
    NS.editor = editor
    -- Establish font metrics before multiline layout and scroll-child sizing.
    editor:SetFontObject(ChatFontNormal)
    editor:SetFont(STANDARD_TEXT_FONT, NS.db.fontSize, "")
    editor:SetMultiLine(true)
    editor:SetAutoFocus(false)
    editor:EnableKeyboard(true)
    editor:EnableMouse(true)
    editor:SetMaxLetters(16000)
    editor:SetTextInsets(0, 4, 0, 8)
    editor:SetSize(NS.db.width - 18, 26)
    scroll:SetScrollChild(editor)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * NS.db.fontSize * 2)))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll())))
    end)
    NS.coloredText = editor:CreateFontString(nil, "OVERLAY")
    NS.coloredText:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, 0)
    NS.coloredText:SetJustifyH("LEFT")
    NS.coloredText:SetJustifyV("TOP")
    NS.coloredText:SetWordWrap(true)
    NS.coloredText:SetNonSpaceWrap(true)
    NS.coloredText:SetMaxLines(0)
    NS.coloredText:SetHeight(0)
    NS.lineMeasure = editor:CreateFontString(nil, "OVERLAY")
    NS.lineMeasure:SetFont(STANDARD_TEXT_FONT, NS.db.fontSize, "")
    NS.lineMeasure:SetText("Ag")
    NS.lineMeasure:Hide()
    -- RP text is drawn over a transparent EditBox, which also hides its native
    -- caret. Draw a caret from the EditBox's own cursor coordinates instead.
    local caret = editor:CreateTexture(nil, "OVERLAY", nil, 7)
    caret:SetColorTexture(1, 0.95, 0.8, 1)
    caret:SetSize(2, NS.db.fontSize)
    caret:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, 0)
    caret:Hide()
    local caretElapsed = 0
    editor:HookScript("OnEditFocusGained", function()
        caretElapsed = 0
        caret:SetAlpha(1)
        caret:SetShown(NS.db.rpColors)
    end)
    editor:HookScript("OnEditFocusLost", function() caret:Hide() end)
    editor:HookScript("OnUpdate", function(_, elapsed)
        local visible = NS.db.rpColors and editor:HasFocus()
        caret:SetShown(visible)
        if visible then
            caretElapsed = (caretElapsed + elapsed) % 1
            caret:SetAlpha(caretElapsed < 0.5 and 1 or 0)
        end
    end)
    scroll:SetScript("OnSizeChanged", function(self, width)
        editor:SetWidth(math.max(100, width)); NS.UpdateEditorLayout()
    end)
    editor:SetScript("OnSizeChanged", function() NS.UpdateEditorLayout() end)
    editor:SetScript("OnCursorChanged", function(_, x, y, _, height)
        -- Cursor coordinates exclude the EditBox's text insets.
        local leftInset, _, topInset = editor:GetTextInsets()
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", editor, "TOPLEFT", x + leftInset, y - topInset)
        caret:SetHeight(height)
        caretElapsed = 0
        caret:SetAlpha(1)
        local top = -y + topInset
        local offset = scroll:GetVerticalScroll()
        if top < offset then scroll:SetVerticalScroll(top)
        elseif top + height > offset + scroll:GetHeight() then scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), top + height - scroll:GetHeight()))) end
    end)
    editor:SetScript("OnTextChanged", function()
        local plain = NS.GetDraftText()
        local changed = plain ~= NS.lastPlainText
        NS.lastPlainText = plain
        if NS.internalEdit then NS.RefreshPreview(); NS.UpdateEditorLayout(true); return end
        if changed then NS.CancelQueue() end
        NS.RefreshPreview()
        NS.UpdateEditorLayout(true)
        NS.SaveDraft()
    end)
    editor:SetScript("OnEnterPressed", function(self)
        if IsShiftKeyDown() then
            self:Insert("\n")
        elseif not NS.queue and not NS.GetDraftText():match("%S") then
            f:Hide()
        else
            NS.SendNext()
        end
    end)
    editor:SetScript("OnEscapePressed", function() f:Hide() end)
    -- The empty area belongs to the scroll frame, rather than its parent well.
    -- Clicking there must focus the editor too, even when its content is short.
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() editor:SetFocus() end)
    well:SetScript("OnMouseDown", function() editor:SetFocus() end)
    well:EnableMouse(true)

    NS.counter = NS.Label(f, "", 10)
    local info = CreateFrame("Frame", nil, f)
    info:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -3)
    info:SetPoint("RIGHT", send, "LEFT", -6, 0)
    info:SetHeight(18)
    NS.counter:SetParent(info)
    NS.counter:SetPoint("LEFT", info, "LEFT", 0, 0)
    NS.counter:SetWidth(62)
    NS.counter:SetWordWrap(false)
    NS.status = NS.Label(f, "", 10)
    NS.status:SetParent(info)
    NS.status:SetPoint("LEFT", NS.counter, "RIGHT", 4, 0)
    NS.status:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    NS.status:SetWordWrap(false)
    -- The whisper recipient uses this same toolbar space while it is visible.
    NS.recipient:HookScript("OnShow", function() info:Hide() end)
    NS.recipient:HookScript("OnHide", function() info:Show() end)
    info:SetShown(not NS.recipient:IsShown())
    local statusHover = CreateFrame("Frame", nil, info)
    statusHover:SetAllPoints(info)
    statusHover:EnableMouse(true)
    -- This mouse-enabled tooltip area covers the toolbar's drag surface.
    statusHover:RegisterForDrag("LeftButton")
    statusHover:SetScript("OnDragStart", f:GetScript("OnDragStart"))
    statusHover:SetScript("OnDragStop", f:GetScript("OnDragStop"))
    NS.Tooltip(statusHover, "MessageSplitter", function()
        return #NS.GetDraftText() .. " bytes | " .. (NS.counter:GetText() or "") .. "\n" .. (NS.status:GetText() or "") .. "\nEnter: send | Shift+Enter: new line | Escape: keep draft"
    end)
    local resize = CreateFrame("Button", nil, f)
    NS.resize = resize
    resize:SetSize(12, 12)
    resize:SetPoint("BOTTOMRIGHT")
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetScript("OnMouseDown", function()
        if not NS.db.locked and not InCombatLockdown() then
            NS.resizing = true
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resize:SetScript("OnMouseUp", function()
        if not NS.resizing then return end
        f:StopMovingOrSizing()
        NS.SaveGeometry(true)
        NS.resizing = nil
    end)

    NS.menu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    NS.menu:SetBackdrop(backdrop)
    NS.menu:SetBackdropColor(0.06, 0.065, 0.08, 1)
    NS.Skin(NS.menu, {0.085, 0.075, 0.060, 0.96}, {0.62, 0.48, 0.25, 0.65})
    NS.menu:SetWidth(198)
    NS.menu:SetPoint("TOPLEFT", NS.channel, "BOTTOMLEFT", 0, -4)
    NS.menu:SetFrameLevel(f:GetFrameLevel() + 20)
    NS.menu.rows = {}
    NS.menu:Hide()
    NS.ApplyStyle()
    NS.composerReady = true
    editor:SetText(NS.db.rememberDraft and NS.db.draft or "")
    NS.RefreshPreview()
end
