
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

function tpad._storage_sanity_check()
	local storage_version = storage:get_string("_version")
	local storage_path = minetest.get_worldpath() .. "/mod_storage/"
	if storage_version == "1.1" then
		tpad._copy_file(storage_path .. tpad.mod_name, storage_path .. tpad.mod_name .. ".1.1.backup") 
		tpad._convert_storage_1_1()
	elseif storage_version ~= "" and storage_version ~= tpad.version then
		error("Mod storage version not supported, aborting to prevent data corruption")
	end
	storage:set_string("_version", tpad.version)
end

function tpad._convert_storage_1_1()
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

tpad._storage_sanity_check()
