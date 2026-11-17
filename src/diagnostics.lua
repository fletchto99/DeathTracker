local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Diagnostics.new()
    return setmetatable({ lines = {}, bytes = 0, dropped = 0 }, Diagnostics)
end

function Diagnostics:clear()
    self.lines, self.bytes, self.dropped = {}, 0, 0
end

function Diagnostics:append(line)
    if #line > 1024 then line = line:sub(1, 1000) .. " [line truncated]" end
    self.lines[#self.lines + 1] = line
    self.bytes = self.bytes + #line + 1
    while #self.lines > 120 or self.bytes > 24000 do
        self.bytes = self.bytes - #table.remove(self.lines, 1) - 1
        self.dropped = self.dropped + 1
    end
    return line
end

function Diagnostics:snapshot()
    if #self.lines == 0 then return "No diagnostics captured. Enable diagnostics, run one test, then turn diagnostics off." end
    return string.format("BoneCollector diagnostic snapshot: %d lines (%d older lines dropped)\n",
        #self.lines, self.dropped) .. table.concat(self.lines, "\n")
end

return Diagnostics
