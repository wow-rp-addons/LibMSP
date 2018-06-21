--[[
	LibMSP - highly portable implementation of the Mary Sue Protocol for RP addon communication
	Written by Etarna Moonshyne <etarna@moonshyne.org>

	Released into the public domain by the author - free for any use or embedding. Go nuts.
	Public domain (CC0): http://creativecommons.org/publicdomain/zero/1.0/
	It would be nice if changes to this were given away in the same manner, but you don't have to.

	- Easy to embed: it's a singleton which defines a global table: msp
	- It requires (only) ChatThrottleLib

	- Put your character's field data in the table msp.my, e.g. msp.my["NA"] = UnitName("player")
	- When you initialise or update your character's field data, call msp:Update(); no parameters
	- Don't mess with msp.my['TT'], that's used internally
	- Please save the contents of the table msp.myver between sessions, so we always count up

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

local libmsp_version = 9

if msp then
	if msp.version >= libmsp_version then
		return
	end
else
	_G.msp = {}
end
local msp = _G.msp
msp.version = libmsp_version
local ChatThrottleLib = assert(ChatThrottleLibMSP, "LibMSP requires ChatThrottleLibMSP")
assert(ChatThrottleLib.version >= 25, "LibMSP requires ChatThrottleLibMSP v25 or later")

msp.protocolversion = 2

msp.callback = {
	received = {}
}

local UNKNOWN = _G.UNKNOWN or "Unknown"

local function emptyindex( table, key )
	table[key] = ""
	return table[key]
end

local function charindex( table, key )
	if key == "field" then
		table[key] = setmetatable( {}, { __index = emptyindex, } )
		return table[key]
	elseif key == "ver" or key == "time" then
		table[key] = {}
		return table[key]
	else 
		return nil
	end
end

local function bufferindex( table, key )
	table[key] = setmetatable( {}, { __index = charindex, } )
	return table[key]
end

msp.char = setmetatable( {}, { __index = bufferindex } )

msp.my = {}
msp.myver = {}
msp.my.VP = tostring( msp.protocolversion )

msp_my_previous = {}
msp_tt_cache = false

local strfind, strmatch, strsub, strgmatch = strfind, strmatch, strsub, string.gmatch
local tinsert, tconcat = tinsert, table.concat
local tostring, tonumber, wipe, next = tostring, tonumber, wipe, next
local GetTime = GetTime

local MSP_TT_ALONE = { 'TT' }
local MSP_FIELDS_IN_TT = { 'VP', 'VA', 'NA', 'NH', 'NI', 'NT', 'RA', 'FR', 'FC', 'CU' }
local MSP_TT_FIELD = { VP=true, VA=true, NA=true, NH=true, NI=true, NT=true, RA=true, FR=true, FC=true, CU=true }
MSP_PROBE_FREQUENCY = 300.0 + math.random(0, 60) -- Wait 5-6 minutes for someone to respond before asking again
MSP_FIELD_UPDATE_FREQUENCY = 10.0 + math.random(0, 5) -- Fields newer than 10-15 seconds old are still fresh

-- Ellypse modifications:
-- With the move to SendAddonMessageLogged, the separator has to be a printable character
-- Using a two characters length separator is necessary for properly escaping the separator from the user inputted text
-- The separator will actually be ~~ and every ~ in the body of the fields will be replace by !~ before being sent
local SEPARATOR_CHARACTER = "~"
local ESCAPING_CHARACTER = "!"
local FIELD_SEPARATOR = SEPARATOR_CHARACTER .. SEPARATOR_CHARACTER
local ESCAPED_SEPARATOR = ESCAPING_CHARACTER .. SEPARATOR_CHARACTER

-- Escape the given text, replacing all instances of SEPARATOR_CHARACTER by ESCAPED_SEPARATOR
local function escapeText(text)
	return text:gsub(SEPARATOR_CHARACTER, ESCAPED_SEPARATOR)
end

-- Un-escape the given text, replacing all instances of ESCAPED_SEPARATOR by SEPARATOR_CHARACTER
local function unescapeText(text)
	return text:gsub(ESCAPED_SEPARATOR, SEPARATOR_CHARACTER)
end

-- Split a string into a table of strings using a given separator
local function strsplit(text, separator)

	local t = {}
	local fpat = "(.-)" .. separator
	local last_end = 1
	local s, e, cap = text:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t,cap)
		end
		last_end = e+1
		s, e, cap = text:find(fpat, last_end)
	end
	if last_end <= #text then
		cap = text:sub(last_end)
		table.insert(t, cap)
	end
	return t
end

local garbage = setmetatable( {}, { __mode = "k" } )
local function newtable()
	local t = next( garbage )
	if t then 
		garbage[t] = nil
		return wipe(t)
	end
	return {}
end

function msp_onevent( this, event, prefix, body, dist, sender )
	if event == "CHAT_MSG_ADDON" then
		if MSP_INCOMING_HANDLER[ prefix ] then
			MSP_INCOMING_HANDLER[ prefix ]( sender, body )
		end
		-- New event, corresponding to messages sent via SendAddonMessageLogged
		-- Messages received from this event are logged on Blizzard's servers
	elseif event == "CHAT_MSG_ADDON_LOGGED" then
		if MSP_INCOMING_HANDLER[ prefix ] then
			MSP_INCOMING_HANDLER[ prefix ]( sender, body, true ) -- We pass true here to indicate that we are receiving logged data
		end
	end
end

function msp_incomingfirst( sender, body, isLogged )
	-- Check if a XC field is provided to indicate the amount of incoming chunks
	local totalChunks = tonumber(body:match("^XC=(%d+)"..FIELD_SEPARATOR))
	if totalChunks then
		msp.char[sender].totalChunks = totalChunks
		msp.char[sender].amountOfChunksAlreadyReceived = 1
		-- We can remove the XC field as it is not a profile info
		body = body:gsub("^XC=%d+"..FIELD_SEPARATOR, "")
	end
	msp.char[ sender ].buffer = body
	-- If we received logged message, we remember that as we will only accept logged messages in the buffer
	msp.char[ sender ].bufferIsLogged = isLogged
end

function msp_incomingnext( sender, body, isLogged )
	-- Protection against sending the first message via SendAddonMessageLogged and then sending non-logged messages.
	-- If we started the buffer in a logged state, we expect the next messages to be logged too.
	-- If what we are receiving is not logged, we will not add it to the buffer
	if not msp.char[ sender ].bufferIsLogged or isLogged then
		local buf = msp.char[ sender ].buffer
		if buf then
			if type( buf ) == "table" then
				tinsert( buf, body )
			else
				local temp = newtable()
				temp[ 1 ] = buf
				temp[ 2 ] = body
				msp.char[ sender ].buffer = temp
			end
		end
	end

	-- If the sender has previously indicated the amount of incoming chunks
	if msp.char[sender].totalChunks then
		-- We increment the amount of chunks already received
		msp.char[sender].amountOfChunksAlreadyReceived = msp.char[sender].amountOfChunksAlreadyReceived + 1;
	end
end

function msp_incominglast( sender, body )
	-- Protection against sending the first message via SendAddonMessageLogged and then sending non-logged messages.
	-- If we started the buffer in a logged state, we expect the next messages to be logged too.
	-- If what we are receiving is not logged, we will not add it to the buffer
	if not msp.char[ sender ].bufferIsLogged or isLogged then
		local buf = msp.char[ sender ].buffer
		if buf then
			if type( buf ) == "table" then
				tinsert( buf, body )
				msp_incoming( sender, tconcat( buf ), isLogged )
				garbage[ buf ] = true
			else
				msp_incoming( sender, buf .. body, isLogged )
			end
		end
	end
	-- If the sender has previously indicated the amount of incoming chunks
	if msp.char[sender].totalChunks then
		-- Make sure the amountOfChunksAlreadyReceived is equal to totalChunks
		-- (can be different in really rare occasions)
		msp.char[sender].amountOfChunksAlreadyReceived = msp.char[sender].totalChunks;
	end
end

function msp_incoming( sender, body, isLogged )
	msp:DebugSpam( "<%s:%s", sender, string.gsub(body, FIELD_SEPARATOR,"|cff808080:|r") or "" )
	msp.char[ sender ].supported = true
	msp.char[ sender ].scantime = nil
	msp.reply = newtable()
	if body ~= "" then
		if strfind( body, FIELD_SEPARATOR, 1, true ) then
			-- Ellypse modification: use strsplit instead of match as the separator is two characters wide
			for _, chunk in pairs(strsplit(body, FIELD_SEPARATOR)) do
				msp_incomingchunk( sender, chunk, isLogged )
			end
		else
			msp_incomingchunk( sender, body, isLogged )
		end
	end
	for k, v in ipairs( msp.callback.received ) do
		v( sender )
	end
	msp:DebugSpam( ">%s:%s", sender, tconcat(msp.reply, "|cff808080:|r") or "|cff808080nothing|r" )
	msp:Send( sender, msp.reply )
	garbage[ msp.reply ] = true
end

function msp_incomingchunk( sender, chunk, isLogged )
	local reply = msp.reply
	local head, field, ver, body = strmatch( chunk, "(%p?)(%a%a)(%d*)=?(.*)" )
	if body then -- Ellypse modification: un-escape previously escaped body (`|` replaced by `!|`)
		body = unescapeText(body)
	end
	ver = tonumber( ver ) or 0
	if not field then
		return
	end
	if head == "?" then
		if (ver == 0) or (ver < (msp.myver[ field ] or 0)) or (ver > (msp.myver[ field ] or 0)) then
			if field == "TT" then
				if not msp_tt_cache then
					msp:Update()
				end
				tinsert( reply, msp_tt_cache )
			else
				if not msp.my[ field ] or msp.my[ field ] == "" then
					tinsert( reply, field .. (msp.myver[ field ] or "") )
				else
					tinsert( reply, field .. (msp.myver[ field ] or "") .. "=" .. escapeText(msp.my[ field ]) )
				end
			end
		else
			tinsert( reply, "!"..field..(msp.myver[ field ] or "") )
		end
	elseif head == "!" then
		msp.char[ sender ].ver[ field ] = ver
		msp.char[ sender ].time[ field ] = GetTime()
		-- We only accept profile data if the messages were sent via SendAddonMessageLogged and received via the CHAT_MSG_ADDON_LOGGED event
	elseif isLogged and head == "" then
		msp.char[ sender ].ver[ field ] = ver
		msp.char[ sender ].time[ field ] = GetTime()
		msp.char[ sender ].field[ field ] = body or ""
	end
end

MSP_INCOMING_HANDLER = {
	["MSP"] = msp_incoming,
	["MSP1"] = msp_incomingfirst,
	["MSP2"] = msp_incomingnext,
	["MSP3"] = msp_incominglast
}

msp.dummyframe = msp.dummyframe or CreateFrame( "Frame", "libmspDummyFrame" )
msp.dummyframe:SetScript( "OnEvent", msp_onevent )
msp.dummyframe:RegisterEvent( "CHAT_MSG_ADDON" )
msp.dummyframe:RegisterEvent( "CHAT_MSG_ADDON_LOGGED" )

for prefix, handler in pairs( MSP_INCOMING_HANDLER ) do
	C_ChatInfo.RegisterAddonMessagePrefix( prefix )
end

--[[
	msp:Update()
	Call this function when you update (or might have updated) one of the fields in the player's own profile (msp.my).
	It'll deal with any version updates necessary and will rebuild the cached tooltip reply.
]]
function msp:Update()
	local updated = false
	local tt = newtable()
	for field, value in pairs( msp_my_previous ) do
		if not msp.my[ field ] then
			updated = true
			msp_my_previous[ field ] = ""
			msp.myver[ field ] = (msp.myver[ field ] or 0) + 1
			if MSP_TT_FIELD[ field ] then
				ttupdated = true
				tinsert( tt, field .. msp.myver[ field ] )
			end
		end
	end
	for field, value in pairs( msp.my ) do
		if (msp_my_previous[ field ] or "") ~= value then
			updated = true
			msp_my_previous[ field ] = value or ""
			msp.myver[ field ] = (msp.myver[ field ] or 0) + 1
		end
	end
	for k, field in ipairs( MSP_FIELDS_IN_TT ) do
		local value = msp.my[ field ]
		if not value or value == "" then
			tinsert( tt, field .. (msp.myver[ field ] or "") )
		else
			tinsert( tt, field .. (msp.myver[ field ] or "") .. "=" .. escapeText(value) )
		end
	end
	local newtt = tconcat( tt, FIELD_SEPARATOR ) or ""
	if msp_tt_cache ~= newtt..FIELD_SEPARATOR.."TT"..(msp.myver.TT or 0) then
		msp.myver.TT = (msp.myver.TT or 0) + 1
		msp_tt_cache = newtt..FIELD_SEPARATOR.."TT"..msp.myver.TT
	end
	garbage[ tt ] = true
	msp:DebugSpam( updated and "msp:Update(): updated" or "msp:Update(): not updated" )
	return updated
end

--[[
	msp:Request( player, fields )
		player = Player name to query; if from a different realm, format should be "Name-Realm"
		fields = One (string) or more (table) fields to request from the player in question

	Returns true if we sent them a request, and false if we didn't (because we either have it
	recently cached already, or they didn't respond to our last request so might not support MSP).

	Notes: 
	- This function does not spam: feel free to use frequently.
	- To avoid problems with network congestion, doesn't work on a player called "Unknown".
	- Player names are CASE SENSITIVE; pass them as you got them.
	- Replies aren't instant: to be notified if/when we get a reply, register a callback function.
	- For a quick shortcut, request field TT to get basic data you'll probably use in the tooltip.
	- Defaults to a TT (tooltip) request, if there is only one parameter.
]]
function msp:Request( player, fields )
	if player == UNKNOWN then
		return false
	else
		local now = GetTime()
		if msp.char[ player ].supported == false and ( now < msp.char[ player ].scantime + MSP_PROBE_FREQUENCY ) then
			return false
		elseif not msp.char[ player ].supported then
			msp.char[ player ].supported = false
			msp.char[ player ].scantime = now
		end
		if type( fields ) == "string" then
			fields = { fields }
		elseif type( fields ) ~= "table" then
			fields = MSP_TT_ALONE
		end
		local updateneeded = false
		local tosend = newtable()
		local todump = newtable()
		for k, field in ipairs(fields) do
			if not msp.char[ player ].supported or not msp.char[ player ].time[ field ] or (now > msp.char[ player ].time[ field ] + MSP_FIELD_UPDATE_FREQUENCY) then
				tinsert( todump, "|cffeeee00"..field.."|r" )
				updateneeded = true
				if not msp.char[ player ].supported or not msp.char[ player ].ver[ field ] or msp.char[ player ].ver[ field ] == 0 then
					tinsert( tosend, "?" .. field )
				else
					tinsert( tosend, "?" .. field .. escapeText( tostring( msp.char[ player ].ver[ field ] ) ) )
				end
			else
				tinsert( todump, "|cff00ee00"..field.."|r" )
			end
		end
		msp:DebugSpam( ">%s:|cff00aaaa?%s", player, tconcat(todump, ", ") )
		if updateneeded then
			-- We pass false for useLoggedMessages here as requests doesn't have a user generated body, so we don't need them to be logged
			msp:Send( player, tosend, false )
		end
		garbage[ tosend ] = true
		garbage[ todump ] = true
		return updateneeded
	end
end

--[[
	msp:Send( player, chunks )
		player = Player name to send to; if from a different realm, format should be "Name-Realm"
		chunks = One (string) or more (table) MSP chunks to send

	Normally internally used, but published just in case you want to 'push' a field onto someone.
	Returns the number of messages used to send the data.
]]
function msp:Send( player, chunks, useLoggedMessages )
	if useLoggedMessages == nil then
		useLoggedMessages = true
	end
	local payload = ""
	if type( chunks ) == "string" then
		payload = chunks
	elseif type( chunks ) == "table" then
		payload = tconcat( chunks, FIELD_SEPARATOR )
	end
	if payload ~= "" then
		local len = #payload
		local queue = "MSPWHISPER" .. player
		if len < 256 then
			msp:DeepDebugSpam( ">%s:[%s](%d)", player, payload, #payload )
			ChatThrottleLib:SendAddonMessage( "BULK", "MSP", payload, "WHISPER", player, queue, nil, nil, useLoggedMessages )
			return 1
		else
			-- If we will be sending more than one message, we insert the number of incoming messages in
			-- the XC field as the beggining of the payload.
			payload = format("XC=%d" .. FIELD_SEPARATOR .. "%s", ((#payload + 6) / 255) + 1, payload);
			local chunk = strsub( payload, 1, 255 )
			msp:DeepDebugSpam( ">%s:[%s]…(%d/%d)", player, chunk, #chunk, #payload )
			ChatThrottleLib:SendAddonMessage( "BULK", "MSP1", chunk, "WHISPER", player, queue, nil, nil, useLoggedMessages )
			local pos = 256
			local parts = 2
			while pos + 255 <= len do
				chunk = strsub( payload, pos, pos + 254 )
				msp:DeepDebugSpam( ">%s:…[%s]…(%d/%d)", player, chunk, #chunk, #payload )
				ChatThrottleLib:SendAddonMessage( "BULK", "MSP2", chunk, "WHISPER", player, queue, nil, nil, useLoggedMessages )
				pos = pos + 255
				parts = parts + 1
			end
			chunk = strsub( payload, pos )
			msp:DeepDebugSpam( ">%s:…[%s](%d/%d)", player, chunk, #chunk, #payload )
			ChatThrottleLib:SendAddonMessage( "BULK", "MSP3", chunk, "WHISPER", player, queue, nil, nil, useLoggedMessages )
			return parts
		end
	end
	return 0
end

--[[
	WoW 4.0.3.13329: Bug Workaround
	(Invisible SendAddonMessage() returning visible ERR_CHAT_PLAYER_NOT_FOUND_S system message on failure)
]]
ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM", function( self, event, msg ) 
	return msp:PlayerKnownAbout( msg:match( ERR_CHAT_PLAYER_NOT_FOUND_S:format( "(.+)" ) ) )
end )
function msp:PlayerKnownAbout( player )
	if player == nil or player == "" then
		return false
	end
	return msp.char[ player ].supported ~= nil
end

function msp:DebugSpam( ... )
	if not msp.Debug then return end
	DEFAULT_CHAT_FRAME:AddMessage( "|cff406840MSPDebug: |r" .. format(...) )
end
function msp:DeepDebugSpam( ... )
	if not msp.DeepDebug then return end
	DEFAULT_CHAT_FRAME:AddMessage( "|cff603850MSPDebug(Deep): |r" .. format(...) )
end
msp.Debug=true
msp.DeepDebug=false