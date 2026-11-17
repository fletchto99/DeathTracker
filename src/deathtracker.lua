local Deaths = require("src/deaths")
local Names = require("src/names")
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
        and type(prettyui.SimpleButton) == "table" and type(prettyui.SimpleView) == "table",
        "Death Tracker requires PrettyUI Window, SimpleButton and SimpleView.")
    local deaths = Deaths.new(PersistentDB)
    local panels, launcher, events = {}, nil, {}
    local sessionOpen, stopped, granted, failure = true, false, false, nil
    local characterKey, characterName, identityError, lastNotice, lastError
    local lastPoll = -10

    local function report(message)
        if message and message ~= lastError then print("[Death Tracker] " .. message) end
        lastError = message
    end

    local function refreshIdentity()
        if not sessionOpen or not Player.IsAvailable() then return end
        local entity = PlayerList.Self()
        if not entity or not entity.isValid then return end
        local key, display = Names.nameKey(entity.displayName)
        if not key then
            characterKey, characterName = nil, nil
            identityError = "Cannot resolve the current character's display name; counting is suspended."
            return
        end
        if key ~= characterKey then lastNotice = nil end
        characterKey, characterName, identityError = key, display, nil
    end

    local function refreshPermission()
        granted = Plugin.HasPermission(PluginPermissions.chatAccess) == true
    end

    local function status()
        local current
        if failure then current = "Monitoring stopped: " .. failure
        elseif deaths.loadError then current = deaths.loadError
        elseif not granted then current = "Disabled: chatAccess permission is denied or revoked."
        elseif identityError then current = identityError
        elseif not characterKey then current = "Waiting to observe your logged-in character."
        else current = "Monitoring your exact self-death game notification." end
        if deaths.saveError then current = deaths.saveError .. "\n" .. current end
        if lastNotice then current = current .. "\n" .. lastNotice end
        return current
    end

    local function guarded(action)
        return function(...)
            if stopped then return end
            local ok, err = pcall(action, ...)
            if not ok then
                failure = tostring(err)
                report(failure)
            end
        end
    end

    local function destroy(kind)
        local owner = panels[kind]
        panels[kind] = nil
        if owner then owner.widget:Destroy() end
    end

    local function destroyUI()
        for kind in pairs(panels) do destroy(kind) end
        if launcher then launcher.widget:Destroy(); launcher = nil end
    end

    local function populate(kind, owner)
        panels[kind] = owner
        local widget = owner.widget
        widget:AddTitle("Death Tracker")
        owner.count = widget:AddText({ text = "", height = 40, maxLines = 1 })
        owner.character = widget:AddText({ text = "", height = 32, maxLines = 1 })
        owner.status = widget:AddText({ text = status(), height = 160, maxLines = 7 })
        widget:AddText({ text = "Self-death test: automatic, no arming or group required.\n"
            .. "Friends-only group tracking is planned next and is not active yet.", height = 64, maxLines = 3 })
        widget:AddSimpleButton("Retry save", guarded(function()
            if panels[kind] ~= owner or not live(owner) then return end
            local saved, err = deaths:save()
            lastNotice = saved and "Death counts saved." or err
            report(err)
        end))
    end

    local function showCounts(parent)
        if panels.window and not live(panels.window) then destroy("window") end
        if not panels.window then
            populate("window", own(prettyui.Window.new(parent, {
                title = "Death Tracker", x = 180, y = 90, width = 520, height = 420,
                minWidth = 440, minHeight = 300, resizable = true,
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
        if event.logicTick - lastPoll < 5 then return end
        lastPoll = event.logicTick
        refreshPermission()
        refreshIdentity()
    end)
    subscribe("ChatMessage", function(event)
        if failure or not Deaths.matches(event) then return end
        refreshPermission()
        if not granted then return end
        refreshIdentity()
        if not sessionOpen or not characterKey then
            lastNotice = "Self-death notification skipped: no known logged-in character."
            report(lastNotice)
            return
        end
        local result, err = deaths:record(characterKey, event.timestamp)
        if result == "counted" then lastNotice = "Self-death notification counted."
        elseif result == "duplicate" then lastNotice = "Duplicate notification ignored."
        else lastNotice = err end
        report(err)
    end)
    subscribe("OptionalPermissionChanged", function(event)
        if event.permissionName == "chatAccess" then refreshPermission() end
    end)
    subscribe("GameStateChanged", function(event)
        local state = event.newState
        if state == GameState.LOGINSCREEN or state == GameState.LOBBY or state == GameState.ACCOUNT_CREATE
            or state == GameState.BOOT or state == GameState.INIT then
            sessionOpen, characterKey, characterName, identityError, lastNotice = false, nil, nil, nil, nil
            destroyUI()
        elseif state == GameState.GAME then
            sessionOpen = true
            refreshIdentity()
        end
        -- Loading/reconnection/world transitions keep a known session identity
        -- so a death notice can arrive while the local entity is unavailable.
    end)
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
        if not sessionOpen then destroyUI(); return end
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
                local count = deaths:count(characterKey)
                local countText = "Your Death Count: " .. (count ~= nil and tostring(count) or "unavailable")
                local current = status()
                if panel.lastStatus ~= current then panel.status.content, panel.lastStatus = current, current end
                if panel.lastCount ~= countText then panel.count.content, panel.lastCount = countText, countText end
                local name = characterName and ("Character: " .. characterName) or "Character: waiting for login"
                if panel.lastCharacter ~= name then panel.character.content, panel.lastCharacter = name, name end
            end
        end
    end)

    guarded(function() refreshPermission(); refreshIdentity() end)()
    report(deaths.loadError)
    print("[Death Tracker] Self-death counter loaded. Only the exact general game notification is counted.")
    return function()
        stopped = true
        for _, event in ipairs(events) do event.Unsubscribe("deathtracker") end
        destroyUI()
        if deaths.unsaved then print("[Death Tracker] WARNING: unsaved death counts may be lost on reload.") end
    end
end

return Tracker
