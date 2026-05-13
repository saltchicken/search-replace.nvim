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

		-- 1. Normalize line endings (strip \r to prevent Windows/Unix mismatch)
		search = search:gsub("\r", "")
		replace = replace:gsub("\r", "")

		-- 2. Strip trailing whitespace from search to prevent the flexible
		-- pattern from greedily eating next-line indentation
		search = search:gsub("%s+$", "")
		if search == "" then
			vim.notify("[search_replace.nvim] ⚠️ Empty SEARCH block in " .. path, vim.log.levels.WARN)
			goto continue
		end

		-- 3. Safely escape Lua pattern magic characters
		local escaped_search = search:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

		-- 4. Make whitespace flexible:
		-- Replace horizontal spaces/tabs with a class that matches one or more
		escaped_search = escaped_search:gsub("[ \t]+", "[ \t]+")
		-- Replace newlines with %s+ to tolerate \r\n, varying indentation, or extra blank lines
		local flex_pattern = escaped_search:gsub("\n", "%%s+")

		-- 5. Find and Replace using the flexible pattern
		if file_text:find(flex_pattern) then
			-- Limit to 1 replacement to avoid unintended side effects on identical lines
			local new_text = file_text:gsub(flex_pattern, function()
				return replace
			end, 1)

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
