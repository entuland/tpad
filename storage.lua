
local storage = minetest.get_mod_storage()

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
	if storage_version == "1" then
		tpad._convert_storage_1()
	end
	storage:set_string("_version", tpad.version)
end

function tpad._convert_storage_1()
	local serial_pads = storage:get_string("pads")
	storage:set_string("pads", "")
	if serial_pads == nil or serial_pads == "" then return end
	local allpads = minetest.deserialize(serial_pads)
	for ownername, pads in pairs(allpads) do
		storage:set_string("pads:" .. ownername, minetest.serialize(pads))
	end
end

tpad._storage_sanity_check()
