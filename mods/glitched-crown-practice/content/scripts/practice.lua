-- Pure cycle/statistics logic, shared by the game and the regression checks.
local Practice = {}
Practice.SPEED_MIN = 0.70
Practice.SPEED_MAX = 2.00
Practice.SPEED_MEAN = 1.35
Practice.SPEED_STDDEV = 0.22

function Practice.newStats()
    -- `other` retains pre-v2 errors whose +/-2 direction was never saved.
    return { total = 0, correct = 0, plus1 = 0, minus1 = 0, plus2 = 0, minus2 = 0, other = 0 }
end

function Practice.restoreStats(saved)
    local stats = Practice.newStats()
    if type(saved) ~= "table" then return stats end
    for _, key in ipairs({ "correct", "plus1", "minus1", "plus2", "minus2", "other" }) do
        local value = saved[key]
        if type(value) == "number" and value == value and value >= 0 and value < math.huge then
            stats[key] = math.floor(value)
        end
    end
    stats.total = stats.correct + stats.plus1 + stats.minus1 + stats.plus2 + stats.minus2 + stats.other
    return stats
end

function Practice.restoreSpeed(value)
    if type(value) == "number" and value >= Practice.SPEED_MIN and value <= Practice.SPEED_MAX then
        return math.floor(value * 100 + 0.5) / 100
    end
end

function Practice.sampleSpeed(randomFloat)
    -- Box-Muller N(1.35, 0.22^2), conditioned on [0.70, 2.00]. Reject tails
    -- instead of clamping them, which would pile up samples at the endpoints.
    for _ = 1, 128 do
        local u, v = 1 - randomFloat(), randomFloat()
        if u > 0 and u <= 1 and v >= 0 and v < 1 then
            local z = math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
            local speed = Practice.SPEED_MEAN + Practice.SPEED_STDDEV * z
            if speed >= Practice.SPEED_MIN and speed <= Practice.SPEED_MAX then
                return math.floor(speed * 100 + 0.5) / 100
            end
        end
    end
    -- Only a broken RNG should reach this safety bound.
    return Practice.SPEED_MEAN
end

-- Generation order need not match animation order. Learn actual transitions and
-- require the first item to reappear after all five distinct candidates.
function Practice.observeCycle(cycle, itemId, candidates)
    cycle.order = cycle.order or {}
    local allowed = false
    for _, id in ipairs(candidates) do
        if itemId == id then allowed = true; break end
    end
    if not allowed then return "invalid" end
    if itemId == cycle.lastId then return "learning" end
    cycle.lastId = itemId
    for index, id in ipairs(cycle.order) do
        if itemId == id then
            if index == 1 and #cycle.order == 5 then return "complete" end
            return "invalid"
        end
    end
    cycle.order[#cycle.order + 1] = itemId
    return "learning"
end

function Practice.offset(order, targetId, pickedId)
    if #order ~= 5 then return nil end
    local targetIndex, pickedIndex
    for index, id in ipairs(order) do
        if id == targetId then targetIndex = index end
        if id == pickedId then pickedIndex = index end
    end
    if not targetIndex or not pickedIndex then return nil end
    local delta = (pickedIndex - targetIndex) % 5
    if delta > 2 then delta = delta - 5 end
    return delta
end

function Practice.record(stats, offset)
    if offset == nil or offset < -2 or offset > 2 or offset % 1 ~= 0 then return false end
    stats.total = stats.total + 1
    if offset == 0 then stats.correct = stats.correct + 1
    elseif offset == 1 then stats.plus1 = stats.plus1 + 1
    elseif offset == -1 then stats.minus1 = stats.minus1 + 1
    elseif offset == 2 then stats.plus2 = stats.plus2 + 1
    else stats.minus2 = stats.minus2 + 1 end
    return true
end

return Practice
