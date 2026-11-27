-- Run from the repository root with Lua 5.3+ (or lupa's Lua 5.3 runtime).
-- The mocks exercise registered callbacks. The engine's callback timing and rendering
-- still need an in-game check.
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local POST_GET, NEW_ROOM, GAME_STARTED, PICKUP_UPDATE, PRE_GAME_EXIT = 1, 2, 3, 4, 5
local PRE_ENTITY_SPAWN, PRE_ROOM_ENTITY_SPAWN, USE_CARD, POST_UPDATE = 6, 7, 8, 9
local PICKUP, COLLECTIBLE = 5, 100
local POOL_NULL, TREASURE, SHOP, ROOM_SHOP = -1, 0, 1, 2
local LOW, Q1, Q2, Q3, Q4, HIDDEN, LOCKED = 1, 2, 3, 4, 5, 6, 7
local QUEST, HIGH_QUEST, UNKNOWN = 8, 9, 9999
local fixedPieces = {
    COLLECTIBLE_BUM_FRIEND = 10, COLLECTIBLE_DARK_BUM = 11, COLLECTIBLE_KEY_BUM = 12,
    COLLECTIBLE_NECRONOMICON = 13, COLLECTIBLE_MISSING_PAGE_2 = 14, COLLECTIBLE_LEO = 15,
}
local BIRTHRIGHT, BINGE_EATER, GLITCHED_CROWN = 619, 664, 689
local SOUL_ISAAC = 81
local ISAAC, MAGDALENE, TAINTED_ISAAC = 0, 1, 21
local collectibleTypes = {
    COLLECTIBLE_NULL = 0, COLLECTIBLE_BIRTHRIGHT = BIRTHRIGHT,
    COLLECTIBLE_BINGE_EATER = BINGE_EATER, COLLECTIBLE_GLITCHED_CROWN = GLITCHED_CROWN,
}
for name, id in pairs(fixedPieces) do collectibleTypes[name] = id end
local itemTags = {
    TAG_SYRINGE = 1 << 1, TAG_MOM = 1 << 2, TAG_GUPPY = 1 << 5, TAG_FLY = 1 << 6,
    TAG_BOB = 1 << 7, TAG_MUSHROOM = 1 << 8, TAG_BABY = 1 << 9, TAG_ANGEL = 1 << 10,
    TAG_DEVIL = 1 << 11, TAG_POOP = 1 << 12, TAG_BOOK = 1 << 13, TAG_SPIDER = 1 << 14,
    TAG_QUEST = 1 << 15, TAG_NO_GREED = 1 << 17, TAG_FOOD = 1 << 18,
}

local function loadMod(draws, setup, options)
    options = options or {}
    local h = {
        callbacks = {}, pickups = {}, draws = draws or {}, calls = {}, roomPool = SHOP, players = {},
        removed = {}, absentFromPool = {}, startSeed = options.startSeed or 123, storage = options.storage or {},
        roomSeed = 456, roomDesc = { SafeGridIndex = 10, Data = { Name = "Shop" } },
    }
    local config = {}
    local function addItem(quality, tags, hidden, achievement, available)
        local id = #config + 1
        config[id] = {
            ID = id, Quality = quality, Tags = tags or 0, Hidden = hidden or false,
            AchievementID = achievement or -1, Available = available ~= false,
            IsAvailable = function(item) return item.Available end,
            IsCollectible = function() return true end,
            HasTags = function(item, mask) return item.Tags & mask ~= 0 end,
        }
        return id
    end
    for quality = 0, 4 do addItem(quality) end
    addItem(4, 0, true)
    addItem(3, 0, false, 1, false)
    addItem(0, itemTags.TAG_QUEST)
    addItem(4, itemTags.TAG_QUEST)
    for quality = 0, 2 do addItem(quality) end
    addItem(1)
    addItem(0)
    addItem(1)
    if setup then
        setup(addItem, config)
    end
    local pool = {
        GetPoolForRoom = function(_, roomType, seed)
            equal(roomType, ROOM_SHOP, "lookup uses current room type")
            equal(seed, h.roomSeed, "lookup uses current room seed")
            return h.roomPool
        end,
        GetCollectible = function(_, poolType, decrease, seed)
            assert(#h.calls < 100, "replacement draws must be bounded and protected from recursion")
            equal(decrease, false, "replacement probe does not decrease pool weights")
            assert(seed > 0, "replacement draws use a nonzero seed")
            h.calls[#h.calls + 1] = { pool = poolType, seed = seed }
            local selected = h.draws[#h.calls] or LOW
            return h.run(POST_GET, selected, poolType, decrease, seed) or selected
        end,
        RemoveCollectible = function(_, id)
            h.removed[#h.removed + 1] = id
            return not h.absentFromPool[id]
        end,
    }
    local room = {
        GetType = function() return ROOM_SHOP end,
        GetSpawnSeed = function() return h.roomSeed end,
    }
    local level = {
        GetCurrentRoomDesc = function() return h.roomDesc end,
        GetRoomByIdx = function(_, index, dimension)
            assert(index == h.roomDesc.SafeGridIndex and dimension == 2, "unexpected room index or dimension")
            return h.deathCertificateRoom or {}
        end,
    }
    local itemConfig = {
        GetCollectible = function(_, id) return config[id] end,
        GetCollectibles = function()
            return { Size = #config + 1 }
        end,
    }
    local mod = {}
    function mod:HasData() return h.storage.value ~= nil end
    function mod:LoadData() return h.storage.value end
    function mod:SaveData(value)
        equal(type(value), "string", "run history is serialized")
        h.storage.value = value
    end
    local function encodeHistory(data)
        return data.seed .. ":" .. table.concat(data.items, ",")
    end
    local function decodeHistory(raw)
        local seed, list = raw:match("^(%d+):([%d,]*)$")
        assert(seed, "invalid mock save")
        local items = {}
        for id in list:gmatch("%d+") do items[#items + 1] = tonumber(id) end
        return { seed = tonumber(seed), items = items }
    end
    local function addCallback(_, callback, fn, filter)
        assert(h.callbacks[callback] == nil, "callback registered twice")
        h.callbacks[callback] = { fn = fn, filter = filter }
    end
    mod.AddCallback = addCallback
    h.run = function(callback, ...)
        return assert(h.callbacks[callback], "callback missing").fn(mod, ...)
    end
    local env = setmetatable({
        ModCallbacks = {
            MC_POST_GET_COLLECTIBLE = POST_GET, MC_POST_NEW_ROOM = NEW_ROOM,
            MC_POST_GAME_STARTED = GAME_STARTED, MC_POST_PICKUP_UPDATE = PICKUP_UPDATE,
            MC_PRE_GAME_EXIT = PRE_GAME_EXIT, MC_PRE_ENTITY_SPAWN = PRE_ENTITY_SPAWN,
            MC_PRE_ROOM_ENTITY_SPAWN = PRE_ROOM_ENTITY_SPAWN, MC_USE_CARD = USE_CARD,
            MC_POST_UPDATE = POST_UPDATE,
        },
        EntityType = { ENTITY_PICKUP = PICKUP },
        PickupVariant = { PICKUP_COLLECTIBLE = COLLECTIBLE },
        CollectibleType = collectibleTypes,
        PlayerType = { PLAYER_ISAAC = ISAAC, PLAYER_MAGDALENE = MAGDALENE, PLAYER_ISAAC_B = TAINTED_ISAAC },
        Card = { CARD_SOUL_ISAAC = SOUL_ISAAC },
        ItemPoolType = { POOL_TREASURE = TREASURE, POOL_SHOP = SHOP, POOL_NULL = POOL_NULL },
        ItemConfig = itemTags,
        require = function(name)
            assert(name == "json", "unexpected module " .. name)
            return { encode = encodeHistory, decode = decodeHistory }
        end,
        RegisterMod = function(name, api)
            equal(name, "假如我直接赢", "display name")
            equal(api, 1, "mod API")
            return mod
        end,
        Game = function()
            return {
                GetItemPool = function() return pool end,
                GetRoom = function() return room end,
                GetLevel = function() return level end,
                GetNumPlayers = function() return #h.players end,
                GetSeeds = function() return { GetStartSeed = function() return h.startSeed end } end,
            }
        end,
        Isaac = {
            GetItemConfig = function() return itemConfig end,
            GetPlayer = function(index) return assert(h.players[index + 1], "player missing") end,
            FindByType = function(entityType, variant)
                equal(entityType, PICKUP, "scan pickup entities")
                equal(variant, COLLECTIBLE, "scan collectible pedestals")
                return h.pickups
            end,
        },
        GetPtrHash = function(object) return object end,
        RNG = function()
            local seed = 1
            local function nextValue()
                seed = (seed % 2147483646 * 48271) % 2147483647
                return seed
            end
            return {
                SetSeed = function(_, value) seed = value end,
                Next = nextValue,
                RandomInt = function(_, maximum) return nextValue() % maximum end,
                RandomFloat = function() return nextValue() / 2147483647 end,
            }
        end,
    }, { __index = _G })
    assert(loadfile("mods/just-win/content/main.lua", "t", env))()
    h.config = config
    return h
end

local function pedestal(id)
    local data = {}
    local pickup = {
        SubType = id, InitSeed = 123456,
        Price = 15, OptionsPickupIndex = 9, AutoUpdatePrice = false, ShopItemId = 2, Touched = true,
        Wait = 20, Timeout = 100,
        morphs = 0,
    }
    function pickup:ToPickup() return self end
    function pickup:GetData() return data end
    function pickup:Morph(entityType, variant, replacement, keepPrice, keepSeed, ignoreModifiers)
        equal(entityType, PICKUP, "morph stays a pickup")
        equal(variant, COLLECTIBLE, "morph stays a collectible pedestal")
        equal(keepPrice, true, "morph keeps price")
        equal(keepSeed, true, "morph keeps seed")
        equal(ignoreModifiers, false, "morph leaves engine item modifiers enabled")
        self.SubType, self.morphs = replacement, self.morphs + 1
        self.nativeChoices = nil
        self.Price, self.OptionsPickupIndex, self.AutoUpdatePrice, self.ShopItemId = 0, 0, true, -1
        self.Wait, self.Timeout = 0, -1
    end
    return pickup
end

local function player(playerType, heldItem)
    local data = {}
    return {
        QueuedItem = {},
        inventory = heldItem and { [heldItem] = true } or {},
        effects = {},
        GetData = function() return data end,
        GetPlayerType = function() return playerType end,
        HasCollectible = function(self, item, ignoreModifiers)
            return self.inventory[item] == true or (not ignoreModifiers and self.effects[item] == true)
        end,
    }
end

for _, low in ipairs({ LOW, Q1, Q2 }) do
    local h = loadMod({ LOW, Q2, Q3 })
    equal(h.run(POST_GET, low, TREASURE, true, 872), Q3, "all low pool draws are upgraded")
    equal(#h.calls, 3, "replacement iterates past low candidates")
    for _, call in ipairs(h.calls) do equal(call.pool, TREASURE, "provided item pool is preserved") end
end

local pass = loadMod()
for _, id in ipairs({ Q3, Q4 }) do
    equal(pass.run(POST_GET, id, SHOP, true, 872) or id, id, "high-quality pool draw is unchanged")
end
equal(pass.run(POST_GET, QUEST, SHOP, true, 872) or QUEST, QUEST,
    "low-quality progression item is unchanged in the item pool")
for _, id in pairs(fixedPieces) do
    equal(pass.run(POST_GET, id, SHOP, true, 872) or id, id,
        "named pieces of fixed combinations are unchanged")
end
equal(#pass.calls, 0, "valid draws do not roll replacements")

local play = loadMod({ Q4, Q3, Q4 })
local starting, good, empty, unknown = pedestal(Q2), pedestal(Q3), pedestal(0), pedestal(UNKNOWN)
local quest, fixed = pedestal(QUEST), pedestal(fixedPieces.COLLECTIBLE_NECRONOMICON)
play.pickups = { starting, good, empty, unknown, quest, fixed }
play.run(GAME_STARTED, false)
equal(starting.SubType, Q4, "game-start sweep replaces low starting pedestal")
equal(starting.Price, 15, "shop price survives replacement")
equal(starting.OptionsPickupIndex, 9, "choice group survives replacement")
equal(starting.AutoUpdatePrice, false, "manual price survives replacement")
equal(starting.ShopItemId, 2, "shop slot survives replacement")
equal(starting.Wait, 20, "pickup delay survives replacement")
equal(starting.Timeout, 100, "pickup timeout survives replacement")
equal(starting.Touched, false, "replacement starts untaken")
for _, pickup in ipairs({ good, empty, unknown, quest, fixed }) do
    equal(pickup.morphs, 0, "valid, empty, unknown, quest and fixed-piece pedestals are unchanged")
end
local roomItem = pedestal(LOW)
play.pickups = { starting }
play.run(NEW_ROOM)
equal(starting.morphs, 1, "returning to a room does not reroll a valid replacement")
play.roomSeed = 457
play.pickups = { roomItem }
play.run(NEW_ROOM)
equal(roomItem.SubType, Q3, "room entry replaces a fixed low-quality pedestal")
equal(play.calls[2].pool, SHOP, "fixed pedestals use the current room pool")
roomItem.SubType = Q1
equal(play.callbacks[PICKUP_UPDATE].filter, COLLECTIBLE, "update is filtered to collectible pickups")
play.run(PICKUP_UPDATE, roomItem)
equal(roomItem.SubType, Q4, "pickup update replaces a later low-quality reroll")

local spawn = loadMod({ Q3, Q3, Q4 })
spawn.players = { player(ISAAC, BIRTHRIGHT) }
local layout = spawn.run(PRE_ROOM_ENTITY_SPAWN, PICKUP, COLLECTIBLE, LOW, 50, 10031)
equal(#layout, 3, "layout spawn override contains the expected fields")
equal(layout[1], PICKUP, "layout spawn keeps entity type")
equal(layout[2], COLLECTIBLE, "layout spawn keeps variant")
equal(layout[3], Q3, "layout spawn upgrades a fixed low item before pickup creation")
local spawned = spawn.run(PRE_ENTITY_SPAWN, PICKUP, COLLECTIBLE, Q1, nil, nil, nil, 10032)
equal(#spawned, 4, "dynamic spawn override contains the expected fields")
equal(spawned[1], PICKUP, "dynamic spawn keeps entity type")
equal(spawned[2], COLLECTIBLE, "dynamic spawn keeps variant")
equal(spawned[3], Q4, "dynamic spawn upgrades a fixed low item before pickup creation")
equal(spawned[4], 10032, "dynamic spawn preserves original seed")
equal(#spawn.calls, 3, "a static replacement cannot be reselected for another pedestal in the room")
for _, id in ipairs({ 0, Q3, QUEST, UNKNOWN }) do
    equal(spawn.run(PRE_ROOM_ENTITY_SPAWN, PICKUP, COLLECTIBLE, id, 50, 10031), nil,
        "layout leaves random placeholder and protected IDs native")
    equal(spawn.run(PRE_ENTITY_SPAWN, PICKUP, COLLECTIBLE, id, nil, nil, nil, 10032), nil,
        "dynamic spawn leaves random placeholder and protected IDs native")
end
equal(spawn.run(PRE_ENTITY_SPAWN, PICKUP, 20, LOW, nil, nil, nil, 10032), nil,
    "dynamic spawn filters out other pickup variants")
equal(spawn.run(PRE_ROOM_ENTITY_SPAWN, 99, COLLECTIBLE, LOW, 50, 10031), nil,
    "layout spawn filters out other entity types")

local cycleCases = {
    { name = "Isaac Birthright", owner = player(ISAAC, BIRTHRIGHT), alternates = { Q2 } },
    { name = "Binge Eater", owner = player(MAGDALENE, BINGE_EATER), alternates = { Q1 } },
    { name = "Glitched Crown", owner = player(MAGDALENE, GLITCHED_CROWN), alternates = { Q2, Q4, LOW, Q3 } },
    { name = "Tainted Isaac", owner = player(TAINTED_ISAAC), alternates = { LOW } },
}
for _, case in ipairs(cycleCases) do
    local active = loadMod({ Q4 }, function(_, config) config[Q1].Tags = itemTags.TAG_FOOD end)
    active.players = { player(MAGDALENE), case.owner }
    local primary = active.run(POST_GET, LOW, SHOP, true, 901)
    equal(primary, Q4, case.name .. " still upgrades pooled low draws")
    local cycling = pedestal(primary)
    cycling.nativeChoices = { primary, table.unpack(case.alternates) }
    active.pickups = { cycling }
    active.run(GAME_STARTED, false)
    for _, id in ipairs(case.alternates) do
        cycling.SubType = id
        active.run(PICKUP_UPDATE, cycling)
        equal(cycling.SubType, id, case.name .. " keeps the native alternate visible")
    end
    active.players[2] = nil
    cycling.SubType = case.alternates[1]
    active.run(NEW_ROOM)
    active.run(PICKUP_UPDATE, cycling)
    equal(cycling.SubType, case.alternates[1], case.name .. " existing alternate survives losing its effect")
    equal(#cycling.nativeChoices, #case.alternates + 1, case.name .. " retains the native cycle")
    equal(cycling.morphs, 0, case.name .. " cycle is left intact")
end

local otherBirthright = loadMod({ Q3 })
otherBirthright.players = { player(MAGDALENE, BIRTHRIGHT) }
local static = pedestal(LOW)
otherBirthright.run(PICKUP_UPDATE, static)
equal(static.SubType, Q3, "non-Isaac Birthright does not bypass the static-pedestal fallback")

local soul = loadMod({ Q4 })
local cardCycle = pedestal(Q3)
soul.pickups = { cardCycle }
equal(soul.callbacks[USE_CARD].filter, SOUL_ISAAC, "card callback only covers Soul of Isaac")
soul.run(USE_CARD, SOUL_ISAAC, player(ISAAC))
cardCycle.SubType = Q2
soul.run(PICKUP_UPDATE, cardCycle)
equal(cardCycle.SubType, Q2, "Soul of Isaac's alternate survives after the consumable is gone")
equal(cardCycle.morphs, 0, "Soul of Isaac cycle is left intact")
local afterCard = pedestal(LOW)
soul.run(PICKUP_UPDATE, afterCard)
equal(afterCard.SubType, Q4, "a separate pedestal spawned later still receives the static fallback")

local extension = loadMod()
local extensionCycle = pedestal(Q2)
function extensionCycle:GetCollectibleCycle() return { Q3 } end
extension.run(PICKUP_UPDATE, extensionCycle)
equal(extensionCycle.SubType, Q2, "extension-reported alternate protects the native cycle")
equal(extensionCycle.morphs, 0, "extension-reported cycle is left intact")

local previews = loadMod({ Q3, Q4 })
equal(previews.run(POST_GET, Q3, SHOP, false, 872), nil, "an ordinary preview can inspect an unused item")
equal(previews.run(POST_GET, Q3, SHOP, true, 872), nil, "the preview does not reserve that item")
equal(previews.run(POST_GET, Q3, TREASURE, false, 872), Q4,
    "an ordinary preview respects reservations even when it looks in another pool")
equal(previews.run(POST_GET, Q4, SHOP, true, 872), nil, "a replacement preview does not reserve its result")
previews.roomSeed = 457
equal(previews.run(POST_GET, Q3, SHOP, true, 872), nil, "an uncollected offer remains available in another room")
previews.roomSeed = 456
equal(previews.run(POST_GET, Q3, SHOP, true, 872), LOCKED,
    "revisiting a room retains existing offers and opens unused locked candidates")
equal(#previews.removed, 0, "reserving a room offer does not perform global removal")
previews.run(PRE_GAME_EXIT, true)
previews.run(GAME_STARTED, true)
equal(previews.run(POST_GET, Q3, SHOP, true, 872), nil, "room reservations are transient across exit and Continue")

local visible = loadMod({ Q3, Q4 })
local lowPedestal = pedestal(LOW)
local visiblePedestal = pedestal(Q3)
visible.pickups = { lowPedestal, visiblePedestal }
visible.run(NEW_ROOM)
equal(lowPedestal.SubType, Q4, "the room sweep reserves existing IDs before replacing the first low pedestal")
equal(visible.run(POST_GET, Q3, SHOP, true, 872), LOCKED,
    "an existing visible pedestal reserves its ID before any item is picked up")
equal(visiblePedestal.morphs, 0, "reserving an existing high-quality pedestal does not modify it")

local crown = loadMod({ Q3 }, function(add)
    add(4)
    add(3)
end)
crown.players = { player(MAGDALENE, GLITCHED_CROWN) }
local crownOptions = {}
local crownSeen = {}
for slot = 1, 5 do
    crown.calls = {}
    local id = crown.run(POST_GET, Q3, SHOP, false, 872) or Q3
    equal(crownSeen[id], nil, "Glitched Crown uses five distinct options despite forced repeats and an identical seed")
    equal(crown.config[id].Quality >= 3, true, "Glitched Crown options keep the quality filter")
    crownSeen[id] = true
    crownOptions[slot] = id
end
equal(crownSeen[LOCKED], true, "Glitched Crown uses a remaining locked option when necessary")
local generatedCycle = pedestal(crownOptions[1])
generatedCycle.nativeChoices = crownOptions
for _, id in ipairs(crownOptions) do
    generatedCycle.SubType = id
    crown.run(PICKUP_UPDATE, generatedCycle)
    equal(generatedCycle.SubType, id, "native rotation visits each generated option without replacement")
end
equal(generatedCycle.morphs, 0, "creating distinct options leaves the native cycle intact")

local certificate = loadMod({ Q4 })
certificate.roomDesc.Data.Name = "Death Certificate"
equal(certificate.run(POST_GET, LOW, SHOP, true, 872), nil, "Death Certificate's native draw bypasses filtering")
equal(certificate.run(PRE_ROOM_ENTITY_SPAWN, PICKUP, COLLECTIBLE, LOW, 50, 10031), nil,
    "Death Certificate's room-layout exhibitions keep their original IDs")
equal(certificate.run(PRE_ENTITY_SPAWN, PICKUP, COLLECTIBLE, LOW, nil, nil, nil, 10032), nil,
    "Death Certificate's later pickups also bypass replacement")
local exhibits = { pedestal(LOW), pedestal(Q3) }
certificate.pickups = exhibits
certificate.run(NEW_ROOM)
certificate.run(PICKUP_UPDATE, exhibits[1])
equal(exhibits[1].SubType, LOW, "Death Certificate's low-quality exhibit stays selectable")
equal(exhibits[1].morphs, 0, "room and pickup checks leave the exhibit intact")
equal(#certificate.calls, 0, "exhibits do not consume replacement attempts")
certificate.roomDesc.Data.Name = "Another exhibition room"
certificate.deathCertificateRoom = certificate.roomDesc
equal(certificate.run(POST_GET, LOW, SHOP, true, 872), nil, "Death Certificate dimension works with another room name")
certificate.roomDesc = { SafeGridIndex = 10, Data = { Name = "Shop" } }
equal(certificate.run(POST_GET, Q3, SHOP, true, 872), nil, "exhibits do not reserve items for ordinary generation")
equal(certificate.run(POST_GET, LOW, SHOP, true, 872), Q4,
    "an ordinary room sharing the exhibition grid index still filters its draws")

local noRoomPool = loadMod({ Q3 })
noRoomPool.roomPool = POOL_NULL
noRoomPool.run(PICKUP_UPDATE, pedestal(LOW))
equal(noRoomPool.calls[1].pool, TREASURE, "rooms without a pool use the treasure pool")

local members = {}
local transformations = loadMod({}, function(add)
    add(4, itemTags.TAG_GUPPY)
    add(3, itemTags.TAG_GUPPY)
    add(4, itemTags.TAG_GUPPY, false, 2, false)
    members.guppyQ2a = add(2, itemTags.TAG_GUPPY)
    members.guppyQ2b = add(2, itemTags.TAG_GUPPY | itemTags.TAG_MUSHROOM)
    members.guppyQ1 = add(1, itemTags.TAG_GUPPY)
    add(4, itemTags.TAG_MUSHROOM)
    add(3, itemTags.TAG_MUSHROOM)
    add(3, itemTags.TAG_MUSHROOM)
    members.mushroomQ2 = add(2, itemTags.TAG_MUSHROOM)
    add(4, itemTags.TAG_MOM)
    add(3, itemTags.TAG_MOM, true)
    members.momQ2 = add(2, itemTags.TAG_MOM)
    add(2, itemTags.TAG_BOB)
    add(1, itemTags.TAG_BOB)
    members.bobQ0 = add(0, itemTags.TAG_BOB)
end)
for _, id in ipairs({ members.guppyQ2a, members.guppyQ2b, members.bobQ0, members.momQ2 }) do
    equal(transformations.run(POST_GET, id, SHOP, true, 872) or id, id,
        "needed transformation members are unchanged, including Q0 and quality ties")
end
equal(#transformations.calls, 0, "preserving needed transformation members does not probe pools")
transformations.draws = { members.guppyQ2a, Q3 }
equal(transformations.run(POST_GET, members.guppyQ1, SHOP, true, 872), Q3,
    "needed low-quality pieces are never substitutes for other items")
for _, id in ipairs({ members.guppyQ1, members.mushroomQ2 }) do
    local replacement = transformations.run(POST_GET, id, SHOP, true, 872)
    equal(replacement ~= nil and transformations.config[replacement].Quality >= 3, true,
        "weaker or unneeded transformation members are upgraded")
end
local neededPedestal = pedestal(members.guppyQ2a)
transformations.pickups = { neededPedestal }
transformations.run(NEW_ROOM)
equal(neededPedestal.morphs, 0, "fixed transformation member survives room entry")

local fallback = loadMod({ HIDDEN, LOCKED, HIGH_QUEST }, function(_, config)
    config[Q3].Hidden = true
    config[LOCKED].AchievementID = -1
end)
equal(fallback.run(POST_GET, LOW, SHOP, false, 872), Q4,
    "fallback excludes hidden, locked, quest, and low-quality collectibles")
local restricted = loadMod({}, function(_, config)
    config[Q3].Hidden = true
    config[LOCKED].Hidden = true
    config[Q4].Available = false
end)
equal(restricted.run(POST_GET, LOW, SHOP, false, 872), Q4,
    "restricted pools can fall back to items without an achievement unlock")
local repeated = loadMod()
local firstChoice = repeated.run(POST_GET, LOW, SHOP, false, 872)
equal(repeated.run(POST_GET, LOW, SHOP, false, 872), firstChoice,
    "fallback is stable for the same seed")

local restrictedToLocked = loadMod({ LOW }, function(_, config)
    config[Q3].Hidden = true
    config[Q4].Available = false
end)
equal(restrictedToLocked.run(POST_GET, LOW, SHOP, true, 872), LOCKED,
    "a low-unlock pool with no available high-quality picks uses a locked item")
equal(restrictedToLocked.config[LOCKED].Available, false, "an injected item remains locked in the save")

local lockedAlternates = loadMod({}, function(add, config)
    config[Q3].Hidden = true
    config[Q4].Hidden = true
    add(3, 0, false, 2, false)
    add(4, 0, false, 3, false)
end)
local lockedSeen = {}
for _ = 1, 3 do
    local id = assert(lockedAlternates.run(POST_GET, LOW, SHOP, true, 872), "missing locked alternative")
    equal(lockedSeen[id], nil, "fresh-save locked supplementation skips an already offered candidate")
    equal(lockedAlternates.config[id].Available, false, "a locked option stays locked in the profile")
    lockedSeen[id] = true
end
equal(lockedAlternates.run(POST_GET, LOW, SHOP, true, 872), nil,
    "an exhausted room does not draw again from already offered locked candidates")
equal(#lockedAlternates.removed, 0, "uncollected locked offers do not modify the native item pool")

local additionalLocked
local fresh = loadMod({ Q4 }, function(add)
    additionalLocked = add(4, 0, false, 2, false)
    add(4, 0, true, 3, false)
    add(4, itemTags.TAG_QUEST, false, 4, false)
    add(2, 0, false, 5, false)
end)
local chosen = {}
local firstLockedSeed
for step = 1, 20 do
    fresh.calls = {}
    local seed = step * 1000003
    local id = fresh.run(POST_GET, LOW, SHOP, false, seed)
    assert(id == Q4 or id == LOCKED or id == additionalLocked, "unexpected low-unlock candidate")
    chosen[id] = true
    if id ~= Q4 then firstLockedSeed = firstLockedSeed or seed end
end
equal(chosen[Q4] == true, true, "low-unlock profile also samples ordinary room pool")
equal(chosen[LOCKED] or chosen[additionalLocked], true, "low-unlock profile samples locked items")
local established = loadMod({ Q4 })
equal(established.run(POST_GET, LOW, SHOP, true, firstLockedSeed), Q4,
    "a profile with exactly two thirds available does not sample locked items")
fresh.config[additionalLocked].Available = true
fresh.calls = {}
fresh.run(PRE_GAME_EXIT, true)
equal(fresh.run(POST_GET, LOW, SHOP, false, firstLockedSeed), Q4,
    "pool rules rebuild for the next profile before game-start callback")
fresh.config[additionalLocked].Available = false
fresh.run(GAME_STARTED, true)
fresh.calls = {}
local afterContinue = fresh.run(POST_GET, LOW, SHOP, true, firstLockedSeed)
equal(afterContinue == LOCKED or afterContinue == additionalLocked, true,
    "continuing a game refreshes the profile's available candidates")

local extraGuppyPiece
local freshTransformation = loadMod({ Q4 }, function(add)
    add(4, itemTags.TAG_GUPPY)
    add(3, itemTags.TAG_GUPPY)
    add(3, itemTags.TAG_GUPPY, false, 2, false)
    add(4, 0, false, 3, false)
    extraGuppyPiece = add(2, itemTags.TAG_GUPPY)
end)
local freshReplacement = freshTransformation.run(POST_GET, extraGuppyPiece, SHOP, true, 872)
equal(freshReplacement ~= nil and freshTransformation.config[freshReplacement].Quality >= 3, true,
    "a supplemental locked high-quality item can complete a transformation's three pieces")

local acquired = loadMod({ Q3, Q4 })
local firstPlayer, secondPlayer = player(ISAAC), player(MAGDALENE)
acquired.players = { firstPlayer, secondPlayer }
acquired.run(GAME_STARTED, false)
local existing = pedestal(Q3)
acquired.run(PICKUP_UPDATE, existing)
acquired.run(POST_UPDATE)
equal(#acquired.removed, 0, "a touched but uncollected pedestal does not remove items from the pool")
secondPlayer.QueuedItem.Item = { ID = Q3, IsCollectible = function() return false end }
acquired.run(POST_UPDATE)
equal(#acquired.removed, 0, "a trinket with the same ID does not remove a collectible")
secondPlayer.QueuedItem.Item = acquired.config[Q3]
acquired.run(POST_UPDATE)
equal(#acquired.removed, 0, "a queued collectible stays in the pool during the pickup animation")
secondPlayer.QueuedItem.Item = nil
secondPlayer.inventory[Q3] = true
acquired.run(POST_UPDATE)
equal(acquired.removed[1], Q3, "a co-op player's completed pickup is removed from the native pool")
firstPlayer.QueuedItem.Item = acquired.config[Q3]
acquired.run(POST_UPDATE)
acquired.run(POST_UPDATE)
firstPlayer.QueuedItem.Item = nil
firstPlayer.inventory[Q3] = true
acquired.run(POST_UPDATE)
equal(#acquired.removed, 1, "repeated animation ticks and co-op pickups share the same exclusion")
equal(acquired.run(POST_GET, Q3, SHOP, true, 872), Q4,
    "a forced natural draw of a picked item is replaced, skipping the same candidate during probes")
equal(#acquired.calls, 2, "the native probe skipped the collected first candidate")
acquired.calls, acquired.draws = {}, {}
acquired.roomSeed = 457
equal(acquired.run(POST_GET, LOW, SHOP, false, 872), Q4,
    "available fallback candidates exclude the picked item")
equal(acquired.run(PRE_ENTITY_SPAWN, PICKUP, COLLECTIBLE, Q3, nil, nil, nil, 10032), nil,
    "fixed drops and active swaps are preserved when their item was previously collected")
acquired.pickups = { existing }
acquired.run(NEW_ROOM)
equal(existing.SubType, Q3, "a previously spawned pedestal stays in place even if the same item was acquired")
acquired.calls = {}
acquired.roomSeed = 458
equal(acquired.run(POST_GET, Q3, SHOP, true, 872), Q4,
    "a room transition in the same run retains the exclusion")
acquired.run(PRE_GAME_EXIT, true)

local continuation = loadMod({ Q4 }, nil, { storage = acquired.storage, startSeed = acquired.startSeed })
equal(continuation.run(POST_GET, Q3, SHOP, true, 872), Q4,
    "continued room generation sees the saved history before the game-start callback")
continuation.run(GAME_STARTED, true)
equal(continuation.removed[1], Q3, "continuing reapplies exclusions to the native item pool")
equal(#continuation.removed, 1, "continuing reapplies each saved ID exactly once")
local unrelated = loadMod({}, nil, { storage = acquired.storage, startSeed = acquired.startSeed + 1 })
equal(unrelated.run(POST_GET, Q3, SHOP, true, 872), nil,
    "a different run seed ignores the prior pickup history")
local malformedSave = loadMod({}, nil, { storage = { value = "corrupt" } })
equal(malformedSave.run(POST_GET, Q3, SHOP, true, 872), nil,
    "malformed pickup history does not corrupt the item pool")
continuation.run(PRE_GAME_EXIT, false)
continuation.run(GAME_STARTED, false)
equal(continuation.run(POST_GET, Q3, SHOP, true, 872), nil,
    "a new run can find the item again even when it reuses the same seed")

local canceled = loadMod()
local interrupted = player(ISAAC)
canceled.players = { interrupted }
interrupted.QueuedItem.Item = canceled.config[Q3]
canceled.run(POST_UPDATE)
interrupted.QueuedItem.Item = nil
interrupted.effects[Q3] = true
canceled.run(POST_UPDATE)
equal(#canceled.removed, 0, "an aborted pickup does not remove the item even if a temporary effect grants it")
equal(canceled.run(POST_GET, Q3, SHOP, true, 872), nil,
    "an aborted pickup leaves the collectible eligible in later draws")

local lastPickup = loadMod()
local swapping = player(ISAAC, Q3)
lastPickup.players = { swapping }
swapping.QueuedItem.Item = lastPickup.config[Q3]
lastPickup.run(POST_UPDATE)
equal(#lastPickup.removed, 0, "a same-item active swap waits for the pickup animation to end")
swapping.QueuedItem.Item = lastPickup.config[Q4]
lastPickup.run(POST_UPDATE)
equal(lastPickup.removed[1], Q3, "a completed active swap is recorded when another item enters the queue")
equal(#lastPickup.removed, 1, "the new queued item is still pending")
swapping.QueuedItem.Item = nil
swapping.inventory[Q4] = true
lastPickup.run(PRE_GAME_EXIT, true)
equal(lastPickup.removed[2], Q4, "exiting to a continuable save records a completed pickup before saving")

local function pick(harness, id)
    harness.players[1] = harness.players[1] or player(ISAAC)
    local collector = harness.players[1]
    collector.QueuedItem.Item = harness.config[id]
    harness.run(POST_UPDATE)
    collector.QueuedItem.Item = nil
    collector.inventory[id] = true
    harness.run(POST_UPDATE)
end

local exhausted = loadMod()
pick(exhausted, Q3)
pick(exhausted, Q4)
equal(exhausted.run(POST_GET, LOW, SHOP, true, 872), LOCKED,
    "remaining locked high-quality items are eligible after ordinary choices are exhausted")
exhausted.absentFromPool[LOCKED] = true
pick(exhausted, LOCKED)
equal(exhausted.removed[3], LOCKED, "an injected locked collectible is still sent to the native removal API")
equal(exhausted.run(POST_GET, LOW, SHOP, true, 872), nil,
    "an injected collectible cannot be selected again if native removal reports it absent")

local restrictedHistory = loadMod({}, function(_, config)
    config[LOCKED].Hidden = true
    config[Q3].Available = false
end)
pick(restrictedHistory, Q4)
equal(restrictedHistory.run(POST_GET, LOW, SHOP, true, 872), Q3,
    "a restricted high-quality candidate can still be picked when the ordinary pool is exhausted")
pick(restrictedHistory, Q3)
equal(restrictedHistory.run(POST_GET, LOW, SHOP, true, 872), nil,
    "restricted fallback also excludes acquired items when no eligible alternatives remain")

print("Just Win: " .. checks .. " checks passed")
