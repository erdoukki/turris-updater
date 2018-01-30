--[[
Copyright 2016, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of the turris updater.

Updater is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Updater is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Updater.  If not, see <http://www.gnu.org/licenses/>.
]]--

local pairs = pairs
local ipairs = ipairs
local next = next
local error = error
local type = type
local setmetatable = setmetatable
local getmetatable = getmetatable
local assert = assert
local table = table
local string = string
local math = math
local io = io
local unpack = unpack
local events_wait = events_wait
local run_util = run_util

local tostring = tostring

local INFO = INFO

module "utils"

-- luacheck: globals lines2set map set2arr arr2set cleanup_dirs slurp clone shallow_copy table_merge arr_append exception multi_index private filter_best strip table_overlay tablelength randstr arr_prune arr_inv

--[[
Convert provided text into set of lines. Doesn't care about the order.
You may override the separator, if your lines aren't terminated by \n.
]]
function lines2set(lines, separator)
	separator = separator or "\n"
	local result = {}
	for line in lines:gmatch("[^" .. separator .. "]+") do
		result[line] = true
	end
	return result
end

--[[
Run a function for each key and value in the table.
The function shall return new key and value (may be
the same and may be modified). A new table with
the results is returned.
]]
function map(table, fun)
	local result = {}
	for k, v in pairs(table) do
		local nk, nv = fun(k, v)
		result[nk] = nv
	end
	return result
end

-- Convert a set to an array
function set2arr(set)
	local idx = 0
	return map(set, function (key)
		idx = idx + 1
		return idx, key
	end)
end

function arr2set(arr)
	return map(arr, function (_, name) return name, true end)
end

-- Removes all nil values by shifting upper elements down.
function arr_prune(arr)
	local indxs = set2arr(arr)
	table.sort(indxs)
	local res = {}
	for _, i in ipairs(indxs) do
		table.insert(res, arr[i])
	end
	return res
end

