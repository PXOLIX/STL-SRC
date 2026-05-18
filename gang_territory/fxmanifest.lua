fx_version 'cerulean'
game 'gta5'

author 'DeepCodes'
description 'Gang Territory — turf war via wall spray (ESX Legacy + ox_lib + oxmysql)'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/sv_points.lua',
    'server/sv_capture.lua',
    'server/sv_stats.lua',
    'server/sv_reward.lua',
    'server/sv_admin.lua',
}

client_scripts {
    'client/main.lua',
    'client/cl_notify.lua',
    'client/cl_blip.lua',
    'client/cl_capture.lua',
    'client/cl_editor.lua',
    'client/cl_leaderboard.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/assets/*.png',
    'html/assets/*.svg',
    'locales/*.json',
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
}
