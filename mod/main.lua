local Wheelchair = RegisterMod("Wheelchair 100-State Timeline", 1)
local game = Game()

local MAX_STATES = 100

local timeline = {}
local liveSnapshot = nil -- refreshed in place; committed only when leaving a room
local pendingTarget = nil
local pendingRestoreFrames = 0
local inputCooldown = 0
local exactRoomRewindAvailable = false
local lastStage = nil
local lastStageType = nil
local message = ""
local messageUntil = 0

local function showMessage(text, duration)
    message = text
    messageUntil = game:GetFrameCount() + (duration or 90)
end

local function snapshotPlayer(player)
    return {
        playerType = player:GetPlayerType(),
        x = player.Position.X,
        y = player.Position.Y,
        maxHearts = player:GetMaxHearts(),
        hearts = player:GetHearts(),
        soulHearts = player:GetSoulHearts(),
        boneHearts = player:GetBoneHearts(),
        eternalHearts = player:GetEternalHearts(),
        goldenHearts = player:GetGoldenHearts(),
        coins = player:GetNumCoins(),
        keys = player:GetNumKeys(),
        bombs = player:GetNumBombs(),
        activeCharge = player:GetActiveCharge()
    }
end

local function snapshotCurrentState()
    local level = game:GetLevel()
    local players = {}
    for index = 0, game:GetNumPlayers() - 1 do
        players[index + 1] = snapshotPlayer(Isaac.GetPlayer(index))
    end

    return {
        frame = game:GetFrameCount(),
        stage = level:GetStage(),
        stageType = level:GetStageType(),
        roomIndex = level:GetCurrentRoomIndex(),
        players = players
    }
end

