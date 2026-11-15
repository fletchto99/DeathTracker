local Store = {}
Store.__index = Store

function Store.nameKey(name)
    if type(name) ~= "string" then return nil end
    local display = name:gsub("_", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #display < 1 or #display > 12 or not display:match("^[A-Za-z0-9 ]+$") then return nil end
    return display:lower(), display
end

function Store.parseNames(text)
    if type(text) ~= "string" then return nil, "Enter comma-separated display names." end
    local names, seen = {}, {}
    for name in (text .. ","):gmatch("(.-),") do
        if name:match("%S") then
            local key, display = Store.nameKey(name)
            if not key then return nil, "Names must be 1-12 letters, numbers, spaces or underscores." end
            if not seen[key] then
                names[#names + 1], seen[key] = display, true
            end
        end
    end
    if #names > 20 then return nil, "This prototype supports at most 20 tracked names." end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Store.new(db)
    local data = db:GetStructuredData("state")
    if data == nil and not db:CheckExists("state") then
        data = { version = 1, names = {}, counts = {} }
    end
    assert(type(data) == "table" and data.version == 1 and type(data.names) == "table"
        and type(data.counts) == "table", "BoneCollector: saved data is invalid; it has NOT been overwritten.")
    local names = {}
    for index, name in pairs(data.names) do
        assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #data.names
            and Store.nameKey(name), "BoneCollector: invalid saved tracked names; data preserved.")
        names[index] = name
    end
    local canonical = assert(Store.parseNames(table.concat(names, ",")))
    assert(#canonical == #names, "BoneCollector: duplicate saved tracked names; data preserved.")
    for key, count in pairs(data.counts) do
        assert(Store.nameKey(key) == key and type(count) == "number" and count % 1 == 0
            and count >= 0 and count <= 2147483647, "BoneCollector: invalid saved counter; data preserved.")
    end
    data.names = canonical
    return setmetatable({ db = db, data = data, unsaved = false }, Store)
end

function Store:tracked()
    local result = {}
    for _, name in ipairs(self.data.names) do result[Store.nameKey(name)] = name end
    return result
end

function Store:save()
    self.unsaved = self.db:SetStructuredData("state", self.data) ~= true
    return not self.unsaved
end

function Store:setNames(text)
    local names, err = Store.parseNames(text)
    if not names then return false, err end
    self.data.names = names
    if not self:save() then return false, "Names apply now, but were NOT saved. Use Retry save." end
    return true
end

function Store:increment(key)
    local count = self.data.counts[key] or 0
    assert(count < 2147483647, "BoneCollector: counter limit reached; no increment saved.")
    self.data.counts[key] = count + 1
    return self:save()
end

return Store
