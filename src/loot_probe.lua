local Probe = {}
Probe.__index = Probe

-- Native names verified in the public API config dump; they identify UI, not
-- which op collects loot or how a row maps to a ground stack.
local targets = {
    { name = "TOPLEVEL_V2_LOOT__SLOT_LAYER", children = true },
    { name = "TOPLEVEL_V2_LOOT__ITEM_LAYER", children = true },
    { name = "TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_LAYER" },
    { name = "TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_HIT_LAYER" },
    { name = "TOPLEVEL_V2_LOOT__LOOT_ALL_BUTTON_ACTIVE_LAYER" },
}
local listener = "BoneCollectorAreaLootProbe"
local limit = 128

local function identity(component)
    local ids = { component.interfaceID, component.staticID, component.categoryID, component.dynamicID }
    return ids, table.concat(ids, ":")
end

function Probe.new(trace)
    return setmetatable({ trace = trace, bindings = {}, errors = {}, enabled = false }, Probe)
end

function Probe:read(label, callback)
    local ok, err = pcall(callback)
    if not ok and self.errors[label] ~= tostring(err) then
        self.errors[label] = tostring(err)
        self.trace("area_probe_error", label, err)
    elseif ok then
        self.errors[label] = nil
    end
end

function Probe:release(binding)
    if ui.Interfaces:GetComponent(table.unpack(binding.ids)) == binding.component then
        for _, hook in ipairs(binding.hooks) do binding.component:Unsubscribe(hook, listener) end
    end
end

function Probe:clear()
    for key, binding in pairs(self.bindings) do
        self:read("unsubscribe " .. key, function() self:release(binding) end)
    end
    self.bindings, self.lastPoll = {}, nil
end

function Probe:setEnabled(enabled)
    self:clear()
    self.enabled, self.errors = enabled == true, {}
    if self.enabled then
        self.trace("area_probe_mode", "read-only; area loot does NOT count")
    end
end

