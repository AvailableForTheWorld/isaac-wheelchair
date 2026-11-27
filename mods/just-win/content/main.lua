local mod = RegisterMod("假如我直接赢", 1)
local json = require("json")
local game = Game()
local pickupType = EntityType.ENTITY_PICKUP
local collectibleVariant = PickupVariant.PICKUP_COLLECTIBLE
local nullCollectible = CollectibleType.COLLECTIBLE_NULL
local collectibles = CollectibleType
local maxPoolRolls = 24
local samplingPool = false
local rules
local collected
local offersByRoom = {}

local transformationTags = {
    ItemConfig.TAG_SYRINGE, ItemConfig.TAG_MOM, ItemConfig.TAG_GUPPY, ItemConfig.TAG_FLY,
    ItemConfig.TAG_BOB, ItemConfig.TAG_MUSHROOM, ItemConfig.TAG_BABY, ItemConfig.TAG_ANGEL,
    ItemConfig.TAG_DEVIL, ItemConfig.TAG_POOP, ItemConfig.TAG_BOOK, ItemConfig.TAG_SPIDER,
}

-- Super Bum, Stompy and Necromancer use specific items instead of transformation tags.
local fixedSetPieces = {
    [CollectibleType.COLLECTIBLE_BUM_FRIEND] = true,
    [CollectibleType.COLLECTIBLE_DARK_BUM] = true,
    [CollectibleType.COLLECTIBLE_KEY_BUM] = true,
    [CollectibleType.COLLECTIBLE_LEO] = true,
    [CollectibleType.COLLECTIBLE_NECRONOMICON] = true,
    [CollectibleType.COLLECTIBLE_MISSING_PAGE_2] = true,
}

local function isHighQuality(item)
    return item.Quality == 3 or item.Quality == 4
end

local function isOrdinaryCollectible(item)
    return item and not item.Hidden and not item:HasTags(ItemConfig.TAG_QUEST)
end

local function getCollected()
    if collected then return collected end
    collected = {}
    if not mod:HasData() then return collected end

    local ok, saved = pcall(json.decode, mod:LoadData())
    if ok and type(saved) == "table" and saved.seed == game:GetSeeds():GetStartSeed()
        and type(saved.items) == "table" then
        for _, itemId in ipairs(saved.items) do
            if type(itemId) == "number" and itemId > nullCollectible and itemId % 1 == 0 then
                collected[itemId] = true
            end
        end
    end
    return collected
end

