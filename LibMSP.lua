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

local LIBMSP_VERSION = 9

assert(AddOn_Chomp and AddOn_Chomp.GetVersion() >= 0, "LibMSP requires Chomp v0 or later.")

if msp and (msp.version or 0) >= LIBMSP_VERSION then
	return
elseif not msp then
	msp = {
		callback = {
			received = {},
			updated = {},
		},
	}
else
	if not msp.callback.updated then
		msp.callback.updated = {}
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

msp.version = LIBMSP_VERSION

-- Protocol version >= 2 indicates support for MSP-over-Battle.net. It also
-- includes MSP-over-group, but that requires a new prefix registered, so the
-- protocol version isn't the real indicator there (meaning, yes, you can do
-- version <= 1 with no Battle.net or version >= 2 with no group).
msp.protocolversion = 2

-- Set this before running msp:Update() to change the first-run version update
-- behaviour. Using 2 is recommended and generally safe.
--	- 0: Increment all field versions by 1 (LibMSP behaviour).
--	- 1: Increment all field versions by 1, except DE and HI.
--	- 2: Only incrememnt runtime field versions (GC, GF, GR, GS, GU, TT, VA).
--	- 3: Do not increment any field versions.
msp.versionUpdate = 2

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

msp.my = {}
msp.myver = {}
msp.my.VP = tostring(msp.protocolversion)

local playerOwnName = NameMergedRealm(UnitName("player"))

local TT_LIST = { "VP", "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC" }
local TT_FIELDS = {
	VP = true, VA = true, NA = true, NH = true, NI = true, NT = true, RA = true,
	RC = true, FR = true, FC = true, CU = true, CO = true, IC = true,
}

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

function msp:SetLoggedOnly(loggedOnly)
	self.loggedOnly = loggedOnly
end

local handlers, ttCache

local requestTime = setmetatable({}, {
	__index = function(self, name)
		self[name] = {}
		return self[name]
	end,
	__mode = "v",
})

