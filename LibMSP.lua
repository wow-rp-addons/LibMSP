--[[
	Project: LibMSP
	Author: "Etarna Moonshyne"
	Author: Renaud "Ellypse" Parize
	Author: Justin Snelgrove

	This work is licensed under the Creative Commons Zero license. While not
	required by the license, it is requested that you retain this notice and
	the list of authors with any distributions, modified or unmodified, as it
	may be required by law in some jurisdictions due to the moral rights of
	authorship.

	It would be appreciated if modified copies of the library are released
	under the same license, but this is also not required.

	- Put your character's field data in the table msp.my, e.g. msp.my["NA"] = UnitName("player")
	- When you initialise or update your character's field data, call msp:Update(); no parameters
	- Don't mess with msp.my['TT'], that's used internally

	- To request one or more fields from someone else, call msp:Request( player, fields )
	  fields can be nil (gets you TT i.e. tooltip), or a string (one field) or a table (multiple)

	- To get a call back when we receive data (such as a request for us, or an answer), so you can
	  update your display: tinsert( msp.callback.received, YourCallbackFunctionHere )
	  You get (as sole parameter) the name of the player sending you the data

	- Player names appear EXACTLY as the game sends them (case sensitive!).
	- Players on different realms are referenced like this: "Name-Realm" - yes, that does work!

	- All field names are two capital letters. Best if you agree any extensions.

	- For more information, see documentation on the Mary Sue Protocol - http://moonshyne.org/msp/
]]

local VERSION = 10
local PROTOCOL_VERSION = 3
local CHOMP_VERSION = 0

if IsLoggedIn() then
	error(("LibMSP (embedded in: %s) cannot be loaded after login."):format((...)))
elseif msp and (msp.version or 0) >= VERSION then
	return
elseif not AddOn_Chomp or AddOn_Chomp.GetVersion() < CHOMP_VERSION then
	error(("LibMSP requires Chomp v%d or later."):format(CHOMP_VERSION))
end

local PREFIX = "MSP"
local SEPARATOR = string.char(0x7f)

local PROBE_FREQUENCY = 300
local FIELD_FREQUENCY = 30

local TIME_MAX = 2 ^ 31 - 1

local TT_LIST = { "VP", "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC" }
local TT_ALL = {
	VP = true, VA = true, NA = true, NH = true,	NI = true, NT = true,
	RA = true, CU = true, FR = true, FC = true,	RC = true, CO = true,
	IC = true,
}

local UNIT_FIELD = { GC = true, GF = true, GR = true, GS = true, GU = true, }

if not msp then
	msp = {
		callback = {
			received = {},
			updated = {},
			status = {},
			dataload = {},
		},
	}
else
	if not msp.callback.updated then
		msp.callback.updated = {}
	end
	if not msp.callback.status then
		msp.callback.status = {}
	end
	if not msp.callback.dataload then
		msp.callback.dataload = {}
	end
end
if msp.dummyframe then
	msp.dummyframe:UnregisterAllEvents()
	msp.dummyframe:SetScript("OnEvent", nil)
end
msp.eventframe = msp.dummyframe or CreateFrame("Frame")
msp.eventframe:Hide()
msp.dummyframe = {
	RegisterEvent = function() end,
	UnregisterEvent = function() end,
}

local function RunCallback(callbackName, ...)
	for i, func in ipairs(msp.callback[callbackName]) do
		xpcall(func, geterrorhandler(), ...)
	end
end

