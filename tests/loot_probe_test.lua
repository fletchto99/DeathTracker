local Probe = require("src/loot_probe")
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function fixture()
    local f = { logs = {}, components = {}, roots = {}, inventories = {}, subscriptions = 0, unsubscriptions = 0 }
    id = { Interface = { TOPLEVEL_V2_LOOT = 1622 }, Component = {
        TOPLEVEL_V2_LOOT__SLOT_LAYER = 106299402,
        TOPLEVEL_V2_LOOT__ITEM_LAYER = 106299403,
        TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_LAYER = 106299407,
        TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_HIT_LAYER = 106299411,
        TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_ACTIVE_LAYER = 106299413,
    } }
    config = { Inv = { INV = { id = 93 }, LOOT = { id = 773 } } }
    Inventory = { Find = function(inv) return f.inventories[inv.id] end }
    PlayerList = { Self = function() return { isValid = true, coordGrid = { level = 0, x = 100, z = 100 } } end }
    ObjStackList = { All = function() return {} end }
    ui = {
        Hook = { ONCLICK = "click", ONOP = "op" },
        Interfaces = { GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
            if staticID == nil then return f.roots[interfaceID] end
            return f.components[table.concat({ interfaceID, staticID, categoryID, dynamicID }, ":")]
        end },
    }
    function f.component(staticID, category, dynamic, interfaceID)
        local ids = { interfaceID or 1622, staticID, category or -1, dynamic or -1 }
        local key = table.concat(ids, ":")
        local data = {
            interfaceID = ids[1], staticID = ids[2], categoryID = ids[3], dynamicID = ids[4],
            visibleGlobal = true, enabled = true, type = 0, children = {}, hooks = {},
            opConfig = { GetOpName = function(_, index) return index == 1 and "Test op (not verified)" or "" end },
        }
        local valid = true
        local component = setmetatable({}, { __index = function(_, field)
            assert(valid, "invalid UI proxy read: " .. field)
            return data[field]
        end })
        data.Subscribe = function(_, hook, ref, callback)
            data.hooks[hook] = data.hooks[hook] or {}
            data.hooks[hook][ref] = callback
            f.subscriptions = f.subscriptions + 1
        end
        data.Unsubscribe = function(_, hook, ref)
            data.hooks[hook][ref] = nil
            f.unsubscriptions = f.unsubscriptions + 1
        end
        data.IterateDynamicComponents = function(_, callback)
            for _, child in ipairs(data.children) do if callback(child, true) then break end end
        end
        f.components[key] = component
        if ids[3] == -1 then f.roots[ids[1] * 65536 + staticID] = component end
        return component, data, function()
            valid = false
            if f.components[key] == component then f.components[key] = nil end
            if f.roots[ids[1] * 65536 + staticID] == component then f.roots[ids[1] * 65536 + staticID] = nil end
        end
    end
    function f.inventory(invID, slots)
        f.inventories[invID] = { isValid = true, GetSlots = function() return slots end }
    end
    function f.text() return table.concat(f.logs, "\n") end
    f.probe = Probe.new(function(...)
        local values = {}
        for i = 1, select("#", ...) do values[i] = tostring(select(i, ...)) end
        f.logs[#f.logs + 1] = table.concat(values, " ")
    end)
    return f
end
test("probe is inactive by default and touches no UI or inventories", function()
    local f = fixture()
    Inventory.Find = function() error("must not read") end
    f.probe:update(10)
    f.probe:menu({ componentData = {} })
    f.probe:inventoryEvent("updated", { inv = config.Inv.INV })
    assert(f.subscriptions == 0 and #f.logs == 0)
end)
test("exact native loot subtree hooks are observational and preserve other subscribers", function()
    local f = fixture()
    local component, data = f.component(21)
    data.hooks.click = { anotherPlugin = function() return true end }
    f.probe:setEnabled(true)
    f.probe:update(10)
    assert(f.subscriptions == 2 and data.hooks.click.anotherPlugin)
    assert(data.hooks.click.BoneCollectorAreaLootProbe(component, 4, 5) == true)
    assert(data.hooks.op.BoneCollectorAreaLootProbe(component, 3, "private subject") == true)
    assert(f.text():match("area_hook ONCLICK 1622:21:") and f.text():match("area_hook ONOP 1622:21:"))
    assert(not f.text():match("private subject"))
    f.probe:setEnabled(false)
    assert(f.unsubscriptions == 2 and data.hooks.click.anotherPlugin and not data.hooks.click.BoneCollectorAreaLootProbe)
end)
test("row payloads and inventories are logged without inferring an operation or slot mapping", function()
    local f = fixture()
    local parent, data = f.component(11)
    local row, rowData = f.component(11, 0, 7)
    rowData.parent = parent
    data.children = { row }
    f.inventory(773, { [8] = { obj = { id = 526 }, count = 2 }, [2] = { obj = { id = 1511 }, count = 4 } })
    f.inventory(93, { [1] = { obj = { id = 526 }, count = 1 } })
    f.probe:setEnabled(true)
    f.probe:update(10)
    f.probe:menu({ actionEntryType = 1, actionType = 57, componentData = {
        component = row, opIndex = 4, objConfig = { id = 526 },
    } })
    f.probe:inventoryEvent("updated", { inv = config.Inv.LOOT, slotsUpdated = { 8 } })
    assert(f.text():match("area_menu 1 57 op 4 obj 526 has_ground_data false"))
    assert(f.text():match("1622:11:0:7") and f.text():match("2:1511:4,8:526:2"))
    assert(f.text():match("area_inventory_event updated 773 updated_slots 8"))
    assert(f.text():match("area_probe_mode read%-only; area loot does NOT count"))
    f.probe:setEnabled(false)
end)
test("unrelated interfaces and inventories do not masquerade as area-loot actions", function()
    local f = fixture()
    local other = f.component(21, -1, -1, 999)
    f.probe:setEnabled(true)
    f.logs = {}
    f.probe:menu({ componentData = { component = other, opIndex = 1, objConfig = { id = 526 } } })
    f.probe:inventoryEvent("updated", { inv = { id = 95 }, slotsUpdated = {} })
    assert(#f.logs == 0)
end)
test("invalid proxies, replaced UI identities and stale callbacks are cleaned up safely", function()
    local f = fixture()
    local old, oldData, invalidate = f.component(21)
    f.probe:setEnabled(true)
    f.probe:update(10)
    local stale = oldData.hooks.click.BoneCollectorAreaLootProbe
    invalidate()
    local replacement, newData = f.component(21)
    f.probe:update(20)
    assert(stale(old, 0, 0) == true)
    assert(newData.hooks.click.BoneCollectorAreaLootProbe(replacement, 0, 0) == true)
    f.probe:clear()
    assert(not newData.hooks.click.BoneCollectorAreaLootProbe)
    assert(stale(old, 0, 0) == true)
    assert(not f.text():match("area_probe_error"))
end)
test("optional read errors are explicit, throttled and never swallow native hooks", function()
    local f = fixture()
    local component, data = f.component(21)
    f.probe:setEnabled(true)
    f.probe:update(10)
    data.opConfig.GetOpName = function() error("unavailable op data") end
    local callback = data.hooks.click.BoneCollectorAreaLootProbe
    assert(callback(component, 1, 2) == true)
    local errors = select(2, f.text():gsub("area_probe_error", ""))
    assert(errors == 1)
    assert(callback(component, 1, 2) == true)
    assert(select(2, f.text():gsub("area_probe_error", "")) == 1)
    f.probe:setEnabled(false)
end)
test("hidden controls detach and no diagnostic subscriber survives disabling", function()
    local f = fixture()
    local _, data = f.component(19)
    f.probe:setEnabled(true)
    f.probe:update(10)
    data.visibleGlobal = false
    f.probe:update(20)
    assert(f.unsubscriptions == 2 and next(f.probe.bindings) == nil)
    f.probe:setEnabled(false)
    f.probe:update(30)
    assert(f.subscriptions == 2)
end)
test("direct pickup inventory updates do not flood the trace with unrelated area snapshots", function()
    local f = fixture()
    f.probe:setEnabled(true)
    f.logs = {}
    ObjStackList.All = function() error("must not scan ground for an inactive area interface") end
    f.probe:inventoryEvent("updated", { inv = config.Inv.INV, slotsUpdated = { 1 } })
    assert(#f.logs == 0)
end)
test("unsupported optional inventory config is reported without failing monitoring", function()
    local f = fixture()
    f.probe:setEnabled(true)
    setmetatable(config.Inv, { __index = function() error("unknown optional config") end })
    config.Inv.LOOT = nil
    f.probe:inventoryEvent("updated", { inv = config.Inv.INV, slotsUpdated = {} })
    assert(f.text():match("area_probe_error inventory event") and f.text():match("unknown optional config"))
end)
test("a partial hook registration is retried rather than silently left unobserved", function()
    local f = fixture()
    local component, data = f.component(21)
    local subscribe = data.Subscribe
    local fail = true
    data.Subscribe = function(self, hook, ref, callback)
        if hook == ui.Hook.ONOP and fail then error("temporarily unavailable") end
        subscribe(self, hook, ref, callback)
    end
    f.probe:setEnabled(true)
    f.probe:update(10)
    assert(f.text():match("area_probe_error") and data.hooks.click.BoneCollectorAreaLootProbe)
    fail = false
    f.probe:update(20)
    assert(data.hooks.op.BoneCollectorAreaLootProbe(component, 1, "") == true)
    f.probe:setEnabled(false)
    assert(not data.hooks.op.BoneCollectorAreaLootProbe and not data.hooks.click.BoneCollectorAreaLootProbe)
end)
return passed
