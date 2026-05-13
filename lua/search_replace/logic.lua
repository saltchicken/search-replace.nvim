local M = {}

-- Helper to update the buffer if open, otherwise write directly to the file
local function update_file_or_buffer(full_path, new_text)
	local updated_buffer = false

	-- Check if the file is loaded in a current buffer
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
			local lines = vim.split(new_text, "\n")
			-- Remove trailing empty line from split to avoid adding extra lines at EOF
			if lines[#lines] == "" then
				table.remove(lines)
			end

			-- Update the buffer directly
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			updated_buffer = true
			break
		end
	end

	-- If not open in any buffer, write directly to the file system using libuv
	if not updated_buffer then
		local uv = vim.uv or vim.loop
		local fd = uv.fs_open(full_path, "w", 438) -- 438 is octal 0666 permissions
		if fd then
			uv.fs_write(fd, new_text)
			uv.fs_close(fd)
		else
			vim.notify("[search_replace.nvim] Failed to write to file: " .. full_path, vim.log.levels.ERROR)
		end
	end
end

function M.apply_blocks(content)
    local found = false

    -- 1. Explicit CREATE blocks
    local create_pattern = "([^\n]+)\n<<<<<<< CREATE\n(.-)\n>>>>>>> CREATE"
    for path, create_content in content:gmatch(create_pattern) do
        found = true
        path = vim.trim(path)
        local full_path = vim.fn.fnamemodify(path, ":p")

        if vim.fn.filereadable(full_path) == 1 then
            vim.notify("[search_replace.nvim] ⚠️ File exists, skipping CREATE: " .. path, vim.log.levels.WARN)
            goto continue_create
        end

        vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
        local uv = vim.uv or vim.loop
        local fd = uv.fs_open(full_path, "w", 438)
        if fd then
            uv.fs_write(fd, create_content)
            uv.fs_close(fd)
            vim.notify("[search_replace.nvim] 🌟 Created: " .. path, vim.log.levels.INFO)
        else
            vim.notify("[search_replace.nvim] ❌ Failed to create: " .. path, vim.log.levels.ERROR)
        end
        ::continue_create::
    end

    -- 2. Standard SEARCH/REPLACE blocks
    local block_pattern = "([^\n]+)\n<<<<<<< SEARCH\n(.-)\n=======\n(.-)\n>>>>>>> REPLACE"
    for path, search, replace in content:gmatch(block_pattern) do
        found = true
        path = vim.trim(path)
        local full_path = vim.fn.fnamemodify(path, ":p")

        if vim.fn.filereadable(full_path) == 0 then
            search = search:gsub("\r", ""):gsub("%s+$", "")
            if search == "" then
                vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
                local uv = vim.uv or vim.loop
                local fd = uv.fs_open(full_path, "w", 438)
                if fd then
                    uv.fs_write(fd, replace)
                    uv.fs_close(fd)
                    vim.notify("[search_replace.nvim] 🌟 Created (Empty Search): " .. path, vim.log.levels.INFO)
                else
                    vim.notify("[search_replace.nvim] ❌ Failed to create: " .. path, vim.log.levels.ERROR)
                end
            else
                vim.notify("[search_replace.nvim] ❌ File not found: " .. path, vim.log.levels.ERROR)
            end
            goto continue
        end

        local uv = vim.uv or vim.loop
        local fd = uv.fs_open(full_path, "r", 438)
		if not fd then
			vim.notify("[search_replace.nvim] Permission denied reading: " .. path, vim.log.levels.ERROR)
			goto continue
		end

		-- Read the whole file safely
		local stat = uv.fs_fstat(fd)
		local file_text = uv.fs_read(fd, stat.size, 0)
		uv.fs_close(fd)

        -- 1. Normalize line endings (strip \r to prevent Windows/Unix mismatch)
        search = search:gsub("\r", ""):gsub("%s+$", "")
        replace = replace:gsub("\r", "")

        if search == "" then
            -- File exists but search is empty: potentially unsafe overwrite
            vim.notify("[search_replace.nvim] ⚠️ Empty SEARCH block on existing file " .. path, vim.log.levels.WARN)
            goto continue
        end

		-- 2. Safely escape Lua pattern magic characters
		local escaped_search = search:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

		-- 3. Make whitespace flexible:
		escaped_search = escaped_search:gsub("[ \t]+", "[ \t]+")
		local flex_pattern = escaped_search:gsub("\n", "%%s+")

		-- 4. Find and Replace using the flexible pattern
		if file_text:find(flex_pattern) then
			local new_text = file_text:gsub(flex_pattern, function()
				return replace
			end, 1)

			-- Use our new smart update function
			update_file_or_buffer(full_path, new_text)
			vim.notify("[search_replace.nvim] ✅ Applied: " .. path, vim.log.levels.INFO)
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
