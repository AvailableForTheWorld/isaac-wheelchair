-- Run from the repository root with Lua 5.3+ (or lupa's Lua runtime).
-- These checks exercise pure math and callback behavior; native Crown animation
-- speed, engine callback ordering, and visual layout still need an in-game check.
local Practice = dofile("mods/glitched-crown-practice/content/scripts/practice.lua")
local count = 0
local function equal(actual, expected, message)
    count = count + 1
    assert(actual == expected, (message or "unexpected value")
        .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function invariant(stats)
    equal(stats.total, stats.correct + stats.plus1 + stats.minus1
        + stats.plus2 + stats.minus2 + stats.other, "count invariant")
end

-- Every target/pick pair, repeated from every possible cycle starting position.
local base = { 11, 22, 33, 44, 55 }
for rotation = 0, 4 do
    local order = {}
    for i = 1, 5 do order[i] = base[(i + rotation - 1) % 5 + 1] end
    for target = 1, 5 do
        for picked = 1, 5 do
            local expected = (picked - target) % 5
            if expected > 2 then expected = expected - 5 end
            equal(Practice.offset(order, order[target], order[picked]), expected, "cycle offset")
        end
    end
end
equal(Practice.offset(base, 11, 55), -1, "first target / last picked wraps early")
equal(Practice.offset(base, 55, 11), 1, "last target / first picked wraps late")
equal(Practice.offset(base, 99, 11), nil, "unknown target")
equal(Practice.offset(base, 11, 99), nil, "unknown picked item")
equal(Practice.offset({ 11, 22 }, 11, 22), nil, "incomplete order")

local cycle, displayed = {}, { 33, 55, 11, 44, 22 }
for _, id in ipairs(displayed) do
    equal(Practice.observeCycle(cycle, id, base), "learning", "learn actual animation order")
    equal(Practice.observeCycle(cycle, id, base), "learning", "held animation frame")
end
equal(Practice.observeCycle(cycle, 33, base), "complete", "require complete wrap")
for i, id in ipairs(displayed) do equal(cycle.order[i], id, "generation order is ignored") end
equal(Practice.observeCycle({}, 99, base), "invalid", "unknown cycle item")
local invalid = {}
Practice.observeCycle(invalid, 11, base)
Practice.observeCycle(invalid, 22, base)
equal(Practice.observeCycle(invalid, 11, base), "invalid", "premature wrap")
local invalidMiddle = {}
for _, id in ipairs(base) do Practice.observeCycle(invalidMiddle, id, base) end
equal(Practice.observeCycle(invalidMiddle, 22, base), "invalid", "repeat middle item")
local duplicateCandidates = { 11, 22, 33, 44, 11 }
local duplicateCycle = {}
for _, id in ipairs({ 11, 22, 33, 44 }) do Practice.observeCycle(duplicateCycle, id, duplicateCandidates) end
equal(Practice.observeCycle(duplicateCycle, 11, duplicateCandidates), "invalid", "duplicate candidate cannot complete")

local stats = Practice.newStats()
for trial = 1, 10000 do
    equal(Practice.record(stats, trial % 5 - 2), true, "endless recording")
    invariant(stats)
end
equal(stats.total, 10000, "no 100/120 round cap")
equal(stats.correct, 2000, "correct count")
equal(stats.plus1, 2000, "late count")
equal(stats.minus1, 2000, "early count")
equal(stats.plus2, 2000, "two-step late count")
equal(stats.minus2, 2000, "two-step early count")
equal(stats.other, 0, "new results never add to legacy unknown errors")
local before = stats.total
for _, bad in ipairs({ -3, 3, 0.5, math.huge, -math.huge, 0 / 0 }) do
    equal(Practice.record(stats, bad), false, "invalid offset rejected")
end
equal(Practice.record(stats, nil), false, "missing offset rejected")
equal(stats.total, before, "invalid attempts do not count")
local restored = Practice.restoreStats(stats)
for key, value in pairs(stats) do equal(restored[key], value, "saved stats survive") end
equal(restored == stats, false, "restored stats are independent")
for _, bad in ipairs({ false, "bad", 7 }) do
    local fresh = Practice.restoreStats(bad)
    equal(fresh.total, 0, "corrupt save resets")
    invariant(fresh)
end
equal(Practice.restoreStats(nil).total, 0, "missing save resets")
local sanitized = Practice.restoreStats({ total = -12, correct = 4.9, plus1 = -1, minus1 = "3", other = 0 / 0 })
equal(sanitized.correct, 4, "fractional count is floored")
equal(sanitized.total, 4, "total is reconstructed")
equal(Practice.restoreStats({ correct = math.huge, plus1 = -math.huge }).total, 0, "infinite counts rejected")
invariant(sanitized)
local legacyStats = Practice.restoreStats({ total = 17, correct = 4, plus1 = 2, minus1 = 3, other = 8 })
equal(legacyStats.total, 17, "migration preserves all previous results")
equal(legacyStats.other, 8, "migration retains unknown direction")
equal(legacyStats.plus2, 0, "migration does not invent late results")
equal(legacyStats.minus2, 0, "migration does not invent early results")
Practice.record(legacyStats, 2)
Practice.record(legacyStats, -2)
equal(legacyStats.other, 8, "new results leave legacy count intact")
equal(legacyStats.total, 19, "migrated session continues counting")
invariant(legacyStats)

-- Independent deterministic uniforms make sampling checks stable between runs.
local function randomStream(seed)
    local state = seed
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end
equal(Practice.SPEED_MIN, 0.70, "slowest speed")
equal(Practice.SPEED_MAX, 2.00, "fastest speed")
equal(Practice.SPEED_MEAN, 1.35, "center speed")
equal(Practice.SPEED_STDDEV, 0.22, "speed spread")
local sum, squared, unique, uniform = 0, 0, {}, randomStream(12789)
for _ = 1, 50000 do
    local speed = Practice.sampleSpeed(uniform)
    equal(speed >= 0.70 and speed <= 2.00, true, "sample stays in normal speed bounds")
    equal(math.abs(speed * 100 - math.floor(speed * 100 + 0.5)) < 0.000001, true,
        "sample uses two decimal places")
    sum, squared, unique[speed] = sum + speed, squared + speed * speed, true
end
local mean = sum / 50000
local deviation = math.sqrt(squared / 50000 - mean * mean)
equal(math.abs(mean - 1.35) < 0.008, true, "sample mean is centered")
equal(deviation > 0.21 and deviation < 0.23, true, "sample standard deviation is normal")
local uniqueCount = 0
for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end
equal(uniqueCount > 100, true, "samples span the requested range")
local firstStream, repeatedStream = randomStream(99), randomStream(99)
for _ = 1, 100 do
    equal(Practice.sampleSpeed(firstStream), Practice.sampleSpeed(repeatedStream), "sampling is deterministic")
end
for _, direction in ipairs({ 0, 0.5 }) do
    -- First pair yields an eight-sigma tail, second pair yields exactly the mean.
    -- Clamping would return 0.70/2.00 after two draws instead of rejecting it.
    local forced, draws = { 1 - math.exp(-32), direction, 0, 0 }, 0
    local speed = Practice.sampleSpeed(function()
        draws = draws + 1
        assert(forced[draws], "unexpected extra draw")
        return forced[draws]
    end)
    equal(speed, 1.35, "tail is rejected instead of clamped")
    equal(draws, 4, "tail rejection consumes a second candidate")
end
local brokenCalls = 0
equal(Practice.sampleSpeed(function() brokenCalls = brokenCalls + 1; return 1 end), 1.35,
    "broken RNG safely returns the mean")
equal(brokenCalls <= 256, true, "broken RNG cannot loop forever")
for _, valid in ipairs({ 0.70, 1.23, 1.35, 2.00 }) do
    equal(Practice.restoreSpeed(valid), valid, "valid saved speed survives")
end
for _, invalidSpeed in ipairs({ false, "1.35", -1, 0.699, 2.001, math.huge, -math.huge, 0 / 0 }) do
    equal(Practice.restoreSpeed(invalidSpeed), nil, "invalid saved speed is rejected")
end
equal(Practice.restoreSpeed(nil), nil, "missing saved speed requests a fresh sample")

-- Isolated game mock. The mod is loaded normally and tested through registered
-- public callback methods; local run/stage state is not inspected or modified.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function enum()
    local nextValue = 0
    return setmetatable({}, { __index = function(t, key)
        nextValue = nextValue + 1
        rawset(t, key, nextValue)
        return nextValue
    end })
end
local function harness(saved, seed, challenge)
    local h = { saved = copy(saved), seed = seed or 123, paused = false, spawns = 0,
        doorsRemoved = 0, hudVisible = true, renders = {}, playerChanges = 0,
        floatCalls = 0, cacheCalls = 0 }
    local env = setmetatable({}, { __index = _G })
    env.CollectibleType, env.ModCallbacks = enum(), enum()
    env.PlayerType = { PLAYER_ISAAC = 0 }
    env.ActiveSlot = { SLOT_PRIMARY = 0 }
    env.CacheFlag = { CACHE_ALL = 65535, CACHE_SPEED = 16, CACHE_DAMAGE = 2 }
    env.LevelCurse = { CURSE_OF_DARKNESS = 1, CURSE_OF_BLIND = 2 }
    env.GridEntityType = { GRID_WALL = 1, GRID_DOOR = 2 }
    env.EntityType = { ENTITY_PLAYER = 1, ENTITY_PICKUP = 5 }
    env.PickupVariant = { PICKUP_COLLECTIBLE = 100 }
    env.ButtonAction, env.InputHook = enum(), enum()
    local vectorMeta = { __add = function(a, b) return { X = a.X + b.X, Y = a.Y + b.Y } end }
    env.Vector = setmetatable({ Zero = setmetatable({ X = 0, Y = 0 }, vectorMeta) }, {
        __call = function(_, x, y) return setmetatable({ X = x, Y = y }, vectorMeta) end,
    })
    env.KColor = function(r, g, b, a) return { Red = r, Green = g, Blue = b, Alpha = a } end
    env.Sprite = function() return {
        Load = function() end, ReplaceSpritesheet = function(_, _, path) h.targetPath = path end,
        LoadGraphics = function() end, SetFrame = function() end, Render = function() end,
        RenderLayer = function() end,
    } end
    env.Font = function() return {
        Load = function() end, IsLoaded = function() return true end,
        GetStringWidthUTF8 = function(_, value) return #value end,
        DrawStringUTF8 = function(_, value) h.renders[#h.renders + 1] = value end,
    } end
    env.RNG = function()
        local uniform = randomStream(h.seed)
        return {
            SetSeed = function(_, value) uniform = randomStream(value) end,
            Next = function() return math.floor(uniform() * 2147483647) end,
            RandomInt = function(_, maximum) assert(maximum > 0); return 0 end,
            RandomFloat = function()
                h.floatCalls = h.floatCalls + 1
                return uniform()
            end,
        }
    end
    local room = {
        RemoveDoor = function() h.doorsRemoved = h.doorsRemoved + 1 end,
        SetClear = function() end, GetGridSize = function() return 0 end,
        GetGridEntity = function() end, RemoveGridEntity = function() end,
        GetCenterPos = function() return env.Vector(320, 280) end,
    }
    local game = {
        Challenge = challenge or 0,
        GetRoom = function() return room end,
        GetSeeds = function() return { GetStartSeed = function() return h.seed end } end,
        GetHUD = function() return { SetVisible = function(_, visible) h.hudVisible = visible end } end,
        GetLevel = function() return { RemoveCurses = function() end } end,
        GetNumPlayers = function() return #h.players end,
        IsPaused = function() return h.paused end,
    }
    env.Game = function() return game end
    local config = {
        GetCollectible = function(_, id)
            return { ID = id, Name = "Item " .. id, GfxFileName = "item-" .. id .. ".png" }
        end,
        GetCollectibles = function() return { Size = 100 } end,
    }
    local player = { Type = 1, QueuedItem = {}, inventory = {}, maxHearts = 0,
        playerType = 0, MoveSpeed = 1 }
    function player:GetPlayerType() return self.playerType end
    function player:ChangePlayerType(id)
        self.playerType = id; h.playerChanges = h.playerChanges + 1
        if h.collapseSecondBody then h.players[2] = nil end
    end
    function player:FlushQueueItem()
        if self.QueuedItem.Item then
            local id = self.QueuedItem.Item.ID
            self.inventory[id] = (self.inventory[id] or 0) + 1
            self.QueuedItem.Item = nil
        end
    end
    function player:GetActiveItem(slot) return self.active and self.active[slot] or 0 end
    function player:RemoveCollectible(id, _, slot)
        self.inventory[id] = math.max(0, (self.inventory[id] or 0) - 1)
        if self.active and self.active[slot] == id then self.active[slot] = nil end
    end
    function player:GetCollectibleNum(id) return self.inventory[id] or 0 end
    function player:HasCollectible(id) return (self.inventory[id] or 0) > 0 end
    function player:AddCollectible(id) self.inventory[id] = (self.inventory[id] or 0) + 1 end
    function player:GetTrinket() return 0 end
    function player:TryRemoveTrinket() end
    function player:GetMaxHearts() return self.maxHearts end
    function player:AddMaxHearts(amount) self.maxHearts = self.maxHearts + amount end
    function player:AddHearts(amount) self.healed = amount end
    function player:AddCacheFlags(flags) self.cacheFlags = (self.cacheFlags or 0) | flags end
    function player:EvaluateItems()
        if (self.cacheFlags or 0) & env.CacheFlag.CACHE_SPEED ~= 0 then
            h.cacheCalls = h.cacheCalls + 1
            self.MoveSpeed = 1
            h.mod:OnEvaluateCache(self, env.CacheFlag.CACHE_SPEED)
        end
        self.cacheFlags = 0
    end
    function player:ToPlayer() return self end
    h.player, h.players = player, { player }
    local mod = {}
    function mod:AddCallback() end
    function mod:SaveData(value) h.saved = copy(value) end
    function mod:LoadData() return copy(h.saved) end
    function mod:HasData() return h.saved ~= nil end
    env.RegisterMod = function() return mod end
    env.include = function(path) return dofile("mods/glitched-crown-practice/content/" .. path .. ".lua") end
    env.require = function(name)
        assert(name == "json")
        return { encode = copy, decode = function(value)
            if value == "invalid json" then error("invalid JSON") end
            return copy(value)
        end }
    end
    env.Isaac = {
        GetItemConfig = function() return config end,
        GetPlayer = function(index) assert(h.players[index + 1], "invalid player index"); return h.players[index + 1] end,
        GetRoomEntities = function() return h.pickup and { player, h.pickup } or { player } end,
        GetScreenWidth = function() return 640 end,
        GetScreenHeight = function() return 480 end,
        GetTextWidth = function(value) return #value end,
        RenderText = function(value) h.renders[#h.renders + 1] = value end,
        Spawn = function()
            h.spawns = h.spawns + 1
            local generated = {}
            for i = 1, 5 do generated[i] = mod:OnGetCollectible() end
            local pickup = { InitSeed = h.spawns, Index = h.spawns, Type = 5,
                SubType = generated[1], generated = generated, exists = true }
            function pickup:ToPickup() return self end
            function pickup:Exists() return self.exists end
            function pickup:Remove() self.exists = false end
            h.pickup = pickup
            return pickup
        end,
    }
    assert(loadfile("mods/glitched-crown-practice/content/main.lua", "t", env))()
    h.mod, h.env, h.game = mod, env, game
    function h:tick(n) for _ = 1, n or 1 do self.mod:OnUpdate() end end
    function h:start(continued) self.mod:OnGameStarted(continued or false) end
    function h:ready()
        local oldSpawns = self.spawns
        for _ = 1, 250 do
            if self.spawns > oldSpawns then break end
            self:tick()
        end
        assert(self.spawns > oldSpawns, "round did not spawn")
        local ids = self.pickup.generated
        self.displayed = { ids[3], ids[5], ids[1], ids[4], ids[2] }
        for _, id in ipairs(self.displayed) do
            self.pickup.SubType = id; self.mod:OnPickupUpdate(self.pickup)
        end
        self.pickup.SubType = self.displayed[1]; self.mod:OnPickupUpdate(self.pickup)
        equal(self.mod:OnPickupCollision(self.pickup, self.player), nil, "ready uses native collision")
        self.target = self.displayed[1]
        return self.target
    end
    function h:queue(id)
        self.player.QueuedItem.Item = { ID = id, IsCollectible = function() return true end }
    end
    return h
end

local h = harness()
h:start()
equal(h.saved.schema, 2, "new sessions use save schema two")
equal(h.hudVisible, false, "practice hides native HUD")
h.paused = true; h:tick(500)
equal(h.spawns, 0, "pause freezes preparation")
h.paused = false; h:tick(7)
equal(h.spawns, 1, "new round spawns after preparation")
equal(h.player:GetMaxHearts(), 6, "converted characters receive health containers")
local initialSpeed, initialFloatCalls = h.player.MoveSpeed, h.floatCalls
equal(initialSpeed >= 0.70 and initialSpeed <= 2.00, true, "sampled speed applied to player")
equal(initialFloatCalls > 0, true, "first round samples speed")
h.player:AddCacheFlags(h.env.CacheFlag.CACHE_SPEED); h.player:EvaluateItems()
equal(h.player.MoveSpeed, initialSpeed, "speed survives cache evaluation")
equal(h.floatCalls, initialFloatCalls, "cache does not resample speed")
h.player.MoveSpeed = 1.19
h.mod:OnEvaluateCache(h.player, h.env.CacheFlag.CACHE_DAMAGE)
equal(h.player.MoveSpeed, 1.19, "unrelated cache flags do not set speed")
h.player:AddCacheFlags(h.env.CacheFlag.CACHE_SPEED); h.player:EvaluateItems()
equal(h.mod:OnGetCollectible(), nil, "generation override ends after five candidates")
equal(h.mod:OnPickupCollision(h.pickup, h.player), true, "calibration blocks collection")
h.paused = true; h:tick(500)
equal(h.spawns, 1, "pause freezes calibration timeout")
equal(h.floatCalls, initialFloatCalls, "pause does not resample speed")
equal(h.player.MoveSpeed, initialSpeed, "pause preserves current speed")
h.paused = false
local generated = h.pickup.generated
local order = { generated[3], generated[5], generated[1], generated[4], generated[2] }
for _, id in ipairs(order) do h.pickup.SubType = id; h.mod:OnPickupUpdate(h.pickup) end
h.pickup.SubType = order[1]; h.mod:OnPickupUpdate(h.pickup)
equal(h.mod:OnPickupCollision(h.pickup, h.player), nil, "completed calibration enables native pickup")
equal(h.targetPath, "item-" .. order[1] .. ".png", "target follows display order")
h.mod:OnRender()
local names = dofile("mods/glitched-crown-practice/content/scripts/items.lua")
local targetName = names[order[1]] and names[order[1]].zh
equal(type(targetName), "string", "target has a bundled Chinese name")
local nameDrawn, speedDrawn, plus2Drawn, minus2Drawn = false, false, false, false
for _, line in ipairs(h.renders) do
    if line:find(targetName, 1, true) then nameDrawn = true end
    if line:find(string.format("%.2f", initialSpeed), 1, true) then speedDrawn = true end
    if line:find("+2", 1, true) then plus2Drawn = true end
    if line:find("-2", 1, true) then minus2Drawn = true end
end
equal(nameDrawn, true, "target Chinese name is drawn alongside its sprite")
equal(speedDrawn, true, "HUD displays current player speed")
equal(plus2Drawn, true, "HUD displays two-step late count")
equal(minus2Drawn, true, "HUD displays two-step early count")
h:queue(order[2]); h.pickup.exists = false; h.pickup.SubType = 0; h:tick()
equal(h.saved.activeRun.stats.plus1, 1, "queue wins over missing/empty pedestal")
equal(h.saved.activeRun.stats.total, 1, "one result counted")
equal(h.saved.activeRun.speed, initialSpeed, "scored round saves its speed")
local completedRoundSave = copy(h.saved)
h:tick(2)
equal(h.saved.activeRun.stats.total, 1, "same queue is not counted twice")
h.paused = true; h:tick(100)
equal(h.spawns, 1, "pause freezes feedback wait")
equal(h.floatCalls, initialFloatCalls, "feedback pause does not resample speed")
h.paused = false; h:tick(43)
equal(h.spawns, 1, "result first transitions through cleanup")
h:tick(2)
equal(h.spawns, 2, "practice advances without an ending")
equal(h.floatCalls > initialFloatCalls, true, "scored result samples next round speed")
equal(h.player.MoveSpeed >= 0.70 and h.player.MoveSpeed <= 2.00, true, "next speed remains in bounds")
equal(h.player.QueuedItem.Item, nil, "previous queue cleared")
equal(h.player:GetCollectibleNum(order[2]), 0, "collected effect removed before next round")
equal(h.player:HasCollectible(h.env.CollectibleType.COLLECTIBLE_GLITCHED_CROWN), true, "native crown retained")

local save = copy(h.saved)
h.mod:OnExit(true)
equal(h.hudVisible, true, "exit restores HUD")
local exitsSpawns, exitDoors = h.spawns, h.doorsRemoved
h:tick(100)
equal(h.spawns, exitsSpawns, "exit leaves no active timer")
equal(h.doorsRemoved, exitDoors, "exit leaves no room mutations")
equal(h.mod:OnGetCollectible(), nil, "exit leaves no generation override")
equal(h.mod:OnPickupCollision(h.pickup, h.player), nil, "exit leaves no collision override")
local resumed = harness(save)
resumed:start(true)
equal(resumed.saved.activeRun.stats.plus1, 1, "continue preserves counter")
resumed:ready()
equal(resumed.player.MoveSpeed, save.activeRun.speed, "continue preserves current round speed")
equal(resumed.floatCalls, 0, "continue does not reroll saved speed")
resumed:queue(resumed.displayed[5]); resumed:tick()
equal(resumed.saved.activeRun.stats.minus1, 1, "continued wraparound early result")
equal(resumed.saved.activeRun.stats.total, 2, "continue preserves total")
invariant(resumed.saved.activeRun.stats)
resumed:start(false)
equal(resumed.saved.activeRun.stats.total, 0, "new run resets counters")
local resumedAfterResult = harness(completedRoundSave)
resumedAfterResult:start(true); resumedAfterResult:ready()
equal(resumedAfterResult.floatCalls > 0, true, "continue after a result samples the next round")
equal(resumedAfterResult.saved.activeRun.stats.total, 1, "continue after a result does not lose the score")
equal(resumedAfterResult.saved.activeRun.nextRound, false, "new round clears pending transition")

local legacySave = { schema = 1, activeRun = { seed = 123,
    stats = { total = 17, correct = 4, plus1 = 2, minus1 = 3, other = 8 } } }
local migrated = harness(legacySave)
migrated:start(true); migrated:ready()
equal(migrated.saved.schema, 2, "old session is saved in the new schema")
equal(migrated.saved.activeRun.stats.total, 17, "old session preserves total")
equal(migrated.saved.activeRun.stats.other, 8, "old two-step mistakes remain unknown")
equal(migrated.saved.activeRun.stats.plus2, 0, "old saves never invent late count")
equal(migrated.saved.activeRun.stats.minus2, 0, "old saves never invent early count")
equal(migrated.floatCalls > 0, true, "old session without speed samples once")
migrated:queue(migrated.displayed[3]); migrated:tick()
equal(migrated.saved.activeRun.stats.plus2, 1, "new late two-step result has its own counter")
migrated:ready(); migrated:queue(migrated.displayed[4]); migrated:tick()
equal(migrated.saved.activeRun.stats.minus2, 1, "new early two-step result has its own counter")
equal(migrated.saved.activeRun.stats.other, 8, "new results do not overwrite legacy unknowns")
invariant(migrated.saved.activeRun.stats)

for _, invalidSave in ipairs({ save, "invalid json", { schema = 9, activeRun = save.activeRun },
        { schema = 1, activeRun = "corrupt" } }) do
    local mismatch = harness(invalidSave, 999)
    mismatch:start(true); mismatch:tick(250)
    equal(mismatch.spawns, 0, "unrelated/corrupt continuation stays ordinary")
    equal(mismatch.hudVisible, true, "ordinary continuation retains HUD")
end
local challenge = harness(nil, 123, 5)
challenge:start(); challenge:tick(250)
equal(challenge.spawns, 0, "existing challenge modes are untouched")

local missing = harness()
missing:start(); missing:ready()
local retrySpeed, retryFloatCalls = missing.player.MoveSpeed, missing.floatCalls
missing.pickup.exists = false; missing:tick()
equal(missing.saved.activeRun.stats.total, 0, "disappearance is not a failed choice")
missing:ready()
equal(missing.saved.activeRun.stats.total, 0, "retry preserves zero count")
equal(missing.player.MoveSpeed, retrySpeed, "pedestal retry preserves speed")
equal(missing.floatCalls, retryFloatCalls, "pedestal retry does not resample speed")
local unrelated = { InitSeed = 999, Index = 999 }
equal(missing.mod:OnPickupCollision(unrelated, missing.player), true, "other collectibles blocked in training")
missing:queue(999); missing:tick()
equal(missing.saved.activeRun.stats.total, 0, "unrelated queued item retries without scoring")
missing.mod:OnExit(false)
equal(missing.saved.activeRun, nil, "discarded run clears persistence")
local ended = harness(save)
ended:start(true); ended.mod:OnGameEnd(); ended:tick(250)
equal(ended.saved.activeRun, nil, "game end clears persistence")
equal(ended.spawns, 0, "game end leaves no active stage")
equal(ended.hudVisible, true, "game end restores HUD")

local compoundCharacter = harness()
compoundCharacter.player.playerType = 77
compoundCharacter.players[2] = compoundCharacter.player
compoundCharacter.collapseSecondBody = true
compoundCharacter.player.active = { [0] = 75, [2] = 76 }
compoundCharacter:start(); compoundCharacter:tick(7)
equal(compoundCharacter.playerChanges, 1, "character conversion tolerates removed second body")
equal(compoundCharacter.player:GetActiveItem(0), 0, "normal active slot cleared")
equal(compoundCharacter.player:GetActiveItem(2), 0, "pocket active slot cleared")

print("Glitched Crown Practice: " .. count .. " assertions passed")
