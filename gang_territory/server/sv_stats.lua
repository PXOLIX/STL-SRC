-- Leaderboard + MVP queries

local function buildLeaderboard()
    local totals = {}
    local owned = 0
    for _, p in pairs(GT.points) do
        if p.owner_job then
            totals[p.owner_job] = (totals[p.owner_job] or 0) + 1
            owned = owned + 1
        end
    end

    local list = {}
    for job, count in pairs(totals) do
        local g = GT.gangs[job] or {}
        list[#list + 1] = {
            job        = job,
            label      = g.label or job,
            color_hex  = g.color_hex or '#FFFFFF',
            blip_color = g.blip_color or 1,
            points     = count,
            percent    = owned > 0 and (count / owned * 100.0) or 0.0,
        }
    end

    table.sort(list, function(a, b) return a.points > b.points end)
    return list, owned
end

lib.callback.register('gt:getLeaderboard', function()
    local list, total = buildLeaderboard()
    return { gangs = list, totalOwned = total, totalPoints = GTUtils.tableLength(GT.points) }
end)

lib.callback.register('gt:getWeeklyMVP', function(_, jobName)
    local week = GTUtils.currentWeekNumber()
    local query = [[
        SELECT player_identifier, COUNT(*) AS captures
        FROM gt_captures
        WHERE week_number = ? AND to_job = ?
        GROUP BY player_identifier
        ORDER BY captures DESC
        LIMIT 5
    ]]
    return MySQL.query.await(query, { week, jobName }) or {}
end)

lib.callback.register('gt:getMyStats', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local week = GTUtils.currentWeekNumber()
    local row = MySQL.single.await([[
        SELECT COUNT(*) AS captures
        FROM gt_captures
        WHERE player_identifier = ? AND week_number = ?
    ]], { xPlayer.identifier, week })
    return {
        identifier = xPlayer.identifier,
        weekly_captures = row and row.captures or 0,
    }
end)

lib.callback.register('gt:getRecentCaptures', function(_, limit)
    limit = math.min(tonumber(limit) or 20, 100)
    return MySQL.query.await([[
        SELECT c.point_id, c.from_job, c.to_job, c.captured_at,
               g.label AS to_label, g.color_hex AS to_color
        FROM gt_captures c
        LEFT JOIN gt_gangs g ON g.job_name = c.to_job
        ORDER BY c.captured_at DESC
        LIMIT ?
    ]], { limit }) or {}
end)