function Probe:inventorySnapshot(name, reason)
    local invConfig = assert(config.Inv[name], "native inventory config unavailable: " .. name)
    local inv = Inventory.Find(invConfig)
    if not inv or not inv.isValid then
        self.trace("area_inventory", reason, name, invConfig.id, "unavailable")
        return
    end
    local slots = assert(inv:GetSlots(), "inventory slots unavailable: " .. name)
    local rows = {}
    for slotID, slot in pairs(slots) do
        if slot.obj and slot.count > 0 then
            rows[#rows + 1] = { slot = slotID, obj = slot.obj.id, count = slot.count }
        end
    end
    table.sort(rows, function(a, b) return a.slot < b.slot end)
    local values = {}
    for index = 1, math.min(limit, #rows) do
        local row = rows[index]
        values[index] = row.slot .. ":" .. row.obj .. ":" .. row.count
    end
    self.trace("area_inventory", reason, name, invConfig.id, "slot:obj:count", table.concat(values, ","))
    if #rows > limit then self.trace("area_probe_truncated", name, #rows, limit) end
end

function Probe:capture(reason)
    if not self.enabled then return end
    for _, name in ipairs({ "LOOT", "INV" }) do
        self:read("snapshot " .. name, function() self:inventorySnapshot(name, reason) end)
    end
    self:read("ground snapshot", function()
        local player = PlayerList.Self()
        if player and player.isValid then
            local coord = player.coordGrid
            self.trace("area_local_tile", reason, coord.level, coord.x, coord.z)
        end
        local count = 0
        for _, entity in ipairs(ObjStackList.All()) do
            if entity.isValid then
                local coord = entity.coordGrid
                for index = 1, entity.stackSize do
                    if count >= limit then self.trace("area_probe_truncated", "ground", limit); return end
                    local entry = assert(entity:GetEntry(index), "ground entry unavailable")
                    self.trace("area_ground", reason, coord.level, coord.x, coord.z, index, entry.configID, entry.count)
                    count = count + 1
                end
            end
        end
    end)
end

function Probe:componentSnapshot(component, reason)
    local _, key = identity(component)
    self.trace("area_component", reason, key, "type", component.type, "visible", component.visibleGlobal, "enabled", component.enabled)
    local ops = component.opConfig
    if ops then
        for index = 1, 10 do
            local name = ops:GetOpName(index)
            if name ~= "" then self.trace("area_op_name", key, index, name) end
        end
    end
end

function Probe:bind(component, label, seen)
    if component.visibleGlobal ~= true then return end
    local ids, key = identity(component)
    if ids[1] ~= id.Interface.TOPLEVEL_V2_LOOT then return end
    seen[key] = true
    local existing = self.bindings[key]
    if existing and existing.component == component and existing.complete then return end
    if existing then self:release(existing) end
    local binding = { ids = ids, component = component, hooks = {} }
    self.bindings[key] = binding
    self:componentSnapshot(component, label)
    for _, name in ipairs({ "ONCLICK", "ONOP" }) do
        local hook = assert(ui.Hook[name], "native hook unavailable: " .. name)
        component:Subscribe(hook, listener, function(_, first, second)
            if self.enabled and self.bindings[key] == binding then
                self:read("hook " .. key, function()
                    if ui.Interfaces:GetComponent(table.unpack(ids)) ~= component then return end
                    -- ONOP's second argument is subject text; do not log it.
                    self.trace("area_hook", name, key, first, name == "ONCLICK" and second or nil)
                    self:componentSnapshot(component, name)
                    self:capture(name)
                end)
            end
            return true
        end)
        binding.hooks[#binding.hooks + 1] = hook
    end
    binding.complete = true
end

function Probe:update(tick)
    if not self.enabled or (self.lastPoll and tick - self.lastPoll < 10) then return end
    self.lastPoll = tick
    self:read("bind loot interface", function()
        assert(id.Interface and id.Interface.TOPLEVEL_V2_LOOT, "native TOPLEVEL_V2_LOOT interface unavailable")
        local previouslyBound = next(self.bindings) ~= nil
        local seen, children = {}, 0
        for _, target in ipairs(targets) do
            local componentID = assert(id.Component[target.name], "native component unavailable: " .. target.name)
            local root = ui.Interfaces:GetComponent(componentID)
            if root then
                self:bind(root, target.name, seen)
                if target.children and root.visibleGlobal == true then
                    root:IterateDynamicComponents(function(child, visible)
                        if children >= limit then return true end
                        children = children + 1
                        if visible then self:bind(child, target.name .. " child", seen) end
                        return false
                    end)
                end
            end
        end
        if children >= limit then self.trace("area_probe_truncated", "dynamic UI children", limit) end
        for key, binding in pairs(self.bindings) do
            if not seen[key] then self:release(binding); self.bindings[key] = nil end
        end
        if not previouslyBound and next(self.bindings) then self:capture("interface visible") end
    end)
end

function Probe:menu(entry)
    if not self.enabled or not entry.componentData then return end
    self:read("menu payload", function()
        local data = entry.componentData
        local expected = id.Interface and id.Interface.TOPLEVEL_V2_LOOT
        if not expected or data.component.interfaceID ~= expected then return end
        self.trace("area_menu", entry.actionEntryType, entry.actionType, "op", data.opIndex,
            "obj", data.objConfig and data.objConfig.id, "has_ground_data", entry.objData ~= nil)
        local current, depth = data.component, 0
        while current and depth < 8 do
            self:componentSnapshot(current, "menu ancestor " .. depth)
            current, depth = current.parent, depth + 1
        end
        if current then self.trace("area_probe_truncated", "menu ancestry", depth) end
        self:capture("menu")
    end)
end

function Probe:inventoryEvent(kind, event)
    if not self.enabled then return end
    self:read("inventory event", function()
        local loot = config.Inv.LOOT
        if (loot and event.inv.id == loot.id) or (next(self.bindings) and event.inv.id == config.Inv.INV.id) then
            self.trace("area_inventory_event", kind, event.inv.id, "updated_slots",
                event.slotsUpdated and table.concat(event.slotsUpdated, ",") or "")
            self:capture(kind)
        end
    end)
end

return Probe
