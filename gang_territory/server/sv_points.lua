-- Admin Editor CRUD for spray points + neighbor graph

local function requireAdmin(source)
    if GT.isAdmin(source) then return true end
    TriggerClientEvent('gt:notify', source, 'admin_only', {})
    return false
end

lib.callback.register('gt:admin:createPoint', function(source, coords, heading, zoneId)
    if not requireAdmin(source) then return false end
    if type(coords) ~= 'vector3' and type(coords) ~= 'table' then return false end

    local x, y, z = coords.x or coords[1], coords.y or coords[2], coords.z or coords[3]
    local h = tonumber(heading) or 0.0

    local id = MySQL.insert.await(
        'INSERT INTO gt_spray_points (pos_x, pos_y, pos_z, heading, zone_id) VALUES (?, ?, ?, ?, ?)',
        { x, y, z, h, zoneId }
    )
    if not id then return false end

    GT.points[id] = {
        id = id, x = x, y = y, z = z, heading = h,
        owner_job = nil, locked_until = nil, zone_id = zoneId,
    }
    GT.broadcastPointUpdate(id)
    TriggerClientEvent('gt:pointCreated', -1, GT.points[id])
    return id
end)

lib.callback.register('gt:admin:deletePoint', function(source, pointId)
    if not requireAdmin(source) then return false end
    if not GT.points[pointId] then return false end

    MySQL.query.await('DELETE FROM gt_spray_points WHERE id = ?', { pointId })
    GT.points[pointId] = nil
    if GT.neighbors[pointId] then
        for nb in pairs(GT.neighbors[pointId]) do
            if GT.neighbors[nb] then GT.neighbors[nb][pointId] = nil end
        end
        GT.neighbors[pointId] = nil
    end
    TriggerClientEvent('gt:pointDeleted', -1, pointId)
    return true
end)

lib.callback.register('gt:admin:linkNeighbors', function(source, idA, idB)
    if not requireAdmin(source) then return false end
    if not GT.points[idA] or not GT.points[idB] or idA == idB then return false end

    local a, b = math.min(idA, idB), math.max(idA, idB)
    MySQL.query.await(
        'INSERT IGNORE INTO gt_neighbors (point_a_id, point_b_id) VALUES (?, ?)',
        { a, b }
    )

    GT.neighbors[idA] = GT.neighbors[idA] or {}
    GT.neighbors[idB] = GT.neighbors[idB] or {}
    GT.neighbors[idA][idB] = true
    GT.neighbors[idB][idA] = true
    TriggerClientEvent('gt:neighborsChanged', -1, idA, idB, true)
    return true
end)

lib.callback.register('gt:admin:unlinkNeighbors', function(source, idA, idB)
    if not requireAdmin(source) then return false end
    local a, b = math.min(idA, idB), math.max(idA, idB)
    MySQL.query.await(
        'DELETE FROM gt_neighbors WHERE point_a_id = ? AND point_b_id = ?',
        { a, b }
    )
    if GT.neighbors[idA] then GT.neighbors[idA][idB] = nil end
    if GT.neighbors[idB] then GT.neighbors[idB][idA] = nil end
    TriggerClientEvent('gt:neighborsChanged', -1, idA, idB, false)
    return true
end)

lib.callback.register('gt:admin:setGang', function(source, jobName, label, colorHex, blipColor)
    if not requireAdmin(source) then return false end
    if not jobName or jobName == '' then return false end

    MySQL.query.await([[
        INSERT INTO gt_gangs (job_name, label, color_hex, blip_color)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label),
                                color_hex = VALUES(color_hex),
                                blip_color = VALUES(blip_color)
    ]], { jobName, label, colorHex or '#FFFFFF', blipColor or 1 })

    GT.gangs[jobName] = {
        label = label, color_hex = colorHex or '#FFFFFF', blip_color = blipColor or 1,
    }
    TriggerClientEvent('gt:gangsUpdated', -1, GT.gangs)
    return true
end)

lib.callback.register('gt:admin:setHQ', function(source, jobName, pointId)
    if not requireAdmin(source) then return false end
    if not GT.gangs[jobName] or not GT.points[pointId] then return false end

    MySQL.query.await('UPDATE gt_gangs SET hq_point_id = ? WHERE job_name = ?',
        { pointId, jobName })
    GT.gangs[jobName].hq_point_id = pointId

    GT.points[pointId].owner_job = jobName
    MySQL.query.await('UPDATE gt_spray_points SET owner_job = ? WHERE id = ?',
        { jobName, pointId })
    GT.broadcastPointUpdate(pointId)
    TriggerClientEvent('gt:gangsUpdated', -1, GT.gangs)
    return true
end)

-- ============================================================
-- Zone CRUD
-- ============================================================

local function broadcastZones()
    TriggerClientEvent('gt:zonesUpdated', -1, GT.zones)
end