-- Inverts order of array
function arr_inv(arr)
	local mid = math.modf(#arr / 2)
	local endi = #arr + 1
	for i = 1, mid do
		local v = arr[i]
		arr[i] = arr[endi - i]
		arr[endi - i] = v
	end
	return arr
end

-- Run rm -rf on all dirs in the provided table
function cleanup_dirs(dirs)
	if next(dirs) then
		events_wait(run_util(function (ecode, _, _, stderr)
			if ecode ~= 0 then
				error("rm -rf failed: " .. stderr)
			end
		end, nil, nil, -1, -1, "rm", "-rf", unpack(dirs)));
	end
end

--[[
Read the whole content of given file. Return the content, or nil and error message.
In case of errors during the reading (instead of when opening), it calls error()
]]
function slurp(filename)
	local f, err = io.open(filename)
	if not f then
		return nil, err
	end
	local content = f:read("*a")
	f:close()
	if not content then error("Could not read content of " .. filename) end
	return content
end

--[[
Make a deep copy of passed data. This does not work on userdata, on functions
(which might have some local upvalues) and metatables (it doesn't fail, it just
doesn't copy them and uses the original).
]]
function clone(data)
	local cloned = {}
	local function clone_internal(data)
		if cloned[data] ~= nil then
			return cloned[data]
		elseif type(data) == "table" then
			local result = {}
			cloned[data] = result
			for k, v in pairs(data) do
				result[clone_internal(k)] = clone_internal(v)
			end
			return result
		else
			return data
		end
	end
	return clone_internal(data)
end

-- Make a shallow copy of passed data structure. Same limitations as with clone.
function shallow_copy(data)
	if type(data) == 'table' then
		local result = {}
		for k, v in pairs(data) do
			result[k] = v
		end
		return result
	else
		return data
	end
end

-- Add all elements of src to dest
function table_merge(dest, src)
	for k, v in pairs(src) do
		dest[k] = v
	end
end

-- Append one table/array at the end of another
function arr_append(into, what)
	local offset = #into
	for i, v in ipairs(what) do
		into[i + offset] = v
	end
end

local error_meta = {
	__tostring = function (err)
		return err.msg
	end
}

-- Generate an exception/error object. It can be further modified, of course.
function exception(reason, msg, extra)
	local except = {
		tp = "error",
		reason = reason,
		msg = msg
	}
	assert(not(extra and (extra.tp or extra.reason or extra.msg)))
	table_merge(except, extra or {})
	return setmetatable(except, error_meta)
end

--[[
If you call multi_index(table, idx1, idx2, idx3), it tries
to return table[idx1][idx2][idx3]. But if it finds anything
that is not a table on the way, nil is returned.
]]
function multi_index(table, ...)
	for _, idx in ipairs({...}) do
		if type(table) ~= "table" then
			return nil
		else
			table = table[idx]
		end
	end
	return table
end

--[[
Provide a hidden table on a given table. It uses a meta table
(and it expects the thing doesn't have one!).

If there's no hidden table yet, one is created. Otherwise,
the current one is returned.
]]
function private(tab)
	local meta = getmetatable(tab)
	if not meta then
		meta = {}
		setmetatable(tab, meta)
	end
	if not meta.private then
		meta.private = {}
	end
	return meta.private
end

--[[
Go through the array, call the property function on each item and compare
them using the cmp function. Return array of only the values that are the
best possible (there may be multiple, in case of equivalence).

The cmp returns true in case the first argument is better than the second.
Equality is compared using ==.

Assumes the array is non-empty. The order of values is preserved.
]]
function filter_best(arr, property, cmp)
	-- Start with empty array, the first item has the same property as the first item, so it gets inserted right away
	local best = {}
	local best_idx = 1
	local best_prop = property(arr[1])
	for _, v in ipairs(arr) do
		local prop = property(v)
		if prop == best_prop then
			-- The same as the currently best
			best[best_idx] = v
			best_idx = best_idx + 1
		elseif cmp(prop, best_prop) then
			-- We have a better one ‒ replace all candidates
			best_prop = prop
			best = {v}
			best_idx = 2
		end
		-- Otherwise it's worse, so just ignore it
	end
	return best
end

--[[
Strip whitespace from both ends of the given string. \n is considered whitespace.
It passes other types through (eg. nil).
]]
function strip(str)
	if type(str) == 'string' then
		return str:match('^%s*(.-)%s*$')
	else
		return str
	end
end

--[[
Returns random string in given length.
]]
function randstr(len)
	local str = ""
	for _ =  1,len do
		str = str .. string.char(math.random(33, 126))
	end
	return str
end

--[[
Create a new table that will be an overlay of another table. Values that are
set here are remembered. Lookups of other values are propagated to the original
table.

This is different from copying the table and setting some values in the copy
in two ways:
• Changes to the original table after the fact are visible in the overlay
  mode.
• It is not possible to remove a key using the overlay.
]]
function table_overlay(table)
	return setmetatable({}, {
		__index = table
	})
end

-- BB: Get table length
function tablelength(table)
	local count = 0
	for _ in pairs(table) do count = count + 1 end
	return count
end

-- +BB support for saving table to a file (debug stuff)


--[[
    mold every value
]]
function mold(value)
    local output = ""
    if type(value) == "string" then
        output = '"' .. value .. '"'
    else
        output = tostring(value)
	end
	return output
end


--[[
    mold value other than table
]]
function mold_value(value)
    local output = ""
    if type(value) == "string" then
        output = '"' .. value .. '"'
    else
        output = tostring(value)
	end
	return output
end

function mold_table(table, depth)
	if depth == nil then depth = 999 end -- max allowed depth
    local indent = ""
	local output = ""
	-- TODO: write just `mold` that wouldn't need this
	if type(table) ~= "table" then
		return mold_value(table)
	end
	function submold_table(table, depth)
		if depth < 1 then return nil end
        for key, value in pairs(table) do
            if type(value) == "table" then
                output = output .. indent .. key .. " = {\n"
				indent = indent .. "  "
				depth = depth - 1
				submold_table(value, depth)
				depth = depth + 1
                indent = indent:sub(1, -3)          -- unindent
--                output = output:sub(1, -3) .. "\n"  -- get rid of last comma
                output = output .. indent .. "}\n"
            else
                output = output .. indent .. key .. " = " .. mold_value(value) .. ",\n"
            end
        end        
    end
    submold_table(table, depth)
--    output = output:sub(1, -3) .. "\n" -- get rid of last comma
    return output
end

function save_table(filename, table, depth)
	INFO("saving table to " .. filename .. "...")
	local file = assert(io.open(filename, "w"))
	file:write(mold_table(table, depth))
	INFO("saving done.")
	file:close()
 end	

function savetxt (t)
	INFO("saving in progress...")
	local file = assert(io.open("/root/test.txt", "w"))
	file:write(mold_table(t))
	INFO("saving done.")
	file:close()
 end

-- -BB

--[[
	Split string with user defined separator
]]
function split(inputstr, sep)
	if sep == nil then
			sep = "%s"
	end
	local t={} ; i=1
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
			t[i] = str
			i = i + 1
	end
	return t
end

--[[
	Read file, return its content
]]
function load(filename)
    local file = io.open(filename, "r")
    local content = file:read("*all")
    file:close()
    return content
end

function save(filename, content)
	local file = io.open(filename, "w")
	file:write(content)
	file:close()
end

return _M
