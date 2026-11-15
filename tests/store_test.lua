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
test("names are trimmed, normalized, exact, deduplicated and sorted", function()
    local names = assert(Store.parseNames(" Bob, ALIce, alice, Friend_one,  "))
    assert(table.concat(names, ",") == "ALIce,Bob,Friend one")
    assert(Store.nameKey("  FrIend_one ") == "friend one")
    assert(Store.nameKey("<col=red>Bob") == nil)
    assert(Store.nameKey("*") == nil)
    assert(Store.nameKey("a very long name") == nil)
end)
test("empty means disabled and invalid edits leave the old list", function()
    local store = Store.new(database())
    assert(next(store:tracked()) == nil)
    assert(store:setNames("Alice"))
    assert(not store:setNames("Bob,*"))
    assert(store:tracked().alice == "Alice")
    assert(store:setNames(""))
    assert(next(store:tracked()) == nil)
end)
test("saved counters survive restart and untracking", function()
    local db = database()
    local store = Store.new(db)
    assert(store:setNames("Alice"))
    assert(store:increment("alice"))
    store:setNames("")
    local nextStore = Store.new(db)
    nextStore:setNames("ALICE")
    assert(nextStore.data.counts.alice == 1)
end)
test("write failure is explicit and retry persists the current count", function()
    local db = database(nil, true)
    local store = Store.new(db)
    local ok, err = store:setNames("Alice")
    assert(not ok and err:match("NOT saved") and store.unsaved)
    assert(not store:increment("alice"))
    assert(store.data.counts.alice == 1 and db.data == nil)
    db.fail = false
    assert(store:save() and not store.unsaved)
    assert(db.data.counts.alice == 1)
end)
test("invalid or future-version storage is preserved, not reset", function()
    for _, data in ipairs({
        "bad",
        { version = 2, names = {}, counts = {} },
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
