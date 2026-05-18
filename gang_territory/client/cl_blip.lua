-- Map blips: per-zone shaded area + (optional) per-point dot
-- Re-coloured whenever ownership changes.

local zoneBlips  = {} -- [zoneId]  = blip handle
local pointBlips = {} -- [pointId] = blip handle

local function colorFor(job)
    if job and GT.gangs[job] then return GT.gangs[job].blip_color end
    return 0 -- white = neutral
end

-- Compute dominant owner of a zone (most points)
local function dominantOwner(zoneId)
    local counts = {}
    for _, p in pairs(GT.points) do
        if p.zone_id == zoneId and p.owner_job then
            counts[p.owner_job] = (counts[p.owner_job] or 0) + 1
        end
    end
    local best, bestCount = nil, 0
    for job, c in pairs(counts) do
        if c > bestCount then best, bestCount = job, c end
    end
    return best
end

local function refreshZoneBlip(zoneId)
    if not Config.Blip.showZones then return end
    local z = GT.zones[zoneId]
    if not z then return end

    if zoneBlips[zoneId] then RemoveBlip(zoneBlips[zoneId]) end

    local cx, cy = (z.min_x + z.max_x) / 2.0, (z.min_y + z.max_y) / 2.0
    local w, h   = math.abs(z.max_x - z.min_x), math.abs(z.max_y - z.min_y)
    local blip   = AddBlipForArea(cx, cy, 0.0, w, h)
    SetBlipColour(blip, colorFor(dominantOwner(zoneId)))
    SetBlipAlpha(blip, Config.Blip.alpha)
    zoneBlips[zoneId] = blip
end

local function refreshPointBlip(pointId)
    if not Config.Blip.showPoints then return end
    local p = GT.points[pointId]
    if not p then
        if pointBlips[pointId] then RemoveBlip(pointBlips[pointId]); pointBlips[pointId] = nil end
        return
    end

    if pointBlips[pointId] then RemoveBlip(pointBlips[pointId]) end
    local blip = AddBlipForCoord(p.x, p.y, p.z)
    SetBlipSprite(blip, 271) -- spray icon
    SetBlipScale(blip, 0.7)
    SetBlipColour(blip, colorFor(p.owner_job))
    SetBlipAsShortRange(blip, true)
    pointBlips[pointId] = blip
end

local function rebuildAll()
    for id, b in pairs(zoneBlips)  do RemoveBlip(b); zoneBlips[id]  = nil end
    for id, b in pairs(pointBlips) do RemoveBlip(b); pointBlips[id] = nil end
    for zid in pairs(GT.zones)  do refreshZoneBlip(zid)  end
    for pid in pairs(GT.points) do refreshPointBlip(pid) end
end

AddEventHandler('gt:dataRebuilt',       rebuildAll)
AddEventHandler('gt:pointUpdatedLocal', function(pointId)
    refreshPointBlip(pointId)
    local p = GT.points[pointId]
    if p and p.zone_id then refreshZoneBlip(p.zone_id) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(zoneBlips)  do RemoveBlip(b) end
    for _, b in pairs(pointBlips) do RemoveBlip(b) end
end)

-- 3D marker for nearby points (only when close, low frequency to save FPS)
CreateThread(function()
    while true do
        local sleep = 1000
        local ped   = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local nearAny = false

        for _, p in pairs(GT.points) do
            local dx, dy, dz = p.x - coords.x, p.y - coords.y, p.z - coords.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist < Config.Marker.drawDistance then
                nearAny = true
                local r, g, b = 255, 255, 255
                if p.owner_job and GT.gangs[p.owner_job] then
                    r, g, b = GTUtils.hexToRgb(GT.gangs[p.owner_job].color_hex)
                end
                DrawMarker(
                    Config.Marker.type, p.x, p.y, p.z - 0.9,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    Config.Marker.size.x, Config.Marker.size.y, Config.Marker.size.z,
                    r, g, b, 150, false, true, 2, false, nil, nil, false)
            end
        end

        if nearAny then sleep = 0 end
        Wait(sleep)
    end
end)
