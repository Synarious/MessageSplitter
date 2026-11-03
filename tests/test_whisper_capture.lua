-- Native whisper activation must not race Whisper Manager's deferred hooks.
local NS, pending = {}, {}
SlashCmdList = {}
CreateFrame = function() return {RegisterEvent=function() end, SetScript=function() end} end
InCombatLockdown = function() return false end
C_Timer = {After=function(_, callback) pending[#pending + 1] = callback end}
assert(loadfile("Core.lua"))("MessageSplitter", NS)
NS.db = {enabled=true}
NS.composerReady = true
local opens, edits, deactivations = 0, 0, 0
NS.Open = function() opens = opens + 1 end
NS.editor = {GetText=function() return "" end, SetText=function() edits = edits + 1 end}
ChatFrameUtil = {DeactivateChat=function(box)
    deactivations = deactivations + 1
    box.focused = false
end}
local box = {
    kind="WHISPER", focused=true,
    HasFocus=function(self) return self.focused end,
    GetChatType=function(self) return self.kind end,
    GetAttribute=function(_, key) if key == "tellTarget" then return "Friend-Realm" end end,
    GetText=function() return "hello" end,
    SetText=function() edits = edits + 1 end,
}
local function flush()
    while #pending > 0 do table.remove(pending, 1)() end
end
local function reset()
    opens, edits, deactivations = 0, 0, 0
    box.kind, box.focused = "WHISPER", true
    NS.route = {type="SAY"}
end
local function assertUntouched()
    assert(opens == 0 and edits == 0 and deactivations == 0)
    assert(NS.route.type == "SAY", "Whisper activation changed the splitter draft route")
end

-- MessageSplitter's timer runs first (the original duplicate-window race).
WhisperManager = {OpenConversation=function() end}
NS.Capture(box)
flush()
assertUntouched()
assert(box.focused, "Native fallback was closed")

-- Whisper Manager runs first and removes focus from the native editor.
reset()
C_Timer.After(0, function() box.focused = false end)
NS.Capture(box)
flush()
assertUntouched()

-- The channel may still be Say when focus is gained; read the final type.
reset()
box.kind = "SAY"
NS.Capture(box)
box.kind = "WHISPER"
flush()
assertUntouched()

-- Other chat channels still use the splitter with Whisper Manager loaded.
reset()
box.kind = "SAY"
NS.Capture(box)
flush()
assert(opens == 1 and edits == 2 and deactivations == 1)

-- Missing or incompletely loaded Whisper Manager leaves whisper capture intact.
for _, manager in ipairs({false, {}}) do
    reset()
    WhisperManager = manager or nil
    NS.Capture(box)
    flush()
    assert(opens == 1 and edits == 2 and deactivations == 1)
    assert(NS.route.type == "WHISPER" and NS.route.target == "Friend-Realm")
end
print("Whisper Manager capture compatibility passed in both callback orders")
