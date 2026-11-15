local Matcher = {}
Matcher.__index = Matcher

-- Client Logic ticks are 20 ms. These deliberately small windows prefer misses.
Matcher.window = 60
Matcher.settle = 120
Matcher.warmup = 150
Matcher.pickupWindow = 100
Matcher.lifetime = 1500

local function sameTile(a, b)
    return a.level == b.level and a.x == b.x and a.z == b.z
end

local function tileKey(tile)
    return tile.level .. ":" .. tile.x .. ":" .. tile.z
end

local function nearby(a, b)
    return a and b and a.level == b.level and math.abs(a.x - b.x) <= 1 and math.abs(a.z - b.z) <= 1
end

function Matcher.new(tracked, onCount, trace)
    local self = setmetatable({ tracked = tracked, onCount = onCount, trace = trace, tick = 0 }, Matcher)
    self:reset("startup")
    return self
end

function Matcher:reset(reason)
    self.started, self.packet = self.tick, 1
    self.players, self.visits, self.departures, self.bones, self.ground = {}, {}, {}, {}, {}
    self.pending, self.localTile, self.dropUntil = nil, nil, 0
    self.trace("reset", reason)
end

function Matcher:block(bone, reason)
    if bone and not bone.blocked and not bone.counted then
        bone.blocked = reason
        self.trace("skip", reason, bone.key)
    end
    if self.pending and self.pending.bone == bone then self.pending = nil end
end

function Matcher:cancel(reason)
    if self.pending then self:block(self.pending.bone, reason) end
end

function Matcher:localPosition(tile)
    self.localTile = tile
    if self.pending and not nearby(tile, self.pending.bone.tile) then self:cancel("left pickup tile") end
end

function Matcher:observePlayer(key, name, tile)
    local player = self.players[key]
    if not player then
        player = { key = key, name = name, since = self.tick, tileSince = self.tick }
        self.players[key] = player
        for _, departure in pairs(self.departures) do
            if departure.name == name then departure.returned = true end
        end
        for _, bone in pairs(self.bones) do
            if bone.name == name then self:block(bone, "player reappeared") end
        end
    elseif player.name ~= name then
        self:reset("player identity changed")
        return
    elseif not sameTile(player.tile, tile) then
        player.tileSince = self.tick
    end
    player.tile, player.last = tile, self.tick
    local id = tileKey(tile)
    self.visits[id] = self.visits[id] or {}
    self.visits[id][key] = self.tick
    for _, bone in pairs(self.bones) do
        if self.tick - bone.at <= Matcher.window and sameTile(bone.tile, tile) then
            bone.occupants[key] = true
        end
    end
    if self.pending and nearby(tile, self.pending.bone.tile) then self:cancel("another player near pickup") end
end

function Matcher:removePlayer(key)
    local player = self.players[key]
    if not player then return end
    self.players[key] = nil
    local departure = {
        key = key, name = player.name, tile = player.tile, at = self.tick,
        eligible = self.tracked[player.name] ~= nil
            and self.tick - self.started >= Matcher.warmup
            and self.tick - player.since >= Matcher.warmup
            and self.tick - player.tileSince >= 30
            and self.tick - player.last <= 10,
    }
    departure.occupants = {}
    for visitor, at in pairs(self.visits[tileKey(player.tile)] or {}) do
        if self.tick - at <= Matcher.window then departure.occupants[visitor] = true end
    end
    self.departures[key] = departure
    self.trace("departure", key, tileKey(player.tile), departure.eligible)
end

function Matcher:seedGround(key, tile, count)
    self.ground[key] = { tile = tile, count = count }
end

function Matcher:groundChange(key, tile, before, after, isOwner, fresh)
    self.ground[key] = { tile = tile, count = after }
    local bone = self.bones[key]
    if self.pending and self.pending.bone ~= bone and before ~= after then
        self:cancel("competing bone change")
    end
    if before == 0 and after > 0 and fresh then
        if bone then
            self:block(bone, "bone reappeared")
            return
        end
        local occupants = {}
        for player, at in pairs(self.visits[tileKey(tile)] or {}) do
            if self.tick - at <= Matcher.window then occupants[player] = true end
        end
        bone = { key = key, tile = tile, at = self.tick, occupants = occupants }
        self.bones[key] = bone
        if after ~= 1 then self:block(bone, "multiple bones on tile") end
        if isOwner ~= false then self:block(bone, "local ownership or unknown ownership") end
        if self.tick - self.started < Matcher.warmup then self:block(bone, "scene warmup") end
        if self.tick <= self.dropUntil then self:block(bone, "recent backpack bone loss") end
        for otherKey, other in pairs(self.bones) do
            if otherKey ~= key and sameTile(other.tile, tile) and self.tick - other.at <= Matcher.settle then
                self:block(other, "multiple bone appearances")
                self:block(bone, "multiple bone appearances")
            end
        end
        self.trace("birth", key, tileKey(tile))
    elseif before == 1 and after == 0 then
        local pending = self.pending
        if fresh and bone and pending and pending.bone == bone and not pending.ground
            and self:safePickup(tile) and isOwner == false then
            pending.ground = self.packet
        else
            self:block(bone, "ground loss without unique pickup intent")
        end
    elseif before ~= after or not fresh then
        self:block(bone, "stack changed or event was not uniquely resolved")
    end
