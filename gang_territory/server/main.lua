ESX = exports['es_extended']:getSharedObject()

GT = {
    gangs        = {},   -- [job_name] = { label, color_hex, blip_color, hq_point_id }
    points       = {},   -- [id]       = { id, x, y, z, heading, owner_job, locked_until, zone_id }
    neighbors    = {},   -- [point_id] = { neighbor_id = true, ... }
    zones        = {},   -- [id]       = { id, name, min_x, min_y, max_x, max_y }
    inProgress   = {},   -- [point_id] = { source, timeoutId, startedAt }
    cooldowns    = {},   -- [identifier] = expiryEpochMs
    adminWarOpen = nil,  -- nil = follow window, true/false = override
}

local function loadGangs()
    GT.gangs = {}
    local rows = MySQL.query.await('SELECT * FROM gt_gangs')
    for _, r in ipairs(rows or {}) do
        GT.gangs[r.job_name] = {
            label       = r.label,
            color_hex   = r.color_hex,
            blip_color  = r.blip_color,
            hq_point_id = r.hq_point_id,
        }
    end
end

local function loadPoints()
    GT.points = {}
    local rows = MySQL.query.await('SELECT * FROM gt_spray_points')
    for _, r in ipairs(rows or {}) do
        GT.points[r.id] = {
            id           = r.id,
            x            = r.pos_x,
            y            = r.pos_y,
            z            = r.pos_z,
            heading      = r.heading,
            owner_job    = r.owner_job,
            locked_until = r.locked_until,
            zone_id      = r.zone_id,
        }
    end
end

local function loadNeighbors()
    GT.neighbors = {}
    local rows = MySQL.query.await('SELECT point_a_id, point_b_id FROM gt_neighbors')
    for _, r in ipairs(rows or {}) do
        GT.neighbors[r.point_a_id] = GT.neighbors[r.point_a_id] or {}
        GT.neighbors[r.point_a_id][r.point_b_id] = true
        GT.neighbors[r.point_b_id] = GT.neighbors[r.point_b_id] or {}
        GT.neighbors[r.point_b_id][r.point_a_id] = true
    end
end

local function loadZones()
    GT.zones = {}
    local rows = MySQL.query.await('SELECT * FROM gt_zones')
    for _, r in ipairs(rows or {}) do
        GT.zones[r.id] = r
    end
end

function GT.isAdmin(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    for _, group in ipairs(Config.AdminGroups) do
        if xPlayer.getGroup() == group then return true end
    end
    return false
end

function GT.isWarOpen()
    if Config.WarWindow.adminOverride and GT.adminWarOpen ~= nil then
        return GT.adminWarOpen
    end
    return GTUtils.isInWarWindow()
end

function GT.countOnlineByJob(jobName)
    local n = 0
    for _, pid in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(pid))
        if xPlayer and xPlayer.job and xPlayer.job.name == jobName then
            n = n + 1
        end
    end
    return n
end

function GT.broadcastPointUpdate(pointId)
    local p = GT.points[pointId]
    if not p then return end
    TriggerClientEvent('gt:pointUpdated', -1, pointId, p.owner_job, p.locked_until)
end

function GT.notifyGang(jobName, key, ...)
    local args = { ... }
    for _, pid in ipairs(GetPlayers()) do
        local xPlayer = ESX.GetPlayerFromId(tonumber(pid))
        if xPlayer and xPlayer.job and xPlayer.job.name == jobName then
            TriggerClientEvent('gt:notify', tonumber(pid), key, args)
        end
    end
end

CreateThread(function()
    while GetResourceState('es_extended') ~= 'started' do Wait(200) end
    while GetResourceState('oxmysql')     ~= 'started' do Wait(200) end

    lib.locale(Config.Locale)

    loadGangs()
    loadZones()
    loadPoints()
    loadNeighbors()

    print(('[gang_territory] loaded %d gangs, %d points, %d zones')
        :format(GTUtils.tableLength(GT.gangs),
                GTUtils.tableLength(GT.points),
                GTUtils.tableLength(GT.zones)))
end)

-- Public map data callback
lib.callback.register('gt:getMapData', function(source)
    local out = { gangs = GT.gangs, points = {}, zones = GT.zones, neighbors = {} }
    for id, p in pairs(GT.points) do out.points[id] = p end
    for id, set in pairs(GT.neighbors) do
        local list = {}
        for nb in pairs(set) do list[#list + 1] = nb end
        out.neighbors[id] = list
    end
    out.warOpen = GT.isWarOpen()
    return out
end)
