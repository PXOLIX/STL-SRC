-- Capture pipeline: validate → start progress → finalize

local function nowMs() return os.time() * 1000 end

local function hasFriendlyNeighbor(pointId, jobName)
    local gang = GT.gangs[jobName]
    if gang and gang.hq_point_id == pointId then return true end -- HQ ตัวเอง

    local set = GT.neighbors[pointId]
    if not set then return false end
    for nbId in pairs(set) do
        local nb = GT.points[nbId]
        if nb and nb.owner_job == jobName then return true end
    end
    return false
end

local function validateRequest(source, pointId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'no_job' end

    local job = xPlayer.job and xPlayer.job.name
    if not job or not GT.gangs[job] then return false, 'no_job' end

    if not GT.isWarOpen() then return false, 'war_closed' end

    if GT.countOnlineByJob(job) < Config.MinMembersOnline then
        return false, 'members_too_few', { Config.MinMembersOnline }
    end

    local point = GT.points[pointId]
    if not point then return false, 'no_neighbor' end

    if point.owner_job == job then return false, 'already_yours' end

    if Config.CaptureLock.enabled and point.locked_until and point.locked_until > nowMs() then
        local mins = math.ceil((point.locked_until - nowMs()) / 60000)
        return false, 'point_locked', { mins }
    end

    if Config.PlayerCooldown.enabled then
        local id = xPlayer.identifier
        local exp = GT.cooldowns[id]
        if exp and exp > nowMs() then
            return false, 'on_cooldown', { math.ceil((exp - nowMs()) / 1000) }
        end
    end

    local ped = GetPlayerPed(source)
    local pCoords = GetEntityCoords(ped)
    local dist = #(pCoords - vector3(point.x, point.y, point.z))
    if dist > Config.Spray.distance + 1.5 then return false, 'too_far' end

    if not hasFriendlyNeighbor(pointId, job) then return false, 'no_neighbor' end

    if Config.Spray.item then
        local item = xPlayer.getInventoryItem(Config.Spray.item)
        if not item or item.count < Config.Spray.itemCount then
            return false, 'no_item'
        end
    end

    if GT.inProgress[pointId] then return false, 'point_locked', { 1 } end

    return true, xPlayer, point
end

local function finalize(pointId, source, fromJob, toJob)
    local point = GT.points[pointId]
    if not point then return end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    -- Re-check item one more time (player may have dropped/used it)
    if Config.Spray.item then
        local item = xPlayer.getInventoryItem(Config.Spray.item)
        if not item or item.count < Config.Spray.itemCount then return end
        xPlayer.removeInventoryItem(Config.Spray.item, Config.Spray.itemCount)
    end

    local lockUntil = Config.CaptureLock.enabled
        and (nowMs() + Config.CaptureLock.durationMin * 60000) or nil

    point.owner_job    = toJob
    point.locked_until = lockUntil

    MySQL.query.await(
        'UPDATE gt_spray_points SET owner_job = ?, locked_until = ? WHERE id = ?',
        { toJob, lockUntil, pointId }
    )
    MySQL.insert.await([[
        INSERT INTO gt_captures
            (point_id, player_identifier, from_job, to_job, week_number)
        VALUES (?, ?, ?, ?, ?)
    ]], { pointId, xPlayer.identifier, fromJob, toJob, GTUtils.currentWeekNumber() })

    if Config.PlayerCooldown.enabled then
        GT.cooldowns[xPlayer.identifier] = nowMs() + Config.PlayerCooldown.seconds * 1000
    end

    GT.broadcastPointUpdate(pointId)
    TriggerClientEvent('gt:notify', source, 'spray_success', {})

    if fromJob and fromJob ~= toJob then
        GT.notifyGang(fromJob, 'zone_lost', {})
    end
    GT.notifyGang(toJob, 'zone_under_attack', {})
end

local function cancel(pointId, source, reasonKey)
    local prog = GT.inProgress[pointId]
    if not prog then return end
    if prog.source ~= source then return end
    GT.inProgress[pointId] = nil
    TriggerClientEvent('gt:captureCancelled', source, pointId, reasonKey or 'spray_cancelled')
end

-- Public: client tries to start capture
lib.callback.register('gt:tryCapture', function(source, pointId)
    pointId = tonumber(pointId)
    if not pointId then return false, 'no_neighbor' end

    local ok, a, b = validateRequest(source, pointId)
    if not ok then
        return false, a, b
    end
    local xPlayer, point = a, b

    GT.inProgress[pointId] = {
        source    = source,
        startedAt = nowMs(),
        fromJob   = point.owner_job,
        toJob     = xPlayer.job.name,
    }

    SetTimeout(Config.Spray.progressMs, function()
        local prog = GT.inProgress[pointId]
        if not prog or prog.source ~= source then return end
        GT.inProgress[pointId] = nil
        finalize(pointId, source, prog.fromJob, prog.toJob)
    end)

    return true, Config.Spray.progressMs
end)

-- Public: client reports cancellation (moved, hit, released key)
RegisterNetEvent('gt:cancelCapture', function(pointId)
    local src = source
    pointId = tonumber(pointId)
    if not pointId then return end
    cancel(pointId, src, 'spray_cancelled')
end)

AddEventHandler('playerDropped', function()
    local src = source
    for pid, prog in pairs(GT.inProgress) do
        if prog.source == src then GT.inProgress[pid] = nil end
    end
end)
