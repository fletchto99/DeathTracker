local Names = {}

function Names.nameKey(name)
    if type(name) ~= "string" then return nil, nil, "displayName is " .. type(name) .. ", not a string" end
    -- Native player names use NBSP variants that Lua's ASCII %s does not match.
    local display = name:gsub("\195\130\194\160", " "):gsub("\194\160", " "):gsub("\160", " ")
        :gsub("_", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #display == 0 then return nil, nil, "name is empty after whitespace normalization" end
    local invalid = display:find("[^A-Za-z0-9 ]")
    if invalid then
        return nil, nil, string.format("unsupported byte 0x%02X at normalized position %d", display:byte(invalid), invalid)
    end
    if #display > 12 then return nil, nil, "normalized name is " .. #display .. " bytes (maximum 12)" end
    return display:lower(), display
end

return Names
