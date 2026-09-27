local mod = RegisterMod("Glitched Crown Practice", 1)
local game = Game()
local json = require("json")
local Practice = include("scripts/practice")
local Items = include("scripts/items")
local C = CollectibleType
local CROWN = C.COLLECTIBLE_GLITCHED_CROWN
local SAVE_SCHEMA = 2
local RESULT_FRAMES = 45
local CALIBRATION_TIMEOUT = 180
local rng = RNG()
local run, round
local stage = "inactive"
local waitFrames = 0
local generationIndex = nil
local pool = {}
local collectibleIds = {}
local feedback = nil
local targetSprite = Sprite()
targetSprite:Load("gfx/005.100_collectible.anm2", true)

-- Restrict practice rewards to passive items without teleportation, rerolls,
-- extra choices, or immediate room-changing effects. Real item collection is
-- retained; inventory and transformation progress are reset every round.
local poolNames = {
    "SAD_ONION", "INNER_EYE", "SPOON_BENDER", "CRICKETS_HEAD", "MY_REFLECTION",
    "NUMBER_ONE", "BLOOD_OF_THE_MARTYR", "WIRE_COAT_HANGER", "LUCKY_FOOT",
    "CUPIDS_ARROW", "PENTAGRAM", "DR_FETUS", "MAGNETO", "TREASURE_MAP",
    "TECHNOLOGY", "CHOCOLATE_MILK", "SPIDER_BITE", "PARASITE", "LUMP_OF_COAL",
    "IPECAC", "TECHNOLOGY_2", "MUTANT_SPIDER", "POLYPHEMUS", "SACRED_HEART",
    "TOOTH_PICKS", "LOST_CONTACT", "BALL_OF_TAR", "DEATHS_TOUCH", "TRINITY_SHIELD",
    "20_20", "SCREW", "DARK_MATTER", "PROPTOSIS", "SCORPIO", "MYSTERIOUS_LIQUID",
    "GODHEAD", "CONTINUUM", "DEAD_EYE", "HOLY_LIGHT", "PUPULA_DUPLEX",
    "GODS_FLESH", "EXPLOSIVO", "EYE_OF_BELIAL", "SULFURIC_ACID", "JACOBS_LADDER",
    "GHOST_PEPPER", "TECHNOLOGY_ZERO", "HAEMOLACRIA", "TRISAGION", "URANUS",
    "NEPTUNUS",
}

local font = Font()
local chineseFont = false
local function loadFont()
    -- Native resource resolution first, then the registered local install path.
    -- Neither another mod nor its Workshop directory is a dependency.
    local paths = {
        "font/gcpractice.fnt",
        "../mods/glitched-crown-practice/resources/font/gcpractice.fnt",
        "mods/glitched-crown-practice/resources/font/gcpractice.fnt",
        "resources-dlc3.zh/font/teammeatfontextended12.fnt",
        "font/cjk/lanapixel.fnt",
    }
    -- Lua debugging extensions expose the script path; using it also supports
    -- a future Workshop-suffixed installation without hardcoding its item ID.
    if debug and debug.getinfo then
        local ok, info = pcall(debug.getinfo, loadFont, "S")
        local directory = ok and info and info.source and info.source:match("^@(.+[/\\])")
        if directory then table.insert(paths, 1, directory .. "resources/font/gcpractice.fnt") end
    end
    for _, path in ipairs(paths) do
        font:Load(path)
        if font:IsLoaded() then chineseFont = true; return end
    end
    font:Load("font/teammeatex/teammeatex12.fnt")
    if not font:IsLoaded() then font:Load("font/terminus.fnt") end
end
loadFont()

local function text(zh, en)
    return chineseFont and zh or en
end

local function saveRun()
    mod:SaveData(json.encode({ schema = SAVE_SCHEMA, activeRun = run }))
end

local function currentSeed()
    return game:GetSeeds():GetStartSeed()
end

