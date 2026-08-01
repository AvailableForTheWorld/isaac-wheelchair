local Wheelchair = RegisterMod("Wheelchair 100-State Timeline", 1)
local game = Game()

local MAX_STATES = 100
local CAPTURE_INTERVAL = 30 -- roughly one second at normal game speed
local CONTINUE_REWIND_WINDOW = 90 -- three seconds to keep stepping backward

local timeline = {}
local pendingTarget = nil
local pendingRestoreFrames = 0
local nextCaptureFrame = 0
local resumeCaptureFrame = 0
local inputCooldown = 0
local rewindSequence = false
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

local function discardFutureAndCapture()
    timeline[#timeline + 1] = snapshotCurrentState()
    while #timeline > MAX_STATES do
        table.remove(timeline, 1)
    end
    nextCaptureFrame = game:GetFrameCount() + CAPTURE_INTERVAL
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
    rewindSequence = true
    resumeCaptureFrame = game:GetFrameCount() + CONTINUE_REWIND_WINDOW
    nextCaptureFrame = resumeCaptureFrame
    showMessage("Restored state " .. #timeline .. "/" .. MAX_STATES, 75)
end

local function requestRewind()
    if pendingTarget ~= nil or game:IsPaused() or game:GetNumPlayers() == 0 then return end

    if not rewindSequence then
        discardFutureAndCapture()
    end

    if #timeline < 2 then
        showMessage("No earlier cached state on this floor", 90)
        return
    end

    table.remove(timeline) -- discard the current/future state: this is a linear timeline
    local target = timeline[#timeline]
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
    pendingTarget = nil
    pendingRestoreFrames = 0
    rewindSequence = false
    exactRoomRewindAvailable = false
    local level = game:GetLevel()
    lastStage = level:GetStage()
    lastStageType = level:GetStageType()
    nextCaptureFrame = game:GetFrameCount() + 2
    showMessage("Timeline ready: F5 or RT steps backward", 120)
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
    end
    lastStage = stage
    lastStageType = stageType
    rewindSequence = false
    exactRoomRewindAvailable = true
    nextCaptureFrame = game:GetFrameCount() + 2
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
                pendingTarget = nil
                showMessage("Room restore was refused by the game", 120)
            end
        end
        return
    end

    local frame = game:GetFrameCount()
    if rewindSequence and frame >= resumeCaptureFrame then
        rewindSequence = false
    end
    if not rewindSequence and frame >= nextCaptureFrame and game:GetNumPlayers() > 0 then
        discardFutureAndCapture()
    end

    if inputCooldown == 0 and rewindInputTriggered() then
        requestRewind()
    end
end

function Wheelchair:OnRender()
    if game:GetNumPlayers() == 0 then return end
    Isaac.RenderText("Wheelchair timeline: " .. #timeline .. "/" .. MAX_STATES .. "  [F5 / RT: back]", 52, 28, 0.72, 1.0, 0.72, 1.0)
    if message ~= "" and game:GetFrameCount() < messageUntil then
        Isaac.RenderText(message, 52, 40, 1.0, 0.9, 0.45, 1.0)
    end
end

Wheelchair:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, Wheelchair.OnGameStarted)
Wheelchair:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, Wheelchair.OnNewRoom)
Wheelchair:AddCallback(ModCallbacks.MC_POST_UPDATE, Wheelchair.OnUpdate)
Wheelchair:AddCallback(ModCallbacks.MC_POST_RENDER, Wheelchair.OnRender)
