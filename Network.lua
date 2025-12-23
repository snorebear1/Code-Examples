--[[
	@class Network
	
	NOTE: This version of Network expands upon the previous iteration. It is stable and battle-tested.
	This version replaces "error" outputs with "warn" in order to quell issues that might arise with
	function termination.
	
	Maintained by taydeooo & snorebear
	Last edit: 05-OCT-2025
	
	------------------------------------------------------------------------------------------------------
	
	>> EXAMPLE CODE
	
	------------------------------------------------------------------------------------------------------
	
	[+] Client-to-Server [+]:
	
		-- Server --
		
		Network.Bind(true, 'ReturnMe!', function(player: Player): boolean
			if player.Name == 'taydeooo' then
				return true
			else
				return false
			end
		end)
		
		-- Client --
		
		local result: boolean = Network.Get(true, 'ReturnMe!')
		
		print(player.Name, result)
		
		-- Output --
		
		> taydeooo, true
		> snorebear, false
	
	[+] Server-to-Client [+]:
	
		-- Server --
		
		Network.Send(taydeooo, true, 'PrintMe!')
		
		-- Client --
		
		Network.Add(true, 'PrintMe!', function(player: Player)
			print(player.Name .. ' prints a cool phrase!')
		end)
		
		-- Output --
		
		> taydeooo prints a cool phrase!
		
	[+] Server-to-Server & Client-to-Client [+]:
		
		-- Server <script 1> --
		
		Network.Bind(false, 'SquareMe!', function(x: number): number
			return x^2
		end)
		
		-- Server <script 2> --
		
		local result: number = Network.Get(1)
		
		print(result)
		
		-- Output --
		
		> 2
]]

local Network = {}

--------------
-- SERVICES --
--------------

local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

---------------
-- CONSTANTS --
---------------

local CLIENT = RunService:IsClient()

local DEBUG = script:GetAttribute('Debug')

local NETWORK_DEBUG_PREFIX = '[Network] DEBUG: '
local NETWORK_ERROR_PREFIX = '[Network] ERROR: '

local SERVICE_READY = false

---------------
-- VARIABLES --
---------------

local BindableEvent = script:WaitForChild('BindableEvent')
local RemoteEvent = script:WaitForChild('RemoteEvent')

local BindableFunction = script:WaitForChild('BindableFunction')
local RemoteFunction = script:WaitForChild('RemoteFunction')

local events = {}
local functions = {}

local remoteEvents = {}
local remoteFunctions = {}

-----------
-- DEBUG --
-----------

if RunService:IsStudio() and script:GetAttribute('DEBUG') then
	DEBUG = true
end

---------------
-- FUNCTIONS --
---------------

--[[
	Binds a function to a Network RemoteEvent or BindableEvent via a name.
	
	@param remote: boolean	//	Determines whether the associated function is a call from server-to-client or from client-to-client/server-to-server.		
	@param name: string
	@param func: function
--]]

