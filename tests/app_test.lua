local App = require("src/app")
local passed = 0
local realPrint = print
local function test(name, run)
    local ok, err = pcall(run)
    print = realPrint
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function proxy(data)
    local valid = true
    return setmetatable({}, {
        __index = function(_, key)
            if key == "isValid" then return valid end
            assert(valid, "invalid proxy read: " .. key)
            return data[key]
        end,
        __newindex = function() error("proxy is read-only") end,
    }), function() valid = false end
end
local function fixture(options)
    options = options or {}
    local f = { tick = 0, logs = {}, slots = {}, visibleStacks = {}, widgets = {}, components = {}, nextID = 0 }
    print = function(...) f.logs[#f.logs + 1] = table.concat({ ... }, " ") end
    config = { Obj = { BONES = { id = 526 }, LOGS = { id = 1511 } }, Inv = { INV = { id = 93 } } }
    MiniMenuEntryType, MiniMenuActionType, GameState = { OBJ = 2, INTERFACE = 1 }, { OP_OBJ3 = 20 }, { GAME = 30 }
    Event = {}
    for _, name in ipairs({
        "Logic", "Draw", "PlayerEntityAdded", "PlayerEntityRemoved", "ObjStackEntityAdded",
        "ObjStackEntityChanged", "ObjStackEntityRemoved", "MiniMenuEntrySelected", "InventoryUpdated",
        "InventoryAdded", "InventoryRemoved", "ServerLogic", "GameStateChanged", "WorldCreated",
        "WorldUpdated", "RegionCreated", "RegionUpdated", "SettingsLayerReady", "ContentLayerReady",
    }) do
        local callbacks = {}
        Event[name] = {
            callbacks = callbacks,
            Subscribe = function(ref, callback) callbacks[ref] = callback end,
            Unsubscribe = function(ref) callbacks[ref] = nil end,
        }
    end
    function f.emit(name, data)
        for _, callback in pairs(Event[name].callbacks) do callback(data) end
    end
    f.localData = { uid = 1, displayName = "Me", coordGrid = { level = 0, x = 100, z = 100 } }
    f.friendData = { uid = 2, displayName = "Alice", coordGrid = { level = 0, x = 100, z = 100 } }
    f.selfEntity, f.invalidateSelf = proxy(f.localData)
    f.friend, f.invalidateFriend = proxy(f.friendData)
    f.visiblePlayers = { f.selfEntity, f.friend }
    Player = { IsAvailable = function() return not f.unavailable end }
    PlayerList = {
        Self = function() return f.selfEntity end,
        All = function() return f.visiblePlayers end,
    }
    ObjStackList = { All = function() return f.visibleStacks end }
    Inventory = { Find = function(inv)
        assert(inv == config.Inv.INV)
        if f.noInventory then return nil end
        return { isValid = true, GetSlots = function() if not f.badSlots then return f.slots end end }
    end }
    PersistentDB = {
        data = { version = 1, names = options.names or { "Alice" }, counts = {} }, writes = 0,
        GetStructuredData = function(self, key) assert(key == "state"); return copy(self.data) end,
        CheckExists = function(self, key) assert(key == "state"); return self.data ~= nil end,
        SetStructuredData = function(self, key, value)
            assert(key == "state")
            if f.failSave then return false end
            self.writes = self.writes + 1
            self.data = copy(value)
            return true
        end,
    }
    function f.component(width, height)
        f.nextID = f.nextID + 1
        local data = { interfaceID = 1, staticID = f.nextID, categoryID = 0, dynamicID = 0, width = width, height = height }
        local component, invalidate = proxy(data)
        f.components[data.staticID] = component
        return component, function()
            f.components[data.staticID] = nil
            invalidate()
        end, data
    end
    ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
        assert(interfaceID == 1 and categoryID == 0 and dynamicID == 0)
        return f.components[staticID]
    end } }
    local SimpleView = {}
    function SimpleView.new(parent, dimensions)
        assert(parent.width == dimensions.width and parent.height == dimensions.height)
        local root, invalidate = f.component(dimensions.width, dimensions.height)
        local widget = setmetatable({ root = root, texts = {}, buttons = {}, invalidate = invalidate }, { __index = SimpleView })
        f.widgets[#f.widgets + 1] = widget
        return widget
    end
    function SimpleView:AddTitle(text) return self:AddText(text) end
    function SimpleView:AddText(options)
        local text = { content = type(options) == "string" and options or options.text }
        self.texts[#self.texts + 1] = text
        return text
    end
    function SimpleView:AddTextField(options)
        local widget = self
        local field = {
            text = options.text, submit = options.onSubmit,
            GetText = function(self) assert(not widget.destroyed, "stale field access"); return self.text end,
            SetText = function(self, text, notify) assert(not notify); self.text = text end,
        }
        self.field = field
        return field
    end
    function SimpleView:AddSimpleButton(label, callback)
        local button = { click = callback, SetActive = function(self, active) self.active = active end }
        self.buttons[label] = button
        return button
    end
    function SimpleView:SetSize(width, height) self.width, self.height = width, height end
    function SimpleView:Destroy() self.destroyed = true; self.invalidate() end
    prettyui = { SimpleView = SimpleView }
    function f.go(target)
        for tick = f.tick + 1, target do
            f.tick = tick
            f.emit("Logic", { logicTick = tick })
            if tick % 30 == 0 then f.emit("ServerLogic") end
        end
    end
    function f.die(valid)
        f.visiblePlayers = { f.selfEntity }
        if not valid then f.invalidateFriend() end
        f.emit("PlayerEntityRemoved", { playerEntity = f.friend })
        if valid then f.invalidateFriend() end
    end
    function f.ground(entries, announce)
        local data = { coordGrid = { level = 0, x = 100, z = 100 }, entries = entries, stackSize = #entries }
        data.GetEntry = function(_, index) return data.entries[index] end
        local entity, invalidate = proxy(data)
        local ground = { entity = entity, data = data, invalidate = invalidate }
        f.visibleStacks[#f.visibleStacks + 1] = entity
        if announce then f.emit("ObjStackEntityAdded", { objStackEntity = entity, objType = config.Obj.BONES, count = 1, isOwner = false }) end
        return ground
    end
    function f.bone() return { configID = 526, config = config.Obj.BONES, count = 1 } end
    function f.click(ground, overrides)
        local entry = {
            actionEntryType = 2, actionType = 20, verbText = "Take",
            objData = { entity = ground.entity, stackIndex = 1, config = config.Obj.BONES },
        }
        for key, value in pairs(overrides or {}) do entry[key] = value end
        f.emit("MiniMenuEntrySelected", { entry = entry })
    end
    function f.remove(ground)
        f.visibleStacks = {}
        ground.invalidate()
        f.emit("ObjStackEntityRemoved", { objStackEntity = ground.entity, objType = config.Obj.BONES, count = 1, isOwner = false })
    end
    function f.gain(other)
        local count = f.slots[1] and f.slots[1].count or 0
        f.slots[1] = { obj = config.Obj.BONES, count = count + 1 }
        if other then f.slots[7] = { obj = config.Obj.LOGS, count = 1 } end
        f.emit("InventoryUpdated", { inv = config.Inv.INV, slotsUpdated = { 1, 7 } })
    end
    function f.collect(ground, inventoryFirst)
        f.click(ground)
        if inventoryFirst then f.gain() end
        f.remove(ground)
        if not inventoryFirst then f.gain() end
        f.emit("ServerLogic")
    end
    function f.credit() return PersistentDB.data.counts.alice or 0 end
    function f.show(kind)
        local parent, invalidate, data = f.component(500, 700)
        f.emit(kind or "SettingsLayerReady", { component = parent })
        return f.widgets[#f.widgets], invalidate, data
    end
    function f.noFatal()
        for _, line in ipairs(f.logs) do assert(not line:match("Monitoring stopped"), line) end
    end
    f.shutdown = App.start()
    return f
end

test("native event sequence with invalid removed proxies counts in either order", function()
    for _, inventoryFirst in ipairs({ true, false }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        f.collect(ground, inventoryFirst)
        assert(f.credit() == 0)
        f.go(300)
        assert(f.credit() == 1)
        f.noFatal()
        f.shutdown()
    end
end)
test("a valid removal snapshot detects last-moment movement instead of using an old tile", function()
    local f = fixture()
    f.go(161)
    f.friendData.coordGrid.x = 101
    f.die(true)
    local ground = f.ground({ f.bone() }, true)
    f.collect(ground)
    f.go(300)
    assert(f.credit() == 0)
    f.noFatal()
    f.shutdown()
end)
test("existing stacks and same-config duplicate entries cannot be mistaken for fresh single bones", function()
    for _, preexisting in ipairs({ true, false }) do
        local f = fixture()
        local ground
        if preexisting then ground = f.ground({ f.bone() }) end
        f.go(161)
        f.die()
        if not preexisting then ground = f.ground({ f.bone(), f.bone() }, true) end
        f.collect(ground)
        f.go(300)
        assert(f.credit() == 0)
        f.noFatal()
        f.shutdown()
    end
end)
test("bone added and removed via Changed on an existing unrelated stack", function()
    local f = fixture()
    local logs = { configID = 1511, config = config.Obj.LOGS, count = 1 }
    local ground = f.ground({ logs })
    f.go(161)
    f.die()
    ground.data.entries, ground.data.stackSize = { logs, f.bone() }, 2
    f.emit("ObjStackEntityChanged", { objStackEntity = ground.entity, objType = config.Obj.BONES, oldCount = 0, newCount = 1, isOwner = false })
    f.click(ground, { objData = { entity = ground.entity, stackIndex = 2, config = config.Obj.BONES } })
    ground.data.entries, ground.data.stackSize = { logs }, 1
    f.emit("ObjStackEntityChanged", { objStackEntity = ground.entity, objType = config.Obj.BONES, oldCount = 1, newCount = 0, isOwner = false })
    f.gain()
    f.emit("ServerLogic")
    f.go(300)
    assert(f.credit() == 1)
    f.noFatal()
    f.shutdown()
end)
test("only exact ground Take with a resolved stack index arms collection", function()
    for _, overrides in ipairs({
        { verbText = "Examine" }, { actionType = 1004 }, { actionEntryType = 1 },
        { verbText = "Prendre" }, { objData = false },
    }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        f.click(ground, overrides)
        f.remove(ground)
        f.gain()
        f.emit("ServerLogic")
        f.go(300)
        assert(f.credit() == 0)
        f.noFatal()
        f.shutdown()
    end
end)
test("unrelated slot changes in a sparse backpack and another inventory reject credit", function()
    for _, mode in ipairs({ "sparse", "bank" }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        f.click(ground)
        if mode == "bank" then f.emit("InventoryUpdated", { inv = { id = 95 }, slotsUpdated = {} }) end
        f.remove(ground)
        f.gain(mode == "sparse")
        f.emit("ServerLogic")
        f.go(300)
        assert(f.credit() == 0)
        f.noFatal()
        f.shutdown()
    end
end)
test("scene, game and backpack lifecycle events invalidate pending evidence", function()
    for _, name in ipairs({
        "WorldCreated", "WorldUpdated", "RegionCreated", "RegionUpdated",
        "GameStateChanged", "InventoryRemoved", "InventoryAdded",
    }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        f.click(ground)
        f.emit(name, { inv = config.Inv.INV, newState = GameState.GAME })
        f.remove(ground)
        f.gain()
        f.emit("ServerLogic")
        f.go(400)
        assert(f.credit() == 0)
        f.noFatal()
        f.shutdown()
    end
end)
test("teleporting or losing the local player clears pickup state", function()
    for _, mode in ipairs({ "teleport", "logout" }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        f.click(ground)
        if mode == "teleport" then f.localData.coordGrid.x = 200 else f.unavailable = true end
        f.remove(ground)
        f.gain()
        f.emit("ServerLogic")
        f.go(400)
        assert(f.credit() == 0)
        f.noFatal()
        f.shutdown()
    end
end)
test("invalid unknown removal fails closed without dereferencing the proxy", function()
    local f = fixture()
    f.go(161)
    local entity, invalidate = proxy({})
    invalidate()
    f.emit("PlayerEntityRemoved", { playerEntity = entity })
    f.go(162)
    f.emit("ObjStackEntityRemoved", { objStackEntity = entity, objType = config.Obj.BONES, count = 1, isOwner = false })
    assert(f.credit() == 0)
    f.noFatal()
    f.shutdown()
end)
test("missing inventory and API read errors stop counting rather than defaulting to zero", function()
    for _, mode in ipairs({ "unavailable", "error" }) do
        local f = fixture()
        f.go(161)
        f.die()
        local ground = f.ground({ f.bone() }, true)
        if mode == "unavailable" then f.noInventory = true else f.badSlots = true end
        f.collect(ground)
        f.go(300)
        assert(f.credit() == 0)
        if mode == "error" then
            assert(table.concat(f.logs):match("Monitoring stopped"))
            local widget = f.show()
            assert(widget.texts[3].content:match("Monitoring stopped"))
        else f.noFatal() end
        f.shutdown()
    end
end)
test("tracked-name editing validates before reset, synchronizes views and persists", function()
    local f = fixture({ names = {} })
    f.go(161)
    local settings = f.show()
    local content = f.show("ContentLayerReady")
    settings.field.text = "Alice,*"
    settings.buttons["Save tracked names"].click()
    assert(#PersistentDB.data.names == 0)
    settings.field.text = " ALIce "
    settings.buttons["Save tracked names"].click()
    assert(PersistentDB.data.names[1] == "ALIce")
    assert(content.field.text == "ALIce")
    f.go(400)
    f.die()
    f.collect(f.ground({ f.bone() }, true))
    f.go(540)
    f.emit("Draw")
    assert(f.credit() == 1)
    assert(content.texts[#content.texts].content == "ALIce: 1")
    f.noFatal()
    f.shutdown()
end)
test("write failure is shown and retry saves the inferred count", function()
    local f = fixture()
    local widget = f.show()
    f.go(161)
    f.failSave = true
    f.die()
    f.collect(f.ground({ f.bone() }, true))
    f.go(300)
    f.emit("Draw")
    assert(f.credit() == 0)
    assert(widget.texts[3].content:match("NOT SAVED"))
    assert(widget.texts[#widget.texts].content == "Alice: 1")
    f.failSave = false
    widget.buttons["Retry save"].click()
    f.emit("Draw")
    assert(f.credit() == 1 and not widget.texts[3].content:match("NOT SAVED"))
    f.noFatal()
    f.shutdown()
end)
test("diagnostics are opt-in, ordered, and do not include display names", function()
    local f = fixture()
    f.go(161)
    assert(not table.concat(f.logs):match("tick="))
    local widget = f.show()
    widget.buttons["Diagnostics (this session)"].click(nil, true)
    f.die()
    f.collect(f.ground({ f.bone() }, true))
    f.go(300)
    local logs = table.concat(f.logs, "\n")
    for _, marker in ipairs({ "#1 ", "tick=", "packet=", "player_removed", "ground_added", "menu",
        "ground_removed", "inventory", "server_boundary", "collection_evidence", "count" }) do
        assert(logs:find(marker, 1, true), marker)
    end
    assert(not logs:match("Alice"))
    f.noFatal()
    f.shutdown()
end)
test("view resizing, invalid UI roots, stale callbacks and shutdown are safe", function()
    local f = fixture()
    local widget, _, parent = f.show()
    parent.width = 420
    f.emit("Draw")
    assert(widget.width == 420)
    widget.invalidate()
    f.emit("Draw")
    assert(widget.destroyed)
    widget.buttons["Save tracked names"].click()
    f.show()
    f.shutdown()
    for _, event in pairs(Event) do assert(next(event.callbacks) == nil) end
    for _, panel in ipairs(f.widgets) do assert(panel.destroyed) end
    f.noFatal()
end)
return passed