end

function Matcher:forgetGround(key)
    self.ground[key] = nil
end

function Matcher:safePickup(tile)
    if not nearby(self.localTile, tile) then return false end
    for _, player in pairs(self.players) do
        if self.tick - player.last <= 10 and nearby(player.tile, tile) then return false end
    end
    return true
end

function Matcher:select(key)
    self:cancel("another menu selection")
    local bone, ground = self.bones[key], self.ground[key]
    if not bone or bone.blocked or bone.counted or bone.collected or not ground or ground.count ~= 1 then
        self.trace("skip", "Take has no eligible single bone", key)
        return
    end
    if not self:safePickup(bone.tile) then
        self:block(bone, "pickup is distant or crowded")
        return
    end
    self.pending = { bone = bone, at = self.tick }
    self.trace("intent", key)
end

-- Exact backpack delta, not just GetTotal(): nothing else may enter or leave.
function Matcher:inventory(boneDelta, otherChanged)
    if boneDelta < 0 then
        self.dropUntil = self.tick + 250
        for _, bone in pairs(self.bones) do self:block(bone, "backpack bone loss") end
    end
    local pending = self.pending
    if not pending or (boneDelta == 0 and not otherChanged) then return end
    if boneDelta ~= 1 or otherChanged or pending.inventory or not self:safePickup(pending.bone.tile) then
        self:cancel("inventory delta is not one isolated bone")
        return
    end
    pending.inventory = self.packet
end

function Matcher:finishPacket()
    local pending = self.pending
    if pending and (pending.ground or pending.inventory) then
        if pending.ground == self.packet and pending.inventory == self.packet then
            pending.bone.collected = self.tick
            self.trace("collection_evidence", pending.bone.key, self.packet)
            self.pending = nil
        else
            self:cancel("ground and inventory did not change in the same server packet")
        end
    end
    self.packet = self.packet + 1
    self:evaluate()
end

function Matcher:evaluate()
    for _, bone in pairs(self.bones) do
        if not bone.blocked and not bone.counted and self.tick - bone.at > Matcher.settle then
            if not bone.departure then
                local matches = {}
                for _, departure in pairs(self.departures) do
                    if sameTile(departure.tile, bone.tile) and math.abs(departure.at - bone.at) <= Matcher.window then
                        matches[#matches + 1] = departure
                    end
                end
                if #matches ~= 1 or not matches[1].eligible or matches[1].used or matches[1].returned then
                    self:block(bone, "no unique fresh tracked departure")
                else
                    local departure = matches[1]
                    for key in pairs(bone.occupants) do
                        if key ~= departure.key then self:block(bone, "multiple players on death tile") end
                    end
                    for key in pairs(departure.occupants) do
                        if key ~= departure.key then self:block(bone, "multiple players on death tile") end
                    end
                    if not bone.blocked then
                        departure.used = true
                        bone.departure, bone.name = departure, departure.name
                    end
                end
            end
            if not bone.blocked and bone.departure and bone.departure.returned then
                self:block(bone, "player reappeared")
            end
            if not bone.blocked and bone.collected and bone.departure then
                bone.counted = true
                self.onCount(bone.name)
                self.trace("count", bone.key)
            end
        end
    end
end

function Matcher:advance(tick)
    assert(type(tick) == "number" and tick >= self.tick, "BoneCollector: non-monotonic client clock")
    self.tick = tick
    if self.pending and tick - self.pending.at > Matcher.pickupWindow then self:cancel("pickup timed out") end
    for key, bone in pairs(self.bones) do
        if tick - bone.at > Matcher.lifetime then
            self:block(bone, "bone expired")
            self.bones[key] = nil
        end
    end
    for key, departure in pairs(self.departures) do
        if tick - departure.at > Matcher.lifetime + Matcher.window then self.departures[key] = nil end
    end
    for tile, visits in pairs(self.visits) do
        for key, at in pairs(visits) do
            if tick - at > Matcher.window then visits[key] = nil end
        end
        if next(visits) == nil then self.visits[tile] = nil end
    end
    self:evaluate()
end

return Matcher