lib.callback.register('gt:admin:createZone', function(source, name)
    if not requireAdmin(source) then return false end
    name = (name and tostring(name):sub(1, 100)) or 'Unnamed'

    local id = MySQL.insert.await(
        'INSERT INTO gt_zones (name, min_x, min_y, max_x, max_y) VALUES (?, 0, 0, 0, 0)',
        { name }
    )
    if not id then return false end
    GT.zones[id] = { id = id, name = name, min_x = 0, min_y = 0, max_x = 0, max_y = 0 }
    broadcastZones()
    return id
end)

lib.callback.register('gt:admin:deleteZone', function(source, zoneId)
    if not requireAdmin(source) then return false end
    zoneId = tonumber(zoneId)
    if not GT.zones[zoneId] then return false end

    MySQL.query.await('DELETE FROM gt_zones WHERE id = ?', { zoneId })
    GT.zones[zoneId] = nil
    for _, p in pairs(GT.points) do
        if p.zone_id == zoneId then p.zone_id = nil end
    end
    broadcastZones()
    TriggerClientEvent('gt:fullRefresh', -1)
    return true
end)

lib.callback.register('gt:admin:renameZone', function(source, zoneId, name)
    if not requireAdmin(source) then return false end
    zoneId = tonumber(zoneId)
    if not GT.zones[zoneId] then return false end
    name = (name and tostring(name):sub(1, 100)) or GT.zones[zoneId].name

    MySQL.query.await('UPDATE gt_zones SET name = ? WHERE id = ?', { name, zoneId })
    GT.zones[zoneId].name = name
    broadcastZones()
    return true
end)

-- Set one corner (which = 'A' or 'B'). On the second call we normalise to min/max.
lib.callback.register('gt:admin:setZoneCorner', function(source, zoneId, which, x, y)
    if not requireAdmin(source) then return false end
    zoneId = tonumber(zoneId)
    local z = GT.zones[zoneId]
    if not z then return false end

    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end

    if which == 'A' then
        z._corner_a = { x = x, y = y }
        if z._corner_b then
            local ax, ay = z._corner_a.x, z._corner_a.y
            local bx, by = z._corner_b.x, z._corner_b.y
            z.min_x, z.max_x = math.min(ax, bx), math.max(ax, bx)
            z.min_y, z.max_y = math.min(ay, by), math.max(ay, by)
            MySQL.query.await(
                'UPDATE gt_zones SET min_x=?, min_y=?, max_x=?, max_y=? WHERE id=?',
                { z.min_x, z.min_y, z.max_x, z.max_y, zoneId })
        end
    elseif which == 'B' then
        z._corner_b = { x = x, y = y }
        if z._corner_a then
            local ax, ay = z._corner_a.x, z._corner_a.y
            local bx, by = z._corner_b.x, z._corner_b.y
            z.min_x, z.max_x = math.min(ax, bx), math.max(ax, bx)
            z.min_y, z.max_y = math.min(ay, by), math.max(ay, by)
            MySQL.query.await(
                'UPDATE gt_zones SET min_x=?, min_y=?, max_x=?, max_y=? WHERE id=?',
                { z.min_x, z.min_y, z.max_x, z.max_y, zoneId })
        end
    else
        return false
    end
    broadcastZones()
    return { min_x = z.min_x, min_y = z.min_y, max_x = z.max_x, max_y = z.max_y }
end)

lib.callback.register('gt:admin:assignPointToZone', function(source, pointId, zoneId)
    if not requireAdmin(source) then return false end
    pointId = tonumber(pointId)
    zoneId  = zoneId and tonumber(zoneId) or nil
    if not GT.points[pointId] then return false end
    if zoneId and not GT.zones[zoneId] then return false end

    MySQL.query.await('UPDATE gt_spray_points SET zone_id = ? WHERE id = ?',
        { zoneId, pointId })
    GT.points[pointId].zone_id = zoneId
    TriggerClientEvent('gt:pointUpdated', -1, pointId,
        GT.points[pointId].owner_job, GT.points[pointId].locked_until)
    return true
end)

-- Auto-assign every point whose (x,y) is inside the zone's bbox.
lib.callback.register('gt:admin:autoAssignZone', function(source, zoneId)
    if not requireAdmin(source) then return false end
    zoneId = tonumber(zoneId)
    local z = GT.zones[zoneId]
    if not z then return false end
    if z.min_x == z.max_x or z.min_y == z.max_y then return false end -- not set yet

    local touched = 0
    for id, p in pairs(GT.points) do
        if p.x >= z.min_x and p.x <= z.max_x
           and p.y >= z.min_y and p.y <= z.max_y then
            if p.zone_id ~= zoneId then
                p.zone_id = zoneId
                MySQL.query.await(
                    'UPDATE gt_spray_points SET zone_id = ? WHERE id = ?',
                    { zoneId, id })
                touched = touched + 1
            end
        end
    end
    TriggerClientEvent('gt:fullRefresh', -1)
    return touched
end)
