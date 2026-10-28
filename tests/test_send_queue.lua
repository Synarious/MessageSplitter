local NS, sent, now = {}, {}, 0
SlashCmdList = {}
CreateFrame = function() return {RegisterEvent=function() end, SetScript=function() end} end
GetTime = function() return now end
InCombatLockdown = function() return false end
C_ChatInfo = {SendChatMessage=function(text) sent[#sent+1] = text end}
assert(loadfile("Splitter.lua"))("MessageSplitter", NS)
assert(loadfile("Core.lua"))("MessageSplitter", NS)
assert(loadfile("Composer.lua"))("MessageSplitter", NS)
NS.db = NS.defaults
NS.db.automatic = false
NS.db.rememberDraft = false
NS.composerReady = true
NS.UpdateEditorLayout = function() end
NS.PaintChannel = function() end
NS.SetStatus = function() end
NS.counter = {SetText=function(self, text) self.text = text end}
local hides = 0
NS.frame = {Hide=function() hides = hides + 1 end}
NS.editor = {
 text="*wave " .. string.rep("test ", 95) .. "test*",
 GetText=function(self) return self.text end,
 EnableMouse=function() end,
 SetText=function(self,text)
  self.text=text
  if not NS.internalEdit then NS.CancelQueue() end
  NS.RefreshPreview()
 end,
}
if TEST_SPELLCHECK then
 local wires = 0
 Misspelled = {
  WireUpEditBox=function(self, editor)
   wires = wires + 1
   assert(editor.__misspelled_selfCleaning)
  end,
  RemoveHighlighting=function(self, text)
   return (text:gsub("|cff7dc6fb(.-)|r", "%1"))
  end,
 }
 NS.AttachSpellcheck()
 NS.AttachSpellcheck()
 assert(wires == 1, "Spellchecker attached twice")
 NS.editor.text = NS.editor.text:gsub("wave", "|cff7dc6fbwave|r")
 assert(not NS.GetDraftText():find("|",1,true), "Highlighting was not cleaned")
end
local draft = NS.editor.text
NS.editor.text = "*hi*"
local emote = assert(NS.Prepare())
assert(emote.route.type == "EMOTE" and emote.parts[1] == "hi", "Standalone action must use native emote")
assert(NS.route.type == "SAY", "Preview changed the selected route")
NS.editor.text = "Hello *waves*"
assert(NS.Prepare().route.type == "SAY", "Mixed speech must stay in Say")
NS.route = {type="PARTY"}
NS.editor.text = "*hi*"
assert(NS.Prepare().route.type == "PARTY", "Explicit group route changed")
NS.route = {type="SAY"}
NS.editor.text = draft
local expected = assert(NS.Prepare()).parts
NS.RefreshPreview()
assert(#expected == 2 and NS.counter.text:find("2p",1,true))
NS.SendNext()
assert(#sent == 1 and NS.queue and NS.counter.text:find("1/2p",1,true))
assert(hides == 0, "Composer closed with pending messages")
now = 1
NS.SendNext()
assert(#sent == 2 and not NS.queue and NS.editor.text == "")
assert(hides == 1, "Composer did not close after the final message")
for i,part in ipairs(expected) do
 assert(sent[i] == part)
 assert(not sent[i]:find("|c",1,true), "Spellcheck colors leaked into chat")
end
now = 2
NS.SendNext()
assert(#sent == 2, "Unexpected third message")
print("Preview and actual send queue agree: exactly two messages")

-- Commands execute only on submit, preserve the channel, and never send chat.
local calls = 0
SLASH_TESTCOMMAND1 = "/testcommand"
SlashCmdList.TESTCOMMAND = function(args)
 calls = calls + 1
 assert(args == "hello")
end
NS.route = {type="PARTY"}
NS.editor.text = "/testcommand hello"
NS.RefreshPreview()
assert(calls == 0, "Command executed while typing")
NS.SendNext()
assert(calls == 1 and NS.editor.text == "")
assert(NS.route.type == "PARTY" and #sent == 2)
NS.editor.text = "/unknowncommand"
NS.SendNext()
assert(NS.editor.text == "/unknowncommand" and #sent == 2)
NS.editor.text = "/s hello"
assert(not NS.RouteSlashCommand(), "Chat route intercepted as command")
print("Commands execute on submit without changing channel or sending chat")

local reloads = 0
ReloadUI = function() reloads = reloads + 1 end
for _, command in ipairs({"/reload", "/rl"}) do
 NS.editor.text = command
 NS.SendNext()
 assert(NS.editor.text == "")
end
assert(reloads == 2 and NS.route.type == "PARTY" and #sent == 2)
print("Built-in reload aliases execute without a SlashCmdList entry")

-- Bare chat commands select a route without submitting an empty message.
GetChannelName = function(id) return id, "General" end
for _, case in ipairs({{"/p", "PARTY"}, {"/RAID", "RAID"}, {"/g   ", "GUILD"},
 {"/s", "SAY"}, {"/e", "EMOTE"}, {"/1", "CHANNEL", 1}}) do
 NS.editor.text = case[1]
 NS.queue = {parts={"stale"}, index=1}
 NS.nextSend = now + 10
 NS.SendNext()
 assert(NS.route.type == case[2] and NS.route.target == case[3], "Bare command did not select route")
 assert(NS.editor.text == "" and not NS.queue and #sent == 2, "Channel selection sent or retained a message")
end
NS.editor.text = "/p hello"
assert(not NS.RouteSlashCommand(), "Channel message intercepted as selection")
NS.editor.text = "/w"
NS.SendNext()
assert(NS.editor.text == "/w" and #sent == 2, "Incomplete whisper discarded")
print("Bare channel commands select their route without sending chat")
