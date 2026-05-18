-- Passive income loop + weekly reset cron

local function payPassiveIncome()
    if not Config.PassiveIncome.enabled then return end
    local totals = {}
    for _, p in pairs(GT.points) do
        if p.owner_job then totals[p.owner_job] = (totals[p.owner_job] or 0) + 1 end
    end
    for job, count in pairs(totals) do
        local amount = count * Config.PassiveIncome.moneyPerPoint
        if amount > 0 then
            -- Add to society account if present, otherwise notify members
            local account = exports['esx_addonaccount']
                and exports['esx_addonaccount']:GetSharedAccount('society_' .. job)
            if account and account.addMoney then
                account.addMoney(amount)
            end
            GT.notifyGang(job, 'passive_paid', { amount })
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.PassiveIncome.intervalMin * 60 * 1000)
        if Config.PassiveIncome.enabled then payPassiveIncome() end
    end
end)

-- ============ Weekly reset ============

local function shouldRunWeekly()
    if not Config.Weekly.enabled then return false end
    local dow  = tonumber(os.date('%u'))                  -- 1=Mon ... 7=Sun
    local hour = tonumber(os.date('%H'))
    local week = GTUtils.currentWeekNumber()

    if dow ~= Config.Weekly.resetDow then return false end
    if hour ~= Config.Weekly.resetHour then return false end

    -- Skip if we've already paid this week
    local row = MySQL.single.await(
        'SELECT 1 AS x FROM gt_weekly_winners WHERE week_number = ? LIMIT 1', { week })
    return row == nil
end

local function distributeRewards(rankedGangs, mvpByJob)
    for rank, entry in ipairs(rankedGangs) do
        local reward = Config.Weekly.rewards[rank]
        if reward then
            -- pay each online member; rest can claim via /claimreward (out of scope here)
            for _, pid in ipairs(GetPlayers()) do
                local xPlayer = ESX.GetPlayerFromId(tonumber(pid))
                if xPlayer and xPlayer.job and xPlayer.job.name == entry.job then
                    if reward.money and reward.money > 0 then
                        xPlayer.addMoney(reward.money)
                    end
                    if reward.item and reward.count and reward.count > 0 then
                        xPlayer.addInventoryItem(reward.item, reward.count)
                    end
                end
            end
            GT.notifyGang(entry.job, 'weekly_reset_done', { entry.label })
        end

        local mvp = mvpByJob[entry.job]
        if mvp then
            local r = Config.Weekly.mvpReward
            for _, pid in ipairs(GetPlayers()) do
                local xPlayer = ESX.GetPlayerFromId(tonumber(pid))
                if xPlayer and xPlayer.identifier == mvp.player_identifier then
                    if r.money and r.money > 0 then xPlayer.addMoney(r.money) end
                    if r.item and r.count and r.count > 0 then
                        xPlayer.addInventoryItem(r.item, r.count)
                    end
                    TriggerClientEvent('gt:notify', tonumber(pid), 'mvp_rewarded', {})
                end
            end
        end
    end
end

local function runWeekly()
    local week = GTUtils.currentWeekNumber()

    -- Snapshot current standings
    local totals = {}
    for _, p in pairs(GT.points) do
        if p.owner_job then totals[p.owner_job] = (totals[p.owner_job] or 0) + 1 end
    end
    local ranked = {}
    for job, count in pairs(totals) do
        ranked[#ranked + 1] = {
            job = job, count = count,
            label = (GT.gangs[job] and GT.gangs[job].label) or job,
        }
    end
    table.sort(ranked, function(a, b) return a.count > b.count end)

    -- MVP per gang
    local mvpByJob = {}
    for _, entry in ipairs(ranked) do
        local row = MySQL.single.await([[
            SELECT player_identifier, COUNT(*) AS captures
            FROM gt_captures
            WHERE week_number = ? AND to_job = ?
            GROUP BY player_identifier
            ORDER BY captures DESC
            LIMIT 1
        ]], { week, entry.job })
        if row then mvpByJob[entry.job] = row end
    end

    -- Persist snapshot
    for _, entry in ipairs(ranked) do
        local mvp = mvpByJob[entry.job]
        MySQL.insert.await([[
            INSERT INTO gt_weekly_winners
                (week_number, job_name, point_count, mvp_identifier, mvp_capture_count)
            VALUES (?, ?, ?, ?, ?)
        ]], {
            week, entry.job, entry.count,
            mvp and mvp.player_identifier or nil,
            mvp and mvp.captures or 0,
        })
    end

    distributeRewards(ranked, mvpByJob)

    -- Reset map: clear owners + locks (HQs auto-restored)
    MySQL.query.await('UPDATE gt_spray_points SET owner_job = NULL, locked_until = NULL')
    for _, p in pairs(GT.points) do
        p.owner_job = nil
        p.locked_until = nil
    end
    -- Restore HQ ownership
    for job, g in pairs(GT.gangs) do
        if g.hq_point_id and GT.points[g.hq_point_id] then
            GT.points[g.hq_point_id].owner_job = job
            MySQL.query.await(
                'UPDATE gt_spray_points SET owner_job = ? WHERE id = ?',
                { job, g.hq_point_id })
        end
    end

    TriggerClientEvent('gt:fullRefresh', -1)
end

CreateThread(function()
    while true do
        Wait(60 * 1000) -- check every minute
        if shouldRunWeekly() then
            local ok, err = pcall(runWeekly)
            if not ok then print('[gang_territory] weekly reset error: ' .. tostring(err)) end
        end
    end
end)