local CRC32C = {
	0x00000000, 0xF26B8303, 0xE13B70F7, 0x1350F3F4,
	0xC79A971F, 0x35F1141C, 0x26A1E7E8, 0xD4CA64EB,
	0x8AD958CF, 0x78B2DBCC, 0x6BE22838, 0x9989AB3B,
	0x4D43CFD0, 0xBF284CD3, 0xAC78BF27, 0x5E133C24,
	0x105EC76F, 0xE235446C, 0xF165B798, 0x030E349B,
	0xD7C45070, 0x25AFD373, 0x36FF2087, 0xC494A384,
	0x9A879FA0, 0x68EC1CA3, 0x7BBCEF57, 0x89D76C54,
	0x5D1D08BF, 0xAF768BBC, 0xBC267848, 0x4E4DFB4B,
	0x20BD8EDE, 0xD2D60DDD, 0xC186FE29, 0x33ED7D2A,
	0xE72719C1, 0x154C9AC2, 0x061C6936, 0xF477EA35,
	0xAA64D611, 0x580F5512, 0x4B5FA6E6, 0xB93425E5,
	0x6DFE410E, 0x9F95C20D, 0x8CC531F9, 0x7EAEB2FA,
	0x30E349B1, 0xC288CAB2, 0xD1D83946, 0x23B3BA45,
	0xF779DEAE, 0x05125DAD, 0x1642AE59, 0xE4292D5A,
	0xBA3A117E, 0x4851927D, 0x5B016189, 0xA96AE28A,
	0x7DA08661, 0x8FCB0562, 0x9C9BF696, 0x6EF07595,
	0x417B1DBC, 0xB3109EBF, 0xA0406D4B, 0x522BEE48,
	0x86E18AA3, 0x748A09A0, 0x67DAFA54, 0x95B17957,
	0xCBA24573, 0x39C9C670, 0x2A993584, 0xD8F2B687,
	0x0C38D26C, 0xFE53516F, 0xED03A29B, 0x1F682198,
	0x5125DAD3, 0xA34E59D0, 0xB01EAA24, 0x42752927,
	0x96BF4DCC, 0x64D4CECF, 0x77843D3B, 0x85EFBE38,
	0xDBFC821C, 0x2997011F, 0x3AC7F2EB, 0xC8AC71E8,
	0x1C661503, 0xEE0D9600, 0xFD5D65F4, 0x0F36E6F7,
	0x61C69362, 0x93AD1061, 0x80FDE395, 0x72966096,
	0xA65C047D, 0x5437877E, 0x4767748A, 0xB50CF789,
	0xEB1FCBAD, 0x197448AE, 0x0A24BB5A, 0xF84F3859,
	0x2C855CB2, 0xDEEEDFB1, 0xCDBE2C45, 0x3FD5AF46,
	0x7198540D, 0x83F3D70E, 0x90A324FA, 0x62C8A7F9,
	0xB602C312, 0x44694011, 0x5739B3E5, 0xA55230E6,
	0xFB410CC2, 0x092A8FC1, 0x1A7A7C35, 0xE811FF36,
	0x3CDB9BDD, 0xCEB018DE, 0xDDE0EB2A, 0x2F8B6829,
	0x82F63B78, 0x709DB87B, 0x63CD4B8F, 0x91A6C88C,
	0x456CAC67, 0xB7072F64, 0xA457DC90, 0x563C5F93,
	0x082F63B7, 0xFA44E0B4, 0xE9141340, 0x1B7F9043,
	0xCFB5F4A8, 0x3DDE77AB, 0x2E8E845F, 0xDCE5075C,
	0x92A8FC17, 0x60C37F14, 0x73938CE0, 0x81F80FE3,
	0x55326B08, 0xA759E80B, 0xB4091BFF, 0x466298FC,
	0x1871A4D8, 0xEA1A27DB, 0xF94AD42F, 0x0B21572C,
	0xDFEB33C7, 0x2D80B0C4, 0x3ED04330, 0xCCBBC033,
	0xA24BB5A6, 0x502036A5, 0x4370C551, 0xB11B4652,
	0x65D122B9, 0x97BAA1BA, 0x84EA524E, 0x7681D14D,
	0x2892ED69, 0xDAF96E6A, 0xC9A99D9E, 0x3BC21E9D,
	0xEF087A76, 0x1D63F975, 0x0E330A81, 0xFC588982,
	0xB21572C9, 0x407EF1CA, 0x532E023E, 0xA145813D,
	0x758FE5D6, 0x87E466D5, 0x94B49521, 0x66DF1622,
	0x38CC2A06, 0xCAA7A905, 0xD9F75AF1, 0x2B9CD9F2,
	0xFF56BD19, 0x0D3D3E1A, 0x1E6DCDEE, 0xEC064EED,
	0xC38D26C4, 0x31E6A5C7, 0x22B65633, 0xD0DDD530,
	0x0417B1DB, 0xF67C32D8, 0xE52CC12C, 0x1747422F,
	0x49547E0B, 0xBB3FFD08, 0xA86F0EFC, 0x5A048DFF,
	0x8ECEE914, 0x7CA56A17, 0x6FF599E3, 0x9D9E1AE0,
	0xD3D3E1AB, 0x21B862A8, 0x32E8915C, 0xC083125F,
	0x144976B4, 0xE622F5B7, 0xF5720643, 0x07198540,
	0x590AB964, 0xAB613A67, 0xB831C993, 0x4A5A4A90,
	0x9E902E7B, 0x6CFBAD78, 0x7FAB5E8C, 0x8DC0DD8F,
	0xE330A81A, 0x115B2B19, 0x020BD8ED, 0xF0605BEE,
	0x24AA3F05, 0xD6C1BC06, 0xC5914FF2, 0x37FACCF1,
	0x69E9F0D5, 0x9B8273D6, 0x88D28022, 0x7AB90321,
	0xAE7367CA, 0x5C18E4C9, 0x4F48173D, 0xBD23943E,
	0xF36E6F75, 0x0105EC76, 0x12551F82, 0xE03E9C81,
	0x34F4F86A, 0xC69F7B69, 0xD5CF889D, 0x27A40B9E,
	0x79B737BA, 0x8BDCB4B9, 0x988C474D, 0x6AE7C44E,
	0xBE2DA0A5, 0x4C4623A6, 0x5F16D052, 0xAD7D5351,
}

