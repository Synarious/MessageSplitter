local addon, NS = ...
NS.name = addon
NS.defaults = {enabled=true, width=280, height=44, fontSize=13, opacity=0.80,
    growth="UP", rpColors=true, maxHeight=260, locked=false, markers=true, emoteContinuation=true, closeAfterSend=true,
    limit=255, delay=0.8, automatic=false, rememberDraft=false, draft=""}
NS.route = {type="SAY"}

function NS.Restricted()
    if NS.chatTransition then return true end
    local types, states = Enum and Enum.AddOnRestrictionType, Enum and Enum.AddOnRestrictionState
    if types and states and types.Chat ~= nil and C_RestrictedActions
        and C_RestrictedActions.GetAddOnRestrictionState then
        local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, types.Chat)
        if not ok or state ~= states.Inactive then return true end
    end
    if InCombatLockdown() then return true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return true end
    if IsEncounterInProgress and IsEncounterInProgress() then return true end
    return false
end

function NS.Notify(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd080MessageSplitter:|r " .. message)
end

function NS.ReadableText(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string"
end

function NS.GetDraftText()
    local text = NS.editor:GetText()
    NS.draftBlocked = not NS.ReadableText(text)
    if NS.draftBlocked then return NS.lastReadableDraft or "" end
    if NS.misspelled and type(NS.misspelled.RemoveHighlighting) == "function" then
        local ok, cleaned = pcall(NS.misspelled.RemoveHighlighting, NS.misspelled, text)
        if ok and NS.ReadableText(cleaned) then text = cleaned end
    end
    NS.lastReadableDraft = text
    return text
end

function NS.RefreshSendStatus()
    if NS.Restricted() then
        if NS.timer then NS.timer:Cancel(); NS.timer = nil end
        NS.SetStatus("Chat restricted: draft retained. Use Default chat.")
    elseif NS.pending then
        NS.SetStatus("Waiting for confirmation; draft retained.")
    elseif NS.sendIssue then
        NS.SetStatus(NS.sendIssue)
    elseif NS.queue then
        NS.SetStatus("Enter: next part; edit: rebuild remaining.")
    else
        NS.SetStatus("Enter: send")
    end
end

function NS.RestoreSubmission()
    if not NS.lastSubmission then NS.Notify("No unconfirmed or remaining submission to restore."); return end
    if NS.GetDraftText():match("%S") or NS.queue or NS.pending or NS.draftBlocked then
        NS.Notify("Finish the current draft before restoring a submission."); return
    end
    NS.route = NS.lastSubmission.route
    NS.editor:SetText(NS.lastSubmission.text)
    NS.queue = {parts=NS.lastSubmission.parts, index=NS.lastSubmission.index, route=NS.lastSubmission.route}
    NS.Open()
end

function NS.RememberRemaining(q)
    NS.lastSubmission = q.index <= #q.parts and {text=table.concat(q.parts, "\n", q.index),
        parts=q.parts, index=q.index, route={type=q.route.type, target=q.route.target,
            language=q.route.language, channelName=q.route.channelName}} or nil
end

function NS.AttachSpellcheck()
    local spellcheck = _G.Misspelled
    if not NS.editor or NS.misspelled or type(spellcheck) ~= "table"
        or type(spellcheck.WireUpEditBox) ~= "function"
        or type(spellcheck.RemoveHighlighting) ~= "function" then return end
    -- We clean text for both the Send button and Enter without rewriting the
    -- editor and invalidating its active queue before every send.
    NS.editor.__misspelled_selfCleaning = true
    spellcheck:WireUpEditBox(NS.editor)
    NS.misspelled = spellcheck
end

function NS.SaveDraft()
    if NS.db and NS.editor then
        NS.GetDraftText()
        if NS.draftBlocked then return end
        NS.db.draft = NS.db.rememberDraft and NS.GetDraftText() or ""
        NS.db.draftRoute = NS.db.rememberDraft and {type=NS.route.type, target=NS.route.target, language=NS.route.language} or nil
    end
end

function NS.CancelQueue()
    if NS.timer then NS.timer:Cancel(); NS.timer = nil end
    NS.queue = nil
    NS.sendIssue = nil
    if NS.editor then NS.editor:EnableMouse(true) end
end

function NS.SetEnabled(enabled)
    NS.db.enabled = enabled and true or false
    NS.CancelQueue()
    if not NS.db.enabled and NS.frame then NS.frame:Hide() end
    NS.Notify(NS.db.enabled and "Enabled." or "Disabled. Use /mse on to re-enable.")
end

function NS.Prepare()
    local text, route = NS.Parse(NS.GetDraftText(), NS.route)
    if not text then return nil, route end
    -- A standalone *action* in Say is a native emote, so chat omits "says:".
    local action = route.type == "SAY" and text:match("^%s*%*([^*]+)%*%s*$")
    if action and action:match("%S") then
        text = action:match("^%s*(.-)%s*$")
        route.type = "EMOTE"
    end
    local baseTypes = {PARTY_LEADER="PARTY", RAID_LEADER="RAID", INSTANCE_CHAT_LEADER="INSTANCE_CHAT"}
    route.type = baseTypes[route.type] or route.type
    if route.type == "WHISPER" and (not route.target or route.target == "") then return nil, "Choose a whisper recipient using /w Name message." end
    if route.type == "CHANNEL" then
        local id, name = GetChannelName(route.target or 0)
        if not id or id == 0 then return nil, "Join and select a valid chat channel first." end
        route.target, route.channelName = id, name
    end
    if not NS.supported[route.type] then return nil, "This chat type uses Default chat (Battle.net and communities are not supported)." end
    local parts, err = NS.Split(text, {limit=NS.db.limit, markers=NS.db.markers,
        emote=route.type == "EMOTE", emoteContinuation=NS.db.emoteContinuation})
    if not parts then return nil, err end
    return {parts=parts, route=route, index=1}
end

-- Local, channel, and emote messages retain a hardware event for every part.
local pacedTypes = {GUILD=true, OFFICER=true, PARTY=true, RAID=true, INSTANCE_CHAT=true, WHISPER=true}
function NS.SendNext(fromTimer)
    NS.GetDraftText()
    if NS.draftBlocked then NS.SetStatus("Draft is inaccessible. Use Default chat."); return end
    if not fromTimer and NS.RouteSlashCommand() then return end
    if NS.Restricted() then
        NS.PauseForRestrictions()
        return
    end
    if NS.pending then NS.SetStatus("Waiting for confirmation; draft retained."); return end
    if not fromTimer and GetTime() < (NS.nextSend or 0) then
        NS.SetStatus("Please wait briefly before sending the next part."); return
    end
    if not NS.queue then
        local queue, err = NS.Prepare()
        if not queue then NS.SetStatus(err); return end
        if #queue.parts == 0 then return end
        NS.queue = queue
    end
    local q = NS.queue
    local route = q.route
    if route.type == "CHANNEL" then
        local id, name = GetChannelName(route.target)
        if id ~= route.target or name ~= route.channelName then
            NS.SetStatus("Channel changed. Edit the draft to rebuild the queue."); return
        end
    end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then NS.SetStatus("Chat send API is unavailable."); return end
    -- Keep the current part in the draft until its own readable chat echo arrives.
    NS.RememberRemaining(q)
    local pending = {queue=q, index=q.index, text=q.parts[q.index]}
    NS.pending = pending
    NS.sendIssue = nil
    pending.timeout = C_Timer.NewTimer(10, function()
        if NS.pending == pending then NS.FailPending("Delivery unconfirmed. Draft retained; retry may duplicate.") end
    end)
    local ok, result = pcall(send, pending.text, route.type, route.language, route.target)
    if not ok or result == false then
        if NS.pending == pending then NS.FailPending("Send blocked. Draft retained; retry manually when safe.") end
        return
    end
    if NS.pending == pending then NS.RefreshSendStatus() end
end

function NS.FailPending(reason)
    local pending = NS.pending
    if pending and pending.timeout then pending.timeout:Cancel() end
    NS.pending = nil
    if NS.timer then NS.timer:Cancel(); NS.timer = nil end
    NS.sendIssue = reason
    NS.SetStatus(reason)
end

function NS.CompletePending()
    local pending = NS.pending
    if not pending then return end
    if pending.timeout then pending.timeout:Cancel() end
    NS.pending = nil
    local q = pending.queue
    local route = q.route
    q.index = pending.index + 1
    NS.RememberRemaining(q)
    -- Edits can detach a queue while a send is in flight. Never overwrite them.
    if NS.queue ~= q then NS.RefreshSendStatus(); return end

    NS.nextSend = GetTime() + NS.db.delay
    NS.route = {type=route.type, target=route.target, language=route.language}
    if NS.recipient then
        NS.recipient:SetShown(route.type == "WHISPER")
        -- OnTextChanged would cancel the active queue; sync only when needed.
        if route.type == "WHISPER" and NS.recipient:GetText() ~= (route.target or "") then
            NS.syncRecipient = true
            NS.recipient:SetText(route.target or "")
            NS.syncRecipient = nil
        end
    end
    if q.index > #q.parts then
        NS.CancelQueue()
        NS.editor:SetText("")
        NS.SaveDraft()
        NS.SetStatus("All parts confirmed.")
        if NS.db.closeAfterSend then NS.frame:Hide() end
    else
        -- Keep ONLY the unsent wire messages as the draft. Editing cancels the
        -- queue, so already submitted parts cannot accidentally be replayed.
        NS.internalEdit = true
        NS.editor:SetText(table.concat(q.parts, "\n", q.index))
        NS.internalEdit = nil
        NS.SaveDraft()
        NS.SetStatus((q.index - 1) .. "/" .. #q.parts .. " confirmed. Enter: next part; edit: rebuild remaining.")
        if NS.db.automatic and pacedTypes[route.type] and not NS.timer and NS.frame:IsShown() then
            NS.timer = C_Timer.NewTimer(NS.db.delay, function()
                NS.timer = nil
                if NS.queue then NS.SendNext(true) end
            end)
        end
    end
end

local function normalizedName(name)
    if not NS.ReadableText(name) then return nil end
    if not name:find("-", 1, true) then
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if not NS.ReadableText(realm) then return nil end
        name = name .. "-" .. realm
    end
    return name:gsub("%s+", ""):lower()
end

function NS.ConfirmChat(event, text, author, channelIndex, guid)
    local pending = NS.pending
    if not pending or NS.Restricted() then return end
    local route = pending.queue.route
    local kind = event:gsub("^CHAT_MSG_", "")
    local base = {PARTY_LEADER="PARTY", RAID_LEADER="RAID", INSTANCE_CHAT_LEADER="INSTANCE_CHAT"}
    kind = base[kind] or kind
    if route.type == "WHISPER" then
        if kind ~= "WHISPER_INFORM" then return end
        local target, sender = normalizedName(route.target), normalizedName(author)
        if not target or sender ~= target then return end
    else
        if kind ~= route.type then return end
        local playerGUID = UnitGUID and UnitGUID("player")
        if not NS.ReadableText(guid) or not NS.ReadableText(playerGUID) or guid ~= playerGUID then return end
        if kind == "CHANNEL" and (issecretvalue and issecretvalue(channelIndex) or channelIndex ~= route.target) then return end
    end
    if NS.ReadableText(text) and text == pending.text then NS.CompletePending() end
end

function NS.PauseForRestrictions()
    if not NS.frame then return end
    NS.SaveDraft()
    if NS.pending then NS.FailPending("Interrupted before confirmation. Draft retained; retry may duplicate.") end
    if NS.timer then NS.timer:Cancel(); NS.timer = nil end
    NS.frame:StopMovingOrSizing()
    if NS.resizing then NS.SaveGeometry(true); NS.resizing = nil end
    NS.SetStatus("Chat restricted: draft retained. Press Enter for normal chat.")
    -- Leave secure native activation to the player's next Enter keypress.
    NS.frame:Hide()
end

local function isChatFailure(text)
    if not NS.ReadableText(text) then return false end
    for _, key in ipairs({"ERR_CHAT_THROTTLED", "ERR_CHAT_RESTRICTED", "ERR_CHAT_SILENCED",
        "ERR_NOT_IN_GROUP", "ERR_NOT_IN_RAID", "ERR_GUILD_PLAYER_NOT_IN_GUILD"}) do
        if NS.ReadableText(_G[key]) and text == _G[key] then return true end
    end
    local route = NS.pending and NS.pending.queue.route
    if route and route.type == "WHISPER" and NS.ReadableText(ERR_CHAT_PLAYER_NOT_FOUND_S) then
        return text == string.format(ERR_CHAT_PLAYER_NOT_FOUND_S, route.target)
    end
    return false
end

NS.supported = {SAY=true,YELL=true,EMOTE=true,PARTY=true,PARTY_LEADER=true,RAID=true,
    RAID_LEADER=true,RAID_WARNING=true,GUILD=true,OFFICER=true,INSTANCE_CHAT=true,
    INSTANCE_CHAT_LEADER=true,WHISPER=true,CHANNEL=true}

function NS.Capture(box, attempt)
    attempt = type(attempt) == "number" and attempt or 0
    if not NS.db or not NS.db.enabled or not NS.composerReady or NS.Restricted() or NS.bypass then return end
    -- Defer until Blizzard has finished setting the initial channel/text.
    C_Timer.After(0, function()
        if NS.bypass or NS.Restricted() or not NS.db.enabled or not box:HasFocus() then return end
        -- OpenChat applies initial /commands from its next OnUpdate. Let that
        -- secure code finish before reading or hiding the native editor.
        if issecretvalue and issecretvalue(box.setText) then return end
        if box.setText == 1 then
            if attempt < 4 then C_Timer.After(0.01, function() NS.Capture(box, attempt + 1) end) end
            return
        end
        local kind
        if box.GetChatType then kind = box:GetChatType() else kind = box:GetAttribute("chatType") end
        if issecretvalue and issecretvalue(kind) then return end
        if not NS.supported[kind] then return end
        -- Whisper Manager opens conversations on a deferred chat hook too.
        -- Leave the native editor untouched so either callback order works,
        -- and its native-chat fallback remains available when needed.
        local whisperManager = _G.WhisperManager
        if kind == "WHISPER" and type(whisperManager) == "table"
            and type(whisperManager.OpenConversation) == "function" then return end
        local target
        if kind == "CHANNEL" then target = box:GetAttribute("channelTarget")
        elseif kind == "WHISPER" then target = box:GetAttribute("tellTarget") end
        local text = box:GetText()
        local language = box.languageID
        if issecretvalue and (issecretvalue(text) or issecretvalue(target) or issecretvalue(language)) then return end
        -- Slash-key activation belongs to Blizzard's command editor.
        if text and text:match("^%s*/") then return end
        -- Never displace an existing unsent draft with a new activation.
        if NS.GetDraftText() == "" then
            -- Slash commands can leave Blizzard's empty editor on its default
            -- Say channel. Keep the composer's selection on the next reopen.
            if not (NS.preserveRouteAfterSlash and kind == "SAY" and (not text or text == "")) then
                NS.route = {type=kind, target=target, language=language}
            end
            NS.preserveRouteAfterSlash = nil
            NS.editor:SetText(text or "")
            box:SetText("")
        elseif text and text ~= "" then
            NS.Notify("Existing draft retained. Finish it before importing another message.")
            return
        end
        NS.native = box
        if ChatFrameUtil and ChatFrameUtil.DeactivateChat then ChatFrameUtil.DeactivateChat(box)
        elseif ChatEdit_DeactivateChat then ChatEdit_DeactivateChat(box)
        else box:ClearFocus(); box:Hide() end
        NS.Open()
    end)
end

function NS.RouteSlashCommand()
    local text = NS.GetDraftText():match("^%s*(.-)%s*$")
    if text:sub(1, 1) ~= "/" then return false end
    -- Chat routes still go through the splitter; other commands run on Enter.
    local body, route = NS.Parse(text, NS.route)
    if body then
        if body:match("^%s*$") then
            NS.CancelQueue()
            NS.route = route
            if NS.recipient then NS.recipient:SetShown(route.type == "WHISPER") end
            NS.editor:SetText("")
            NS.SaveDraft()
            NS.RefreshPreview()
            NS.SetStatus("Channel selected. Enter: send")
            return true
        end
        return false
    end
    local command, args = text:match("^(/%S+)%s*(.*)$")
    if not command then
        NS.SetStatus("Finish typing a command before pressing Enter.")
        return true
    end
    command = command:lower()
    if (command == "/mse" or command == "/msplit" or command == "/messagesplitter") and args:lower() == "restore" then
        NS.editor:SetText("")
        NS.RestoreSubmission()
        return true
    end
    local handler
    -- Reload is a built-in command and may not be registered in SlashCmdList.
    if command == "/reload" or command == "/rl" then
        handler = ReloadUI
    elseif command == "/mse" or command == "/msplit" or command == "/messagesplitter" then
        handler = SlashCmdList.MESSAGESPLITTER
    end
    if type(handler) == "function" then
        NS.CancelQueue()
        local ok = pcall(handler, args, NS.native or NS.editor)
        if ok then
            NS.editor:SetText("")
            NS.SaveDraft()
            NS.SetStatus("Command executed.")
        else
            NS.SetStatus("Command could not run here. Use Default chat.")
        end
        return true
    end
    NS.DefaultChat()
    NS.Notify("Enter that command in Default chat. Your draft was retained.")
    return true
end

function NS.HookBoxes()
    NS.hooked = NS.hooked or setmetatable({}, {__mode="k"})
    for _, name in ipairs(CHAT_FRAMES or {"ChatFrame1"}) do
        local chat = _G[name]
        local box = chat and chat.editBox or _G[name .. "EditBox"]
        if box and not NS.hooked[box] then
            NS.hooked[box] = true
            box:HookScript("OnEditFocusGained", NS.Capture)
        end
    end
end

function NS.DefaultChat()
    NS.CancelQueue()
    NS.frame:Hide()
    -- Do not inject addon text into the native secure send path. Draft stays in
    -- our composer; native chat opens empty and remains native during lockdown.
    NS.bypass = true
    local box = NS.native or (ChatFrame1 and ChatFrame1.editBox)
    if box then
        if ChatFrameUtil and ChatFrameUtil.ActivateChat then ChatFrameUtil.ActivateChat(box)
        elseif ChatEdit_ActivateChat then ChatEdit_ActivateChat(box) end
    end
    C_Timer.After(0.2, function() NS.bypass = nil end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ENCOUNTER_END")
for _, kind in ipairs({"SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
    "RAID_WARNING", "GUILD", "OFFICER", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER_INFORM", "CHANNEL"}) do
    events:RegisterEvent("CHAT_MSG_" .. kind)
end
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_RESTRICTED")
events:RegisterEvent("CHAT_REGIONAL_SEND_FAILED")
if Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat ~= nil then
    events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
end
events:SetScript("OnEvent", function(_, event, name, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if name == Enum.AddOnRestrictionType.Chat then
            local state = ...
            NS.chatTransition = state ~= Enum.AddOnRestrictionState.Inactive
            if NS.chatTransition then NS.PauseForRestrictions()
            elseif NS.composerReady then NS.RefreshSendStatus() end
        end
        return
    elseif event == "CHAT_MSG_RESTRICTED" or event == "CHAT_REGIONAL_SEND_FAILED" then
        if NS.pending then NS.FailPending("Chat rejected the send. Draft retained; retry manually.") end
        return
    elseif event == "CHAT_MSG_SYSTEM" then
        if NS.pending and isChatFailure(name) then NS.FailPending("Chat rejected the send. Draft retained; retry manually.") end
        return
    elseif event:match("^CHAT_MSG_") then
        local author, _, _, _, _, _, channelIndex, _, _, _, guid = ...
        NS.ConfirmChat(event, name, author, channelIndex, guid)
        return
    end
    if event == "ADDON_LOADED" and name == addon then
        MessageSplitterDB = type(MessageSplitterDB) == "table" and MessageSplitterDB or {}
        NS.db = MessageSplitterDB
        -- Enable closing on completion for existing installations as well.
        if not NS.db.closeOnCompletionUpdated then
            NS.db.closeAfterSend = true
            NS.db.closeOnCompletionUpdated = true
        end
        -- Apply the compact layout once to existing installations too.
        if NS.db.compactLayout ~= 3 then
            NS.db.width, NS.db.height, NS.db.fontSize = 280, 82, 13
            NS.db.compactLayout = 3
        end
        for key, value in pairs(NS.defaults) do
            if type(NS.db[key]) ~= type(value) then NS.db[key] = value end
        end
        -- Replace the previous compact baseline, including its padding revision.
        if not NS.db.compactChannelHeight then
            if NS.db.height <= 90 then NS.db.height = 64 end
            NS.db.compactChannelHeight = true
        end
        if not NS.db.roundedStyle then
            NS.db.opacity = 0.80
            NS.db.roundedStyle = true
        end
        -- Undo the expanded layout's saved minimum size on existing installs.
        if NS.db.composerLayoutV4 then
            NS.db.width, NS.db.height = NS.defaults.width, NS.defaults.height
            NS.db.composerLayoutV4 = nil
        end
        if not NS.db.hoverControlsLayout then
            if NS.db.height <= 64 then NS.db.height = 44 end
            NS.db.hoverControlsLayout = true
        end
        if NS.db.growth ~= "UP" and NS.db.growth ~= "DOWN" then NS.db.growth = "UP" end
        NS.db.maxHeight = math.max(64, math.min(600, NS.db.maxHeight))
        NS.db.limit = math.max(64, math.min(255, NS.db.limit))
        NS.db.delay = math.max(0.5, math.min(3, NS.db.delay))
        NS.db.width = math.max(260, math.min(1200, NS.db.width))
        NS.db.height = math.max(44, math.min(800, NS.db.height))
        NS.db.fontSize = math.max(12, math.min(24, NS.db.fontSize))
        NS.db.opacity = math.max(0.4, math.min(1, NS.db.opacity))
        local saved = NS.db.rememberDraft and NS.db.draftRoute
        if type(saved) == "table" and NS.supported[saved.type]
            and (saved.target == nil or type(saved.target) == "string" or type(saved.target) == "number") then
            NS.route = {type=saved.type, target=saved.target, language=type(saved.language) == "number" and saved.language or nil}
        end
        local ok, err = pcall(NS.CreateComposer)
        if not ok then
            NS.composerReady = nil
            NS.composerError = tostring(err)
            NS.Notify("Composer setup failed: " .. NS.composerError)
            geterrorhandler()(err)
            return
        end
        NS.AttachSpellcheck()
        NS.CreateSettings()
    elseif event == "PLAYER_LOGIN" then
        NS.AttachSpellcheck()
        NS.HookBoxes()
        if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", NS.HookBoxes) end
    elseif event == "ADDON_LOADED" and NS.db then
        NS.AttachSpellcheck()
        NS.HookBoxes()
    elseif event == "PLAYER_REGEN_DISABLED" then NS.PauseForRestrictions()
    elseif event == "PLAYER_LOGOUT" then NS.SaveDraft()
    elseif NS.composerReady then NS.RefreshSendStatus() end
end)

SLASH_MESSAGESPLITTER1 = "/msplit"
SLASH_MESSAGESPLITTER2 = "/messagesplitter"
SLASH_MESSAGESPLITTER3 = "/mse"
SlashCmdList.MESSAGESPLITTER = function(input)
    input = (input or ""):match("^%s*(.-)%s*$"):lower()
    if input == "on" then NS.SetEnabled(true)
    elseif input == "off" then NS.SetEnabled(false)
    elseif input == "restore" then NS.RestoreSubmission()
    elseif input == "settings" then NS.OpenSettings()
    elseif input == "reset" then
        NS.db.x, NS.db.y, NS.db.point, NS.db.relativePoint = nil, nil, nil, nil
        NS.db.width, NS.db.height = NS.defaults.width, NS.defaults.height
        NS.ApplyStyle()
    else NS.Open() end
end
