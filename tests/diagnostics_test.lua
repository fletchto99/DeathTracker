local Diagnostics = require("src/diagnostics")
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
test("snapshot retains recent lines and reports discarded history", function()
    local log = Diagnostics.new()
    for i = 1, 150 do log:append("line " .. i) end
    local snapshot = log:snapshot()
    assert(snapshot:match("120 lines %(30 older lines dropped%)"))
    assert(snapshot:find("\nline 31\n", 1, true) and not snapshot:find("\nline 30\n", 1, true))
    assert(snapshot:sub(-8) == "line 150")
end)
test("large events are bounded and explicitly marked rather than overflowing the copy field", function()
    local log = Diagnostics.new()
    for _ = 1, 100 do log:append(string.rep("x", 3000)) end
    local snapshot = log:snapshot()
    assert(#snapshot < 26000 and snapshot:find("[line truncated]", 1, true))
    assert(log.dropped > 0)
end)
test("starting a new capture clears only diagnostic history", function()
    local log = Diagnostics.new()
    log:append("previous")
    log:clear()
    assert(log:snapshot():match("No diagnostics captured") and log.dropped == 0)
    log:append("current")
    assert(not log:snapshot():match("previous") and log:snapshot():match("current"))
end)
return passed
