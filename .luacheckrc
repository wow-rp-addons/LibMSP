-- Disable unused self warnings.
self = false

-- Allow unused arguments.
unused_args = false

-- Disable line length limits.
max_line_length = false
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = false

exclude_files = {
	"Chomp/*"
}

-- Add exceptions for external libraries.
std = "lua51+wow+wowstd"

globals = {
	"msp",
}

read_globals = {
	"AddOn_Chomp",
}

stds.wow = {
	read_globals = {
		C_Timer = {
			fields = {
				"After",
			},
		},

		"CallErrorHandler",
		"CreateFrame",
		"debugprofilestop",
		"GetPlayerInfoByGUID",
		"GetTime",
		"IsInGroup",
		"IsInRaid",
		"IsLoggedIn",
		"IsTrialAccount",
		"IsVeteranTrialAccount",
		"LE_REALM_RELATION_COALESCED",
		"MAX_PARTY_MEMBERS",
		"MAX_RAID_MEMBERS",
		"UnitFactionGroup",
		"UnitFullName",
		"UnitGUID",
		"UnitRealmRelationship",
		"UNKNOWNOBJECT",
	},
}

stds.wowstd = {
	read_globals = {
		bit = {
			fields = {
				"arshift",
				"bxor",
				"band",
				"rshift",
			},
		},

		"tContains",
	},
}