local function pushRoomState(state)
    if state == nil then return end
    timeline[#timeline + 1] = state
    while #timeline > MAX_STATES do
        table.remove(timeline, 1)
    end
end

local function safeAdd(method, player, amount, extra)
    if amount == 0 then return end
    if extra == nil then
        pcall(method, player, amount)
    else
        pcall(method, player, amount, extra)
    end
end

local function restorePlayer(player, saved)
    if player:GetPlayerType() ~= saved.playerType then return end

    safeAdd(player.AddMaxHearts, player, saved.maxHearts - player:GetMaxHearts(), false)
    safeAdd(player.AddBoneHearts, player, saved.boneHearts - player:GetBoneHearts())
    safeAdd(player.AddHearts, player, saved.hearts - player:GetHearts())
    safeAdd(player.AddSoulHearts, player, saved.soulHearts - player:GetSoulHearts())
    safeAdd(player.AddEternalHearts, player, saved.eternalHearts - player:GetEternalHearts())
    safeAdd(player.AddGoldenHearts, player, saved.goldenHearts - player:GetGoldenHearts())
    safeAdd(player.AddCoins, player, saved.coins - player:GetNumCoins())
    safeAdd(player.AddKeys, player, saved.keys - player:GetNumKeys())
    safeAdd(player.AddBombs, player, saved.bombs - player:GetNumBombs())

    pcall(player.SetActiveCharge, player, saved.activeCharge or 0)

    player.Position = Vector(saved.x, saved.y)
    player.Velocity = Vector.Zero
end

local function applyTarget(target)
    for index = 0, math.min(game:GetNumPlayers(), #target.players) - 1 do
        restorePlayer(Isaac.GetPlayer(index), target.players[index + 1])
    end
    pendingTarget = nil
    pendingRestoreFrames = 0
    liveSnapshot = target
    showMessage("Returned to previous room (" .. #timeline .. " older cached)", 75)
end

local function requestRewind()
    if pendingTarget ~= nil or game:IsPaused() or game:GetNumPlayers() == 0 then return end

    if #timeline == 0 then
        showMessage("No previous room cached on this floor", 90)
        return
    end

    -- Popping the latest completed room makes this a single linear history.
    -- Entering a new room after a rewind records the new future normally.
    local target = table.remove(timeline)
    local level = game:GetLevel()

    if target.stage ~= level:GetStage() or target.stageType ~= level:GetStageType() then
        showMessage("Deep rewind across floors is disabled for safety", 120)
        return
    end

    pendingTarget = target
    pendingRestoreFrames = 3
    inputCooldown = 12

    if target.roomIndex == level:GetCurrentRoomIndex() then
        applyTarget(target)
    elseif exactRoomRewindAvailable then
        exactRoomRewindAvailable = false
        Isaac.ExecuteCommand("rewind")
    else
        -- ChangeRoom is limited to the already-generated current floor. It does not
        -- touch disk saves and is safer than pretending the process can be restored.
        game:ChangeRoom(target.roomIndex)
    end
end

local function rewindInputTriggered()
    if Input.IsButtonTriggered(Keyboard.KEY_F5, 0) then return true end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if Input.IsActionTriggered(ButtonAction.ACTION_MENURT, player.ControllerIndex) then
            return true
        end
    end
    return false
end

function Wheelchair:OnGameStarted()
    timeline = {}
    liveSnapshot = nil
    pendingTarget = nil
    pendingRestoreFrames = 0
    exactRoomRewindAvailable = false
    local level = game:GetLevel()
    lastStage = level:GetStage()
    lastStageType = level:GetStageType()
    showMessage("Room timeline ready: F5 or RT goes back one room", 120)
end

function Wheelchair:OnNewRoom()
    if pendingTarget ~= nil then
        pendingRestoreFrames = 3
        return
    end

    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    if lastStage ~= nil and (stage ~= lastStage or stageType ~= lastStageType) then
        timeline = {}
        showMessage("New floor: timeline cache reset", 90)
    elseif liveSnapshot ~= nil then
        -- liveSnapshot was refreshed during the final update in the room we just
        -- left. Commit it now: movement never creates timeline entries.
        pushRoomState(liveSnapshot)
    end
    lastStage = stage
    lastStageType = stageType
    liveSnapshot = nil
    exactRoomRewindAvailable = true
end

function Wheelchair:OnUpdate()
    if inputCooldown > 0 then inputCooldown = inputCooldown - 1 end

    if pendingTarget ~= nil then
        if pendingRestoreFrames > 0 then
            pendingRestoreFrames = pendingRestoreFrames - 1
        else
            local level = game:GetLevel()
            if level:GetCurrentRoomIndex() == pendingTarget.roomIndex then
                applyTarget(pendingTarget)
            else
                pushRoomState(pendingTarget)
                pendingTarget = nil
                showMessage("Room restore was refused by the game", 120)
            end
        end
        return
    end

    -- This working copy follows Isaac every frame, but it is not a timeline
    -- entry. Only MC_POST_NEW_ROOM commits it as the room-exit state.
    if game:GetNumPlayers() > 0 then liveSnapshot = snapshotCurrentState() end

    if inputCooldown == 0 and rewindInputTriggered() then
        requestRewind()
    end
end

function Wheelchair:OnRender()
    if game:GetNumPlayers() == 0 then return end
    Isaac.RenderText("Wheelchair rooms: " .. #timeline .. "/" .. MAX_STATES .. "  [F5 / RT: previous room]", 52, 28, 0.72, 1.0, 0.72, 1.0)
    if message ~= "" and game:GetFrameCount() < messageUntil then
        Isaac.RenderText(message, 52, 40, 1.0, 0.9, 0.45, 1.0)
    end
end

Wheelchair:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Wheelchair.OnGameStarted)
Wheelchair:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Wheelchair.OnNewRoom)
Wheelchair:AddCallback(ModCallbacks.MC_POST_UPDATE, Wheelchair.OnUpdate)
Wheelchair:AddCallback(ModCallbacks.MC_POST_RENDER, Wheelchair.OnRender)