local function crc32c_hash(s)
	local XOR, AND, RSHIFT, byte = bit.bxor, bit.band, bit.rshift, string.byte
	local crc = 0xffffffff
	for i = 1, #s do
		local b = byte(s, i)
		crc = XOR(RSHIFT(crc, 8), CRC32C[AND(XOR(crc, b), 0xFF) + 1])
	end
	return XOR(crc, 0xffffffff)
end

local function tohex(n)
	local high = bit.rshift(n, 16)
	local low = n % 0x10000
	return ("%04X%04X"):format(high, low):match("^0*(%x-)$")
end

local function crc32c_tostring(s)
	return tohex(crc32c_hash(s))
end

local CRC32CCache = setmetatable({}, {
	__index = function(self, s)
		if not s or s == "" then
			return ""
		end
		local crc = crc32c_tostring(s)
		self[s] = crc
		return crc
	end,
})

-- Benchmarking function.
function msp:DebugHashTest(text, silent)
	local startTime = debugprofilestop()
	local currentTime = startTime
	local count = 0
	while currentTime < startTime + 1000 do
		crc32c_hash(text)
		count = count + 1
		currentTime = debugprofilestop()
	end
	if silent then
		return count, currentTime - startTime, (currentTime - startTime) / count
	end
	print(("%d iterations of crc32c in %d milliseconds, %f milliseconds per CRC32C."):format(count, currentTime - startTime, (currentTime - startTime) / count))
end

local emptyMeta = {
	__index = function(self, field)
		return ""
	end,
	__metatable = false,
}

local charMeta = {
	__index = function(self, key)
		if key == "field" then
			self[key] = setmetatable({}, emptyMeta)
			return self[key]
		elseif key == "ver" or key == "time" or key == "buffer" then
			self[key] = {}
			return self[key]
		else
			return nil
		end
	end,
	__metatable = false,
}

msp.char = setmetatable({}, {
	__index = function(self, name)
		-- Account for unmaintained code using names without realms.
		name = AddOn_Chomp.NameMergedRealm(name)
		if not rawget(self, name) then
			rawset(self, name, setmetatable({}, charMeta))
			RunCallback("dataload", name, self[name])
		end
		return rawget(self, name)
	end,
	__newindex = function(self, name, value)
		-- No legitimate reason for anything except us (using rawset above)
		-- to create anything here.
		return
	end,
	__metatable = false,
})

