local NS, sent, timers, now, events = {}, {}, {}, 0
local combat, lockdown, restriction = false, false, 0
Enum = {AddOnRestrictionType={Chat=5}, AddOnRestrictionState={Inactive=0, Activating=1, Active=2}}
C_RestrictedActions = {GetAddOnRestrictionState=function() return restriction end}
SlashCmdList = {}
CreateFrame = function()
 events = {registered={}, RegisterEvent=function(self, event) self.registered[event]=true end,
  SetScript=function(self, _, fn) self.onEvent=fn end}
 return events
end
C_Timer = {NewTimer=function(delay, callback)
 local t = {delay=delay, callback=callback, Cancel=function(self) self.cancelled=true end}
 timers[#timers+1] = t
 return t
end}
GetTime = function() return now end
UnitGUID = function() return "Player-Me" end
GetNormalizedRealmName = function() return "MyRealm" end
InCombatLockdown = function() return combat end
C_ChatInfo = {InChatMessagingLockdown=function() return lockdown end}
local function send(text, kind, language, target) sent[#sent+1]={text=text, kind=kind, target=target} end
C_ChatInfo.SendChatMessage = send
assert(loadfile("Splitter.lua"))("MessageSplitter", NS)
assert(loadfile("Core.lua"))("MessageSplitter", NS)
assert(loadfile("Composer.lua"))("MessageSplitter", NS)
NS.db = NS.defaults
NS.db.rememberDraft = true
NS.composerReady = true
NS.SetStatus = function(text) NS.statusText=text end
NS.Notify = function(text) NS.notice=text end
NS.RefreshPreview = function() end
NS.frame = {shown=true, hides=0, Hide=function(self) self.shown=false; self.hides=self.hides+1 end,
 Show=function(self) self.shown=true end, IsShown=function(self) return self.shown end, StopMovingOrSizing=function() end}
NS.editor = {text="", GetText=function(self) return self.text end, EnableMouse=function() end,
 SetText=function(self,text) self.text=text; if not NS.internalEdit then NS.CancelQueue() end end,
 SetFocus=function(self) self.focused=true end}
NS.recipient = {SetShown=function() end, SetText=function() end, GetText=function() return "" end}
local function event(name, ...)
 events.onEvent(events, name, ...)
end
local function echo(kind, text, author, channel, guid)
 event("CHAT_MSG_" .. kind, text, author or "Me-MyRealm", "Common", "", "", "", 0, channel or 0, "", 0, 123, guid or "Player-Me")
end
local function reset(text, kind, target)
 if NS.pending then NS.FailPending("test reset") end
 NS.CancelQueue()
 NS.editor.text=text or "first paragraph\nsecond paragraph"
 NS.route={type=kind or "SAY", target=target}
 NS.nextSend=0
 NS.frame.shown=true
 NS.db.automatic=false
 combat, lockdown, restriction=false,false,0
 NS.chatTransition=false
 now=now+20
 C_ChatInfo.SendChatMessage=send
end
assert(events.registered.ADDON_RESTRICTION_STATE_CHANGED)

-- A successful API invocation alone cannot consume the part or send another.
reset()
NS.SendNext()
local original=NS.editor.text
local timeout=NS.pending.timeout
local count=#sent
NS.SendNext()
assert(#sent==count and NS.editor.text==original and NS.queue.index==1)
echo("SAY", "first paragraph", nil, nil, "Player-Other")
echo("GUILD", "first paragraph")
echo("SAY", "wrong message")
assert(NS.pending and NS.queue.index==1)
echo("SAY", "first paragraph")
assert(not NS.pending and timeout.cancelled and NS.editor.text=="second paragraph")
assert(NS.lastSubmission.text=="second paragraph" and NS.lastSubmission.index==2)

-- Recovery preserves the exact remaining wire parts, never confirmed prefixes.
NS.CancelQueue()
NS.editor.text=""
NS.RestoreSubmission()
assert(NS.editor.text=="second paragraph" and NS.queue.index==2)
now=now+1
NS.SendNext()
echo("SAY", "second paragraph")
assert(NS.editor.text=="" and not NS.queue and not NS.lastSubmission)
NS.RestoreSubmission()
assert(NS.notice:find("No unconfirmed",1,true))

-- Timeout, explicit false, exceptions and chat failure events retain the draft.
reset("no echo")
NS.SendNext()
local t=NS.pending.timeout
count=#sent
t.callback()
assert(not NS.pending and NS.editor.text=="no echo" and NS.queue.index==1 and #sent==count)
assert(NS.statusText:find("retry may duplicate",1,true))
NS.RefreshSendStatus()
assert(NS.statusText:find("retry may duplicate",1,true))
for _, sender in ipairs({function() return false end, function() error("blocked") end}) do
 reset("blocked")
 C_ChatInfo.SendChatMessage=sender
 NS.SendNext()
 assert(not NS.pending and NS.editor.text=="blocked" and NS.queue.index==1)
end
for _, failure in ipairs({"CHAT_MSG_RESTRICTED", "CHAT_REGIONAL_SEND_FAILED"}) do
 reset("rejected")
 NS.SendNext()
 event(failure)
 assert(not NS.pending and NS.editor.text=="rejected")
end
reset("throttled")
ERR_CHAT_THROTTLED="Too many messages"
NS.SendNext()
event("CHAT_MSG_SYSTEM", "An unrelated system notice")
assert(NS.pending)
event("CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED)
assert(not NS.pending and NS.editor.text=="throttled")

-- Matching recipient/channel and accessible values are required for confirmation.
reset("whisper", "WHISPER", "Friend")
NS.SendNext()
echo("WHISPER_INFORM", "whisper", "Other-MyRealm")
assert(NS.pending)
echo("WHISPER_INFORM", "whisper", "Friend-MyRealm")
assert(not NS.pending and NS.editor.text=="")
GetChannelName=function(id) return id,"General" end
reset("channel", "CHANNEL", 1)
NS.SendNext()
echo("CHANNEL", "channel", nil, 2)
assert(NS.pending)
echo("CHANNEL", "channel", nil, 1)
assert(not NS.pending)
reset("secret check")
NS.SendNext()
local secret={}
issecretvalue=function(value) return value==secret end
echo("SAY", secret)
echo("SAY", "secret check", nil, nil, secret)
assert(NS.pending)
issecretvalue=nil
echo("SAY", "secret check")
assert(not NS.pending)

-- Editing during an in-flight send must not be overwritten by its later echo.
reset("old draft", "GUILD")
NS.db.automatic=true
NS.SendNext()
NS.editor:SetText("new draft")
echo("GUILD", "old draft")
assert(NS.editor.text=="new draft" and not NS.pending and not NS.timer)

-- Closing while waiting must not restart automatic sending when the echo arrives.
reset(nil, "GUILD")
NS.db.automatic=true
NS.SendNext()
NS.frame:Hide()
echo("GUILD", "first paragraph")
assert(not NS.pending and not NS.timer and NS.editor.text=="second paragraph")

-- The confirmed group route can continue on its pacing timer; leader echoes match.
reset(nil, "PARTY")
NS.db.automatic=true
NS.SendNext()
echo("PARTY_LEADER", "first paragraph")
assert(NS.timer and not NS.pending)
NS.timer.callback()
assert(NS.pending and NS.pending.text=="second paragraph")
echo("PARTY_LEADER", "second paragraph")
assert(not NS.pending and not NS.queue and NS.editor.text=="")

-- Automatic pacing starts only after confirmation, and transitions cancel it.
reset(nil, "GUILD")
NS.db.automatic=true
NS.SendNext()
assert(NS.pending and not NS.timer)
echo("GUILD", "first paragraph")
assert(NS.timer and NS.queue.index==2)
local pacing=NS.timer
local remaining=NS.editor.text
event("ADDON_RESTRICTION_STATE_CHANGED", 5, 1)
assert(NS.Restricted() and pacing.cancelled and not NS.timer and not NS.frame.shown)
assert(NS.editor.text==remaining and NS.db.draft==remaining)
count=#sent
NS.SendNext()
assert(#sent==count)
event("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
assert(not NS.Restricted() and not NS.timer and NS.queue.index==2)

-- Active API state and legacy lockdown still block even without a transition.
restriction=2
assert(NS.Restricted())
restriction=0
lockdown=true
NS.editor.focused=false
NS.Open()
assert(not NS.editor.focused)
lockdown=false

-- Combat interrupts an unconfirmed part without advancing it or retrying it.
reset()
NS.SendNext()
count=#sent
combat=true
event("PLAYER_REGEN_DISABLED")
assert(not NS.pending and not NS.frame.shown and NS.queue.index==1)
assert(NS.lastSubmission.text==NS.editor.text)
combat=false
event("PLAYER_REGEN_ENABLED")
assert(#sent==count and not NS.timer)
print("Delivery, recovery, secret values, edits and restriction transitions passed")
