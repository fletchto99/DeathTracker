local Store = {}
Store.__index = Store

Store.nameKey = require("src/names").nameKey

function Store.new(db)
    local data = db:GetStructuredData("state")
    if data == nil and not db:CheckExists("state") then
        data = { version = 2, displayNames = {}, counts = {} }
    end
    assert(type(data) == "table" and (data.version == 1 or data.version == 2)
        and type(data.counts) == "table", "BoneCollector: saved data is invalid; it has NOT been overwritten.")
    local names, counts = {}, {}
    if data.version == 1 then
        assert(type(data.names) == "table", "BoneCollector: invalid legacy names; data preserved.")
        for index, name in pairs(data.names) do
            local key, display = Store.nameKey(name)
            assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #data.names
                and key and not names[key], "BoneCollector: invalid legacy names; data preserved.")
            names[key] = display
        end
    else
        assert(type(data.displayNames) == "table", "BoneCollector: invalid saved display names; data preserved.")
        for key, display in pairs(data.displayNames) do
            assert(Store.nameKey(display) == key and Store.nameKey(key) == key,
                "BoneCollector: invalid saved display name; data preserved.")
            names[key] = display
        end
    end
    for key, count in pairs(data.counts) do
        assert(Store.nameKey(key) == key and type(count) == "number" and count % 1 == 0
            and count >= 0 and count <= 2147483647, "BoneCollector: invalid saved counter; data preserved.")
        counts[key] = count
        -- Version 1 retained totals for removed names but not their display case.
        if data.version == 1 and not names[key] then names[key] = key end
        assert(names[key], "BoneCollector: saved counter has no display name; data preserved.")
    end
    local self = setmetatable({
        db = db, data = { version = 2, counts = counts, displayNames = names }, unsaved = false, revision = 1,
    }, Store)
    if data.version == 1 then self:save() end
    return self
end

function Store:save()
    self.unsaved = self.db:SetStructuredData("state", self.data) ~= true
    return not self.unsaved
end

function Store:increment(key, display)
    display = display or key
    assert(Store.nameKey(key) == key and Store.nameKey(display) == key,
        "BoneCollector: invalid collection name; no increment saved.")
    local count = self.data.counts[key] or 0
    assert(count < 2147483647, "BoneCollector: counter limit reached; no increment saved.")
    self.data.counts[key] = count + 1
    self.data.displayNames[key] = display
    self.revision = self.revision + 1
    return self:save()
end

function Store:rows()
    local rows = {}
    for key, count in pairs(self.data.counts) do
        if count > 0 then rows[#rows + 1] = { key = key, name = self.data.displayNames[key], count = count } end
    end
    table.sort(rows, function(a, b) return a.key < b.key end)
    return rows
end

return Store