local function buildPool()
    local config = Isaac.GetItemConfig()
    pool, collectibleIds = {}, {}
    for _, name in ipairs(poolNames) do
        local id = C["COLLECTIBLE_" .. name]
        if id and config:GetCollectible(id) then pool[#pool + 1] = id end
    end
    for id = 1, config:GetCollectibles().Size - 1 do
        if config:GetCollectible(id) then collectibleIds[#collectibleIds + 1] = id end
    end
end

local function sealRoom()
    local room = game:GetRoom()
    for slot = 0, 7 do room:RemoveDoor(slot) end
    room:SetClear(true)
end

local function clearRoom()
    local room = game:GetRoom()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type ~= EntityType.ENTITY_PLAYER then entity:Remove() end
    end
    for index = 0, room:GetGridSize() - 1 do
        local grid = room:GetGridEntity(index)
        if grid and grid:GetType() ~= GridEntityType.GRID_WALL
            and grid:GetType() ~= GridEntityType.GRID_DOOR then
            room:RemoveGridEntity(index, 0, false)
        end
    end
    sealRoom()
end

local function resetPlayers()
    local index = 0
    -- Converting Jacob & Esau can remove the second body during this loop.
    while index < game:GetNumPlayers() do
        local player = Isaac.GetPlayer(index)
        -- Normalize character-specific pickup rules; the cache callback applies
        -- this round's randomized speed after the inventory reset.
        if player:GetPlayerType() ~= PlayerType.PLAYER_ISAAC then
            player:ChangePlayerType(PlayerType.PLAYER_ISAAC)
        end
        player:FlushQueueItem()
        for slot = 0, 3 do
            local active = player:GetActiveItem(slot)
            if active ~= 0 then player:RemoveCollectible(active, false, slot, true) end
        end
        for _, id in ipairs(collectibleIds) do
            if id ~= CROWN then
                local count = player:GetCollectibleNum(id, true)
                for _ = 1, count do player:RemoveCollectible(id, false, ActiveSlot.SLOT_PRIMARY, true) end
            end
        end
        -- Removing the first trinket can move the second one into its slot.
        for _ = 1, 2 do
            for slot = 0, 1 do
                local trinket = player:GetTrinket(slot)
                if trinket ~= 0 then player:TryRemoveTrinket(trinket) end
            end
        end
        if not player:HasCollectible(CROWN, true) then player:AddCollectible(CROWN, 0, false) end
        -- ChangePlayerType does not supply Isaac's normal starting health.
        -- In particular, a Lost/Keeper start must not become a zero-health Isaac.
        if player:GetMaxHearts() < 6 then player:AddMaxHearts(6 - player:GetMaxHearts(), false) end
        player:AddHearts(6)
        player.Position = game:GetRoom():GetCenterPos() + Vector(0, 80)
        player.Velocity = Vector.Zero
        player.ControlsCooldown = 2
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
        player:EvaluateItems()
        index = index + 1
    end
end

local function prepareRound()
    generationIndex = nil
    round = nil
    if not run.speed or run.nextRound then
        run.speed = Practice.sampleSpeed(function() return rng:RandomFloat() end)
        run.nextRound = false
    end
    resetPlayers()
    clearRoom()
    game:GetLevel():RemoveCurses(LevelCurse.CURSE_OF_DARKNESS | LevelCurse.CURSE_OF_BLIND)
    saveRun()
    -- Grid removals take effect on the next frame; don't force Room:Update().
    stage, waitFrames = "spawn", 2
end

local function retryRound()
    generationIndex = nil
    stage, waitFrames = "retry", RESULT_FRAMES
    feedback = { retry = true }
end

local function spawnRound()
    if #pool < 5 then
        stage = "unavailable"
        return
    end
    local available = {}
    for index, id in ipairs(pool) do available[index] = id end
    local candidates = {}
    for index = 1, 5 do
        candidates[index] = table.remove(available, rng:RandomInt(#available) + 1)
    end
    round = { candidates = candidates, cycle = {}, age = 0, target = nil }
    generationIndex = 1
    stage = "learning"
    round.pickup = Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
        0, game:GetRoom():GetCenterPos(), Vector.Zero, nil):ToPickup()
    round.pickup.Price = 0
    round.pickup.OptionsPickupIndex = 0
end

local function isTrainingPickup(pickup)
    return round and round.pickup and round.pickup:Exists() and pickup.InitSeed == round.pickup.InitSeed
        and pickup.Index == round.pickup.Index
end

function mod:OnGetCollectible()
    -- Crown's extra choices may be generated on the following pickup update.
    -- Scope the override to precisely five rolls during this round's setup.
    if not run or not generationIndex or not round then return end
    local id = round.candidates[generationIndex]
    generationIndex = generationIndex + 1
    if generationIndex > 5 then generationIndex = nil end
    return id
end

function mod:OnPickupUpdate(pickup)
    if not run or not isTrainingPickup(pickup) then return end
    if stage == "learning" then
        local status = Practice.observeCycle(round.cycle, pickup.SubType, round.candidates)
        if status == "invalid" then
            retryRound()
        elseif status == "complete" and not generationIndex then
            round.target = round.cycle.order[rng:RandomInt(5) + 1]
            local item = Isaac.GetItemConfig():GetCollectible(round.target)
            targetSprite:ReplaceSpritesheet(1, item.GfxFileName)
            targetSprite:LoadGraphics()
            targetSprite:SetFrame("Idle", 0)
            round.lastShown = pickup.SubType
            stage = "ready"
        end
    elseif stage == "ready" and pickup.SubType > 0 and pickup.SubType ~= round.lastShown then
        -- A reroll into another known candidate can still invalidate the order.
        -- The emptied pedestal after collection is handled only after the queue.
        local nextOffset = Practice.offset(round.cycle.order, round.lastShown, pickup.SubType)
        if nextOffset ~= 1 then retryRound() else round.lastShown = pickup.SubType end
    end
end

function mod:OnPickupCollision(pickup, collider)
    if not run or not collider:ToPlayer() then return end
    if not isTrainingPickup(pickup) or stage ~= "ready" then return true end
    if Practice.offset(round.cycle.order, round.target, pickup.SubType) == nil then
        retryRound()
        return true
    end
    -- nil intentionally runs Isaac's native collision/pickup code. In this
    -- callback false would skip native pickup processing, so never return false.
end

local function checkCollectedItem()
    for index = 0, game:GetNumPlayers() - 1 do
        local queued = Isaac.GetPlayer(index).QueuedItem.Item
        if queued and queued:IsCollectible() then
            local offset = Practice.offset(round.cycle.order, round.target, queued.ID)
            if offset == nil then retryRound(); return true end
            Practice.record(run.stats, offset)
            -- If the player exits during feedback, Continue starts the next
            -- round with a fresh speed, not the completed round's speed.
            run.nextRound = true
            feedback = { offset = offset }
            stage, waitFrames = "result", RESULT_FRAMES
            generationIndex = nil
            saveRun()
            return true
        end
    end
    return false
end

function mod:OnGameStarted(isContinued)
    run, round, feedback = nil, nil, nil
    generationIndex = nil
    stage = "inactive"
    -- Existing unrelated saves remain ordinary runs. Only runs started with this
    -- mod (and recorded with this seed) are resumed as training sessions.
    if isContinued then
        if mod:HasData() then
            local ok, saved = pcall(json.decode, mod:LoadData())
            if ok and type(saved) == "table" and (saved.schema == 1 or saved.schema == SAVE_SCHEMA)
                and type(saved.activeRun) == "table" and saved.activeRun.seed == currentSeed() then
                run = {
                    seed = currentSeed(), stats = Practice.restoreStats(saved.activeRun.stats),
                    speed = Practice.restoreSpeed(saved.activeRun.speed),
                    nextRound = saved.activeRun.nextRound == true,
                }
            end
        end
    elseif game.Challenge == 0 then
        run = { seed = currentSeed(), stats = Practice.newStats() }
    end
    if not run then return end
    rng:SetSeed(math.max(1, currentSeed()), 35)
    -- Avoid repeating the opening sequence after each Continue.
    for _ = 1, run.stats.total % 997 do rng:Next() end
    buildPool()
    stage, waitFrames = "setup", 5
    game:GetHUD():SetVisible(false)
    saveRun()
end

function mod:OnNewRoom()
    if not run then return end
    generationIndex = nil
    stage, waitFrames = "setup", 2
    round = nil
end

function mod:OnUpdate()
    if not run or game:IsPaused() then return end
    sealRoom()
    if stage ~= "ready" then
        for index = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(index)
            player.ControlsCooldown = 2
            player.Velocity = Vector.Zero
        end
    end
    if stage == "setup" or stage == "spawn" or stage == "retry" or stage == "result" then
        waitFrames = waitFrames - 1
        if waitFrames <= 0 then
            if stage == "spawn" then spawnRound() else prepareRound() end
        end
    elseif stage == "learning" then
        round.age = round.age + 1
        if not round.pickup:Exists() or round.age > CALIBRATION_TIMEOUT then retryRound() end
    elseif stage == "ready" then
        -- Check the queue BEFORE the pedestal: a successful native pickup can
        -- already have removed or emptied it in this same simulation frame.
        if checkCollectedItem() then return end
        if not round.pickup:Exists() or round.pickup.SubType == 0 then
            retryRound()
        end
    end
end

function mod:OnEvaluateCache(player, flag)
    -- Vanilla stats are evaluated before this callback. Reapply the chosen
    -- round speed even if the native pickup or its removal triggers a recache.
    if run and run.speed and flag == CacheFlag.CACHE_SPEED then player.MoveSpeed = run.speed end
end

local blockedActions = {
    [ButtonAction.ACTION_SHOOTLEFT] = true, [ButtonAction.ACTION_SHOOTRIGHT] = true,
    [ButtonAction.ACTION_SHOOTUP] = true, [ButtonAction.ACTION_SHOOTDOWN] = true,
    [ButtonAction.ACTION_BOMB] = true, [ButtonAction.ACTION_ITEM] = true,
    [ButtonAction.ACTION_PILLCARD] = true, [ButtonAction.ACTION_DROP] = true,
}

function mod:OnInputAction(entity, hook, action)
    if not run or not entity or not entity:ToPlayer() or not blockedActions[action] then return end
    if hook == InputHook.GET_ACTION_VALUE then return 0 end
    return false
end

function mod:OnDamage(entity)
    if run and entity:ToPlayer() then return false end
end

function mod:OnExit(shouldSave)
    if not run then return end
    if shouldSave then saveRun() else run = nil; saveRun() end
    game:GetHUD():SetVisible(true)
    run, round = nil, nil
    generationIndex = nil
    stage = "inactive"
end

function mod:OnGameEnd()
    if not run then return end
    run, round = nil, nil
    generationIndex = nil
    stage = "inactive"
    game:GetHUD():SetVisible(true)
    saveRun()
end

local white = KColor(1, 1, 1, 1)
local gold = KColor(1, 0.82, 0.35, 1)
local green = KColor(0.45, 1, 0.6, 1)
local blue = KColor(0.45, 0.8, 1, 1)
local red = KColor(1, 0.48, 0.48, 1)
local muted = KColor(0.7, 0.72, 0.76, 1)
local shadow = KColor(0.03, 0.03, 0.03, 0.65)

local function draw(value, x, y, color, centered)
    if not font:IsLoaded() then
        if centered then x = x - Isaac.GetTextWidth(value) / 2 end
        local ink = color or white
        Isaac.RenderText(value, math.floor(x), math.floor(y), ink.Red, ink.Green, ink.Blue, ink.Alpha)
        return
    end
    local stringWidth = font:GetStringWidthUTF8(value)
    -- The atlas is rasterized at its final size; use native pixels throughout
    -- to keep thin Chinese strokes sharp. All training item names fit at 1x.
    if centered then x = x - stringWidth / 2 end
    x, y = math.floor(x), math.floor(y)
    font:DrawStringUTF8(value, x + 1, y + 1, shadow, 0, false)
    font:DrawStringUTF8(value, x, y, color or white, 0, false)
end

local function feedbackText()
    if not feedback then return "" end
    if feedback.retry then return text("道具被改变，本轮重试", "Pedestal changed - retrying") end
    local labels = {
        [-2] = text("-2 提前两项", "-2 Two items before"),
        [-1] = text("-1 目标前一个", "-1 Previous item"),
        [0] = text("选中目标", "Correct target"),
        [1] = text("+1 目标后一个", "+1 Next item"),
        [2] = text("+2 滞后两项", "+2 Two items after"),
    }
    return text("本次: ", "Last: ") .. labels[feedback.offset]
end

local function targetName(id)
    local entry = Items[id]
    if entry then return text(entry.zh, entry.en) end
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if config and type(config.Name) == "string" and config.Name:sub(1, 1) ~= "#" then
        return config.Name
    end
    return text("道具", "Item") .. " #" .. id
end

function mod:OnRender()
    if not run then return end
    local width, height = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local stats = run.stats
    draw(text("无尽模式", "Endless Mode"), width / 2, 12, gold, true)
    local x, y, line = 24, 42, 17
    local rate = stats.total == 0 and 0 or stats.correct * 100 / stats.total
    draw(text("已选择: ", "Picked: ") .. stats.total, x, y, white)
    draw(text("正确: ", "Correct: ") .. stats.correct .. text("  错误: ", "  Wrong: ")
        .. (stats.total - stats.correct), x, y + line, white)
    draw(text("成功率: ", "Accuracy: ") .. string.format("%.1f%%", rate), x, y + line * 2, white)
    draw(text("+1 次数: ", "+1 count: ") .. stats.plus1, x, y + line * 3, red)
    draw(text("-1 次数: ", "-1 count: ") .. stats.minus1, x, y + line * 4, blue)
    draw(text("+2 次数: ", "+2 count: ") .. stats.plus2, x, y + line * 5, red)
    draw(text("-2 次数: ", "-2 count: ") .. stats.minus2, x, y + line * 6, blue)
    if stats.other > 0 then
        draw(text("历史未分类: ", "Legacy errors: ") .. stats.other, x, y + line * 7, white)
    end
    -- Read the actual player stat so the label never conceals a conflicting
    -- external stat modifier. Practice's cache handler keeps it at run.speed.
    draw(text("当前移速: ", "Current speed: ") .. string.format("%.2f", Isaac.GetPlayer(0).MoveSpeed),
        width / 2, height - 49, green, true)
    draw(feedbackText(), width / 2, height - 25,
        feedback and feedback.offset == 0 and green or gold, true)
    if stage == "ready" or stage == "result" then
        local targetX = width - 90
        draw(text("目标道具", "Target item"), targetX, 42, green, true)
        if round and round.target then
            -- Render just the item, keeping the name close to its image without
            -- the world pedestal and shadow taking up space in this HUD group.
            targetSprite:RenderLayer(1, Vector(targetX, 92), Vector.Zero, Vector.Zero)
            draw(targetName(round.target), targetX, 100, white, true)
            draw("#" .. round.target, targetX, 116, muted, true)
        end
    elseif stage == "learning" then
        draw(text("识别轮换中", "Learning cycle..."), width / 2, height - 75, gold, true)
    elseif stage == "unavailable" then
        draw("Item pool unavailable", width / 2, height - 75, red, true)
    else
        draw(text("准备中", "Preparing..."), width / 2, height - 75, gold, true)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)
mod:AddCallback(ModCallbacks.MC_PRE_GET_COLLECTIBLE, mod.OnGetCollectible)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnPickupUpdate, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, mod.OnPickupCollision, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnEvaluateCache, CacheFlag.CACHE_SPEED)
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, mod.OnInputAction)
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnDamage, EntityType.ENTITY_PLAYER)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnExit)
mod:AddCallback(ModCallbacks.MC_POST_GAME_END, mod.OnGameEnd)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)
