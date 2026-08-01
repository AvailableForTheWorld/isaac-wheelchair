local Wheelchair = RegisterMod("Wheelchair Quick Rewind", 1)
local game = Game()
local cooldown = 0

local function rewind()
    if not game:IsPaused() and game:GetNumPlayers() > 0 then
        cooldown = 45
        Isaac.ExecuteCommand("rewind")
    end
end

function Wheelchair:OnUpdate()
    if cooldown > 0 then cooldown = cooldown - 1 return end
    if Input.IsButtonTriggered(Keyboard.KEY_F5, 0) then rewind() return end
end

Wheelchair:AddCallback(ModCallbacks.MC_POST_UPDATE, Wheelchair.OnUpdate)
