RegisterNetEvent('gt:notify', function(key, args)
    local msg = locale(key, table.unpack(args or {})) or key
    lib.notify({ description = msg, type = 'inform' })
end)
