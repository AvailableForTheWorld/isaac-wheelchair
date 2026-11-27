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
local PRE_ENTITY_SPAWN, PRE_ROOM_ENTITY_SPAWN, USE_CARD = 6, 7, 8
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

local function loadMod(draws, setup)
    local h = { callbacks = {}, pickups = {}, draws = draws or {}, calls = {}, roomPool = SHOP, players = {} }
    local config = {}
    local function addItem(quality, tags, hidden, achievement, available)
        local id = #config + 1
        config[id] = {
            ID = id, Quality = quality, Tags = tags or 0, Hidden = hidden or false,
            AchievementID = achievement or -1, Available = available ~= false,
            IsAvailable = function(item) return item.Available end,
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
            equal(seed, 456, "lookup uses current room seed")
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
    }
    local room = {
        GetType = function() return ROOM_SHOP end,
        GetSpawnSeed = function() return 456 end,
    }
    local itemConfig = {
        GetCollectible = function(_, id) return config[id] end,
        GetCollectibles = function()
            return { Size = #config + 1 }
        end,
    }
    local mod = {}
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
        },
        EntityType = { ENTITY_PICKUP = PICKUP },
        PickupVariant = { PICKUP_COLLECTIBLE = COLLECTIBLE },
        CollectibleType = collectibleTypes,
        PlayerType = { PLAYER_ISAAC = ISAAC, PLAYER_MAGDALENE = MAGDALENE, PLAYER_ISAAC_B = TAINTED_ISAAC },
        Card = { CARD_SOUL_ISAAC = SOUL_ISAAC },
        ItemPoolType = { POOL_TREASURE = TREASURE, POOL_SHOP = SHOP, POOL_NULL = POOL_NULL },
        ItemConfig = itemTags,
        RegisterMod = function(name, api)
            equal(name, "假如我直接赢", "display name")
            equal(api, 1, "mod API")
            return mod
        end,
        Game = function()
            return {
                GetItemPool = function() return pool end,
                GetRoom = function() return room end,
                GetNumPlayers = function() return #h.players end,
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
    return {
        GetPlayerType = function() return playerType end,
        HasCollectible = function(_, item) return heldItem ~= nil and item == heldItem end,
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
play.pickups = { starting, roomItem }
play.run(NEW_ROOM)
equal(starting.morphs, 1, "returning to a room does not reroll a valid replacement")
equal(roomItem.SubType, Q3, "room entry replaces a fixed low-quality pedestal")
equal(play.calls[2].pool, SHOP, "fixed pedestals use the current room pool")
roomItem.SubType = Q1
equal(play.callbacks[PICKUP_UPDATE].filter, COLLECTIBLE, "update is filtered to collectible pickups")
play.run(PICKUP_UPDATE, roomItem)
equal(roomItem.SubType, Q4, "pickup update replaces a later low-quality reroll")

local spawn = loadMod({ Q3, Q4 })
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
    local id = fresh.run(POST_GET, LOW, SHOP, true, seed)
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
equal(fresh.run(POST_GET, LOW, SHOP, true, firstLockedSeed), Q4,
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

print("Just Win: " .. checks .. " checks passed")
