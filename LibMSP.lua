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

local VERSION = 9
local PROTOCOL_VERSION = 3
local CHOMP_VERSION = 0

assert(not IsLoggedIn(), ("LibMSP (embedded: %s) cannot be loaded after login."):format((...)))
if msp and (msp.version or 0) >= VERSION then return end
assert(AddOn_Chomp and AddOn_Chomp.GetVersion() >= CHOMP_VERSION, "LibMSP requires Chomp v0 or later.")

local PREFIX_UNICAST = "MSP"
local SEPARATOR = string.char(0x7f)

local TT_ALONE = { "TT" }
local PROBE_FREQUENCY = 120
local FIELD_FREQUENCY = 15

local LONG_FIELD = { DE = true, HI = true }
local RUNTIME_FIELD = { GC = true, GF = true, GR = true, GS = true, GU = true, VA = true }

local TT_LIST = { "VP", "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC" }
local TT_ALL_LIST = { "VP", "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC", "RC", "CO", "IC" }

if not msp then
	msp = {
		callback = {
			received = {},
			updated = {},
			status = {},
		},
	}
else
	if not msp.callback.updated then
		msp.callback.updated = {}
	end
	if not msp.callback.status then
		msp.callback.status = {}
	end
end
if msp.dummyframe then
	msp.dummyframe:UnregisterAllEvents()
	msp.dummyframe:Hide()
end
msp.dummyframe = {
	RegisterEvent = function() end,
	UnregisterEvent = function() end,
}

msp.version = VERSION

-- Realm part matching is greedy, as realm names will rarely have dashes, but
-- player names will never.
local FULL_PLAYER_SPLIT = FULL_PLAYER_NAME:gsub("-", "%%%%-"):format("^(.-)", "(.+)$")

local function NameMergedRealm(name, realm)
	if type(name) ~= "string" or name == "" then
		return nil
	elseif not realm or realm == "" then
		-- Normally you'd just return the full input name without reformatting,
		-- but Blizzard has started returning an occasional "Name-Realm Name"
		-- combination with spaces and hyphens in the realm name.
		local splitName, splitRealm = name:match(FULL_PLAYER_SPLIT)
		if splitName and splitRealm then
			name = splitName
			realm = splitRealm
		else
			realm = GetRealmName()
		end
	end
	return FULL_PLAYER_NAME:format(name, (realm:gsub("%s*%-*", "")))
end

local emptyMeta = {
	__index = function(self, field)
		return ""
	end,
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
}

msp.char = setmetatable({}, {
	__index = function(self, name)
		-- Account for unmaintained code using names without realms.
	name = NameMergedRealm(name)
		if not rawget(self, name) then
			self[name] = setmetatable({}, charMeta)
		end
		return rawget(self, name)
	end,
})

msp.protocolversion = PROTOCOL_VERSION

msp.my = {}
msp.myver = {}
msp.my.VP = tostring(msp.protocolversion)

local playerOwnName = NameMergedRealm(UnitName("player"))

