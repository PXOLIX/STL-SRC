Config = {}

Config.Locale = 'th'

-- Spray mechanic
Config.Spray = {
    progressMs   = 7000,
    item         = 'spraycan',
    itemCount    = 1,
    distance     = 2.0,
    cancelOnMove = true,
    cancelOnHit  = true,
    animDict     = 'switch@franklin@trev_meet_floyd',
    animName     = 'trev_meet_floyd_franklin',
}

-- After a point flips, it can't be flipped again for X minutes
Config.CaptureLock = {
    enabled     = true,
    durationMin = 5,
}

-- Per-player spray cooldown
Config.PlayerCooldown = {
    enabled = true,
    seconds = 30,
}

-- War can only be waged inside this window (server clock)
Config.WarWindow = {
    enabled       = true,
    startHour     = 18,
    endHour       = 23,
    adminOverride = true,
}

-- Minimum gang members online (same job) to capture
Config.MinMembersOnline = 1

-- Passive income tick (money → society of the job)
Config.PassiveIncome = {
    enabled       = true,
    intervalMin   = 15,
    moneyPerPoint = 100,
}

-- Weekly reset & reward
Config.Weekly = {
    enabled  = true,
    resetDow = 1, -- 1=Mon ... 7=Sun (ISO)
    resetHour = 0,
    rewards = {
        [1] = { money = 1000000, item = 'goldbar', count = 5 },
        [2] = { money = 500000,  item = 'goldbar', count = 2 },
        [3] = { money = 250000,  item = nil,       count = 0 },
    },
    mvpReward = { money = 200000, item = 'goldbar', count = 1 },
}

-- Admin
Config.AdminGroups = { 'admin', 'superadmin' }

-- UI / interaction
Config.Keys = {
    sprayKey         = 38,  -- E
    openLeaderboard  = 'F7',
    openEditor       = 'F6',
}

-- Visuals
Config.Marker = {
    drawDistance = 50.0,
    type         = 23, -- vertical cylinder
    size         = vector3(0.7, 0.7, 0.7),
}

Config.Blip = {
    showZones  = true,
    showPoints = false,
    alpha      = 128,
}