msp.protocolversion = PROTOCOL_VERSION

msp.my = {}
-- myver is unused, but if legacy code wants to use it, knock themselves out.
msp.myver = setmetatable({}, {
	__index = function(self, field)
		if TT_ALL[field] then
			return nil
		end
		return tonumber(CRC32CCache[msp.my[field]], 16)
	end,
	__newindex = function() end
})
msp.my.VP = tostring(msp.protocolversion)

local playerOwnName = AddOn_Chomp.NameMergedRealm(UnitFullName("player"))

local function AddTTField(field)
	if type(field) ~= "string" or not field:find("^%u%u$") then
		error("msp:AddFieldsToTooltip(): All fields must be strings matching Lua pattern \"%u%u\".", 3)
	end
	TT_LIST[#TT_LIST + 1] = field
	if not TT_ALL[field] then
		TT_ALL[field] = true
	end
end

function msp:AddFieldsToTooltip(fields)
	if type(fields) == "table" then
		for i, field in ipairs(fields) do
			AddTTField(field)
		end
	else
		AddTTField(fields)
	end
end

local requestTime = setmetatable({}, {
	__index = function(self, name)
		self[name] = {}
		return self[name]
	end,
})

local OPTS_MATRIX = {
	SAFE = {
		REPLY = {
			priority = "LOW",
			allowBroadcast = true,
			universalBroadcast = true,
		},
		REQUEST = { -- This should never happen, but if it does...
			priority = "LOW",
			allowBroadcast = true,
		},
	},
	UNSAFE = {
		REPLY = {
			binaryBlob = true,
			priority = "LOW",
			allowBroadcast = true,
			universalBroadcast = true,
		},
		REQUEST = {
			binaryBlob = true,
			priority = "LOW",
			allowBroadcast = true,
		},
	},
}

local function Send(name, chunks, msgSafety, msgType)
	local payload
	if type(chunks) == "string" then
		payload = chunks
	elseif type(chunks) == "table" then
		payload = table.concat(chunks, SEPARATOR)
	else
		return 0
	end
	local sentMethod = AddOn_Chomp.SmartAddonMessage(PREFIX, payload, "WHISPER", name, OPTS_MATRIX[msgSafety][msgType])
	return math.ceil(#payload / 255)
end

local ttCache
local Process
function Process(name, command, isSafe)
	local action, field, crc, contents = command:match("(%p?)(%u%u)(%x*)=?(.*)")
	if not field then return end
	if crc == "0" then
		crc = ""
	end
	if contents == "" then
		contents = nil
	end
	local crcNum = tonumber(crc, 16)
	local now = GetTime()
	if action == "?" then
		if TT_ALL[field] then
			field = "TT"
		end
		if requestTime[name][field] and requestTime[name][field] > now then
			requestTime[name][field] = now + 5
			return
		end
		requestTime[name][field] = now + 5
		if crc ~= CRC32CCache[msp.my[field]] then
			if not msp.char[name].safeReply then
				msp.char[name].safeReply = {}
			end
			local reply = msp.char[name].safeReply
			if field == "TT" then
				if not ttCache then
					msp:Update()
				end
				reply[#reply + 1] = ttCache
			elseif not msp.my[field] or msp.my[field] == "" then
				reply[#reply + 1] = field
			else
				reply[#reply + 1] = ("%s%s=%s"):format(field, CRC32CCache[msp.my[field]], msp.my[field])
			end
		else
			if not msp.char[name].unsafeReply then
				msp.char[name].unsafeReply = {}
			end
			local reply = msp.char[name].unsafeReply
			reply[#reply + 1] = ("!%s%s"):format(field, CRC32CCache[msp.my[field]] or "")
		end
	elseif action == "!" and crcNum == msp.char[name].ver[field] then
		msp.char[name].time[field] = now
	elseif action == "" and isSafe then
		msp.char[name].field[field] = contents
		msp.char[name].ver[field] = crcNum
		-- Assume unit fields won't change during a session, so only request
		-- them once after getting a response.
		msp.char[name].time[field] = not UNIT_FIELD[field] and now or TIME_MAX
		if field == "TT" then
			for field in pairs(TT_ALL) do
				-- Clear fields that haven't been updated in PROBE_FREQUENCY,
				-- but should have been sent with a tooltip (if they're used by
				-- the opposing addon).
				if msp.char[name].field[field] and (msp.char[name].time[field] or 0) < now - PROBE_FREQUENCY then
					Process(name, field)
				end
			end
		end
		if field then
			RunCallback("updated", name, field, contents, crcNum)
		end
	end
end

local PROCESS = ("([^%s]+)%s"):format(SEPARATOR, SEPARATOR)
local PROCESS_COMPLETE = PROCESS .. "?"
local function HandleMessage(name, message, isSafe, sessionID, isComplete)
	if isComplete or message:find(SEPARATOR, nil, true) then
		local buffer = msp.char[name].buffer[sessionID or 0]
		if buffer then
			if type(buffer) == "string" then
				message = buffer .. message
			else
				buffer[#buffer + 1] = message
				message = table.concat(buffer)
			end
			msp.char[name].buffer[sessionID] = nil
		end
		for command in message:gmatch(isComplete and PROCESS_COMPLETE or PROCESS) do
			Process(name, command, isSafe)
			if not isComplete then
				message = message:gsub(command:gsub("(%W)","%%%1") .. SEPARATOR, "")
			end
		end
	end
	local buffer = msp.char[name].buffer[sessionID or 0]
	if isComplete then
		local safeReply = msp.char[name].safeReply
		if safeReply then
			msp.char[name].safeReply = nil
			Send(name, safeReply, "SAFE", "REPLY")
		end
		local unsafeReply = msp.char[name].unsafeReply
		if unsafeReply then
			msp.char[name].unsafeReply = nil
			Send(name, unsafeReply, "UNSAFE", "REPLY")
		end
		RunCallback("received", name)
	elseif buffer then
		if type(buffer) == "string" then
			msp.char[name].buffer[sessionID] = { buffer, message }
		else
			buffer[#buffer + 1] = message
		end
	else
		msp.char[name].buffer[sessionID] = message
	end
end

local function Chomp_Callback(...)
	local prefix, message, channel, sender = ...
	local sessionID, msgID, msgTotal = select(13, ...)
	local name = AddOn_Chomp.NameMergedRealm(sender)
	msp.char[name].supported = true
	msp.char[name].scantime = nil
	local method = channel:match("%:(.+)$")
	local isSafe = method == "BATTLENET" or method == "LOGGED"
	HandleMessage(name, message, isSafe, sessionID, msgID == msgTotal)

	-- Inform status handlers of the message.
	RunCallback("status", name, "MESSAGE", msgID, msgTotal)
end

AddOn_Chomp.RegisterAddonPrefix(PREFIX, Chomp_Callback, {
	fullMsgOnly = false,
	broadcastPrefix = true,
	validTypes = {
		string = true,
	},
})

local function Chomp_Error(name)
	RunCallback("status", name, "ERROR")
end
AddOn_Chomp.RegisterErrorCallback(Chomp_Error)

local firstUpdateRun = false
local function EventFrame_Handler(self, event, ...)
	if event == "PLAYER_LOGIN" then
		local GU = UnitGUID("player")
		local class, GC, race, GR, GS, name, realm = GetPlayerInfoByGUID(GU)
		local GF = UnitFactionGroup("player")
		msp.my.GU = tostring(GU)
		msp.my.GC = tostring(GC)
		msp.my.GR = tostring(GR)
		msp.my.GS = tostring(GS)
		msp.my.GF = tostring(GF)
		if GF == "Neutral" then
			self:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
		end
	elseif event == "NEUTRAL_FACTION_SELECT_RESULT" then
		local GF = UnitFactionGroup("player")
		msp.my.GF = tostring(GF)
	end
	if firstUpdateRun then
		msp:Update()
	end
end
msp.eventframe:SetScript("OnEvent", EventFrame_Handler)
msp.eventframe:RegisterEvent("PLAYER_LOGIN")

function msp:Update()
	local updated = false
	local charTable = self.char[playerOwnName]
	charTable.supported = true
	for field, contents in pairs(charTable.field) do
		if not self.my[field] then
			updated = true
			charTable.field[field] = nil
			charTable.ver[field] = nil
			RunCallback("updated", playerOwnName, field, nil, nil)
		end
	end
	for field, contents in pairs(self.my) do
		if contents == "" then
			contents = nil
			self.my[field] = nil
		end
		if field ~= "TT" then
			if contents and contents:find(SEPARATOR, nil, true) then
				self.my[field] = charTable.field[field]
				geterrorhandler()(("LibMSP: Found illegal separator byte in field %s, contents reverted to last known-good value."):format(field))
			elseif charTable.field[field] ~= contents then
				updated = true
				charTable.field[field] = contents
				if not TT_ALL[field] then
					charTable.ver[field] = tonumber(CRC32CCache[contents], 16)
				end
				RunCallback("updated", playerOwnName, field, contents, tonumber(CRC32CCache[contents], 16))
			end
		end
	end
	if updated or not ttCache then
		local tt = {}
		for i, field in ipairs(TT_LIST) do
			if not self.my[field] then
				tt[#tt + 1] = field
			else
				tt[#tt + 1] = ("%s=%s"):format(field, self.my[field])
			end
		end
		local ttContents = table.concat(tt, SEPARATOR) or ""
		ttCache = ("%s%sTT%s"):format(ttContents, SEPARATOR, CRC32CCache[ttContents])
		-- Set this here for CRC checking elsewhere.
		msp.my.TT = ttContents
		charTable.ver.TT = tonumber(CRC32CCache[ttContents], 16)
		RunCallback("received", playerOwnName)
	end
	firstUpdateRun = true
	return updated
end

function msp:Request(name, fields)
	name = AddOn_Chomp.NameMergedRealm(name)
	if name == playerOwnName or name:match("^([^%-]+)") == UNKNOWN then
		return false
	end
	local now = GetTime()
	if self.char[name].supported == false and now < self.char[name].scantime + PROBE_FREQUENCY then
		return false
	elseif not self.char[name].supported then
		self.char[name].supported = false
		self.char[name].scantime = now
	end
	if type(fields) == "string" then
		fields = { fields }
	end
	local toSend = {}
	for i, field in ipairs(fields) do
		if type(field) == "string" and field:find("^%u%u$") then
			if TT_ALL[field] then
				-- Will only get requested once, due to time marking/checking.
				field = "TT"
			end
			if now > (self.char[name].time[field] or 0) + FIELD_FREQUENCY then
				if not self.char[name].ver[field] then
					toSend[#toSend + 1] = "?" .. field
				else
					toSend[#toSend + 1] = ("?%s%s"):format(field, tohex(self.char[name].ver[field]))
				end
				-- Marking time here prevents rapid re-requesting. Also done in
				-- receive.
				self.char[name].time[field] = now
			end
		end
	end
	if #toSend > 0 then
		Send(name, toSend, "UNSAFE", "REQUEST")
		return true
	end
	return false
end

function msp:Send(name, chunks)
	name = AddOn_Chomp.NameMergedRealm(name)
	if name == playerOwnName then
		return 0
	end
	return Send(name, chunks, "SAFE", "REQUEST")
end

-- GHI makes use of this. Even if not used for filtering, keep it.
function msp:PlayerKnownAbout(name)
	if not name or name == "" then
		return false
	end
	-- AddOn_Chomp.NameMergedRealm() is called on this in the msp.char metatable.
	return self.char[name].supported ~= nil
end

msp.version = VERSION
