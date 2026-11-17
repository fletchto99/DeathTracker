local Deaths = require("src/deaths")
local Names = require("src/names")
local Tracker = {}

local function own(component)
    assert(component, "Death Tracker: native UI component creation failed.")
    return {
        reference = component, componentType = component.type,
        ids = { component.interfaceID, component.staticID, component.categoryID, component.dynamicID },
    }
end

local function resolve(handle)
    if not handle then return nil end
    local component = ui.Interfaces:GetComponent(table.unpack(handle.ids))
    if component == handle.reference and component.type == handle.componentType then return component end
end

local function setText(handle, value)
    local component = resolve(handle)
    if not component then return false end
    component.content = value
    return true
end

function Tracker.start()
    local deaths = Deaths.new(PersistentDB)
    local panels, events = {}, {}
    local sessionOpen, stopped, granted, failure = true, false, false, nil
    local characterKey, characterName, identityError, lastNotice, lastError
    local identityDetail = "Identity: local player data has not been read yet."
    local lastPoll = -10

    local function report(message)
        if message and message ~= lastError then print("[Death Tracker] " .. message) end
        lastError = message
    end

    local function refreshIdentity()
        if not sessionOpen then identityDetail = "Identity: session ended."; return end
        identityError = nil
        local cached = characterKey and "Using the known session character." or "No session character has been resolved."
        if not Player.IsAvailable() then
            identityDetail = "Identity: player available=false. " .. cached
            return
        end
        local entity = PlayerList.Self()
        if not entity then identityDetail = "Identity: player available=true; entity=nil. " .. cached; return end
        if not entity.isValid then
            identityDetail = "Identity: player available=true; entity valid=false; name not read. " .. cached
            return
        end
        local rawName = entity.displayName
        local key, display, reason = Names.nameKey(rawName)
        identityDetail = "Identity: player available=true; entity valid=true; name type=" .. type(rawName)
            .. (type(rawName) == "string" and ("; bytes=" .. #rawName) or "") .. "."
        if not key then
            characterKey, characterName = nil, nil
            identityError = "Local player is loaded, but its name could not be normalized. Counting is suspended."
            identityDetail = identityDetail .. " Name rejected: " .. reason .. "."
            return
        end
        identityDetail = identityDetail .. " Normalization succeeded."
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
        elseif not characterKey then current = "Waiting for usable local-player name data."
        else current = "Monitoring your exact self-death game notification." end
        if deaths.saveError then current = deaths.saveError .. "<br>" .. current end
        if lastNotice then current = current .. "<br>" .. lastNotice end
        if identityDetail then current = current .. "<br>" .. identityDetail end
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
        if not owner then return end
        -- Native parent removal already disposes its children. Never invoke
        -- methods on cached proxies after GetComponent stops returning them.
        local root = resolve(owner.root)
        if root then
            local retry = resolve(owner.retry)
            if retry then retry:Unsubscribe(ui.Hook.ONBUTTONPRESSED, "deathtracker.retry") end
            root = resolve(owner.root)
            if root then root:Destroy() end
        end
    end

    local function destroyUI()
        for kind in pairs(panels) do destroy(kind) end
    end

    local function populate(kind, parent)
        local root = assert(ui.Layer.new(parent, 0), "Death Tracker: native panel creation failed.")
        local owner = { root = own(root) }
        panels[kind] = owner
        root:SetSize(0, 0, 1.0, 1.0)
        root.clickthrough = false
        local function text(y, height, maxLines, content, heightAnchor, yAnchor)
            local label = assert(ui.Text.new(root), "Death Tracker: native text creation failed.")
            label:SetPos(12, y, 0, yAnchor or 0)
            label:SetSize(-24, height, 1.0, heightAnchor or 0)
            label.font = id.Font.MUSEO_SANS_15PT_REGULAR
            label.maxLines, label.content, label.clickthrough = maxLines, content, true
            return own(label)
        end
        owner.count = text(12, 32, 1, "")
        owner.character = text(48, 24, 1, "")
        owner.status = text(80, -160, 0, status(), 1.0)
        owner.note = text(-72, 24, 1, "Self-only test; friends-only group tracking is planned next.", 0, 1.0)
        local retry = assert(ui.Button.new(root), "Death Tracker: native retry button creation failed.")
        owner.retry = own(retry)
        retry:SetPos(12, -40, 0, 1.0)
        retry:SetSize(120, 28)
        retry.stylesheetID, retry.label = id.StyleSheet.BUTTON_DEFAULT, "Retry save"
        retry:Subscribe(ui.Hook.ONBUTTONPRESSED, "deathtracker.retry", guarded(function(button)
            if panels[kind] ~= owner or not resolve(owner.root) or resolve(owner.retry) ~= button then return end
            local saved, err = deaths:save()
            lastNotice = saved and "Death counts saved." or err
            report(err)
        end))
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
            identityDetail = "Identity: session ended."
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
            populate(kind, event.component)
        end)
    end
    subscribe("Draw", function()
        if not sessionOpen then destroyUI(); return end
        for kind, panel in pairs(panels) do
            if not resolve(panel.root) or not resolve(panel.count) or not resolve(panel.character) or not resolve(panel.status) then
                destroy(kind)
            else
                local count = deaths:count(characterKey)
                local countText = "Your Death Count: " .. (count ~= nil and tostring(count) or "unavailable")
                local current = status()
                local name = characterName and ("Character: " .. characterName) or "Character: name unavailable (see status)"
                if (panel.lastStatus == current or setText(panel.status, current))
                    and (panel.lastCount == countText or setText(panel.count, countText))
                    and (panel.lastCharacter == name or setText(panel.character, name)) then
                    panel.lastStatus, panel.lastCount, panel.lastCharacter = current, countText, name
                else
                    destroy(kind)
                end
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
