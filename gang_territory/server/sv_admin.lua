local function isConsoleOrAdmin(source)
    if source == 0 then return true end
    return GT.isAdmin(source)
end

RegisterCommand('openwar', function(source)
    if not isConsoleOrAdmin(source) then return end
    GT.adminWarOpen = true
    TriggerClientEvent('gt:warStateChanged', -1, true)
    if source > 0 then TriggerClientEvent('gt:notify', source, 'war_opened', {}) end
    print('[gang_territory] war opened (admin override) by ' .. tostring(source))
end, false)

RegisterCommand('closewar', function(source)
    if not isConsoleOrAdmin(source) then return end
    GT.adminWarOpen = false
    TriggerClientEvent('gt:warStateChanged', -1, false)
    if source > 0 then TriggerClientEvent('gt:notify', source, 'war_closed_admin', {}) end
    print('[gang_territory] war closed (admin override) by ' .. tostring(source))
end, false)

RegisterCommand('warauto', function(source)
    if not isConsoleOrAdmin(source) then return end
    GT.adminWarOpen = nil
    TriggerClientEvent('gt:warStateChanged', -1, GT.isWarOpen())
    print('[gang_territory] war window restored to schedule')
end, false)

RegisterCommand('gangreset', function(source)
    if not isConsoleOrAdmin(source) then return end
    MySQL.query.await('UPDATE gt_spray_points SET owner_job = NULL, locked_until = NULL')
    for _, p in pairs(GT.points) do
        p.owner_job   = nil
        p.locked_until = nil
    end
    for job, g in pairs(GT.gangs) do
        if g.hq_point_id and GT.points[g.hq_point_id] then
            GT.points[g.hq_point_id].owner_job = job
            MySQL.query.await('UPDATE gt_spray_points SET owner_job = ? WHERE id = ?',
                { job, g.hq_point_id })
        end
    end
    TriggerClientEvent('gt:fullRefresh', -1)
    print('[gang_territory] reset done by ' .. tostring(source))
end, false)

-- Allow admin to toggle editor for self
RegisterCommand('gangeditor', function(source)
    if not GT.isAdmin(source) then return end
    TriggerClientEvent('gt:openEditor', source)
end, false)
