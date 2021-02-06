game 'rdr3'
fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

dependency 'ghmattimysql'

files {
	'ui/index.html',
	'ui/style.css',
	'ui/script.js',
	'ui/CHINESER.TTF'
}

ui_page 'ui/index.html'

shared_scripts {
	'config.lua'
}

client_scripts {
	'undead.lua',
	'client.lua'
}

server_scripts {
	'server.lua'
}
