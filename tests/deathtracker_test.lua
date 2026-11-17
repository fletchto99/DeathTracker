local Deaths = require("src/deaths")
local passed, originalPrint = 0, print
local function test(name, callback)
    local ok, err = pcall(callback)
    print = originalPrint
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function fixture(options)
    options = options or {}
    local f = {
        data = options.data, granted = options.granted ~= false, name = options.name or "Alice", messages = {},
        widgets = {}, buttons = {}, components = {}, nextID = 0, writes = 0, tick = 0,
        failRead = options.failRead,
    }
    print = function(message) f.messages[#f.messages + 1] = message end
    -- Opaque userdata model the required native PluginPermission, not strings.
    PluginPermissions = { chatAccess = io.stdout }
    Plugin = { HasPermission = function(permission)
        assert(type(permission) == "userdata" and permission == PluginPermissions.chatAccess, "expected chatAccess permission userdata")
        return f.granted
    end }
    Player = {
        IsAvailable = function() return not f.unavailable end,
        GetTrackingID = function() error("self counting must not request a tracking ID") end,
    }
    PlayerList = { Self = function()
        if f.noEntity then return nil end
        if f.invalidEntity then return setmetatable({ isValid = false }, { __index = function() error("invalid entity access") end }) end
        return { isValid = true, displayName = f.name }
    end }
    ChatType = { GENERAL = 0 }
    GameState = { BOOT = 0, INIT = 1, LOGINSCREEN = 10, LOBBY = 20, ACCOUNT_CREATE = 23,
        GAME = 30, RECONNECTING = 35, RECONNECTING_FULL = 36, SWITCH_WORLD = 37, LOADING = 40 }
    id = { Component = { TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 9999 } }
    PersistentDB = {
        GetStructuredData = function(_, key)
            assert(key == Deaths.key)
            if f.failRead then error("read unavailable") end
            return copy(f.data)
        end,
        CheckExists = function(_, key) assert(key == Deaths.key); return f.data ~= nil end,
        SetStructuredData = function(_, key, value)
            assert(key == Deaths.key)
            f.writes = f.writes + 1
            if f.throwWrite then error("write unavailable") end
            if f.failWrite then return false end
            f.data = copy(value)
            return true
        end,
    }
    function f.component(width, height)
        f.nextID = f.nextID + 1
        local root = { interfaceID = 1, staticID = f.nextID, categoryID = 0, dynamicID = 0, width = width, height = height }
        f.components[f.nextID] = root
        return root
    end
    f.parent = f.component(1000, 800)
    ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID)
        if staticID then return f.components[staticID] end
        assert(interfaceID == id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP, "self counter must not inspect a roster")
        return f.parent
    end } }
    Event = {}
    for _, name in ipairs({ "Logic", "ChatMessage", "OptionalPermissionChanged", "GameStateChanged",
        "SettingsLayerReady", "ContentLayerReady", "Draw" }) do
        local callbacks = {}
        Event[name] = { callbacks = callbacks,
            Subscribe = function(ref, callback) callbacks[ref] = callback end,
            Unsubscribe = function(ref) callbacks[ref] = nil end }
    end
    function f.emit(name, data)
        for _, callback in pairs(Event[name].callbacks) do callback(data) end
    end
    local Widget = {}
    function Widget:AddTitle(text) self.title = text end
    function Widget:AddText(options)
        local text = { content = options.text }
        self.texts[#self.texts + 1] = text
        return text
    end
    function Widget:AddSimpleButton(label, action) self.buttons[label] = action end
    function Widget:Show() self.shown = true end
    function Widget:SetSize(width, height) self.root.width, self.root.height = width, height end
    function Widget:Destroy() f.components[self.root.staticID] = nil; self.destroyed = true end
    local function newWidget(_, options)
        local widget = setmetatable({ root = f.component(options.width, options.height), texts = {}, buttons = {} }, { __index = Widget })
        f.widgets[#f.widgets + 1] = widget
        return widget
    end
    prettyui = {
        Window = { new = newWidget }, SimpleView = { new = newWidget },
        SimpleButton = { new = function(parent, label, action, dimensions)
            local button = newWidget(parent, dimensions)
            button.label, button.click = label, action
            f.buttons[#f.buttons + 1] = button
            return button
        end },
    }
    function f.step()
        f.tick = f.tick + 5
        f.emit("Logic", { logicTick = f.tick })
        f.emit("Draw")
    end
    function f.start()
        dofile("main.lua")
        f.shutdown = PluginShutdown
        f.step()
        f.buttons[#f.buttons].click()
        f.step()
        f.panel = f.widgets[#f.widgets]
    end
    function f.reload() f.shutdown(); f.start() end
    function f.notice(overrides)
        local message = {
            chatType = 0, chatMessage = "Oh dear, you are dead!", timestamp = 1000,
            senderNameUnfiltered = "", senderNameFiltered = "", senderNameSimple = "",
        }
        for key, value in pairs(overrides or {}) do message[key] = value end
        return message
    end
    function f.death(overrides) f.emit("ChatMessage", f.notice(overrides)); f.emit("Draw") end
    function f.count(key)
        local record = f.data and f.data.characters and f.data.characters[key or "alice"]
        return record and record.count or 0
    end
    function f.noFatal()
        for _, line in ipairs(f.messages) do assert(not line:match("expected chatAccess") and not line:match("invalid entity access"), line) end
        assert(not f.panel.texts[3].content:match("Monitoring stopped"))
    end
    f.start()
    return f
end

test("exact general game notice increments automatically and persists across reload", function()
    local f = fixture()
    assert(f.panel.texts[1].content == "Your Death Count: 0" and f.buttons[1].label == "Death Tracker")
    assert(f.panel.buttons["Capture one group death notice"] == nil)
    f.death()
    assert(f.count() == 1 and f.panel.texts[1].content == "Your Death Count: 1")
    f.reload()
    assert(f.panel.texts[1].content == "Your Death Count: 1")
    f.death({ timestamp = 1001 })
    assert(f.count() == 2 and f.writes == 2)
    f.noFatal()
    f.shutdown()
end)
test("native nonbreaking-space name variants resolve to the existing character total", function()
    for _, separator in ipairs({ "\194\160", "\160", "\195\130\194\160" }) do
        local f = fixture({
            name = "Alice" .. separator .. "Smith",
            data = { version = 1, characters = { ["alice smith"] = { count = 4, recent = { 900 } } } },
        })
        assert(f.panel.texts[1].content == "Your Death Count: 4")
        assert(f.panel.texts[2].content == "Character: Alice Smith")
        assert(f.panel.texts[3].content:match("Normalization succeeded"))
        assert(f.writes == 0, "resolving a name must not create or backfill a death")
        f.death()
        f.death()
        assert(f.count("alice smith") == 5 and f.writes == 1)
        f.reload()
        assert(f.panel.texts[1].content == "Your Death Count: 5")
        f.noFatal()
        f.shutdown()
    end
end)
test("logged-in name rejection shows exact identity diagnostics and readable boundaries without backfilling", function()
    local f = fixture({ name = "<unknown>Alice</unknown>" })
    local status = f.panel.texts[3].content
    assert(status:match("Local player is loaded") and status:match("player available=true"))
    assert(status:match("entity valid=true") and status:match("name type=string"))
    assert(status:match("unsupported byte 0x3C at normalized position 1"))
    assert(not f.panel.texts[2].content:match("waiting for login"))
    assert(status:find("<br>", 1, true) and not status:find("\n", 1, true))
    f.death()
    status = f.panel.texts[3].content
    assert(status:find("<br>Self-death notification skipped", 1, true) and f.writes == 0)
    f.name = "Alice\194\160Smith"
    f.step()
    assert(f.panel.texts[1].content == "Your Death Count: 0" and f.writes == 0)
    f.death({ timestamp = 1001 })
    assert(f.count("alice smith") == 1 and f.writes == 1)
    f.shutdown()
end)
test("diagnostics distinguish unavailable entities and unavailable or malformed names", function()
    local f = fixture()
    f.noEntity = true
    f.step()
    assert(f.panel.texts[3].content:match("entity=nil") and f.panel.texts[1].content == "Your Death Count: 0")
    f.noEntity, f.invalidEntity = false, true
    f.step()
    assert(f.panel.texts[3].content:match("entity valid=false"))
    f.invalidEntity, f.name = false, nil
    f.step()
    assert(f.panel.texts[3].content:match("name type=nil") and f.panel.texts[1].content == "Your Death Count: unavailable")
    f.name = "   "
    f.step()
    assert(f.panel.texts[3].content:match("empty after whitespace normalization"))
    f.name = "AverylongnameX"
    f.step()
    assert(f.panel.texts[3].content:match("normalized name is 14 bytes"))
    f.name = "Alice"
    f.step()
    assert(f.panel.texts[1].content == "Your Death Count: 0" and f.writes == 0)
    f.shutdown()
end)
test("native colour tags normalize without accepting unrelated or loose text", function()
    local f = fixture()
    for _, text in ipairs({
        "hello", "Oh dear, you are dead", "Oh dear, you are dead! Again.",
        "Someone says Oh dear, you are dead!", "oh dear, you are dead!", " Oh dear, you are dead!",
        "<unknown>Oh dear, you are dead!</unknown>", "Oh dear, you are dead!\n",
    }) do f.death({ chatMessage = text }) end
    assert(f.count() == 0 and f.writes == 0)
    f.death({ chatMessage = "<col=ff0000>Oh dear, you are dead!</col>" })
    assert(f.count() == 1)
    f.shutdown()
end)
test("player chat and plugin-generated lookalikes cannot increment even with empty sender fields", function()
    local f = fixture()
    for _, category in ipairs({ 1, 2, 3, 4, 5, 6, 7, 9, 17, 18, 19, 20, 22, 23, 24, 25, 33,
        41, 42, 43, 44, 45, 46, 99, 115, 128, 139, 144, 145 }) do f.death({ chatType = category }) end
    assert(f.count() == 0 and f.writes == 0 and #f.messages == 1)
    f.shutdown()
end)
test("all documented sender fields must be empty and valid timestamps are required", function()
    local f = fixture()
    for _, name in ipairs({ "senderNameUnfiltered", "senderNameFiltered", "senderNameSimple" }) do
        local event = f.notice()
        event[name] = "Alice"
        f.emit("ChatMessage", event)
        event[name] = nil
        f.emit("ChatMessage", event)
    end
    assert(f.writes == 0)
    f.death({ timestamp = 0 })
    assert(f.count() == 0 and f.panel.texts[3].content:match("timestamp is invalid"))
    f.shutdown()
end)
test("duplicate evidence is ignored across lifecycle callbacks and reload without a cooldown", function()
    local f = fixture()
    f.death()
    f.death()
    f.emit("GameStateChanged", { newState = GameState.GAME })
    f.death()
    f.reload()
    f.death()
    assert(f.count() == 1 and f.writes == 1)
    f.death({ timestamp = 1001 })
    f.death({ timestamp = 1000 })
    assert(f.count() == 2 and f.writes == 2)
    for _, event in pairs(Event) do
        local subscriptions = 0
        for _ in pairs(event.callbacks) do subscriptions = subscriptions + 1 end
        assert(subscriptions == 1)
    end
    f.shutdown()
    for _, event in pairs(Event) do assert(next(event.callbacks) == nil) end
end)
test("recent duplicate history stays bounded without imposing a delay between later deaths", function()
    local f = fixture()
    for timestamp = 1000, 1040 do f.death({ timestamp = timestamp }) end
    assert(f.count() == 41 and #f.data.characters.alice.recent == Deaths.recentLimit)
    f.reload()
    f.death({ timestamp = 1040 })
    f.death({ timestamp = 1041 })
    assert(f.count() == 42)
    f.shutdown()
end)
test("death transition keeps known identity while the local entity is absent or invalid", function()
    for _, state in ipairs({ 35, 36, 37, 40 }) do
        local f = fixture()
        f.unavailable = true
        f.emit("GameStateChanged", { newState = state })
        f.death()
        assert(f.count() == 1)
        f.unavailable, f.invalidEntity = false, true
        f.death({ timestamp = 1001 })
        assert(f.count() == 2)
        f.invalidEntity, f.noEntity = false, true
        f.death({ timestamp = 1002 })
        assert(f.count() == 3)
        f.noEntity = false
        f.emit("GameStateChanged", { newState = GameState.GAME })
        f.noFatal()
        f.shutdown()
    end
end)
test("actual logout clears cached identity and characters retain separate totals", function()
    local f = fixture()
    f.death()
    f.emit("GameStateChanged", { newState = GameState.LOBBY })
    f.death({ timestamp = 1001 })
    assert(f.count() == 1)
    f.name = "Bob"
    f.emit("GameStateChanged", { newState = GameState.GAME })
    f.step()
    f.buttons[#f.buttons].click()
    f.step()
    f.panel = f.widgets[#f.widgets]
    assert(f.panel.texts[1].content == "Your Death Count: 0")
    f.death()
    assert(f.count("bob") == 1 and f.count("alice") == 1)
    f.name = "ALICE"
    f.step()
    assert(f.panel.texts[1].content == "Your Death Count: 1")
    f.death({ timestamp = 1002 })
    assert(f.count("alice") == 2 and f.count("bob") == 1)
    f.shutdown()
end)
test("missing initial identity does not attribute a death to an old or default character", function()
    local f = fixture()
    f.shutdown()
    f.unavailable = true
    f.start()
    f.death()
    assert(f.writes == 0 and f.panel.texts[1].content == "Your Death Count: unavailable")
    f.unavailable = false
    f.step()
    f.death({ timestamp = 1001 })
    assert(f.count() == 1)
    f.shutdown()
end)
test("native permission userdata handles denied startup, revocation and automatic resume after grant", function()
    local f = fixture({ granted = false })
    f.death()
    assert(f.writes == 0 and f.panel.texts[3].content:match("Disabled: chatAccess"))
    f.granted = true
    f.emit("OptionalPermissionChanged", { permissionName = "chatAccess", enabled = true })
    f.death()
    assert(f.count() == 1)
    f.granted = false
    f.emit("OptionalPermissionChanged", { permissionName = "chatAccess", enabled = false })
    f.death({ timestamp = 1001 })
    assert(f.count() == 1)
    f.granted = true
    f.death({ timestamp = 1001 })
    assert(f.count() == 2)
    f.noFatal()
    f.shutdown()
end)
test("save failures stay visible and retry persists the in-memory count and duplicate history", function()
    for _, throws in ipairs({ false, true }) do
        local f = fixture()
        f.failWrite, f.throwWrite = true, throws
        f.death()
        assert(f.data == nil and f.panel.texts[1].content == "Your Death Count: 1")
        assert(f.panel.texts[3].content:match("NOT SAVED"))
        f.death()
        assert(f.writes == 1)
        f.failWrite, f.throwWrite = false, false
        f.panel.buttons["Retry save"]()
        f.emit("Draw")
        assert(f.count() == 1 and not f.panel.texts[3].content:match("NOT SAVED"))
        f.reload()
        f.death()
        assert(f.count() == 1)
        f.shutdown()
    end
end)
test("invalid or unreadable storage visibly disables counting without overwriting data", function()
    for _, options in ipairs({
        { data = "invalid" },
        { data = { version = 99, characters = {} } },
        { data = { version = 1, characters = { alice = { count = -1, recent = {} } } } },
        { data = { version = 1, characters = { alice = { count = 0, recent = { 1000 } } } } },
        { failRead = true },
    }) do
        local f = fixture(options)
        f.death()
        assert(f.writes == 0 and f.panel.texts[1].content == "Your Death Count: unavailable")
        assert(f.panel.texts[3].content:match("Cannot load death counts"))
        f.panel.buttons["Retry save"]()
        assert(f.writes == 0)
        f.shutdown()
    end
end)
test("opener, settings resizing, stale callbacks and shutdown preserve single-subscription behavior", function()
    local f = fixture()
    local window = f.panel
    f.buttons[1].click()
    assert(f.widgets[#f.widgets] == window)
    local parent = f.component(450, 600)
    f.emit("SettingsLayerReady", { component = parent })
    local settings = f.widgets[#f.widgets]
    parent.width = 480
    f.step()
    assert(settings.root.width == 480)
    f.death()
    assert(settings.texts[1].content == "Your Death Count: 1")
    f.shutdown()
    settings.buttons["Retry save"]()
    f.buttons[1].click()
    for _, widget in ipairs(f.widgets) do assert(widget.destroyed) end
    for _, event in pairs(Event) do assert(next(event.callbacks) == nil) end
end)
return passed
