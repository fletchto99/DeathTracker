local Names = require("src/names")
local Deaths = {}
Deaths.__index = Deaths
Deaths.key = "selfDeaths.v1"
Deaths.recentLimit = 16

local function integer(value, minimum)
    return type(value) == "number" and value < math.huge and value % 1 == 0 and value >= minimum
end

function Deaths.matches(event)
    if event.chatType ~= ChatType.GENERAL then return false end
    if event.senderNameUnfiltered ~= "" or event.senderNameFiltered ~= "" or event.senderNameSimple ~= "" then return false end
    if type(event.chatMessage) ~= "string" then return false end
    local text = event.chatMessage:gsub("<col=%x+>", ""):gsub("</col>", "")
    return text == "Oh dear, you are dead!"
end

function Deaths.new(db)
    local self = setmetatable({ db = db, unsaved = false }, Deaths)
    local ok, data = pcall(function()
        local stored = db:GetStructuredData(Deaths.key)
        if stored == nil then
            local exists = db:CheckExists(Deaths.key)
            assert(type(exists) == "boolean", "could not determine whether death data exists")
            if not exists then return { version = 1, characters = {} } end
        end
        assert(type(stored) == "table" and stored.version == 1 and type(stored.characters) == "table",
            "saved death data has an invalid or unsupported format")
        local result = { version = 1, characters = {} }
        for key, record in pairs(stored.characters) do
            assert(Names.nameKey(key) == key and type(record) == "table" and integer(record.count, 0)
                and record.count <= 2147483647 and type(record.recent) == "table", "invalid saved character counter")
            local recent, count = {}, 0
            for index, timestamp in pairs(record.recent) do
                assert(integer(index, 1) and index <= #record.recent and integer(timestamp, 1), "invalid saved notification timestamp")
                recent[index], count = timestamp, count + 1
            end
            assert(count == #record.recent and count <= Deaths.recentLimit and count <= record.count,
                "invalid saved notification history")
            result.characters[key] = { count = record.count, recent = recent }
        end
        return result
    end)
    if ok then self.data = data
    else self.loadError = "Cannot load death counts: " .. tostring(data) .. ". Data was not overwritten." end
    return self
end

function Deaths:count(key)
    if not self.data or not key then return nil end
    local record = self.data.characters[key]
    return record and record.count or 0
end

function Deaths:save()
    if self.loadError then return false, self.loadError end
    local ok, result = pcall(self.db.SetStructuredData, self.db, Deaths.key, self.data)
    self.unsaved = not (ok and result == true)
    self.saveError = self.unsaved and ("NOT SAVED: death counts are in memory only. Use Retry save."
        .. (not ok and (" " .. tostring(result)) or "")) or nil
    return not self.unsaved, self.saveError
end

function Deaths:record(key, timestamp)
    if self.loadError then return "error", self.loadError end
    if type(key) ~= "string" or Names.nameKey(key) ~= key or not integer(timestamp, 1) then
        return "error", "Self-death message ignored: character identity or notification timestamp is invalid."
    end
    local record = self.data.characters[key] or { count = 0, recent = {} }
    -- ChatMessage has seconds-resolution timestamps, not a unique message ID.
    -- Remember recent equal timestamps, including across reloads; no cooldown.
    for _, seen in ipairs(record.recent) do
        if seen == timestamp then return "duplicate" end
    end
    if record.count >= 2147483647 then return "error", "Death counter limit reached; no increment recorded." end
    record.count = record.count + 1
    record.recent[#record.recent + 1] = timestamp
    if #record.recent > Deaths.recentLimit then table.remove(record.recent, 1) end
    self.data.characters[key] = record
    local _, err = self:save()
    return "counted", err
end

return Deaths