local function AddTTField(field)
	if type(field) ~= "string" then
		error("msp:AddFieldsToTooltip(): All fields must be strings.", 2)
	elseif not field:find("^%u%u$") then
		error("msp:AddFieldsToTooltip(): All fields must match Lua pattern \"%u%u\".", 2)
	end
	TT_LIST[#TT_LIST + 1] = field
	if not TT_FIELDS[field] then
		TT_FIELDS[field] = true
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

msp.versionUpdate = 2

-- Use this before running msp:Update() to change the first-run version update
-- behaviour. Using 2 is recommended and generally safe.
--	- ALL: Increment all field versions by 1 (LibMSP behaviour).
--	- SHORT: Increment all field versions by 1, except DE and HI.
--	- RUNTIME: Only incrememnt runtime field versions (GC, GF, GR, GS, GU, TT, VA).
--	- NONE: Do not increment any field versions.
function msp:SetInitialVersionUpdate(method)
	if method == "ALL" then
		self.versionUpdate = 0
	elseif method == "SHORT" then
		self.versionUpdate = 1
	elseif method == "RUNTIME" then
		self.versionUpdate = 2
	elseif method == "NONE" then
		self.versionUpdate = 3
	else
		error("msp:SetInitialVersionUpdate(): method: method must be one of \"ALL\", \"SHORT\", \"RUNTIME\", or \"NONE\".", 2)
	end
end

-- Stub functions for future use.
function msp:SetSaveContents(saveContents)
	error("Function unimplemented.", 2)
end

function msp:LoadCache(cacheTable)
	error("Function unimplemented.", 2)
end

local requestTime = setmetatable({}, {
	__index = function(self, name)
		self[name] = {}
		return self[name]
	end,
	__mode = "v",
})

local function UnicastSend(name, chunks, isRequest)
	local payload
	if type(chunks) == "string" then
		payload = chunks
	elseif type(chunks) == "table" then
		payload = table.concat(chunks, SEPARATOR)
	else
		return 0
	end
	local bnetSent, loggedSent, inGameSent = AddOn_Chomp.SmartAddonMessage(PREFIX, payload, "WHISPER", name, isRequest and "MEDIUM" or "LOW", "MSP-" .. name)
	return math.ceil(#payload / 255)
end

local ttCache
local Process
function Process(name, command)
	local action, field, version, contents = command:match("(%p?)(%u%u)(%x*)=?(.*)")
	version = tonumber(version, 16) or 0
	if not field then return end
	if action == "?" then
		local now = GetTime()
		if requestTime[name][field] and requestTime[name][field] > now then
			requestTime[name][field] = now + 5
			return
		end
		requestTime[name][field] = now + 5
		if not msp.reply then
			msp.reply = {}
		end
		local reply = msp.reply
		if version == 0 or version ~= (msp.myver[field] or 0) then
			if field == "TT" then
				if not ttCache then
					msp:Update()
				end
				reply[#reply + 1] = ttCache
			elseif not msp.my[field] or msp.my[field] == "" then
				reply[#reply + 1] = field
			else
				reply[#reply + 1] = ("%s%X=%s"):format(field, msp.myver[field], msp.my[field])
			end
		else
			reply[#reply + 1] = ("!%s%X"):format(field, msp.myver[field])
		end
	elseif action == "!" and version == (msp.char[name].ver[field] or 0) then
		msp.char[name].time[field] = GetTime()
	elseif action == "" then
		local now = GetTime()
		msp.char[name].ver[field] = version
		msp.char[name].time[field] = now
		msp.char[name].field[field] = contents
		if field == "TT" then
			for i, field in ipairs(TT_ALL_LIST) do
				-- Clear fields that haven't been updated in PROBE_FREQUENCY,
				-- but should have been sent with a tooltip (if they're used by
				-- the opposing addon).
				if msp.char[name].time[field] < now - PROBE_FREQUENCY then
					Process(name, field)
				end
			end
		elseif field == "VP" then
			local VP = tonumber(contents)
			if VP then
				msp.char[name].bnet = VP >= 2
			end
		end
		if field then
			for i, func in ipairs(msp.callback.updated) do
				xpcall(func, geterrorhandler(), name, field, contents)
			end
		end
	end
end

local PROCESS_GMATCH = ("([^%s]+)%s"):format(SEPARATOR, SEPARATOR)
local function HandleMessage(method, name, message, sessionID, isComplete)
	local hasEndOfCommand = message:find(SEPARATOR, nil, true)
	local buffer = msp.char[name].buffer[sessionID or 0]
	if isComplete or hasEndOfCommand then
		if buffer then
			if type(buffer) == "string" then
				message = buffer .. message
			else
				buffer[#buffer + 1] = message
				message = table.concat(buffer)
			end
			msp.char[name].buffer[sessionID] = nil
		end
		if not hasEndOfCommand then
			Process(name, message)
		else
			for command in message:gmatch(PROCESS_GMATCH) do
				if isComplete or command:find("^[^%?]") then
					Process(name, command)
					if not isComplete then
						message = message:gsub(command:gsub("(%W)","%%%1") .. SEPARATOR, "")
					end
				end
			end
		end
	end
	if isComplete then
		if msp.reply then
			local reply = msp.reply
			msp.reply = nil
			UnicastSend(name, reply, false)
		end
		for i, func in ipairs(msp.callback.received) do
			xpcall(func, geterrorhandler(), name)
			local ambiguated = Ambiguate(name, "none")
			if ambiguated ~= name then
				-- Same thing, but for name without realm, supports
				-- unmaintained code.
				xpcall(func, geterrorhandler(), ambiguated)
			end
		end
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

local function Chomp_Unicast(...)
	local prefix, message, channel, sender = ...
	local sessionID, msgID, msgTotal = select(13, ...)
	local name = NameMergedRealm(sender)
	msp.char[name].supported = true
	msp.char[name].scantime = nil
	HandleMessage("UNICAST", name, message, sessionID, msgID == msgTotal)

	-- Inform status handlers of the message.
	for i, func in ipairs(self.callback.status) do
		xpcall(func, geterrorhandler(), name, "MESSAGE", msgID, msgTotal)
	end
end

AddOn_Chomp.RegisterAddonPrefix(PREFIX_UNICAST, Chomp_Unicast, {
	needBuffer = true,
	permitBattleNet = true,
	permitLogged = true,
	permitUnlogged = false,
})

local function Chomp_Error(name)
	for i, func in ipairs(self.callback.status) do
		xpcall(func, geterrorhandler(), name, "ERROR")
	end
end

local myPrevious = {}
function msp:Update()
	local updated, firstUpdate = false, self.versionUpdate ~= 0 and next(myPrevious) == nil
	local tt = {}
	for field, contents in pairs(myPrevious) do
		if not self.my[field] then
			updated = true
			myPrevious[field] = ""
			self.myver[field] = (self.myver[field] or 0) + 1
		end
	end
	for field, contents in pairs(self.my) do
		if contents:find(SEPARATOR, nil, true) then
			self.my[field] = myPrevious[field]
			geterrorhandler()(("LibMSP: Found illegal separator byte in field %s, contents reverted to last known-good value."):format(field))
		elseif (myPrevious[field] or "") ~= contents then
			updated = true
			myPrevious[field] = contents or ""
			if field == "VP" then
				-- Since VP is always a number, just use the protocol
				-- version as the field version. Simple!
				self.myver[field] = self.protocolversion
			elseif self.myver[field] and (not firstUpdate or self.versionUpdate == 1 and not LONG_FIELD[field] or self.versionUpdate == 2 and RUNTIME_FIELD[field]) then
				self.myver[field] = (self.myver[field] or 0) + 1
			elseif contents ~= "" and not self.myver[field] then
				self.myver[field] = 1
			end
		end
	end
	for i, field in ipairs(TT_LIST) do
		local contents = self.my[field]
		if not contents or contents == "" then
			tt[#tt + 1] = field
		else
		tt[#tt + 1] = ("%s%X=%s"):format(field, self.myver[field], contents)
		end
	end
	local newtt = table.concat(tt, SEPARATOR) or ""
	if (not firstUpdate or self.versionUpdate ~= 3) and ttCache ~= ("%s%sTT%X"):format(newtt, SEPARATOR, (self.myver.TT or 0)) then
		self.myver.TT = (self.myver.TT or 0) + 1
		ttCache = ("%s%sTT%X"):format(newtt, SEPARATOR, self.myver.TT)
	end
	return updated
end

function msp:Request(name, fields)
	if name:match("^([^%-]+)") == UNKNOWN then
		return false
	end
	name = self:Name(name)
	local now = GetTime()
	if self.char[name].supported == false and now < self.char[name].scantime + PROBE_FREQUENCY then
		return false
	elseif not self.char[name].supported then
		self.char[name].supported = false
		self.char[name].scantime = now
	end
	if type(fields) == "string" and fields ~= "TT" then
		fields = { fields }
	elseif type(fields) ~= "table" then
		fields = TT_ALONE
	end
	local toSend = {}
	for i, field in ipairs(fields) do
		if not self.char[name].supported or not self.char[name].time[field] or now > self.char[name].time[field] + FIELD_FREQUENCY then
			if not self.char[name].supported or not self.char[name].ver[field] or self.char[name].ver[field] == 0 then
				toSend[#toSend + 1] = "?" .. field
			else
				toSend[#toSend + 1] = ("?%s%X"):format(field, self.char[name].ver[field])
			end
			-- Marking time here prevents rapid re-requesting. Also done in
			-- receive.
			self.char[name].time[field] = now
		end
	end
	if #toSend > 0 then
		UnicastSend(name, toSend, true)
		return true
	end
	return false
end

function msp:Send(name, chunks)
	name = NameMergedRealm(name)
	return UnicastSend(name, chunks)
end

-- GHI makes use of this. Even if not used for filtering, keep it.
function msp:PlayerKnownAbout(name)
	if not name or name == "" then
		return false
	end
	-- NameMergedRealm() is called on this in the msp.char metatable.
	return self.char[name].supported ~= nil
end
