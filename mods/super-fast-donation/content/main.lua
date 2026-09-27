local SuperFastDonation = RegisterMod("Super Fast Donation", 1)
local game = Game()

-- Isaac advances gameplay at 30 logic frames per second. Three donations on
-- two frames and four on every third frame gives exactly 100 per 30 frames.
local LOGIC_FRAMES_PER_SECOND = 30
local DONATIONS_PER_SECOND = 100

local SLOT_DONATION_MACHINE = 8
local SLOT_GREED_DONATION_MACHINE = 11
local MAX_IDLE_INTERNAL_TICKS = 45
local MAX_TOTAL_INTERNAL_TICKS = 240
local FAILED_RETRY_DELAY = LOGIC_FRAMES_PER_SECOND

local pendingCollisionByPlayer = {}
local donationsBySlot = {}
local retryAfterFrameBySlot = {}
local trackedFrame = -1
local activeSlotHash = nil
local activeDonationCount = 0

local function isDonationMachine(entity)
    return entity ~= nil
        and entity.Type == EntityType.ENTITY_SLOT
        and (entity.Variant == SLOT_DONATION_MACHINE
            or entity.Variant == SLOT_GREED_DONATION_MACHINE)
end

local function jamFlagForVariant(variant)
    if variant == SLOT_DONATION_MACHINE then
        return GameStateFlag.STATE_DONATION_SLOT_JAMMED
    end
    if variant == SLOT_GREED_DONATION_MACHINE then
        return GameStateFlag.STATE_GREED_SLOT_JAMMED
    end
    return nil
end

local function beginLogicFrame()
    local frame = game:GetFrameCount()
    if trackedFrame ~= frame then
        trackedFrame = frame
        donationsBySlot = {}
    end
    return frame
end

local function recordDonation(slotHash, amount)
    if amount <= 0 then return end
    beginLogicFrame()
    donationsBySlot[slotHash] = (donationsBySlot[slotHash] or 0) + amount
    if activeSlotHash == slotHash then
        activeDonationCount = activeDonationCount + amount
    end
end

local function playerKey(player)
    return GetPtrHash(player)
end

-- Capture the wallet immediately before the engine processes an actual
-- donation collision. Refunding in MC_POST_PLAYER_UPDATE avoids mistaking a
-- shop purchase or another coin cost for a donation.
function SuperFastDonation:OnPrePlayerCollision(player, collider)
    if not isDonationMachine(collider) then return end
    beginLogicFrame()
    pendingCollisionByPlayer[playerKey(player)] = {
        coins = player:GetNumCoins(),
        slotHash = GetPtrHash(collider),
    }
end

function SuperFastDonation:OnPostPlayerUpdate(player)
    local key = playerKey(player)
    local pending = pendingCollisionByPlayer[key]
    if pending == nil then return end

    local spent = pending.coins - player:GetNumCoins()
    if spent > 0 then
        player:AddCoins(spent)
        recordDonation(pending.slotHash, spent)
    end
    pendingCollisionByPlayer[key] = nil
end

local function targetDonationsThisFrame(frame)
    local base = math.floor(DONATIONS_PER_SECOND / LOGIC_FRAMES_PER_SECOND)
    local remainder = DONATIONS_PER_SECOND % LOGIC_FRAMES_PER_SECOND
    -- With 100/30 this is 3, 3, 4. The generic expression keeps the constant
    -- pair above authoritative if the requested rate changes later.
    local phase = frame % LOGIC_FRAMES_PER_SECOND
    local extraBefore = math.floor((phase + 1) * remainder / LOGIC_FRAMES_PER_SECOND)
    local extraAfter = math.floor(phase * remainder / LOGIC_FRAMES_PER_SECOND)
    return base + extraBefore - extraAfter
end

local function touchingPlayer(slot)
    local closest = nil
    local closestDistance = math.huge
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local distance = player.Position:Distance(slot.Position)
        if distance < player.Size + slot.Size + 1 and distance < closestDistance then
            closest = player
            closestDistance = distance
        end
    end
    return closest
end

local function spawnFreshMachine(slot, anchor)
    local variant = slot.Variant
    local subtype = slot.SubType
    if slot:Exists() then slot:Remove() end
    local replacement = Isaac.Spawn(
        EntityType.ENTITY_SLOT,
        variant,
        subtype,
        anchor,
        Vector(0, 0),
        nil
    )
    replacement.Position = anchor
    replacement.Velocity = Vector(0, 0)
    return replacement
end

local function recoverJammedMachine(slot, anchor)
    local jamFlag = jamFlagForVariant(slot.Variant)
    if jamFlag == nil or not game:GetStateFlag(jamFlag) then return slot end

    local oldHash = GetPtrHash(slot)
    game:SetStateFlag(jamFlag, false)
    local replacement = spawnFreshMachine(slot, anchor)
    local newHash = GetPtrHash(replacement)
    donationsBySlot[newHash] = donationsBySlot[oldHash] or 0
    retryAfterFrameBySlot[oldHash] = nil
    activeSlotHash = newHash
    return replacement
end

local function recoverMachinesJammedByTheNormalUpdate(machines)
    local jammedVariants = {}
    for _, variant in ipairs({ SLOT_DONATION_MACHINE, SLOT_GREED_DONATION_MACHINE }) do
        local flag = jamFlagForVariant(variant)
        if game:GetStateFlag(flag) then
            jammedVariants[variant] = true
            game:SetStateFlag(flag, false)
        end
    end
    if next(jammedVariants) == nil then return machines end

    for index, slot in ipairs(machines) do
        if jammedVariants[slot.Variant] then
            local oldHash = GetPtrHash(slot)
            local replacement = spawnFreshMachine(slot, slot.Position)
            local newHash = GetPtrHash(replacement)
            donationsBySlot[newHash] = donationsBySlot[oldHash] or 0
            retryAfterFrameBySlot[oldHash] = nil
            machines[index] = replacement
        end
    end
    return machines
