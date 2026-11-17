local Names = {}

function Names.nameKey(name)
    if type(name) ~= "string" then return nil end
    local display = name:gsub("_", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #display < 1 or #display > 12 or not display:match("^[A-Za-z0-9 ]+$") then return nil end
    return display:lower(), display
end

return Names