function Network.Add(remote: boolean, name: string, func)
	if remote then
		if not remoteEvents[name] then
			remoteEvents[name] = {func}
		else
			remoteEvents[name][#remoteEvents[name] + 1] = func
		end
	else
		if not events[name] then
			events[name] = {func}
		else
			events[name][#events[name] + 1] = func
		end
	end

	if DEBUG then
		print(NETWORK_DEBUG_PREFIX .. 
			'Added (remote ' .. tostring(remote) .. ') ' .. name)
	end

	return true
end

--[[
	Binds a function to a Network RemoteFunction or BindableFunction via a name.
	
	@param remote: boolean
	@param name: string
	@param func: function
	
	@return: boolean	// 	Success or failure to bind.
]]

function Network.Bind(remote: boolean, name: string, func): boolean
	if (not remote and functions[name]) or (remote and remoteFunctions[name]) then
		error(NETWORK_ERROR_PREFIX .. name .. ' already exists.', 2)

		return false
	end

	if not remote then
		functions[name] = func
	end

	if remote then
		remoteFunctions[name] = func
	end

	if DEBUG then
		print(NETWORK_DEBUG_PREFIX .. 
			'Binded (remote ' .. tostring(remote) .. ') ' .. name)
	end

	return true
end

--[[
	Sends the associated function call to a Network RemoteEvent or BindableEvent via a name.
	
	@param player: Player, {Player}, nil		//		The Send() function can send to a player, multiple players, or none at all (if using the same environment).
	@param remote: boolean
	@param name: string
]]

function Network.Send(player: Player | { Player } | nil, remote: boolean, name: string, ...): boolean
	while not SERVICE_READY do task.wait() end
	
	if remote then
		if CLIENT then
			RemoteEvent:FireServer(name, ...)
		else
			if typeof(player) == 'table' then
				for _, p in pairs(player) do
					RemoteEvent:FireClient(p, name, ...)
				end
			else
				RemoteEvent:FireClient(player, name, ...)
			end
		end
	else
		BindableEvent:Fire(name, ...)
	end

	if DEBUG then
		local props = ...
		if ... == nil then
			props = 'nil'
		end

		print(NETWORK_DEBUG_PREFIX .. 
			'Sent (remote ' .. tostring(remote) .. ') to ' .. name)
	end

	return true
end

--[[
	Network.Send() but to all players. Can only be called from the server!
	
	@param name: string
]]

function Network.SendAllPlayers(name: string, ...)
	if CLIENT then return false end
	
	while not SERVICE_READY do task.wait() end

	RemoteEvent:FireAllClients(name, ...)

	--if DEBUG then
	--	local props = ...
	--	if ... == nil then
	--		props = 'nil'
	--	end

	--	print(NETWORK_DEBUG_PREFIX .. 
	--		'Sent ' .. name .. ' - ' .. props .. ' to all clients.')
	--end

	return true
end

--[[
	Retrieves the result of the associated function call from a Network RemoteFunction or BindableFunction via a name.
	
	@param player: Player, nil
	@param remote: boolean
	@param name: string
	
	@return: any
]]

function Network.Get(player: Player | nil, remote: boolean, name: string, ...): any
	while not SERVICE_READY do task.wait() end
	
	local args = table.pack(...)
	
	if remote then
		if CLIENT then
			local results
			local success, err = pcall(function()
				results = table.pack(RemoteFunction:InvokeServer(name, table.unpack(args, 1, args.n)))
			end)

			if success then
				return table.unpack(results, 1, results.n)
			else
				error(err, 2)
			end
		else
			local results
			local success, err = pcall(function()
				results = table.pack(RemoteFunction:InvokeClient(player, name, table.unpack(args, 1, args.n)))
			end)

			if success then
				return table.unpack(results, 1, results.n)
			else
				error(err, 2)
			end
		end
	else
		local results
		local success, err = pcall(function()
			results = table.pack(BindableFunction:Invoke(name, table.unpack(args, 1, args.n)))
		end)

		if success then
			return table.unpack(results, 1, results.n)
		elseif err then
			error(err, 2)
		end
	end
end

--[[
	Removes a function from a Network event via a name.
	
	@param name: string
	@return: boolean
]]

function Network.Remove(name: string): boolean
	if events[name] then
		events[name] = nil
	end

	if functions[name] then
		functions[name] = nil
	end

	if remoteEvents[name] then
		remoteEvents[name] = nil
	end

	if remoteFunctions[name] then
		remoteFunctions[name] = nil
	end

	return true
end

--[[
	Verifies if a network connection exists or not.
	
	@param name: string
	@return: boolean
]]

function Network.Verify(player: Player | nil, name: string): boolean
	if events[name] then
		return true
	end

	if functions[name] then
		return true
	end

	if remoteEvents[name] then
		return true
	end

	if remoteFunctions[name] then
		return true
	end
	
	if CLIENT then
		return false
	else
		return Network.Get(player, true, 'Verify', name)
	end
end

----------
-- CORE --
----------

Network.Bind(true, 'Verify', function(...) return Network.Verify(nil,...) end)

BindableEvent.Event:Connect(function(name, ...)
	-- Resolves faulty loading
	
	local start: number = os.clock()
	
	while not events[name] do
		if os.clock() - start > 3 then
			break
		end
		
		task.wait()
	end
	
	-- Core
	
	if events[name] then
		for _,func in ipairs(events[name]) do
			func(...)
		end
	else
		warn('Bindable event ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
	end
end)

BindableFunction.OnInvoke = function(name, ...)
	if not name then error("The parsed string is nil, cannot search for bindabe events") end
	
	-- Resolves faulty loading

	local start: number = os.clock()

	while not functions[name] do
		if os.clock() - start > 3 then
			break
		end
		
		task.wait()
	end

	-- Core
	
	if functions[name] then
		return functions[name](...)
	else
		warn('Bindable function ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
	end
end

if CLIENT then
	RemoteEvent.OnClientEvent:Connect(function(name, ...)
		-- Resolves faulty loading

		local start: number = os.clock()

		while not remoteEvents[name] do
			if os.clock() - start > 3 then
				break
			end

			task.wait()
		end

		-- Core
		
		if remoteEvents[name] then
			for _,func in ipairs(remoteEvents[name]) do
				func(...)
			end
		else
			warn('Remote event ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
		end
	end)

	RemoteFunction.OnClientInvoke = function(name, ...)
		-- Resolves faulty loading

		local start: number = os.clock()

		while not remoteFunctions[name] do
			if os.clock() - start > 3 then
				break
			end

			task.wait()
		end

		-- Core
		
		if remoteFunctions[name] then
			return remoteFunctions[name](...)
		else
			warn('Remote function ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
		end
	end
else
	RemoteEvent.OnServerEvent:Connect(function(plr, name, ...)
		-- Resolves faulty loading

		local start: number = os.clock()

		while not remoteEvents[name] do
			if os.clock() - start > 3 then
				break
			end

			task.wait()
		end

		-- Core
		
		if remoteEvents[name] then
			for _,func in ipairs(remoteEvents[name]) do
				func(plr,...)
			end
		else
			warn('Remote event ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
		end
	end)

	RemoteFunction.OnServerInvoke = function(plr, name, ...)
		-- Resolves faulty loading

		local start: number = os.clock()

		while not remoteFunctions[name] do
			if os.clock() - start > 3 then
				break
			end

			task.wait()
		end

		-- Core
		
		if remoteFunctions[name] then
			return remoteFunctions[name](plr,...)
		else
			warn('Remote function ' .. name .. ' does not exist.', 2) -- Passes error (level 2)
		end
	end
end

SERVICE_READY = true

return Network