local function saveCollected()
    local items = {}
    for itemId in pairs(collected) do
        items[#items + 1] = itemId
    end
    table.sort(items)
    mod:SaveData(json.encode({ seed = game:GetSeeds():GetStartSeed(), items = items }))
end

local function onPostUpdate()
    local taken = getCollected()
    local changed = false
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local data = player:GetData()
        local queued = player.QueuedItem.Item
        local queuedId = queued and queued:IsCollectible() and queued.ID > nullCollectible and queued.ID or nil
        local pending = data.JustWinPendingPickup
        data.JustWinPendingPickup = queuedId

        -- The pickup animation queues the item before it is granted.
        if pending and pending ~= queuedId and not taken[pending] and player:HasCollectible(pending, true) then
            taken[pending] = true
            game:GetItemPool():RemoveCollectible(pending)
            changed = true
        end
    end
    if changed then
        rules = nil
        saveCollected()
    end
end

local function buildRules()
    local available, locked, restricted = {}, {}, {}
    local availableCount, lockedCount = 0, 0
    local taken = getCollected()
    local setMembers = {}
    for _, tag in ipairs(transformationTags) do
        setMembers[tag] = {}
    end

    local config = Isaac.GetItemConfig()
    for itemId = 1, config:GetCollectibles().Size - 1 do
        local item = config:GetCollectible(itemId)
        if isOrdinaryCollectible(item) then
            local isAvailable = item:IsAvailable()
            local highQuality = isHighQuality(item)
            local isLocked = not isAvailable and item.AchievementID >= 0
            if highQuality then
                if isAvailable then
                    availableCount = availableCount + 1
                elseif isLocked then
                    lockedCount = lockedCount + 1
                end
                if not taken[itemId] then
                    local pool = isAvailable and available or (isLocked and locked or restricted)
                    pool[#pool + 1] = itemId
                end
            end

            for _, tag in ipairs(transformationTags) do
                if item:HasTags(tag) then
                    local members = setMembers[tag]
                    members[#members + 1] = {
                        id = itemId,
                        quality = item.Quality,
                        available = isAvailable,
                        lockedHighQuality = isLocked and highQuality,
                    }
                end
            end
        end
    end

    local supplementLocked = availableCount * 3 < (availableCount + lockedCount) * 2
    local setPieces = {}
    for _, members in pairs(setMembers) do
        local qualities = {}
        for _, member in ipairs(members) do
            if member.available or (supplementLocked and member.lockedHighQuality) then
                qualities[#qualities + 1] = member.quality
            end
        end
        table.sort(qualities, function(a, b) return a > b end)
        -- Count different item IDs and keep every piece tied with the third-best quality.
        local cutoff = qualities[3] or 0
        for _, member in ipairs(members) do
            if member.quality >= cutoff and member.quality < 3 then
                setPieces[member.id] = true
            end
        end
    end

    return {
        setPieces = setPieces,
        available = available,
        locked = locked,
        restricted = restricted,
        supplementLocked = supplementLocked,
    }
end

local function getRules()
    if not rules then rules = buildRules() end
    return rules
end

local function isDeathCertificateRoom()
    local level = game:GetLevel()
    local current = level:GetCurrentRoomDesc()
    if not current.Data then return false end
    if current.Data.Name == "Death Certificate" then return true end
    local certificate = level:GetRoomByIdx(current.SafeGridIndex, 2)
    return certificate.Data ~= nil and GetPtrHash(certificate) == GetPtrHash(current)
end

local function getRoomOffers()
    local seed = game:GetRoom():GetSpawnSeed()
    if not offersByRoom[seed] then offersByRoom[seed] = {} end
    return offersByRoom[seed]
end

local function needsReplacement(itemId, offered)
    if itemId <= nullCollectible then return false end
    local item = Isaac.GetItemConfig():GetCollectible(itemId)
    if not item or item:HasTags(ItemConfig.TAG_QUEST) then return false end
    if offered and (offered[itemId] or getCollected()[itemId]) then return true end
    return not isHighQuality(item) and not fixedSetPieces[itemId] and not getRules().setPieces[itemId]
end

local function remainingChoices(candidates, offered)
    local remaining = {}
    for _, itemId in ipairs(candidates) do
        if not offered[itemId] then remaining[#remaining + 1] = itemId end
    end
    return remaining
end

local function findReplacement(poolType, seed, offered)
    local rng = RNG()
    rng:SetSeed(seed == 0 and 1 or seed, 35)
    local currentRules = getRules()
    local available = remainingChoices(currentRules.available, offered)
    local locked = remainingChoices(currentRules.locked, offered)
    if currentRules.supplementLocked and #locked > 0 and rng:RandomInt(#available + #locked) < #locked then
        return locked[rng:RandomInt(#locked) + 1]
    end

    if #available > 0 then
        local config = Isaac.GetItemConfig()
        local pool = game:GetItemPool()
        local taken = getCollected()
        if poolType == ItemPoolType.POOL_NULL then
            poolType = ItemPoolType.POOL_TREASURE
        end

        for _ = 1, maxPoolRolls do
            local rollSeed = rng:Next()
            -- These probes must not reserve choices or deplete the pool.
            samplingPool = true
            local itemId = pool:GetCollectible(poolType, false, rollSeed == 0 and 1 or rollSeed)
            samplingPool = false
            local item = itemId > nullCollectible and config:GetCollectible(itemId)
            if not taken[itemId] and not offered[itemId] and isOrdinaryCollectible(item)
                and isHighQuality(item) and item:IsAvailable() then
                return itemId
            end
        end
        return available[rng:RandomInt(#available) + 1]
    end

    if #locked > 0 then return locked[rng:RandomInt(#locked) + 1] end
    local restricted = remainingChoices(currentRules.restricted, offered)
    if #restricted > 0 then
        return restricted[rng:RandomInt(#restricted) + 1]
    end
end

local function playersCanRotatePedestals()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local playerType = player:GetPlayerType()
        if playerType == PlayerType.PLAYER_ISAAC_B
            or (playerType == PlayerType.PLAYER_ISAAC and player:HasCollectible(collectibles.COLLECTIBLE_BIRTHRIGHT))
            or player:HasCollectible(collectibles.COLLECTIBLE_GLITCHED_CROWN)
            or player:HasCollectible(collectibles.COLLECTIBLE_BINGE_EATER) then
            return true
        end
    end
    return false
end

local function onGetCollectible(_, itemId, poolType, decrease, seed)
    if samplingPool or itemId <= nullCollectible or isDeathCertificateRoom() then return end
    local offered = getRoomOffers()
    local replacement
    if needsReplacement(itemId, offered) then
        replacement = findReplacement(poolType, seed, offered)
    end
    -- Native rotation can request more than one choice before any is picked up.
    if decrease or playersCanRotatePedestals() then
        offered[replacement or itemId] = true
    end
    return replacement
end

local function replaceFromRoomPool(itemId, seed)
    if itemId <= nullCollectible or isDeathCertificateRoom() then return end
    local offered = getRoomOffers()
    local replacement
    if needsReplacement(itemId) then
        local room = game:GetRoom()
        local poolType = game:GetItemPool():GetPoolForRoom(room:GetType(), room:GetSpawnSeed())
        replacement = findReplacement(poolType, seed, offered)
    end
    offered[replacement or itemId] = true
    return replacement
end

-- Explicit drops bypass item-pool selection. Upgrade their subtype before
-- the engine builds the pedestal and its native options.
local function onEntitySpawn(_, entityType, variant, subtype, _position, _velocity, _spawner, seed)
    if entityType ~= pickupType or variant ~= collectibleVariant then return end
    local itemId = replaceFromRoomPool(subtype, seed)
    if itemId then return { entityType, variant, itemId, seed } end
end

local function onRoomEntitySpawn(_, entityType, variant, subtype, _gridIndex, seed)
    if entityType ~= pickupType or variant ~= collectibleVariant then return end
    local itemId = replaceFromRoomPool(subtype, seed)
    if itemId then return { entityType, variant, itemId } end
end

local function onPickupUpdate(_, pickup)
    if pickup.SubType <= nullCollectible or isDeathCertificateRoom() then return end
    getRoomOffers()[pickup.SubType] = true

    -- Morph recreates the pedestal's options. Pool rolls have already been
    -- filtered, so do not touch a native cycle or its Binge Eater food slot.
    local data = pickup:GetData()
    if data.JustWinKeepCycle then return end
    if playersCanRotatePedestals() then
        data.JustWinKeepCycle = true
        return
    end

    if not needsReplacement(pickup.SubType) then return end
    if pickup.GetCollectibleCycle then
        local cycle = pickup:GetCollectibleCycle()
        if #cycle > 1 or (#cycle == 1 and cycle[1] ~= pickup.SubType) then return end
    end

    local itemId = replaceFromRoomPool(pickup.SubType, pickup.InitSeed)
    if not itemId then return end

    local price, shopItemId, autoUpdatePrice = pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice
    local optionsIndex = pickup.OptionsPickupIndex
    local wait, timeout = pickup.Wait, pickup.Timeout
    pickup:Morph(pickupType, collectibleVariant, itemId, true, true, false)
    pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice = price, shopItemId, autoUpdatePrice
    pickup.OptionsPickupIndex = optionsIndex
    pickup.Wait, pickup.Timeout = wait, timeout
    pickup.Touched = false
end

local function onSoulOfIsaac()
    for _, pickup in ipairs(Isaac.FindByType(pickupType, collectibleVariant)) do
        pickup:GetData().JustWinKeepCycle = true
    end
end

local function updateRoomPickups()
    if isDeathCertificateRoom() then return end
    local pedestals = Isaac.FindByType(pickupType, collectibleVariant)
    local offered = getRoomOffers()
    for _, entity in ipairs(pedestals) do
        if entity.SubType > nullCollectible then offered[entity.SubType] = true end
    end
    for _, entity in ipairs(pedestals) do
        onPickupUpdate(mod, entity:ToPickup())
    end
end

local function onGameExit(_, shouldSave)
    if shouldSave then onPostUpdate() end
    if collected then
        if not shouldSave then collected = {} end
        saveCollected()
    end
    collected = nil
    rules = nil
    offersByRoom = {}
end

local function onGameStarted(_, isContinued)
    rules = nil
    if isContinued then
        collected = nil
        local pool = game:GetItemPool()
        for itemId in pairs(getCollected()) do
            pool:RemoveCollectible(itemId)
        end
    else
        collected = {}
        saveCollected()
    end
    updateRoomPickups()
end

mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, onGetCollectible)
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, onEntitySpawn)
mod:AddCallback(ModCallbacks.MC_PRE_ROOM_ENTITY_SPAWN, onRoomEntitySpawn)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, updateRoomPickups)
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onGameStarted)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, onPostUpdate)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, collectibleVariant)
mod:AddCallback(ModCallbacks.MC_USE_CARD, onSoulOfIsaac, Card.CARD_SOUL_ISAAC)