end

local function accelerateMachine(slot, player, frame, target)
    local slotHash = GetPtrHash(slot)
    local alreadyDonated = donationsBySlot[slotHash] or 0
    if alreadyDonated >= target then return end
    if (retryAfterFrameBySlot[slotHash] or -1) > frame then return end

    activeSlotHash = slotHash
    activeDonationCount = alreadyDonated

    -- A temporary reserve lets a zero-coin player activate the machine. Every
    -- successful spend is refunded immediately; only this reserve is removed.
    local temporaryCoin = 0
    if player:GetNumCoins() == 0 then
        player:AddCoins(1)
        temporaryCoin = 1
    end

    local anchor = slot.Position
    local totalTicks = 0
    local idleTicks = 0

    while activeDonationCount < target
        and totalTicks < MAX_TOTAL_INTERNAL_TICKS
        and idleTicks < MAX_IDLE_INTERNAL_TICKS do
        totalTicks = totalTicks + 1
        local countBefore = activeDonationCount
        local coinsBefore = player:GetNumCoins()
        local playerPosition = player.Position
        local playerVelocity = player.Velocity

        slot:Update()
        -- Some machine variants take their payment during their own update,
        -- while others do it during the player's collision pass.
        local slotUpdateSpent = coinsBefore - player:GetNumCoins()
        if slotUpdateSpent > 0 then
            player:AddCoins(slotUpdateSpent)
            recordDonation(activeSlotHash, slotUpdateSpent)
        end
        pendingCollisionByPlayer[playerKey(player)] = nil
        coinsBefore = player:GetNumCoins()

        if not slot:Exists() then
            local jamFlag = jamFlagForVariant(slot.Variant)
            if jamFlag ~= nil and game:GetStateFlag(jamFlag) then
                slot = recoverJammedMachine(slot, anchor)
            else
                break
            end
        end
        slot.Position = anchor
        slot.Velocity = Vector(0, 0)

        if activeDonationCount >= target then break end

        player:Update()
        player.Position = playerPosition
        player.Velocity = playerVelocity

        -- MC_POST_PLAYER_UPDATE normally performs the refund and count. This
        -- fallback also keeps the feature safe if another mod suppresses that
        -- callback during a manual EntityPlayer:Update call.
        local spent = coinsBefore - player:GetNumCoins()
        if spent > 0 then
            player:AddCoins(spent)
            recordDonation(activeSlotHash, spent)
        end
        pendingCollisionByPlayer[playerKey(player)] = nil

        slot = recoverJammedMachine(slot, anchor)
        if not slot:Exists() then break end
        slot.Position = anchor
        slot.Velocity = Vector(0, 0)

        if activeDonationCount > countBefore then
            idleTicks = 0
        else
            idleTicks = idleTicks + 1
        end
    end

    if temporaryCoin > 0 then player:AddCoins(-temporaryCoin) end

    if slot:Exists() then slotHash = GetPtrHash(slot) end
    if activeDonationCount < target then
        -- A full machine cannot accept another coin. Backing off avoids doing
        -- a large failed update loop on every real frame while still retrying
        -- if another effect makes the machine usable again.
        retryAfterFrameBySlot[slotHash] = frame + FAILED_RETRY_DELAY
    else
        retryAfterFrameBySlot[slotHash] = nil
    end

    activeSlotHash = nil
    activeDonationCount = 0
end

function SuperFastDonation:OnPostUpdate()
    local frame = beginLogicFrame()
    if game:GetNumPlayers() == 0 then return end

    local machines = Isaac.FindByType(EntityType.ENTITY_SLOT, -1, -1, false, false)
    local donationMachines = {}
    for _, entity in ipairs(machines) do
        if isDonationMachine(entity) then
            donationMachines[#donationMachines + 1] = entity
        end
    end

    donationMachines = recoverMachinesJammedByTheNormalUpdate(donationMachines)
    if not game:GetRoom():IsClear() then return end

    local target = targetDonationsThisFrame(frame)
    for _, slot in ipairs(donationMachines) do
        local player = touchingPlayer(slot)
        if player ~= nil then
            accelerateMachine(slot, player, frame, target)
        end
    end
end

local function resetRoomState()
    pendingCollisionByPlayer = {}
    donationsBySlot = {}
    retryAfterFrameBySlot = {}
    trackedFrame = -1
    activeSlotHash = nil
    activeDonationCount = 0
    game:SetStateFlag(GameStateFlag.STATE_DONATION_SLOT_JAMMED, false)
    game:SetStateFlag(GameStateFlag.STATE_GREED_SLOT_JAMMED, false)
end

SuperFastDonation:AddCallback(
    ModCallbacks.MC_PRE_PLAYER_COLLISION,
    SuperFastDonation.OnPrePlayerCollision
)
SuperFastDonation:AddCallback(
    ModCallbacks.MC_POST_PLAYER_UPDATE,
    SuperFastDonation.OnPostPlayerUpdate
)
SuperFastDonation:AddCallback(ModCallbacks.MC_POST_UPDATE, SuperFastDonation.OnPostUpdate)
SuperFastDonation:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, resetRoomState)
SuperFastDonation:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, resetRoomState)