local function Process(self, name, command)
	local action, field, version, contents = command:match("(%p?)(%u%u)(%d*)=?(.*)")
	version = tonumber(version) or 0
	if not field then return end
	if action == "?" then
		local now = GetTime()
		if requestTime[name][field] and requestTime[name][field] > now then
			requestTime[name][field] = now + 5
			return
		end
		requestTime[name][field] = now + 5
		if not self.reply then
			self.reply = {}
		end
		local reply = self.reply
		if version == 0 or version ~= (self.myver[field] or 0) then
			if field == "TT" then
				if not ttCache then
					self:Update()
				end
				reply[#reply + 1] = ttCache
			elseif not self.my[field] or self.my[field] == "" then
				reply[#reply + 1] = field
			else
				reply[#reply + 1] = ("%s%.0f=%s"):format(field, self.myver[field], self.my[field])
			end
		else
			reply[#reply + 1] = ("!%s%.0f"):format(field, self.myver[field])
		end
	elseif action == "!" and version == (self.char[name].ver[field] or 0) then
		self.char[name].time[field] = GetTime()
	elseif action == "" then
		-- If the message was only partly received, don't update TT
		-- versioning -- we may have missed some of it.
		if field == "TT" and self.char[name].buffer.partialMessage then
			return
		end
		self.char[name].ver[field] = version
		self.char[name].time[field] = GetTime()
		self.char[name].field[field] = contents
		if field == "VP" then
			local VP = tonumber(contents)
			if VP then
				self.char[name].bnet = VP >= 2
			end
		end
		if field then
			for i, func in ipairs(self.callback.updated) do
				xpcall(func, geterrorhandler(), name, field, contents)
			end
		end
		return field, contents
	end
end

handlers = {
	["MSP"] = function(self, name, message, channel)
		if message:find("\001", nil, true) then
			for command in message:gmatch("([^\001]+)\001*") do
				local field, contents = Process(self, name, command)
			end
		else
			local field, contents = Process(self, name, message)
		end
		for i, func in ipairs(self.callback.received) do
			xpcall(func, geterrorhandler(), name)
			local ambiguated = Ambiguate(name, "none")
			if ambiguated ~= name then
				-- Same thing, but for name without realm, supports
				-- unmaintained code.
				xpcall(func, geterrorhandler(), ambiguated)
			end
		end
		if self.reply then
		self:Send(name, self.reply, false)
			self.reply = nil
		end
	end,
	["MSP\001"] = function(self, name, message, channel)
		-- This drops chunk metadata.
		self.char[name].buffer[channel] = message:gsub("^XC=%d+\001", "")
	end,
	["MSP\002"] = function(self, name, message, channel)
		local buffer = self.char[name].buffer[channel]
		if not buffer then
			message = message:match(".-\001(.+)$")
			if not message then return end
			buffer = { "", partial = true }
		end
		if type(buffer) == "table" then
			buffer[#buffer + 1] = message
		else
			self.char[name].buffer[channel] = { buffer, message }
		end
	end,
	["MSP\003"] = function(self, name, message, channel)
		local buffer = self.char[name].buffer[channel]
		if not buffer then
			message = message:match(".-\001(.+)$")
			if not message then return end
			buffer = ""
			self.char[name].buffer.partialMessage = true
		end
		if type(buffer) == "table" then
			if buffer.partial then
				self.char[name].buffer.partialMessage = true
			end
			buffer[#buffer + 1] = message
			handlers["MSP"](self, name, table.concat(buffer))
		else
			handlers["MSP"](self, name, buffer .. message)
		end
		self.char[name].buffer[channel] = nil
		self.char[name].buffer.partialMessage = nil
	end,
}

local function Chomp_Callback(prefix, body, channel, sender)
	if msp.loggedOnly then
		local method = channel:match("%:(%u+)$")
		if not method or method ~= "BATTLENET" or method ~= "LOGGED" then
			return
		end
	end
	if not handlers[prefix] then return end
	local name = NameMergedRealm(sender)
	if name == playerOwnName then return end
	msp.char[name].supported = true
	msp.char[name].scantime = nil
	handlers[prefix](msp, name, body, channel)
end

local PREFIX = { [0] = 
	"MSP",
	"MSP\001",
	"MSP\002",
	"MSP\003",
}

AddOn_Chomp.RegisterAddonPrefix(PREFIX, Chomp_Callback)

local LONG_FIELD = { DE = true, HI = true }
local RUNTIME_FIELD = { GC = true, GF = true, GR = true, GS = true, GU = true, VA = true }
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
		if (myPrevious[field] or "") ~= contents then
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
		tt[#tt + 1] = ("%s%.0f=%s"):format(field, self.myver[field], contents)
		end
	end
	local newtt = table.concat(tt, "\001") or ""
	if (not firstUpdate or self.versionUpdate ~= 3) and ttCache ~= ("%s\001TT%.0f"):format(newtt, (self.myver.TT or 0)) then
		self.myver.TT = (self.myver.TT or 0) + 1
		ttCache = ("%s\001TT%.0f"):format(newtt, self.myver.TT)
	end
	return updated
end

local TT_ALONE = { "TT" }
local PROBE_FREQUENCY = 120
local FIELD_FREQUENCY = 15
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
				toSend[#toSend + 1] = ("?%s%.0f"):format(field, self.char[name].ver[field])
			end
			-- Marking time here prevents rapid re-requesting. Also done in
			-- receive.
			self.char[name].time[field] = now
		end
	end
	if #toSend > 0 then
		self:Send(name, toSend, true)
		return true
	end
	return false
end

function msp:Send(name, chunks, isRequest)
	local payload = table.concat(chunks, "\001")
	-- Guess six added characters from metadata.
	local numChunks = ((#payload + 6) / 255) + 1
	payload = ("XC=%d\001%s"):format(numChunks, payload)
	local bnetSent, loggedSent, inGameSent = AddOn_Chomp.SmartAddonWhisper(PREFIX, payload, name, isRequest and "HIGH" or "LOW", "MSP-" .. name)
	-- START: GMSP
	--[[if not bnetSent then
		GMSP.HandOffSend(name, payload, isRequest)
	end]]
	-- END: GMSP
	return numChunks
	end

-- GHI makes use of this. Even if not used for filtering, keep it.
function msp:PlayerKnownAbout(name)
	if not name or name == "" then
		return false
	end
	-- NameMergedRealm() is called on this in the msp.char metatable.
	return self.char[name].supported ~= nil
end
