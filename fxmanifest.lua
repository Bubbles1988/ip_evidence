fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

author 'ib'
description 'Evidence & crime folder system for RSG Lawman'
version '1.2.1'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

client_scripts {
    'client/draw.lua',
    'client/main.lua',
}

dependencies {
    'rsg-core',
    'rsg-inventory',
    'ox_lib',
    'oxmysql',
}
