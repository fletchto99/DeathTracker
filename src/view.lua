local View = {}
View.__index = View

function View.new(store, callbacks)
    assert(type(prettyui) == "table" and type(prettyui.SimpleView) == "table"
        and type(prettyui.SimpleView.new) == "function" and type(prettyui.Window) == "table"
        and type(prettyui.Window.new) == "function" and type(prettyui.SimpleButton) == "table"
        and type(prettyui.SimpleButton.new) == "function",
        "BoneCollector requires PrettyUI (mod.io 6398181) with SimpleView, Window and SimpleButton support.")
    return setmetatable({ store = store, callbacks = callbacks, panels = {} }, View)
end

local function identity(component)
    return { component.interfaceID, component.staticID, component.categoryID, component.dynamicID }
end

local function own(widget)
    return { widget = widget, root = widget.root, id = identity(widget.root), rows = {} }
end

local function live(panel)
    return ui.Interfaces:GetComponent(table.unpack(panel.id)) == panel.root
end

function View:destroy(kind)
    local panel = self.panels[kind]
    self.panels[kind] = nil
    if panel then panel.widget:Destroy() end
end

function View:destroyOverlay()
    self:destroy("window")
    local launcher = self.launcher
    self.launcher = nil
    if launcher then launcher.widget:Destroy() end
end

function View:destroyAll()
    self:destroy("settings")
    self:destroy("content")
    self:destroyOverlay()
end

function View:populate(kind, panel)
    local widget = panel.widget
    self.panels[kind] = panel
    widget:AddTitle("BoneCollector")
    widget:AddText({
        text = "All nearby players are considered automatically.\nPickup attribution is inferred, not proof of death.",
        height = 52, maxLines = 2,
    })
    panel.status = widget:AddText({ text = "", height = 76, maxLines = 3 })
    widget:AddSimpleButton("Retry save", function()
        if self.panels[kind] == panel and live(panel) then self.callbacks.save() end
    end)
    panel.diagnostics = widget:AddSimpleButton("Diagnostics (this session)", function(_, active)
        if self.panels[kind] == panel and live(panel) then self.callbacks.diagnostics(active) end
    end, { toggleable = true })
    widget:AddTitle("Collected bones")
end

function View:show(kind, parent)
    self:destroy(kind)
    local panel = own(prettyui.SimpleView.new(parent, { width = parent.width, height = parent.height }))
    panel.parentID, panel.width, panel.height = identity(parent), parent.width, parent.height
    self:populate(kind, panel)
    self:refresh()
end

function View:openCounts(parent)
    local panel = self.panels.window
    if panel and not live(panel) then self:destroy("window"); panel = nil end
    if not panel then
        panel = own(prettyui.Window.new(parent, {
            title = "BoneCollector", x = 180, y = 90,
            width = 500, height = 480, minWidth = 420, minHeight = 260,
            resizable = true, scrollable = true,
        }))
        self:populate("window", panel)
    end
    self:refresh()
    panel.widget:Show()
end

function View:updateLauncher(inGame)
    if not inGame then self:destroyOverlay(); return end
    if self.launcher and not live(self.launcher) then self:destroyOverlay() end
    if self.launcher then return end
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if not parent then return end
    local launcher
    local widget = prettyui.SimpleButton.new(parent, "BoneCollector", function()
        if self.launcher ~= launcher or not live(launcher) then return end
        self:openCounts(parent)
    end, { x = 20, y = 90, width = 150, height = 30 })
    launcher = own(widget)
    self.launcher = launcher
end

function View:refresh(inGame)
    if inGame ~= nil then self:updateLauncher(inGame) end
    local status, diagnostics = self.callbacks.status()
    if self.store.unsaved then status = "NOT SAVED - changes may be lost. Use Retry save.\n" .. status end
    local rows
    for kind, panel in pairs(self.panels) do
        if not live(panel) then
            self:destroy(kind)
        else
            local parent = panel.parentID and ui.Interfaces:GetComponent(table.unpack(panel.parentID))
            if parent and (parent.width ~= panel.width or parent.height ~= panel.height) then
                panel.width, panel.height = parent.width, parent.height
                panel.widget:SetSize(parent.width, parent.height)
            end
            if panel.lastStatus ~= status then panel.status.content, panel.lastStatus = status, status end
            if panel.lastRevision ~= self.store.revision then
                rows = rows or self.store:rows()
                for index = 1, math.max(1, #rows) do
                    local row = rows[index]
                    local text = row and string.format("You have picked up %d %s bones", row.count, row.name)
                        or "No bones collected yet."
                    if not panel.rows[index] then
                        panel.rows[index] = panel.widget:AddText({ text = text, height = 44, maxLines = 2 })
                    else
                        panel.rows[index].content = text
                    end
                end
                panel.lastRevision = self.store.revision
            end
            if panel.lastDiagnostics ~= diagnostics then
                panel.diagnostics:SetActive(diagnostics)
                panel.lastDiagnostics = diagnostics
            end
        end
    end
end

return View
