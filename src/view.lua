local Store = require("src/store")
local View = {}
View.__index = View

function View.new(store, callbacks)
    assert(type(prettyui) == "table" and type(prettyui.SimpleView) == "table"
        and type(prettyui.SimpleView.new) == "function"
        and type(prettyui.SimpleView.AddTextField) == "function",
        "BoneCollector requires PrettyUI (mod.io 6398181) with SimpleView and TextField support.")
    return setmetatable({ store = store, callbacks = callbacks, panels = {} }, View)
end

local function identity(component)
    return { component.interfaceID, component.staticID, component.categoryID, component.dynamicID }
end

local function live(panel)
    return ui.Interfaces:GetComponent(table.unpack(panel.id)) == panel.root
end

function View:destroy(kind)
    local panel = self.panels[kind]
    self.panels[kind] = nil
    if panel then panel.widget:Destroy() end
end

function View:destroyAll()
    self:destroy("settings")
    self:destroy("content")
end

function View:show(kind, parent)
    self:destroy(kind)
    local widget = prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height })
    local panel = {
        widget = widget, root = widget.root, id = identity(widget.root), parentID = identity(parent),
        width = parent.width, height = parent.height,
    }
    self.panels[kind] = panel
    widget:AddTitle("BoneCollector")
    widget:AddText({ text = "Inferred bone collections, NOT proven deaths.\nOnly explicitly tracked names can receive credit.", height = 52, maxLines = 2 })
    panel.status = widget:AddText({ text = "", height = 76, maxLines = 3 })
    widget:AddText({ text = "Tracked names (comma-separated; empty disables tracking):", height = 48, maxLines = 2 })
    local function save(text)
        if self.panels[kind] ~= panel or not live(panel) then return end
        self.callbacks.names(text)
        self:refresh()
    end
    panel.names = widget:AddTextField({
        text = table.concat(self.store.data.names, ", "),
        maxLength = 280,
        placeholder = "Friend One, Friend Two",
        onSubmit = function(_, text) save(text) end,
    })
    widget:AddSimpleButton("Save tracked names", function()
        if self.panels[kind] == panel and live(panel) then save(panel.names:GetText()) end
    end)
    widget:AddSimpleButton("Retry save", function()
        if self.panels[kind] == panel and live(panel) then self.callbacks.save() end
    end)
    panel.diagnostics = widget:AddSimpleButton("Diagnostics (this session)", function(_, active)
        if self.panels[kind] == panel and live(panel) then self.callbacks.diagnostics(active) end
    end, { toggleable = true })
    widget:AddText({
        text = "Take one ordinary bone at a time, from at most one tile away.\nAvoid area loot, stacks, and other players beside the pickup.",
        height = 76, maxLines = 3,
    })
    widget:AddTitle("Collected bones / inferred deaths")
    panel.counts = widget:AddText({ text = "", height = 504, maxLines = 21 })
    self:refresh()
end

function View:refresh()
    local lines = {}
    for _, name in ipairs(self.store.data.names) do
        local key = Store.nameKey(name)
        lines[#lines + 1] = name .. ": " .. (self.store.data.counts[key] or 0)
    end
    if #lines == 0 then lines[1] = "No tracked names. Add your friends above." end
    local status, diagnostics = self.callbacks.status()
    if self.store.unsaved then status = "NOT SAVED - changes may be lost. Use Retry save.\n" .. status end
    local counts, names = table.concat(lines, "\n"), table.concat(self.store.data.names, ", ")
    for kind, panel in pairs(self.panels) do
        if not live(panel) then
            self:destroy(kind)
        else
            local parent = ui.Interfaces:GetComponent(table.unpack(panel.parentID))
            if parent and (parent.width ~= panel.width or parent.height ~= panel.height) then
                panel.width, panel.height = parent.width, parent.height
                panel.widget:SetSize(parent.width, parent.height)
            end
            if panel.lastStatus ~= status then panel.status.content, panel.lastStatus = status, status end
            if panel.lastCounts ~= counts then panel.counts.content, panel.lastCounts = counts, counts end
            if panel.lastNames ~= names then panel.names:SetText(names, false); panel.lastNames = names end
            if panel.lastDiagnostics ~= diagnostics then
                panel.diagnostics:SetActive(diagnostics)
                panel.lastDiagnostics = diagnostics
            end
        end
    end
end

return View
