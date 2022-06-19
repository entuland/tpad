
local storage = minetest.get_mod_storage()

function tpad._get_all_pads()
	local storage_table = storage:to_table()
	local allpads = {}
	for key, value in pairs(storage_table.fields) do
		local parts = key:split(":")
		if parts[1] == "pads" then
			local pads = minetest.deserialize(value)
			if type(pads) == "table" then
				allpads[parts[2]] = pads			
			end
		end
	end
	return allpads
end

function tpad._get_stored_pads(ownername)
	local serial_pads = storage:get_string("pads:" .. ownername)
	if serial_pads == nil or serial_pads == "" then return {} end
	return minetest.deserialize(serial_pads)
end

function tpad._set_stored_pads(ownername, pads)
	storage:set_string("pads:" .. ownername, minetest.serialize(pads))
end

function tpad.set_max_total_pads(max)
	if not max then max = 0 end
	storage:set_string("max_total_pads_per_player", max)
end

function tpad.get_max_total_pads()
	local max = tonumber(storage:get_string("max_total_pads_per_player"))
	if not max then
		tpad.set_max_total_pads(100)
		return 100
	end
	return max
end

function tpad.set_max_global_pads(max)
	if not max then max = 0 end
	storage:set_string("max_global_pads_per_player", max)
end

function tpad.get_max_global_pads()
	local max = tonumber(storage:get_string("max_global_pads_per_player"))
	if not max then
		tpad.set_max_global_pads(4)
		return 4
	end
	return max
end

local function _convert_legacy_settings()
	local legacy_settings_file = minetest.get_worldpath() .. "/mod_storage/" .. tpad.mod_name .. ".custom.conf"
	local file = io.open(legacy_settings_file, "r")
	if file then
		file:close()
		local settings = Settings(legacy_settings_file)
		local max_global = tonumber(settings:get("max_global_pads_per_player"))
		if max_global then
			tpad.set_max_global_pads(max_global)
		end
		local max_total = tonumber(settings:get("max_total_pads_per_player"))
		if max_total then
			tpad.set_max_total_pads(max_total)
		end
		os.remove(legacy_settings_file)
	end
end

_convert_legacy_settings()
tpad.get_max_total_pads()
tpad.get_max_global_pads()

local function _convert_storage_1_1()
	local storage_table = storage:to_table()
	for field, value in pairs(storage_table.fields) do
		local parts = field:split(":")
		if parts[1] == "pads" then
			local pads = minetest.deserialize(value)
			for key, name in pairs(pads) do
				pads[key] = { name = name }
			end
			storage_table.fields[field] = minetest.serialize(pads)
		end
	end
	storage:from_table(storage_table)
end

local function _storage_version_check()
	local storage_version = storage:get_string("_version")
	local storage_path = minetest.get_worldpath() .. "/mod_storage/"
	if storage_version == "1.1" then
		local file = io.open(storage_path .. tpad.mod_name, "r")
		if file then
			file:close()
			tpad._copy_file(storage_path .. tpad.mod_name, storage_path .. tpad.mod_name .. ".1.1.backup") 
		end
		_convert_storage_1_1()
	elseif storage_version ~= "" and storage_version ~= tpad.version then
		error("Mod storage version not supported, aborting to prevent data corruption")
	end
	storage:set_string("_version", tpad.version)
end

_storage_version_check()
