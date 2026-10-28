local NS = {}
assert(loadfile("Splitter.lua"))("MessageSplitter", NS)
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function split(text, options)
    local parts, err = NS.Split(text, options or {})
    check(parts ~= nil, err)
    for _, part in ipairs(parts) do
        check(#part <= ((options and options.limit) or 255), "Wire limit exceeded")
    end
    return parts
end
local function balanced(text)
    local stack = {}
    for c in text:gmatch(".") do
        local top = stack[#stack]
        if c == "(" then stack[#stack + 1] = c
        elseif c == ")" then
            if top ~= "(" then return false end
            stack[#stack] = nil
        elseif c == "*" or c == '"' then
            if top == c then stack[#stack] = nil else stack[#stack + 1] = c end
        end
    end
    return #stack == 0
end
for _, span in ipairs({{"(", ")"}, {"((", "))"}, {"*", "*"}, {'"', '"'}, {"(*", "*)"}}) do
    for _, limit in ipairs({64, 100, 255}) do
        for _, markers in ipairs({false, true}) do
            local text = span[1] .. string.rep("hey there how are you ", 40) .. span[2]
            local parts = split(text, {limit=limit, markers=markers, emote=true, emoteContinuation=true})
            check(#parts > 1, "Expected multiple messages")
            for _, part in ipairs(parts) do check(balanced(part), "Unbalanced part: " .. part) end
        end
    end
end
local plain = split(string.rep("a", 500))
check(#plain[1] == 245 and #plain[2] == 245 and #plain[3] == 10, "Ten-byte reserve")
local lines = split("((first line\nsecond line))")
check(lines[1] == "((first line))" and lines[2] == "((second line))", "Newline span continuity")
local mixed = split("hello *waves* then (OOC) goodbye")
check(mixed[1] == "hello *waves* then (OOC) goodbye", "Short text changed")
local utf8 = string.char(240,159,152,128)
local unicode = split("(" .. string.rep(utf8, 140) .. ")")
for _, part in ipairs(unicode) do
    check(balanced(part), "Unicode delimiters")
    check((#part - 2) % 4 == 0, "Split UTF-8 codepoint")
end
local link = "|cffffffff|Hitem:123|h[Thing (special) *name*]|h|r"
local linked = split(string.rep("word ", 60) .. link .. string.rep(" more", 60))
local found = 0
for _, part in ipairs(linked) do if part:find(link, 1, true) then found = found + 1 end end
check(found == 1, "Hyperlink split or duplicated")
local oversized, err = NS.Split("|Hitem:123|h[" .. string.rep("x", 300) .. "]|h")
check(not oversized and err, "Oversized link should fail")
check(NS.Split(string.char(255)) == nil, "Invalid UTF-8 accepted")
-- Ensure many combinations of nesting, words and wire limits remain bounded.
math.randomseed(42)
for i = 1, 200 do
    local n = math.random(1, 12)
    local text = string.rep("(", n) .. "*" .. string.rep("test ", math.random(1, 120)) .. "*" .. string.rep(")", n)
    local parts = split(text, {limit=math.random(64,255), markers=true})
    for _, part in ipairs(parts) do check(balanced(part), "Nested randomized split") end
end
-- Regression: short intro + long unbroken word must not become three parts.
local regression = split("*wave test " .. string.rep("t", 244) .. "*", {markers=true})
check(#regression == 2, "Short introduction created excessive messages")
for _, part in ipairs(regression) do
    check(balanced(part), "Regression part lost emote markers")
    check(part ~= "**" and part ~= "** >>", "Formatting-only message")
end
for _, span in ipairs({{"*", "*"}, {"(", ")"}, {"((", "))"}}) do
    local text = span[1] .. string.rep("x", 245 - #span[1]) .. span[2]
    local parts = split(text, {markers=true})
    check(#parts == 1 and parts[1] == text, "Trailing delimiter became a separate message")
end
-- Word-boundary packing must not add a tiny third message near two-part capacity.
local packed = split("*wave " .. string.rep("test ", 95) .. "test*", {markers=true})
check(#packed == 2, "Word boundaries created a tiny third message")
for _, part in ipairs(packed) do check(balanced(part), "Packed emote lost formatting") end
print("Splitter tests passed: " .. checks .. " assertions")

