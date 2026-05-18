-- Capture interaction: detect nearest point → press E → progressBar → confirm
-- Cancellation: move / die / take damage / release key

local active = nil -- { pointId, started, watchdog }

local function nearestPoint()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local bestId, bestDist
    for id, p in pairs(GT.points) do
        local dx, dy, dz = p.x - coords.x, p.y - coords.y, p.z - coords.z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d <= Config.Spray.distance and (not bestDist or d < bestDist) then
            bestId, bestDist = id, d
        end
    end
    return bestId
end

local function cancelLocal(reason)
    if not active then return end
    TriggerServerEvent('gt:cancelCapture', active.pointId)
    active = nil
    ClearPedTasksImmediately(PlayerPedId())
    if lib.progressActive() then lib.cancelProgress() end
    lib.notify({ description = locale(reason or 'spray_cancelled') or 'Cancelled', type = 'error' })
end

local function startCapture(pointId)
    if active then return end
    local p = GT.points[pointId]
    if not p then return end

    local ok, payload, args = lib.callback.await('gt:tryCapture', false, pointId)
    if not ok then
        local key = payload or 'no_neighbor'
        lib.notify({ description = locale(key, table.unpack(args or {})) or key, type = 'error' })
        return
    end

    local duration = tonumber(payload) or Config.Spray.progressMs
    active = { pointId = pointId, started = GetGameTimer() }

    -- Play anim (best-effort)
    local ped = PlayerPedId()
    lib.requestAnimDict(Config.Spray.animDict, 5000)
    TaskPlayAnim(ped, Config.Spray.animDict, Config.Spray.animName,
        2.0, 2.0, duration, 49, 0, false, false, false)

    local done = lib.progressBar({
        duration = duration,
        label    = locale('spraying') or 'Spraying...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { car = true, move = Config.Spray.cancelOnMove, combat = true },
        anim         = { dict = Config.Spray.animDict, clip = Config.Spray.animName },
    })

    if not active then return end -- already cancelled externally

    if not done then
        cancelLocal('spray_cancelled')
        return
    end

    -- Progress finished locally; server will finalize via its SetTimeout
    active = nil
    ClearPedTasks(PlayerPedId())
end

-- Listen for server-side cancel
RegisterNetEvent('gt:captureCancelled', function(pointId, reasonKey)
    if active and active.pointId == pointId then
        active = nil
        if lib.progressActive() then lib.cancelProgress() end
        ClearPedTasksImmediately(PlayerPedId())
        lib.notify({ description = locale(reasonKey or 'spray_cancelled') or 'Cancelled',
                     type = 'error' })
    end
end)

-- Watch for damage / death while capturing
CreateThread(function()
    while true do
        Wait(250)
        if active then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                cancelLocal('spray_cancelled')
            elseif Config.Spray.cancelOnHit
                and (HasEntityBeenDamagedByAnyPed(ped) or HasEntityBeenDamagedByAnyVehicle(ped)) then
                ClearEntityLastDamageEntity(ped)
                cancelLocal('spray_cancelled')
            end
        end
    end
end)

-- Interaction prompt + key handler
CreateThread(function()
    while true do
        local sleep = 500
        if GT.warOpen and not active then
            local pid = nearestPoint()
            if pid then
                sleep = 0
                local p   = GT.points[pid]
                local pj  = ESX.PlayerData and ESX.PlayerData.job and ESX.PlayerData.job.name
                local mine = p.owner_job == pj
                if not mine then
                    lib.showTextUI(('[E] %s'):format(locale('spraying') or 'Spray'),
                        { position = 'right-center' })
                    if IsControlJustReleased(0, Config.Keys.sprayKey) then
                        lib.hideTextUI()
                        startCapture(pid)
                    end
                else
                    lib.hideTextUI()
                end
            else
                lib.hideTextUI()
            end
        else
            lib.hideTextUI()
        end
        Wait(sleep)
    end
end)
