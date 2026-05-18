-- Admin Editor (F6): in-game NUI for spray-point CRUD + neighbor linking

local editorOpen   = false
local linkSourceId = nil -- when set, next clicked point links to this one
local previewOpen  = false

local function setNui(state)
    SetNuiFocus(state, state)
    SendNUIMessage({ action = state and 'openEditor' or 'close' })
end

local function refreshEditorData()
    local points = {}
    for id, p in pairs(GT.points) do
        points[#points + 1] = {
            id = id, x = p.x, y = p.y, z = p.z,
            owner_job = p.owner_job, zone_id = p.zone_id,
        }
    end
    local neighbors = {}
    for id, list in pairs(GT.neighbors) do neighbors[id] = list end
    local zones = {}
    for id, z in pairs(GT.zones) do zones[#zones + 1] = z end
    SendNUIMessage({
        action    = 'editorData',
        points    = points,
        neighbors = neighbors,
        gangs     = GT.gangs,
        zones     = zones,
        linkSrc   = linkSourceId,
    })
end

AddEventHandler('gt:dataRebuilt', function()
    if editorOpen then refreshEditorData() end
end)

local function openEditor()
    if editorOpen then return end
    editorOpen = true
    setNui(true)
    refreshEditorData()
end

local function closeEditor()
    editorOpen = false
    linkSourceId = nil
    setNui(false)
end

RegisterNetEvent('gt:openEditor', openEditor)

-- Keybind via ox_lib
lib.addKeybind({
    name        = 'gt_open_editor',
    description = 'Open Gang Territory Editor',
    defaultKey  = Config.Keys.openEditor,
    onPressed   = function() openEditor() end,
})

-- NUI callbacks
RegisterNUICallback('closeEditor', function(_, cb)
    closeEditor(); cb('ok')
end)

RegisterNUICallback('createHere', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local zoneId = tonumber(data and data.zoneId) or nil
    local newId = lib.callback.await('gt:admin:createPoint', false,
        vector3(coords.x, coords.y, coords.z), heading, zoneId)
    cb({ ok = newId and true or false, id = newId })
    refreshEditorData()
end)

RegisterNUICallback('deletePoint', function(data, cb)
    local ok = lib.callback.await('gt:admin:deletePoint', false, tonumber(data.id))
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('startLink', function(data, cb)
    linkSourceId = tonumber(data.id)
    cb({ ok = true })
    refreshEditorData()
end)

RegisterNUICallback('cancelLink', function(_, cb)
    linkSourceId = nil
    cb({ ok = true })
    refreshEditorData()
end)

RegisterNUICallback('finishLink', function(data, cb)
    local target = tonumber(data.id)
    if not linkSourceId or not target or linkSourceId == target then
        cb({ ok = false }); return
    end
    local ok = lib.callback.await('gt:admin:linkNeighbors', false, linkSourceId, target)
    linkSourceId = nil
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('unlink', function(data, cb)
    local a, b = tonumber(data.a), tonumber(data.b)
    local ok = lib.callback.await('gt:admin:unlinkNeighbors', false, a, b)
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('teleportTo', function(data, cb)
    local p = GT.points[tonumber(data.id)]
    if p then
        SetEntityCoords(PlayerPedId(), p.x, p.y, p.z + 0.5, false, false, false, false)
    end
    cb('ok')
end)

RegisterNUICallback('setGang', function(data, cb)
    local ok = lib.callback.await('gt:admin:setGang', false,
        data.job, data.label, data.color, tonumber(data.blip) or 1)
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('setHQ', function(data, cb)
    local ok = lib.callback.await('gt:admin:setHQ', false, data.job, tonumber(data.id))
    cb({ ok = ok })
    refreshEditorData()
end)

-- ============== Zone callbacks ==============

RegisterNUICallback('createZone', function(data, cb)
    local id = lib.callback.await('gt:admin:createZone', false, data.name)
    cb({ ok = id and true or false, id = id })
    refreshEditorData()
end)

RegisterNUICallback('deleteZone', function(data, cb)
    local ok = lib.callback.await('gt:admin:deleteZone', false, tonumber(data.id))
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('renameZone', function(data, cb)
    local ok = lib.callback.await('gt:admin:renameZone', false,
        tonumber(data.id), data.name)
    cb({ ok = ok })
    refreshEditorData()
end)

RegisterNUICallback('setZoneCorner', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local res = lib.callback.await('gt:admin:setZoneCorner', false,
        tonumber(data.id), data.which, coords.x, coords.y)
    cb({ ok = res and true or false, bbox = res })
    refreshEditorData()
end)

RegisterNUICallback('autoAssignZone', function(data, cb)
    local n = lib.callback.await('gt:admin:autoAssignZone', false, tonumber(data.id))
    cb({ ok = n and true or false, count = n })
    refreshEditorData()
end)

RegisterNUICallback('assignPointZone', function(data, cb)
    local zoneId = data.zoneId == '' and nil or tonumber(data.zoneId)
    local ok = lib.callback.await('gt:admin:assignPointToZone', false,
        tonumber(data.pointId), zoneId)
    cb({ ok = ok })
    refreshEditorData()
end)

-- Visual preview: when editor is open, highlight every point with debug spheres + ids
CreateThread(function()
    while true do
        local sleep = 1000
        if editorOpen then
            sleep = 0
            for id, p in pairs(GT.points) do
                local r, g, b = 255, 255, 255
                if p.owner_job and GT.gangs[p.owner_job] then
                    r, g, b = GTUtils.hexToRgb(GT.gangs[p.owner_job].color_hex)
                end
                DrawMarker(28, p.x, p.y, p.z, 0,0,0, 0,0,0, 0.4,0.4,0.4,
                    r, g, b, 200, false, false, 2, false, nil, nil, false)
                -- draw lines to neighbors
                if GT.neighbors[id] then
                    for _, nb in ipairs(GT.neighbors[id]) do
                        local np = GT.points[nb]
                        if np and nb > id then
                            DrawLine(p.x, p.y, p.z, np.x, np.y, np.z, 0, 255, 255, 200)
                        end
                    end
                end
            end
            if linkSourceId and GT.points[linkSourceId] then
                local p = GT.points[linkSourceId]
                DrawMarker(1, p.x, p.y, p.z - 1.0, 0,0,0, 0,0,0, 1.2,1.2,2.0,
                    255, 255, 0, 100, false, false, 2, false, nil, nil, false)
            end

            -- Draw zone bounding boxes as 4 connected lines on the ground
            local ped = PlayerPedId()
            local pz = GetEntityCoords(ped).z
            for _, z in pairs(GT.zones) do
                if z.min_x ~= z.max_x and z.min_y ~= z.max_y then
                    local h = pz
                    DrawLine(z.min_x, z.min_y, h, z.max_x, z.min_y, h, 255, 165, 0, 200)
                    DrawLine(z.max_x, z.min_y, h, z.max_x, z.max_y, h, 255, 165, 0, 200)
                    DrawLine(z.max_x, z.max_y, h, z.min_x, z.max_y, h, 255, 165, 0, 200)
                    DrawLine(z.min_x, z.max_y, h, z.min_x, z.min_y, h, 255, 165, 0, 200)
                end
            end
        end
        Wait(sleep)
    end
end)
