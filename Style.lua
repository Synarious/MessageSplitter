local _, NS = ...
local function roundedShape(frame, outline)
    local shape = {textures = {}}
    local radius = 4
    local function texture()
        local t = frame:CreateTexture(nil, outline and "BORDER" or "BACKGROUND", nil, outline and 0 or -7)
        shape.textures[#shape.textures + 1] = t
        return t
    end
    for _, corner in ipairs({
        {"TOPLEFT", 0, 1, 0, 1}, {"TOPRIGHT", 1, 0, 0, 1},
        {"BOTTOMLEFT", 0, 1, 1, 0}, {"BOTTOMRIGHT", 1, 0, 1, 0},
    }) do
        local t = texture()
        t:SetTexture("Interface\\AddOns\\MessageSplitter\\Media\\" .. (outline and "RoundedOutline4.tga" or "RoundedCorner.tga"))
        t:SetSize(radius, radius)
        t:SetPoint(corner[1], frame, corner[1], 0, 0)
        t:SetTexCoord(corner[2], corner[3], corner[4], corner[5])
    end
    for _, side in ipairs({"TOP", "BOTTOM"}) do
        local t = texture()
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetPoint(side .. "LEFT", frame, side .. "LEFT", radius, 0)
        t:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", -radius, 0)
        t:SetHeight(outline and 1 or radius)
    end
    if outline then
        for _, side in ipairs({"LEFT", "RIGHT"}) do
            local t = texture()
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, -radius)
            t:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, radius)
            t:SetWidth(1)
        end
    else
        local t = texture()
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -radius)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, radius)
    end
    function shape:SetColor(color)
        for _, t in ipairs(self.textures) do t:SetVertexColor(unpack(color)) end
    end
    return shape
end

function NS.Skin(frame, color, border)
    if not frame then return end
    if frame.SetBackdrop then frame:SetBackdrop(nil) end
    frame.wmRoundedFill = frame.wmRoundedFill or roundedShape(frame, false)
    frame.wmRoundedBorder = frame.wmRoundedBorder or roundedShape(frame, true)
    frame.wmRoundedFill:SetColor(color)
    frame.wmRoundedBorder:SetColor(border)
end

