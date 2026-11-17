local Capture = require("src/group_capture")
local passed, originalPrint = 0, print
local function test(name, callback)
    local ok, err = pcall(callback)
    print = originalPrint
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function fixture()
    local f = {
        permissions = { chatAccess = true, trackingAccess = true }, character = "character-A",
        selfName = "Me", friends = { "Alice" }, group = { "Me", "Alice", "Bob" },
        friendVisible = true, groupVisible = true, messages = {}, widgets = {}, buttons = {}, components = {}, nextID = 0,
    }
    print = function(message) f.messages[#f.messages + 1] = message end
    Plugin = { HasPermission = function(permission) return f.permissions[permission] == true end }
    Player = {
        IsAvailable = function() return not f.unavailable end,
        GetTrackingID = function() return f.character end,
    }
    PlayerList = { Self = function() return { isValid = not f.invalidSelf, displayName = f.selfName } end }
    ChatType = { GENERAL = 0, ENGINE = 4, GROUPCHAT_NOTIFICATION = 128, GROUP_IRONMAN_NOTIFICATION = 144 }
    GameState = { GAME = 30 }
    id = { Component = {
        FRIENDS2__FRIEND_NAME_LAYER = 36044807, GROUP_CHILD__BUILD_AREA = 99549187,
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = 9999,
    } }
    local friendsRoot = { visibleGlobal = true, IterateDynamicComponents = function(_, callback)
        for index, name in ipairs(f.friends) do
            if callback({ visibleGlobal = true, content = name, dynamicID = index, categoryID = 0 }, true) then break end
        end
    end }
    local groupRoot = { visibleGlobal = true, IterateDynamicComponents = function(_, callback)
        callback({ visibleGlobal = true, content = "Me's group", dynamicID = 0, categoryID = 0 }, true)
        for index, name in ipairs(f.group) do
            if callback({ visibleGlobal = true, content = name, dynamicID = 1 + (index - 1) * 23, categoryID = 0 }, true) then break end
            callback({ visibleGlobal = true, content = "Bob", dynamicID = 2 + (index - 1) * 23, categoryID = 0 }, true)
        end
    end }
    function f.component(width, height)
        f.nextID = f.nextID + 1
        local root = { interfaceID = 1, staticID = f.nextID, categoryID = 0, dynamicID = 0, width = width, height = height }
        f.components[f.nextID] = root
        return root
    end
    f.parent = f.component(1000, 800)
    ui = { Interfaces = { GetComponent = function(_, interfaceID, staticID)
        if staticID then return f.components[staticID] end
        if interfaceID == id.Component.FRIENDS2__FRIEND_NAME_LAYER then
            if f.missingFriends then return nil end
            friendsRoot.visibleGlobal = f.friendVisible
            return friendsRoot
        elseif interfaceID == id.Component.GROUP_CHILD__BUILD_AREA then
            groupRoot.visibleGlobal = f.groupVisible
            return groupRoot
        elseif interfaceID == id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP then
            return f.parent
        end
        error("unexpected component")
    end } }
    function f.notice(overrides)
        local event = { chatType = 128, timestamp = 1000, chatMessage = "Player Alice has died.",
            senderNameUnfiltered = "", senderNameFiltered = "", senderNameSimple = "" }
        for key, value in pairs(overrides or {}) do event[key] = value end
        return event
    end
    function f.context() return Capture.context() end
    function f.arm(capture, tick)
        local context, err, identity = f.context()
        return capture:arm(context, err, identity, tick or 100)
    end
    function f.deliver(capture, event, tick)
        local context, err, identity = f.context()
        return capture:message(event or f.notice(), context, err, identity, tick or 110)
    end
    return f
end

test("exact supplied example captures metadata only with visible friend and group observations", function()
    local f, capture = fixture(), Capture.new()
    assert(f.arm(capture))
    assert(f.deliver(capture))
    assert(capture.result:match("chatType=128") and capture.result:match("subject=friend"))
    assert(capture.result:find("redactedRaw=Player [player] has died.", 1, true))
    assert(not capture.result:match("Alice") and not capture.result:match("character%-A"))
    assert(capture.status:match("NOT authenticated or counted"))
end)
test("ordinary public private friends and group chat never becomes a captured death", function()
    local f = fixture()
    for _, chatType in ipairs({ 1, 2, 3, 5, 6, 7, 9, 17, 18, 19, 20, 22, 23, 24, 25, 33, 41, 43, 44, 99 }) do
        local capture = Capture.new()
        assert(f.arm(capture))
        assert(not f.deliver(capture, f.notice({ chatType = chatType })))
        assert(capture.result == nil and capture.armed)
    end
end)
test("attributed senders or missing sender metadata are not treated as system messages", function()
    local f = fixture()
    for _, field in ipairs({ "senderNameUnfiltered", "senderNameFiltered", "senderNameSimple" }) do
        for _, missing in ipairs({ false, true }) do
            local capture, event = Capture.new(), f.notice()
            assert(f.arm(capture))
            event[field] = missing and nil or "Player"
            if missing then event[field] = nil end
            assert(not f.deliver(capture, event) and capture.result == nil)
        end
    end
end)
test("non-friend group members and non-group friends are excluded without logging their chat", function()
    local f, capture = fixture(), Capture.new()
    assert(f.arm(capture))
    assert(not f.deliver(capture, f.notice({ chatMessage = "Player Bob has died." })))
    assert(capture.result == nil)
    f.friends = { "Alice", "Charlie" }
    assert(f.arm(capture))
    assert(not f.deliver(capture, f.notice({ chatMessage = "Player Charlie has died." })))
    assert(capture.result == nil and #f.messages == 0)
end)
test("own grouped notice is explicitly separate from the friends filter", function()
    local f, capture = fixture(), Capture.new()
    f.friends = {}
    assert(f.arm(capture))
    assert(f.deliver(capture, f.notice({ chatMessage = "Player Me has died" })))
    assert(capture.result:match("subject=local character") and capture.result:match("friendRowObserved=false"))
end)
test("duplicate events cannot append a second result to a one-shot capture", function()
    local f, capture = fixture(), Capture.new()
    assert(f.arm(capture) and f.deliver(capture))
    local result = capture.result
    for _ = 1, 5 do assert(not f.deliver(capture)) end
    assert(capture.result == result)
end)
test("unrelated text, unknown templates and invalid timestamps are not stored", function()
    local f = fixture()
    for _, message in ipairs({ "hello", "Someone said Player Alice has died.", "Player Alice has died. Again.",
        "Alice has died.", "Oh dear, you are dead!", "Player Alice has died.\nsecret", "Player AReallyLongName has died.",
        "Player <unknown>Alice</unknown> has died." }) do
        local capture = Capture.new()
        assert(f.arm(capture))
        assert(not f.deliver(capture, f.notice({ chatMessage = message })))
        assert(capture.result == nil and #f.messages == 0)
    end
    local capture = Capture.new()
    assert(f.arm(capture))
    assert(not f.deliver(capture, f.notice({ timestamp = 0 })))
end)
test("redaction preserves supported formatting without retaining parts of the name", function()
    local f, capture = fixture(), Capture.new()
    assert(f.arm(capture))
    assert(f.deliver(capture, f.notice({ chatMessage = "<col=ff0000>Player <shad=00ff00>Al</shad>ice has died.</col>" })))
    assert(capture.result:find("<col=ff0000>Player <shad=00ff00>[player]</shad> has died.</col>", 1, true))
    assert(not capture.result:match("Alice") and not capture.result:match(">Al<"))
end)
test("permissions and missing identity prevent capture and clear earlier results", function()
    for _, mode in ipairs({ "chatAccess", "trackingAccess", "identity", "local" }) do
        local f, capture = fixture(), Capture.new()
        assert(f.arm(capture) and f.deliver(capture))
        if mode == "identity" then f.character = nil
        elseif mode == "local" then f.unavailable = true
        else f.permissions[mode] = false end
        local context, problem, identity = f.context()
        capture:observe(context, problem, identity)
        assert(not capture.armed and capture.result == nil and not f.arm(capture))
        assert(type(capture.status) == "string")
    end
end)
test("closed missing or changed rosters never use cached membership", function()
    for _, mode in ipairs({ "closed-friends", "missing-friends", "closed-group", "removed-friend", "left-group" }) do
        local f, capture = fixture(), Capture.new()
        assert(f.arm(capture))
        if mode == "closed-friends" then f.friendVisible = false
        elseif mode == "missing-friends" then f.missingFriends = true
        elseif mode == "closed-group" then f.groupVisible = false
        elseif mode == "removed-friend" then f.friends = {}
        else f.group = { "Me" } end
        assert(not f.deliver(capture) and capture.result == nil and not capture.armed)
    end
end)
test("character changes and scene invalidation cancel transient capture", function()
    local f, capture = fixture(), Capture.new()
    assert(f.arm(capture) and f.deliver(capture))
    f.character = "character-B"
    local context, problem, identity = f.context()
    capture:observe(context, problem, identity)
    assert(capture.result == nil and not capture.armed)
    assert(f.arm(capture))
    capture:reset("world changed")
    assert(not f.deliver(capture) and capture.result == nil)
end)
test("capture expires and no fabricated roster rows grant membership", function()
    local f, capture = fixture(), Capture.new()
    f.group = { "Me", "Alice" }
    f.friends = { "Bob" }
    assert(f.arm(capture))
    assert(not f.deliver(capture, f.notice({ chatMessage = "Player Bob has died." })))
    capture:advance(3101)
    assert(not capture.armed and capture.status:match("timed out"))
    capture:observe(f.context())
    assert(capture.status:match("timed out"))
end)

local function appFixture()
    local f = fixture()
    f.database = { state = { version = 2, counts = { alice = 99 }, displayNames = { alice = "Alice" } } }
    PersistentDB = setmetatable({}, { __index = function() error("validation build must not read or write saved counters") end })
    Event = {}
    for _, name in ipairs({ "Logic", "ChatMessage", "OptionalPermissionChanged", "GameStateChanged", "WorldCreated",
        "WorldUpdated", "RegionCreated", "RegionUpdated", "SettingsLayerReady", "ContentLayerReady", "Draw" }) do
        local callbacks = {}
        Event[name] = { callbacks = callbacks,
            Subscribe = function(ref, callback) callbacks[ref] = callback end,
            Unsubscribe = function(ref) callbacks[ref] = nil end }
    end
    function f.emit(name, event) for _, callback in pairs(Event[name].callbacks) do callback(event) end end
    local Widget = {}
    function Widget:AddTitle(text) self.title = text end
    function Widget:AddText(options)
        local text = { content = options.text }
        self.texts[#self.texts + 1] = text
        return text
    end
    function Widget:AddTextField(options)
        self.field = { text = options.text, SetText = function(self, text, notify) assert(not notify); self.text = text end }
        return self.field
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
        Window = { new = newWidget, AddTextField = Widget.AddTextField }, SimpleView = { new = newWidget },
        SimpleButton = { new = function(parent, label, action, options)
            local button = newWidget(parent, options)
            button.label, button.click = label, action
            f.buttons[#f.buttons + 1] = button
            return button
        end },
    }
    -- Execute the real entrypoint: the legacy bone app must not subscribe.
    dofile("main.lua")
    assert(Event.ChatMessage.callbacks.deathtracker, "entrypoint must use the deathtracker identifier")
    f.shutdown = PluginShutdown
    f.emit("Logic", { logicTick = 100 })
    f.emit("Draw")
    f.buttons[1].click()
    f.panel = f.widgets[#f.widgets]
    return f
end
test("active Death Tracker entrypoint has an opener and honestly unavailable distinct counters", function()
    local f = appFixture()
    assert(f.buttons[1].label == "Death Tracker" and f.panel.title == "Death Tracker")
    assert(f.panel.texts[2].content:match("Your Death Count: unavailable"))
    assert(f.panel.texts[2].content:match("Friend death counts: unavailable"))
    assert(f.panel.buttons["Capture one group death notice"] and not f.panel.buttons["Retry save"])
    assert(f.database.state.counts.alice == 99)
    f.shutdown()
    for _, event in pairs(Event) do assert(next(event.callbacks) == nil) end
    for _, widget in ipairs(f.widgets) do assert(widget.destroyed) end
end)
test("one eligible candidate is inspectable but never increments or imports legacy counters", function()
    local f = appFixture()
    f.panel.buttons["Capture one group death notice"]()
    f.emit("ChatMessage", f.notice())
    f.emit("ChatMessage", f.notice())
    f.panel.buttons["Show captured notice"]()
    local snapshot = f.widgets[#f.widgets]
    assert(snapshot.field.text:match("NOT a counted death") and not snapshot.field.text:match("Alice"))
    assert(f.database.state.counts.alice == 99)
    f.emit("Draw")
    assert(f.panel.texts[2].content:match("unavailable"))
    f.shutdown()
end)
test("permission revocation and character changes clear displayed captures", function()
    for _, mode in ipairs({ "permission", "character" }) do
        local f = appFixture()
        f.panel.buttons["Capture one group death notice"]()
        f.emit("ChatMessage", f.notice())
        f.panel.buttons["Show captured notice"]()
        local snapshot = f.widgets[#f.widgets]
        if mode == "permission" then
            f.permissions.chatAccess = false
            f.emit("OptionalPermissionChanged", { permissionName = "chatAccess", enabled = false })
        else f.character = "character-B" end
        f.emit("Logic", { logicTick = 120 })
        f.emit("Draw")
        assert(snapshot.field.text:match("No eligible candidate"))
        f.emit("ChatMessage", f.notice())
        assert(snapshot.field.text:match("No eligible candidate") and f.database.state.counts.alice == 99)
        f.shutdown()
    end
end)
test("group and scene loss disable capture; no unavailable-membership fallback is possible", function()
    for _, mode in ipairs({ "friends", "world", "logout" }) do
        local f = appFixture()
        f.panel.buttons["Capture one group death notice"]()
        if mode == "friends" then f.friendVisible = false
        elseif mode == "world" then f.emit("WorldCreated")
        else f.emit("GameStateChanged", { newState = 20 }) end
        f.emit("ChatMessage", f.notice())
        f.emit("Logic", { logicTick = 120 })
        f.emit("Draw")
        if mode == "friends" then assert(f.panel.texts[2].content:match("Friend capture suspended")) end
        assert(f.database.state.counts.alice == 99)
        f.shutdown()
    end
end)
test("native roster errors are visible, stop capture and preserve old storage", function()
    local f = appFixture()
    f.panel.buttons["Capture one group death notice"]()
    local get = ui.Interfaces.GetComponent
    ui.Interfaces.GetComponent = function(self, componentID, ...)
        if componentID == id.Component.FRIENDS2__FRIEND_NAME_LAYER then error("native roster unavailable") end
        return get(self, componentID, ...)
    end
    f.emit("ChatMessage", f.notice())
    f.emit("Logic", { logicTick = 120 })
    f.emit("Draw")
    assert(f.panel.texts[2].content:match("Monitoring error") and f.panel.texts[2].content:match("native roster unavailable"))
    assert(f.database.state.counts.alice == 99)
    f.shutdown()
end)
test("settings resizing and stale UI callbacks cannot rearm after shutdown", function()
    local f = appFixture()
    local parent = f.component(450, 600)
    f.emit("SettingsLayerReady", { component = parent })
    local settings = f.widgets[#f.widgets]
    parent.width = 480
    f.emit("Draw")
    assert(settings.root.width == 480)
    f.shutdown()
    settings.buttons["Capture one group death notice"]()
    f.buttons[1].click()
    for _, event in pairs(Event) do assert(next(event.callbacks) == nil) end
    assert(f.database.state.counts.alice == 99)
end)
return passed
