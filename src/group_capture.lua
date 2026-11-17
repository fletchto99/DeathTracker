local Names = require("src/names")
local Capture = {}
Capture.__index = Capture

local function plain(text)
    if type(text) ~= "string" then return nil end
    return text:gsub("<col=%x+>", ""):gsub("</col>", ""):gsub("<shad=%x+>", ""):gsub("</shad>", "")
end

local function readNames(componentID, group)
    assert(type(componentID) == "number", "native roster component is unavailable")
    local root = ui.Interfaces:GetComponent(componentID)
    if not root or root.visibleGlobal ~= true then return nil end
    local names, count = {}, 0
    root:IterateDynamicComponents(function(child, visible)
        if not visible or child.visibleGlobal ~= true then return false end
        -- Group name labels: category 0, IDs 1 + 23*n (RuneUI native adapter).
        -- This is a diagnostic observation, not an authenticated membership API.
        if group and (child.categoryID ~= 0 or child.dynamicID < 1 or (child.dynamicID - 1) % 23 ~= 0) then return false end
        local key = Names.nameKey(plain(child.content))
        if key then names[key] = true end
        count = count + 1
        assert(count <= 1000, "roster capture exceeded its safety bound")
        return false
    end)
    return names
end

local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end

function Capture.context()
    if not Plugin.HasPermission("chatAccess") then return nil, "Disabled: chatAccess permission is denied or revoked." end
    if not Plugin.HasPermission("trackingAccess") then return nil, "Disabled: grant trackingAccess to bind the local character." end
    if not Player.IsAvailable() then return nil, "Waiting for the local character." end
    local self = PlayerList.Self()
    if not self or not self.isValid then return nil, "Waiting for a valid local player." end
    local name = Names.nameKey(self.displayName)
    local trackingID = Player.GetTrackingID()
    if not name or trackingID == nil then return nil, "Waiting for local name and character identity; no fallback identity is used." end
    local identity = tostring(trackingID)
    local friends = readNames(id.Component.FRIENDS2__FRIEND_NAME_LAYER, false)
    if not friends then return nil, "Friend capture suspended: keep the Friends list visible.", identity end
    local group = readNames(id.Component.GROUP_CHILD__BUILD_AREA, true)
    if not group or not group[name] then return nil, "Group capture suspended: keep your current group roster and own row visible.", identity end
    local friendKeys, groupKeys = keys(friends), keys(group)
    if #groupKeys < 2 then return nil, "Group capture suspended: observe at least yourself and one other member.", identity end
    return {
        identity = identity, self = name, friends = friends, group = group,
        friendCount = #friendKeys, groupCount = #groupKeys,
        signature = identity .. "|" .. name .. "|" .. table.concat(friendKeys, ",") .. "|" .. table.concat(groupKeys, ","),
    }
end

-- Only recognize the user's reported sentence for an opt-in capture. This
-- syntax and these possible system categories are NOT a verified death rule.
local function candidate(event)
    local possibleSystem = event.chatType == ChatType.GENERAL or event.chatType == ChatType.ENGINE
        or event.chatType == ChatType.GROUPCHAT_NOTIFICATION or event.chatType == ChatType.GROUP_IRONMAN_NOTIFICATION
    if type(event.chatType) ~= "number" or not possibleSystem then return nil end
    if event.senderNameUnfiltered ~= "" or event.senderNameFiltered ~= "" or event.senderNameSimple ~= "" then return nil end
    local raw = event.chatMessage
    if type(raw) ~= "string" or #raw > 512 or raw:find("[\r\n]") then return nil end
    local text = plain(raw)
    local display = text:match("^Player ([A-Za-z0-9 _]+) has died%.?$")
    local key = Names.nameKey(display)
    if not key then return nil end
    if type(event.timestamp) ~= "number" or event.timestamp <= 0 or event.timestamp % 1 ~= 0 then return nil end
    return key, display, raw
end

local function redact(raw, nameLength)
    local result, index, visible, replaced = {}, 1, 0, false
    while index <= #raw do
        if raw:sub(index, index) == "<" then
            local ending = assert(raw:find(">", index, true))
            result[#result + 1], index = raw:sub(index, ending), ending + 1
        else
            visible = visible + 1
            if visible > 7 and visible <= 7 + nameLength then
                if not replaced then result[#result + 1], replaced = "[player]", true end
            else
                result[#result + 1] = raw:sub(index, index)
            end
            index = index + 1
        end
    end
    return table.concat(result)
end

function Capture.new()
    return setmetatable({ armed = false, status = "Counting disabled: notification contract is not verified." }, Capture)
end

function Capture:reset(reason)
    self.armed, self.signature, self.result, self.identity = false, nil, nil, nil
    self.status = reason
end

function Capture:observe(context, problem, identity)
    local currentIdentity = context and context.identity or identity
    if not currentIdentity then self:reset(problem); return end
    if currentIdentity and self.identity and self.identity ~= currentIdentity then self:reset("Character changed; capture cleared.") end
    if currentIdentity then self.identity = currentIdentity end
    if not context then
        self.armed, self.signature = false, nil
        self.status = problem
        return
    end
    if self.signature and self.signature ~= context.signature then
        self.armed = false
        self.status = "Roster or character changed; arm a new capture."
    elseif self.result then
        self.status = "One candidate captured; NOT authenticated or counted. Open the capture to inspect."
    elseif not self.signature then
        self.status = "Ready for a diagnostic capture, NOT death counting."
    end
    self.signature = context.signature
end

function Capture:arm(context, problem, identity, tick)
    self:observe(context, problem, identity)
    if not context then return false end
    self.armed, self.result, self.startTick = true, nil, tick
    self.status = "Capture armed for 60 seconds; counting remains disabled."
    return true
end

function Capture:advance(tick)
    if self.armed and tick - self.startTick > 3000 then
        self.armed = false
        self.status = "Capture timed out. No matching candidate was captured."
    end
end

function Capture:message(event, context, problem, identity, tick)
    if not self.armed then return false end
    self:observe(context, problem, identity)
    self:advance(tick)
    if not self.armed or not context then return false end
    local key, display, raw = candidate(event)
    if not key or not context.group[key] then return false end
    local isSelf = key == context.self
    if not isSelf and not context.friends[key] then return false end
    self.result = string.format(
        "Death Tracker 0.3.1 validation capture - NOT a counted death\nchatType=%d; timestamp=%d; logicTick=%d\n"
        .. "All three sender fields were empty.\nsubject=%s; groupRowObserved=true; friendRowObserved=%s\n"
        .. "visibleGroupNames=%d; visibleFriendNames=%d\nredactedRaw=%s\n"
        .. "Template/category, roster freshness, and exactly-once behavior still require verification.",
        event.chatType, event.timestamp, tick, isSelf and "local character" or "friend",
        tostring(context.friends[key] == true), context.groupCount, context.friendCount, redact(raw, #display))
    self.armed = false
    self.status = "One candidate captured; NOT authenticated or counted. Open the capture to inspect."
    return true
end

return Capture
