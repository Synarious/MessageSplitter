local _, NS = ...

-- Original implementation. Count wire bytes, never cut a UTF-8 codepoint or
-- a hyperlink escape. Formatting other than hyperlinks is deliberately rejected.
local function tokens(text)
    local result, i = {}, 1
    while i <= #text do
        local tail = text:sub(i)
        local link = tail:match("^|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r")
            or tail:match("^|H.-|h.-|h")
        if link then
            result[#result + 1] = link
            i = i + #link
        else
            local b = text:byte(i)
            if b == 124 then return nil, "Unsupported or incomplete chat markup. Remove it before sending." end
            local width = b < 128 and 1 or b >= 194 and b <= 223 and 2
                or b >= 224 and b <= 239 and 3 or b >= 240 and b <= 244 and 4
            if not width or i + width - 1 > #text then return nil, "Invalid UTF-8 text." end
            for n = 1, width - 1 do
                local c = text:byte(i + n)
                if c < 128 or c > 191 then return nil, "Invalid UTF-8 text." end
            end
            -- Reject overlong sequences, surrogate codepoints and values > U+10FFFF.
            local c = text:byte(i + 1)
            if width == 3 and ((b == 224 and c < 160) or (b == 237 and c >= 160))
                or width == 4 and ((b == 240 and c < 144) or (b == 244 and c >= 144)) then
                return nil, "Invalid UTF-8 text."
            end
            result[#result + 1] = text:sub(i, i + width - 1)
            i = i + width
        end
    end
    return result
end

-- Formatting belongs to each wire message, not just the combined draft.
-- Track source delimiters independently of the synthetic closers/reopeners.
local function wrappers(stack)
    local opening, closing = {}, {}
    for i, token in ipairs(stack) do opening[i] = token end
    for i = #stack, 1, -1 do
        closing[#closing + 1] = stack[i] == "(" and ")" or stack[i]
    end
    return table.concat(opening), table.concat(closing)
end

local function advance(stack, token)
    local top = stack[#stack]
    if token == ")" then
        if top == "(" then stack[#stack] = nil end
    elseif token == "(" then
        stack[#stack + 1] = token
    elseif token == "*" or token == '"' then
        if top == token then stack[#stack] = nil
        else stack[#stack + 1] = token end
    end
    -- Hyperlinks are atomic tokens, so their labels never change this stack.
end

function NS.Split(text, options)
    options = options or {}
    local limit = math.max(64, math.min(255, tonumber(options.limit) or 255))
    -- Leave ten bytes for formatting/continuation overhead, while also checking
    -- the exact final wire length in case deeply nested spans need more room.
    local payloadLimit = limit - 10
    local marker = options.markers and " >>" or ""
    local prefix = options.emote and options.emoteContinuation and "... " or ""
    local out, stack = {}, {}
    -- Newlines intentionally become separate messages. Preserve active spans
    -- across lines, closing/reopening them on each independently sent message.
    for line in text:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local units, err = tokens(line)
            if not units then return nil, err end
            local opens, closes, bytes = {}, {}, {[0]=0}
            opens[0], closes[0] = wrappers(stack)
            for i, token in ipairs(units) do
                advance(stack, token)
                opens[i], closes[i] = wrappers(stack)
                bytes[i] = bytes[i - 1] + #token
            end
            local start = 1
            while start <= #units do
                local head = (#out > 0 and prefix or "") .. opens[start - 1]
                local finish, size, lastSpace, spaceSize = start - 1, 0, nil, 0
                while finish < #units do
                    local nextIndex = finish + 1
                    local nextSize = size + #units[nextIndex]
                    local tail = nextIndex < #units and marker or ""
                    if nextSize > payloadLimit
                        or #head + nextSize + #closes[nextIndex] + #tail > limit then break end
                    finish, size = nextIndex, nextSize
                    if units[finish]:match("^%s$") then lastSpace, spaceSize = finish, size end
                end
                if finish < start then
                    return nil, "A hyperlink or nested formatting is too large for the message limit (10 bytes reserved)."
                end
                -- Prefer word boundaries only when they use at least half the
                -- available payload. A short introduction followed by a long
                -- unbroken word should not become its own tiny message.
                if finish < #units and lastSpace and lastSpace > start and spaceSize >= size / 2 then
                    local afterSpace = lastSpace + 1
                    while afterSpace <= #units and units[afterSpace]:match("^%s$") do afterSpace = afterSpace + 1 end
                    local wordRemainder = bytes[#units] - bytes[afterSpace - 1]
                    local fullRemainder = bytes[#units] - bytes[finish]
                    -- Do not sacrifice capacity for a word boundary if it would
                    -- leave an extra message containing just a few characters.
                    if math.ceil(wordRemainder / payloadLimit) <= math.ceil(fullRemainder / payloadLimit) then
                        finish, size = lastSpace, spaceSize
                    end
                end
                -- Original closing delimiters can use the reserved overhead.
                -- Keep them with their text instead of emitting a final "**"
                -- or "()" message solely because the payload budget was full.
                while finish < #units and #opens[finish + 1] < #opens[finish] do
                    local nextSize = size + #units[finish + 1]
                    local tail = finish + 1 < #units and marker or ""
                    if #head + nextSize + #closes[finish + 1] + #tail > limit then break end
                    finish, size = finish + 1, nextSize
                end
                local body = table.concat(units, "", start, finish):gsub("%s+$", "")
                local nextStart = finish + 1
                while nextStart <= #units and units[nextStart]:match("^%s$") do nextStart = nextStart + 1 end
                out[#out + 1] = head .. body .. closes[finish] .. (nextStart <= #units and marker or "")
                start = nextStart
            end
        end
    end
    return out
end

local aliases = {s="SAY", say="SAY", y="YELL", yell="YELL", p="PARTY", party="PARTY",
    ra="RAID", raid="RAID", rw="RAID_WARNING", g="GUILD", guild="GUILD",
    o="OFFICER", officer="OFFICER", i="INSTANCE_CHAT", instance="INSTANCE_CHAT",
    e="EMOTE", em="EMOTE", me="EMOTE", emote="EMOTE"}

function NS.Parse(text, route)
    local command, rest = text:match("^/(%S+)%s*(.*)$")
    if not command then
        if text:sub(1, 1) == "/" then return nil, "Complete the channel command, or use Default chat for other slash commands." end
        return text, {type=route.type, target=route.target, language=route.language}
    end
    command = command:lower()
    if aliases[command] then return rest, {type=aliases[command], language=route.language} end
    if command == "w" or command == "whisper" or command == "tell" then
        local target, body = rest:match("^(%S+)%s+(.*)$")
        if not target then return nil, "Use /w Character-Realm message." end
        return body, {type="WHISPER", target=target, language=route.language}
    end
    if command:match("^%d+$") then return rest, {type="CHANNEL", target=tonumber(command), language=route.language} end
    return nil, "Use Default chat for /" .. command .. ". This composer only handles chat channel commands."
end
