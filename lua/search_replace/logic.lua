local M = {}

function M.apply_blocks(content)
	local block_pattern = "([^\n]+)\n<<<<<<< SEARCH\n(.-)\n=======\n(.-)\n>>>>>>> REPLACE"
	local found = false

	for path, search, replace in content:gmatch(block_pattern) do
		found = true
		path = vim.trim(path)
		local full_path = vim.fn.fnamemodify(path, ":p")

		if vim.fn.filereadable(full_path) == 0 then
			vim.notify("[search_replace.nvim] File not found: " .. path, vim.log.levels.ERROR)
			goto continue
		end

		local f = io.open(full_path, "r")
		if not f then
			vim.notify("[search_replace.nvim] Permission denied reading: " .. path, vim.log.levels.ERROR)
			goto continue
		end
		local file_text = f:read("*all")
		f:close()

		-- Literal match: escape special Lua pattern characters
		local escaped_search = search:gsub("([^%w])", "%%%1")

		if file_text:find(escaped_search, 1, true) then
			local new_text = file_text:gsub(escaped_search, function()
				return replace
			end)

			local out = io.open(full_path, "w")
			out:write(new_text)
			out:close()

			vim.notify("[search_replace.nvim] ✅ Applied: " .. path, vim.log.levels.INFO)

			-- Refresh buffers if open
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_get_name(buf) == full_path then
					vim.api.nvim_buf_call(buf, function()
						vim.cmd("checktime")
					end)
				end
			end
		else
			vim.notify("[search_replace.nvim] ⚠️ SEARCH block mismatch in " .. path, vim.log.levels.WARN)
		end

		::continue::
	end

	if not found then
		vim.notify("[search_replace.nvim] No blocks found in input.", vim.log.levels.WARN)
	end
end

return M
