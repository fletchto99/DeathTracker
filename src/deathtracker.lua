local Capture = require("src/group_capture")
local Tracker = {}

local function own(widget)
    local root = widget.root
    return { widget = widget, root = root, ids = { root.interfaceID, root.staticID, root.categoryID, root.dynamicID } }
end

local function live(owner)
    return owner and ui.Interfaces:GetComponent(table.unpack(owner.ids)) == owner.root
end

function Tracker.start()
    assert(type(prettyui) == "table" and type(prettyui.Window) == "table"
        and type(prettyui.Window.AddTextField) == "function" and type(prettyui.SimpleButton) == "table"
        and type(prettyui.SimpleView) == "table", "Death Tracker requires PrettyUI Window/TextField, SimpleButton and SimpleView.")
    local capture = Capture.new()
    local tick, lastPoll, inGame, stopped, failure = 0, -10, true, false, nil
    local panels, launcher, snapshot = {}, nil, nil
    local events = {}

    local function destroy(kind)
        local panel = panels[kind]
        panels[kind] = nil
        if panel then panel.widget:Destroy() end
    end

    local function destroyUI()
        for kind in pairs(panels) do destroy(kind) end
        if launcher then launcher.widget:Destroy(); launcher = nil end
        if snapshot then snapshot.widget:Destroy(); snapshot = nil end
    end

    local function readContext()
        if not inGame then return nil, "Waiting for an active game." end
        return Capture.context()
    end

    local function status()
        return (failure and ("Monitoring error: " .. failure) or capture.status)
            .. "\nYour Death Count: unavailable (validation mode)"
            .. "\nFriend death counts: unavailable (validation mode)"
    end

    local function guarded(action)
        return function(...)
            if stopped then return end
            local ok, err = pcall(action, ...)
            if not ok then
                local previous = failure
                failure = tostring(err)
                capture:reset("Monitoring error; capture disabled.")
                if previous ~= failure then print("[Death Tracker] " .. failure) end
            end
        end
    end

    local function snapshotText()
        return capture.result or "No eligible candidate captured. This build records no death counts."
    end

    local function showSnapshot(parent)
        if snapshot and not live(snapshot) then snapshot.widget:Destroy(); snapshot = nil end
        if not snapshot then
            snapshot = own(prettyui.Window.new(parent, {
                title = "Death Tracker capture", x = 200, y = 110, width = 620, height = 440,
                minWidth = 440, minHeight = 300, resizable = true,
            }))
            local owner = snapshot
            owner.widget:AddText({ text = "Local, name-redacted capture only. Click the field, Ctrl+A, Ctrl+C.\n"
                .. "No unrelated chat is stored; no death counter is enabled.", height = 60, maxLines = 3 })
            owner.field = owner.widget:AddTextField({ text = snapshotText(), height = 260, maxLength = 4000 })
            owner.widget:AddSimpleButton("Refresh capture", guarded(function()
                if snapshot == owner and live(owner) then owner.field:SetText(snapshotText(), false) end
            end))
        end
        snapshot.field:SetText(snapshotText(), false)
        snapshot.lastResult = capture.result
        snapshot.widget:Show()
    end

    local function populate(kind, owner)
        panels[kind] = owner
        local widget = owner.widget
        widget:AddTitle("Death Tracker")
        widget:AddText({ text = "VALIDATION MODE - automatic counting is not enabled.\n"
            .. "Friends in your visible group only; your own group notice is the exception.\n"
            .. "Keep the Friends and Group rosters open during capture.", height = 88, maxLines = 4 })
        owner.status = widget:AddText({ text = status(), height = 120, maxLines = 5 })
        widget:AddSimpleButton("Capture one group death notice", guarded(function()
            if panels[kind] ~= owner or not live(owner) then return end
            local context, problem, identity = readContext()
            failure = nil
            capture:arm(context, problem, identity, tick)
        end))
        widget:AddSimpleButton("Stop capture", guarded(function()
            if panels[kind] == owner and live(owner) then
                capture.armed = false
                capture.status = "Capture stopped; no death counts were recorded."
            end
        end))
        widget:AddSimpleButton("Show captured notice", guarded(function()
            if panels[kind] ~= owner or not live(owner) then return end
            local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
            assert(parent, "Open the capture while logged into the game.")
            showSnapshot(parent)
        end))
    end

    local function showCounts(parent)
        if panels.window and not live(panels.window) then destroy("window") end
        if not panels.window then
            populate("window", own(prettyui.Window.new(parent, {
                title = "Death Tracker", x = 180, y = 90, width = 520, height = 480,
                minWidth = 440, minHeight = 320, resizable = true,
            })))
        end
        panels.window.widget:Show()
    end

    local function subscribe(name, callback)
        local event = assert(Event[name], "Death Tracker: missing native event " .. name)
        event.Subscribe("deathtracker", guarded(callback))
        events[#events + 1] = event
    end

    subscribe("Logic", function(event)
        tick = event.logicTick
        capture:advance(tick)
        if tick - lastPoll < 10 then return end
        lastPoll = tick
        local context, problem, identity = readContext()
        capture:observe(context, problem, identity)
        if not Plugin.HasPermission(PluginPermissions.chatAccess) or not Plugin.HasPermission(PluginPermissions.trackingAccess)
            or not Player.IsAvailable() then
            capture.result = nil
            if snapshot and live(snapshot) then snapshot.field:SetText(snapshotText(), false) end
        end
    end)
    subscribe("ChatMessage", function(event)
        if not capture.armed then return end
        local context, problem, identity = readContext()
        capture:message(event, context, problem, identity, tick)
    end)
    subscribe("OptionalPermissionChanged", function(event)
        if event.permissionName == "chatAccess" or event.permissionName == "trackingAccess" then
            capture:reset("Permission changed; arm a new capture after permissions are available.")
            if snapshot and live(snapshot) then snapshot.field:SetText(snapshotText(), false) end
        end
    end)
    subscribe("GameStateChanged", function(event)
        inGame = event.newState == GameState.GAME
        capture:reset("Game state changed; arm a new capture.")
        if not inGame then destroyUI() end
    end)
    for _, name in ipairs({ "WorldCreated", "WorldUpdated", "RegionCreated", "RegionUpdated" }) do
        subscribe(name, function() capture:reset("Scene changed; capture cleared.") end)
    end
    for _, kind in ipairs({ "settings", "content" }) do
        subscribe(kind == "settings" and "SettingsLayerReady" or "ContentLayerReady", function(event)
            destroy(kind)
            local owner = own(prettyui.SimpleView.new(event.component, { width = event.component.width, height = event.component.height }))
            owner.parent = { event.component.interfaceID, event.component.staticID, event.component.categoryID, event.component.dynamicID }
            owner.width, owner.height = event.component.width, event.component.height
            populate(kind, owner)
        end)
    end
    subscribe("Draw", function()
        if not inGame or not Player.IsAvailable() then destroyUI(); return end
        if launcher and not live(launcher) then destroyUI() end
        if not launcher then
            local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
            if parent then
                local owner
                owner = own(prettyui.SimpleButton.new(parent, "Death Tracker", guarded(function()
                    if launcher == owner and live(owner) then showCounts(parent) end
                end), { x = 20, y = 90, width = 150, height = 30 }))
                launcher = owner
            end
        end
        for kind, panel in pairs(panels) do
            if not live(panel) then destroy(kind)
            else
                local parent = panel.parent and ui.Interfaces:GetComponent(table.unpack(panel.parent))
                if parent and (parent.width ~= panel.width or parent.height ~= panel.height) then
                    panel.width, panel.height = parent.width, parent.height
                    panel.widget:SetSize(parent.width, parent.height)
                end
                local current = status()
                if panel.lastStatus ~= current then panel.status.content, panel.lastStatus = current, current end
            end
        end
        if snapshot and not live(snapshot) then snapshot.widget:Destroy(); snapshot = nil end
        if snapshot and snapshot.lastResult ~= capture.result then
            snapshot.field:SetText(snapshotText(), false)
            snapshot.lastResult = capture.result
        end
    end)

    print("[Death Tracker] Validation build: counting disabled; group-death notification verification required.")
    return function()
        stopped = true
        for _, event in ipairs(events) do event.Unsubscribe("deathtracker") end
        capture:reset("Shutdown")
        destroyUI()
    end
end

return Tracker
