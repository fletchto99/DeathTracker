local Store = require("src/store")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function database(data, fail)
    return {
        data = data, fail = fail, writes = 0,
        CheckExists = function(self) return self.data ~= nil end,
        GetStructuredData = function(self) return self.data end,
        SetStructuredData = function(self, _, value)
            self.writes = self.writes + 1
            if self.fail then return false end
            self.data = value
            return true
        end,
    }
end
test("name keys normalize case and spacing while preserving display case", function()
    local key, display = Store.nameKey("  FrIend_one ")
    assert(key == "friend one" and display == "FrIend one")
    assert(Store.nameKey("<col=red>Bob") == nil)
    assert(Store.nameKey("*") == nil)
    assert(Store.nameKey("a very long name") == nil)
end)
test("fresh storage counts an unseen name and persists its display case", function()
    local db = database()
    local store = Store.new(db)
    assert(#store:rows() == 0)
    assert(store:increment("stranger", "Stranger"))
    assert(store:increment("stranger", "Stranger"))
    local nextStore = Store.new(db)
    local rows = nextStore:rows()
    assert(#rows == 1 and rows[1].name == "Stranger" and rows[1].count == 2)
    assert(db.data.names == nil)
end)
test("version 1 migrates every total including names removed from the old allowlist", function()
    local old = { version = 1, names = { "Alice", "Zero" }, counts = { alice = 3, bob = 7, zero = 0 } }
    local db = database(old)
    local store = Store.new(db)
    assert(db.data.version == 2 and db.data.names == nil)
    assert(store.data.counts.alice == 3 and store.data.counts.bob == 7 and store.data.counts.zero == 0)
    local rows = store:rows()
    assert(#rows == 2 and rows[1].name == "Alice" and rows[2].name == "bob")
    assert(old.version == 1 and old.counts.bob == 7)
    local nextStore = Store.new(db)
    assert(db.writes == 1 and nextStore.data.counts.bob == 7)
    assert(nextStore:increment("bob", "Bob"))
    assert(nextStore:rows()[2].name == "Bob" and nextStore.data.counts.bob == 8)
end)
test("an empty legacy allowlist does not disable or erase historical counters", function()
    local db = database({ version = 1, names = {}, counts = { alice = 4 } })
    local store = Store.new(db)
    assert(store:increment("bob", "Bob"))
    assert(store.data.counts.alice == 4 and store.data.counts.bob == 1)
    assert(#store:rows() == 2)
end)
test("more than 20 distinct collected names are saved and returned as rows", function()
    local db = database()
    local store = Store.new(db)
    for i = 1, 25 do assert(store:increment("player" .. i, "Player" .. i)) end
    local restored = Store.new(db)
    local rows = restored:rows()
    assert(#rows == 25)
    for _, row in ipairs(rows) do assert(row.count == 1 and row.name:match("^Player%d+$")) end
end)
test("failed migration preserves the original storage and retry saves subsequent increments", function()
    local old = { version = 1, names = { "Alice" }, counts = { alice = 3, bob = 2 } }
    local db = database(old, true)
    local store = Store.new(db)
    assert(store.unsaved and db.data == old and old.version == 1)
    assert(not store:increment("alice", "Alice"))
    assert(store.data.counts.alice == 4 and old.counts.alice == 3 and old.counts.bob == 2)
    db.fail = false
    assert(store:save() and not store.unsaved)
    assert(db.data.version == 2 and db.data.counts.alice == 4 and db.data.counts.bob == 2)
end)
test("failed counter writes retain in-memory values for retry", function()
    local db = database(nil, true)
    local store = Store.new(db)
    assert(not store:increment("alice", "Alice") and store.unsaved)
    assert(store.data.counts.alice == 1 and db.data == nil)
    db.fail = false
    assert(store:save() and not store.unsaved)
    assert(db.data.counts.alice == 1)
end)
test("invalid or future-version storage is preserved, not reset", function()
    for _, data in ipairs({
        "bad",
        { version = 3, displayNames = {}, counts = {} },
        { version = 2, counts = {} },
        { version = 2, displayNames = {}, counts = { alice = 1 } },
        { version = 2, displayNames = { alice = "Bob" }, counts = { alice = 1 } },
        { version = 1, names = { "Alice" }, counts = { alice = -1 } },
        { version = 1, names = { "Alice" }, counts = { Alice = 1 } },
        { version = 1, names = { "Alice", "alice" }, counts = {} },
    }) do
        local db = database(data)
        local ok = pcall(Store.new, db)
        assert(not ok and db.writes == 0 and db.data == data)
    end
end)
return passed
