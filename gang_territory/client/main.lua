ESX = exports['es_extended']:getSharedObject()

GT = {
    gangs     = {},
    points    = {},   -- [id] = { id, x, y, z, heading, owner_job, locked_until, zone_id }
    neighbors = {},   -- [id] = { neighborId, ... }
    zones     = {},
    warOpen   = false,
}

local function rebuildFromServer()
    local data = lib.callback.await('gt:getMapData', false)
    if not data then return end
    GT.gangs     = data.gangs or {}
    GT.points    = data.points or {}
    GT.zones     = data.zones or {}
    GT.neighbors = data.neighbors or {}
    GT.warOpen   = data.warOpen and true or false
    TriggerEvent('gt:dataRebuilt')
end

CreateThread(function()
    while not ESX or not ESX.PlayerData or not ESX.PlayerData.identifier do Wait(200) end
    lib.locale(Config.Locale)
    rebuildFromServer()
end)

RegisterNetEvent('gt:pointUpdated', function(pointId, newOwner, lockedUntil)
    if GT.points[pointId] then
        GT.points[pointId].owner_job    = newOwner
        GT.points[pointId].locked_until = lockedUntil
        TriggerEvent('gt:pointUpdatedLocal', pointId)
    end
end)

RegisterNetEvent('gt:pointCreated', function(point)
    GT.points[point.id] = point
    TriggerEvent('gt:pointUpdatedLocal', point.id)
end)

RegisterNetEvent('gt:pointDeleted', function(pointId)
    GT.points[pointId]    = nil
    GT.neighbors[pointId] = nil
    TriggerEvent('gt:pointUpdatedLocal', pointId)
end)

RegisterNetEvent('gt:neighborsChanged', function(idA, idB, linked)
    GT.neighbors[idA] = GT.neighbors[idA] or {}
    GT.neighbors[idB] = GT.neighbors[idB] or {}
    if linked then
        table.insert(GT.neighbors[idA], idB)
        table.insert(GT.neighbors[idB], idA)
    else
        for i, v in ipairs(GT.neighbors[idA]) do if v == idB then table.remove(GT.neighbors[idA], i) break end end
        for i, v in ipairs(GT.neighbors[idB]) do if v == idA then table.remove(GT.neighbors[idB], i) break end end
    end
end)

RegisterNetEvent('gt:gangsUpdated', function(gangs)
    GT.gangs = gangs
    TriggerEvent('gt:dataRebuilt')
end)

RegisterNetEvent('gt:zonesUpdated', function(zones)
    GT.zones = zones
    TriggerEvent('gt:dataRebuilt')
end)

RegisterNetEvent('gt:warStateChanged', function(isOpen)
    GT.warOpen = isOpen and true or false
end)

RegisterNetEvent('gt:fullRefresh', function()
    rebuildFromServer()
end)
