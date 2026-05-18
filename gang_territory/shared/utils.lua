GTUtils = {}

function GTUtils.isInWarWindow()
    if not Config.WarWindow.enabled then return true end
    local h = tonumber(os.date('%H'))
    local s, e = Config.WarWindow.startHour, Config.WarWindow.endHour
    if s <= e then
        return h >= s and h < e
    else
        return h >= s or h < e
    end
end

function GTUtils.currentWeekNumber()
    return tonumber(os.date('%Y%V'))
end

function GTUtils.hexToRgb(hex)
    hex = hex:gsub('#', '')
    return tonumber('0x' .. hex:sub(1, 2)),
           tonumber('0x' .. hex:sub(3, 4)),
           tonumber('0x' .. hex:sub(5, 6))
end

function GTUtils.distance3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function GTUtils.tableLength(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
