-- F7 leaderboard NUI

local lbOpen = false

local function openLeaderboard()
    if lbOpen then return end
    local board = lib.callback.await('gt:getLeaderboard', false)
    local recent = lib.callback.await('gt:getRecentCaptures', false, 15)
    if not board then return end
    lbOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openLeaderboard',
        board  = board,
        recent = recent or {},
    })
end

local function closeLeaderboard()
    lbOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('closeLeaderboard', function(_, cb)
    closeLeaderboard(); cb('ok')
end)

lib.addKeybind({
    name        = 'gt_open_leaderboard',
    description = 'Open Gang Territory Leaderboard',
    defaultKey  = Config.Keys.openLeaderboard,
    onPressed   = function() openLeaderboard() end,
})
