local Store = require("src/store")
local Matcher = require("src/matcher")
local View = require("src/view")
local LootProbe = require("src/loot_probe")
local Diagnostics = require("src/diagnostics")
local App = {}

local function tile(entity)
    local coord = entity.coordGrid
    return { level = coord.level, x = coord.x, z = coord.z }
end

local function find(records, entity)
    for index, record in ipairs(records) do
        if record.entity == entity then return record, index end
    end
end

function App.start()
    local store = Store.new(PersistentDB)
    local bonesConfig = assert(config.Obj.BONES, "BoneCollector: ordinary BONES config unavailable.")
    local boneID = bonesConfig.id
    local ready, inGame, stopped, fatal, diagnostics = false, true, false, nil, false
    local players, stacks, serial = {}, {}, 0
    local selfEntity, selfTile, inventory, lastPoll = nil, nil, nil, 0
    local message, sequence = "", 0
    local matcher, view
    local diagnosticLog = Diagnostics.new()

    local function trace(kind, ...)
        if kind == "skip" then message = "Skipped: " .. tostring((...)) end
        if not diagnostics then return end
        sequence = sequence + 1
        local values = {}
        for i = 1, select("#", ...) do values[i] = tostring(select(i, ...)) end
        local line = string.format("[BoneCollector] #%d tick=%d packet=%d %s %s",
            sequence, matcher and matcher.tick or 0, matcher and matcher.packet or 0, kind, table.concat(values, " "))
        print(diagnosticLog:append(line))
    end

    matcher = Matcher.new(function(name, display)
        if store:increment(name, display) then
            message = "Inferred collection recorded."
        else
            message = "Collection recorded in memory, but NOT saved. Use Retry save."
            print("[BoneCollector] " .. message)
        end
    end, trace)
    local lootProbe = LootProbe.new(trace)

    local function restart(reason)
        lootProbe:clear()
        ready, players, stacks, selfEntity, selfTile, inventory = false, {}, {}, nil, nil, nil
        matcher:reset(reason)
    end

    local function nextKey(prefix)
        serial = serial + 1
        return prefix .. serial
    end

    local function readInventory()
        local inv = Inventory.Find(config.Inv.INV)
        if not inv or not inv.isValid then return nil end
        local slots = inv:GetSlots()
        assert(type(slots) == "table", "backpack slots unavailable")
        local totals = {}
        for _, slot in pairs(slots) do
            if slot.obj and slot.count > 0 then
                local id = slot.obj.id
                totals[id] = (totals[id] or 0) + slot.count
            end
        end
        return totals
    end

    local function delta(before, after)
        local other = false
        for id, count in pairs(before) do
            if id ~= boneID and count ~= (after[id] or 0) then other = true end
        end
        for id, count in pairs(after) do
            if id ~= boneID and count ~= (before[id] or 0) then other = true end
        end
        return (after[boneID] or 0) - (before[boneID] or 0), other
    end

    local function stackCount(entity)
        local count = 0
        for index = 1, entity.stackSize do
            local entry = assert(entity:GetEntry(index), "ground stack entry unavailable")
            if entry.configID == boneID then count = count + entry.count end
        end
        return count
    end

    local function rememberPlayer(entity)
        if not entity or not entity.isValid or entity == selfEntity or entity.uid == selfEntity.uid then return end
        local record = find(players, entity)
        local uid = entity.uid
        if not record then
            for _, known in ipairs(players) do
                if known.entity.isValid and known.uid == uid then record = known; break end
            end
        end
        if not record then
            record = { key = nextKey("p"), entity = entity, uid = uid }
            players[#players + 1] = record
        end
        record.entity = entity
        local name, display = Store.nameKey(entity.displayName)
        matcher:observePlayer(record.key, name, tile(entity), display)
        return record
    end

    local function rememberStack(entity)
        local record = { key = nextKey("g"), entity = entity, tile = tile(entity), count = stackCount(entity) }
        stacks[#stacks + 1] = record
        return record
    end

    -- Removed proxies may already be invalid: identity comparisons use cached
    -- handles, while all positions/counts used later are copied Lua values.
    local function syncSelf()
        if not inGame or not Player.IsAvailable() then
            if ready then restart("local player unavailable") end
            return false
        end
        local entity = PlayerList.Self()
        if not entity or not entity.isValid then
            if ready then restart("local entity unavailable") end
            return false
        end
        local position = tile(entity)
        if ready and (entity ~= selfEntity or position.level ~= selfTile.level
            or math.abs(position.x - selfTile.x) > 2 or math.abs(position.z - selfTile.z) > 2) then
            restart("local identity, level or position discontinuity")
            return false
        end
        selfEntity, selfTile = entity, position
        matcher:localPosition(position)
        return true
    end

    local function seed()
        inventory = readInventory()
        if not inventory then return end
        matcher:reset("scene baseline")
        matcher:localPosition(selfTile)
        for _, entity in ipairs(PlayerList.All()) do rememberPlayer(entity) end
        for _, entity in ipairs(ObjStackList.All()) do
            if entity.isValid then
                local record = rememberStack(entity)
                matcher:seedGround(record.key, record.tile, record.count)
            end
        end
        ready = true
        trace("baseline", boneID, inventory[boneID] or 0)
    end

    local function active()
        return ready and syncSelf()
    end

    local function groundEvent(kind, event)
        if not active() then trace("ground_event_ignored", kind, "monitoring not ready"); return end
        local entity, objID = event.objStackEntity, event.objType.id
        local record, index = find(stacks, entity)
        trace("ground_" .. kind, record and record.key or "new", objID, event.count,
            event.oldCount, event.newCount, event.isOwner, entity.isValid, "config", event.objType.configName)
        if not record then
            if not entity.isValid then restart("unresolved invalid ground proxy"); return end
            record = rememberStack(entity)
            if kind ~= "added" then
                matcher:seedGround(record.key, record.tile, record.count)
                trace("skip", "unobserved ground stack", record.key)
                return
            end
            record.count = 0
        elseif kind == "added" then
            restart("duplicate ground-added event")
            return
        end
        local before = record.count
        local expectedDelta = 0
        if objID == boneID then
            if kind == "added" then expectedDelta = event.count
            elseif kind == "removed" then expectedDelta = -event.count
            else expectedDelta = event.newCount - event.oldCount end
        end
        local after = 0
        if kind ~= "removed" then
            if not entity.isValid then restart("invalid changed ground proxy"); return end
            after = stackCount(entity)
        end
        local resolved = after - before == expectedDelta
        trace("ground_state", record.key, "tile", record.tile.level, record.tile.x, record.tile.z,
            "bone_before_after", before, after, "expected_delta", expectedDelta, "resolved", resolved)
        if objID == boneID or before ~= after then
            matcher:groundChange(record.key, record.tile, before, after, event.isOwner, resolved)
        end
        record.count = after
        if kind == "removed" then
            matcher:forgetGround(record.key)
            if index then table.remove(stacks, index) end
        end
    end

    local subscriptions = {}
    local function subscribe(name, callback, monitoring)
        local event = assert(Event[name], "BoneCollector: missing native event " .. name)
        event.Subscribe("BoneCollector", function(payload)
            if stopped or (monitoring and fatal) then return end
            -- An API contract failure must stop counting, not manufacture data.
            local ok, err = pcall(callback, payload)
            if not ok then
                fatal = name .. ": " .. tostring(err)
                trace("error", fatal)
                restart("API error")
                print("[BoneCollector] Monitoring stopped: " .. fatal)
            end
        end)
        subscriptions[#subscriptions + 1] = event
    end

    view = View.new(store, {
        save = function()
            message = store:save() and "Saved." or "NOT saved. Check the client console and retry."
            if store.unsaved then print("[BoneCollector] " .. message) end
        end,
        diagnostics = function(enabled)
            if enabled == true then
                diagnostics, sequence = true, 0
                diagnosticLog:clear()
                trace("diagnostics_on", "0.2.1 direct pickup investigation", "ordinary_bone_config", boneID)
                trace("readiness", "ready", ready, "in_game", inGame, "player_cache", #players,
                    "scene_age_ticks", matcher.tick - matcher.started)
                trace("thresholds", "warmup_ticks", Matcher.warmup, "stationary_ticks", 30,
                    "sample_age_max", 10, "match_window", Matcher.window, "pickup_window", Matcher.pickupWindow)
                for key, player in pairs(matcher.players) do
                    trace("observed_player", key, "name_resolved", player.name ~= nil,
                        "tile", player.tile.level, player.tile.x, player.tile.z,
                        "seen_ticks", matcher.tick - player.since, "sample_age", matcher.tick - player.last)
                end
                if type(bonesConfig.groundOpNames) == "table" then
                    for index, name in pairs(bonesConfig.groundOpNames) do trace("bone_ground_op", index, name) end
                end
                lootProbe:setEnabled(true)
            else
                trace("diagnostics_off", "snapshot retained until next capture or reload")
                lootProbe:setEnabled(false)
                diagnostics = false
            end
        end,
        snapshot = function() return diagnosticLog:snapshot() end,
        status = function()
            local status
            if fatal then status = "Monitoring stopped; reload with prl bonecollector. " .. fatal
            elseif not ready then status = "Waiting for a game and backpack baseline."
            elseif matcher.tick - matcher.started < Matcher.warmup then status = "Warming up (3 seconds)."
            else status = "Monitoring all nearby players; attribution is an inference." end
            return status .. "\n" .. message, diagnostics
        end,
    })

    subscribe("Logic", function(event)
        assert(event.logicTick >= matcher.tick, "non-monotonic client clock")
        matcher.tick = event.logicTick
        if not syncSelf() then return end
        lootProbe:update(event.logicTick)
        if not ready then seed(); return end
        if event.logicTick - lastPoll >= 5 then
            lastPoll = event.logicTick
            for _, entity in ipairs(PlayerList.All()) do rememberPlayer(entity) end
            -- A lost event is not a death. Drop stale caches rather than infer it.
            for index = #players, 1, -1 do
                local record = players[index]
                if not record.entity.isValid then
                    trace("player_cache_lost", record.key, "invalid before removal callback")
                    matcher.players[record.key] = nil
                    table.remove(players, index)
                end
            end
            for index = #stacks, 1, -1 do
                local record = stacks[index]
                if not record.entity.isValid then
                    matcher:block(matcher.bones[record.key], "ground proxy lost without removal event")
                    matcher:forgetGround(record.key)
                    table.remove(stacks, index)
                end
            end
        end
        matcher:advance(event.logicTick)
    end, true)

    subscribe("PlayerEntityAdded", function(event)
        if active() then
            local record = rememberPlayer(event.playerEntity)
            trace("player_added", record and record.key or "self")
        end
    end, true)
    subscribe("PlayerEntityRemoved", function(event)
        if not active() then trace("player_event_ignored", "removed", "monitoring not ready"); return end
        local record, index = find(players, event.playerEntity)
        local uidMatched = false
        if diagnostics and event.playerEntity.isValid then
            for _, cached in ipairs(players) do
                if cached.uid == event.playerEntity.uid then uidMatched = true; break end
            end
        end
        trace("player_removed", record and record.key or "unknown", "valid", event.playerEntity.isValid,
            "uid_matched", uidMatched, "cached_players", #players, "last_poll", lastPoll)
        if not record then restart("unresolved player removal"); return end
        if event.playerEntity.isValid then rememberPlayer(event.playerEntity) end
        matcher:removePlayer(record.key)
        table.remove(players, index)
    end, true)
    subscribe("ObjStackEntityAdded", function(event) groundEvent("added", event) end, true)
    subscribe("ObjStackEntityChanged", function(event) groundEvent("changed", event) end, true)
    subscribe("ObjStackEntityRemoved", function(event) groundEvent("removed", event) end, true)
    subscribe("MiniMenuEntrySelected", function(event)
        lootProbe:menu(event.entry)
        if not active() then trace("skip", "menu while monitoring not ready"); return end
        local entry, data = event.entry, event.entry.objData
        trace("menu", "entry_type", entry.actionEntryType, "action_type", entry.actionType, "verb", entry.verbText,
            "stack_index", data and data.stackIndex, "obj_id", data and data.config.id,
            "component_op", entry.componentData and entry.componentData.opIndex,
            "local_tile", selfTile.level, selfTile.x, selfTile.z)
        if entry.actionEntryType ~= MiniMenuEntryType.OBJ or entry.actionType ~= MiniMenuActionType.OP_OBJ3
            or entry.verbText ~= "Take" or not data or not data.entity.isValid or data.config.id ~= boneID then
            matcher:cancel("non-supported menu action")
            trace("skip", "unsupported menu action; expected OBJ / OP_OBJ3 / Take / BONES")
            return
        end
        local obj = data.entity:GetEntry(data.stackIndex)
        local record = find(stacks, data.entity)
        local boneCount = stackCount(data.entity)
        trace("menu_target", record and record.key or "uncached", "entry_obj", obj and obj.configID,
            "entry_count", obj and obj.count, "tile_bones", boneCount)
        if not obj or obj.configID ~= boneID or obj.count ~= 1 or not record or boneCount ~= 1 then
            matcher:cancel("ambiguous menu target")
            trace("skip", "ambiguous menu target")
            return
        end
        local current = readInventory()
        if not current then restart("backpack unavailable during Take"); return end
        local change, other = delta(inventory, current)
        if change ~= 0 or other then restart("backpack baseline drift"); return end
        matcher:select(record.key)
    end, true)
    subscribe("InventoryUpdated", function(event)
        lootProbe:inventoryEvent("updated", event)
        if not active() then return end
        if event.inv.id ~= config.Inv.INV.id then
            trace("other_inventory_update", event.inv.id, "cancel_pending", matcher.pending ~= nil)
            matcher:cancel("another inventory updated")
            return
        end
        local current = readInventory()
        if not current then restart("backpack unavailable"); return end
        local change, other = delta(inventory, current)
        trace("inventory", inventory[boneID] or 0, current[boneID] or 0, "delta", change,
            "other_changed", other, "slots", #event.slotsUpdated)
        inventory = current
        matcher:inventory(change, other)
    end, true)
    for _, name in ipairs({ "InventoryAdded", "InventoryRemoved" }) do
        subscribe(name, function(event)
            lootProbe:inventoryEvent(name, event)
            if event.inv.id == config.Inv.INV.id then restart(name) end
        end, true)
    end
    subscribe("ServerLogic", function()
        if active() then
            trace("server_boundary")
            matcher:finishPacket()
        end
    end, true)
    subscribe("GameStateChanged", function(event)
        inGame = event.newState == GameState.GAME
        restart("game state " .. tostring(event.newState))
        if not inGame then view:destroyAll() end
    end)
    for _, name in ipairs({ "WorldCreated", "WorldUpdated", "RegionCreated", "RegionUpdated" }) do
        subscribe(name, function() restart(name) end, true)
    end
    subscribe("SettingsLayerReady", function(event) view:show("settings", event.component) end)
    subscribe("ContentLayerReady", function(event) view:show("content", event.component) end)
    subscribe("Draw", function() view:refresh(inGame and Player.IsAvailable()) end)

    if store.unsaved then print("[BoneCollector] Saved totals loaded, but the data upgrade was NOT saved. Use Retry save.") end
    print("[BoneCollector] Monitoring all nearby players. Click BoneCollector to open collected-bone counts.")
    return function()
        stopped = true
        lootProbe:setEnabled(false)
        for _, event in ipairs(subscriptions) do event.Unsubscribe("BoneCollector") end
        restart("shutdown")
        view:destroyAll()
        if store.unsaved then print("[BoneCollector] WARNING: unsaved changes were not persisted.") end
    end
end

return App
