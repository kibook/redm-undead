fx_version "adamant"
game "rdr3"
rdr3_warning "I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships."

dependencies {
	"uiprompt",
	"uifeed",
	-- You can comment this out if you disable Config.enableDb
	"ghmattimysql"
}

files {
	"ui/index.html",
	"ui/style.css",
	"ui/script.js",
	"ui/CHINESER.TTF"
}

ui_page "ui/index.html"

this_is_a_map "yes"

shared_scripts {
	"config.lua"
}

client_scripts {
	"@uiprompt/uiprompt.lua",
	"natives.lua",
	"undead.lua",
	"client.lua"
}

server_scripts {
	"server.lua"
}
