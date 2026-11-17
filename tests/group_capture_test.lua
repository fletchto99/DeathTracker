-- Deferred group work remains source-only; it is not loaded by the self counter.
local Capture = require("src/group_capture")
local passed = 0
ChatType = { GENERAL = 0, ENGINE = 4, GROUPCHAT_NOTIFICATION = 128, GROUP_IRONMAN_NOTIFICATION = 144 }
local function context()
    return { identity = "test-character", self = "me", friends = { alice = true },
        group = { me = true, alice = true, bob = true }, friendCount = 1, groupCount = 3, signature = "same-group" }
end
local function notice(name, kind)
    return { chatMessage = "Player " .. (name or "Alice") .. " has died.", chatType = kind or 128,
        timestamp = 1000, senderNameUnfiltered = "", senderNameFiltered = "", senderNameSimple = "" }
end
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
test("friend and local group candidates remain a non-counting one-shot diagnostic", function()
    for _, name in ipairs({ "Alice", "Me" }) do
        local capture, ctx = Capture.new(), context()
        assert(capture:arm(ctx, nil, nil, 100))
        assert(capture:message(notice(name), ctx, nil, nil, 110))
        assert(capture.result:match("NOT a counted death") and not capture.result:match(name))
        assert(not capture:message(notice(name), ctx, nil, nil, 110))
    end
end)
test("non-friend group members and ordinary chat remain excluded", function()
    local capture, ctx = Capture.new(), context()
    assert(capture:arm(ctx, nil, nil, 100))
    assert(not capture:message(notice("Bob"), ctx, nil, nil, 110))
    for _, kind in ipairs({ 2, 3, 9, 22, 24, 33 }) do
        assert(not capture:message(notice("Alice", kind), ctx, nil, nil, 110))
    end
    assert(capture.result == nil)
end)
test("lost or changed context and timeout cancel deferred capture", function()
    local capture, ctx = Capture.new(), context()
    assert(capture:arm(ctx, nil, nil, 100))
    assert(not capture:message(notice(), nil, "Roster unavailable", ctx.identity, 110))
    assert(not capture.armed)
    assert(capture:arm(ctx, nil, nil, 120))
    ctx.signature = "changed"
    assert(not capture:message(notice(), ctx, nil, nil, 130))
    assert(capture:arm(ctx, nil, nil, 140))
    capture:advance(3141)
    assert(not capture.armed)
end)
return passed
