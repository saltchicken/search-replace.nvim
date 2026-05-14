-- lua/search_replace/logic.lua
local M = {}

-- Helper to read from buffer if open, otherwise read from file system
-- (Crucial for chained blocks: ensures we read the newly updated text from the buffer)
local function read_file_or_buffer(full_path)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		end
	end

	local uv = vim.uv or vim.loop
	local fd = uv.fs_open(full_path, "r", 438)
	if not fd then
		return nil
	end

	local stat = uv.fs_fstat(fd)
	local text = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	return text
end

-- Helper to update the buffer if open, otherwise write directly to the file
local function update_file_or_buffer(full_path, new_text)
	local updated_buffer = false

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
			local lines = vim.split(new_text, "\n")
			if lines[#lines] == "" then
				table.remove(lines)
			end

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			updated_buffer = true
			break
		end
	end

	if not updated_buffer then
		local uv = vim.uv or vim.loop
		local fd = uv.fs_open(full_path, "w", 438)
		if fd then
			uv.fs_write(fd, new_text)
			uv.fs_close(fd)
		else
			vim.notify("[search_replace.nvim] Failed to write to file: " .. full_path, vim.log.levels.ERROR)
		end
	end
end

function M.apply_blocks(content)
    -- Sanitize Non-Breaking Spaces (NBSP) commonly introduced by LLM web interfaces
    content = content:gsub("\194\160", " ")

    local blocks_found = 0
    local pos = 1
    local current_path = nil

    -- Sequential parser to maintain the `current_path` state across chained blocks
    while pos <= #content do
		local search_s, search_e = content:find("<<<<<<< SEARCH\n", pos, true)
		local create_s, create_e = content:find("<<<<<<< CREATE\n", pos, true)

		local is_search = search_s and (not create_s or search_s < create_s)
		local is_create = create_s and (not search_s or create_s < search_s)

        if not is_search and not is_create then
            break
        end

        blocks_found = blocks_found + 1

        local start_idx = is_search and search_s or create_s
		local end_idx = is_search and search_e or create_e

        -- Extract path from text before the block
        local pre_text = vim.trim(content:sub(pos, start_idx - 1))
        if pre_text ~= "" then
            local lines = vim.split(pre_text, "\n")
            -- Find the last non-empty line that isn't a closing block tag or markdown fence
            for i = #lines, 1, -1 do
                local line = vim.trim(lines[i])
                if line ~= "" and not line:match("^>>>>>>>") and not line:match("^```") then
                    current_path = line
                    break
                end
            end
        end

		if not current_path then
			vim.notify("[search_replace.nvim] Skipping block: No file path found.", vim.log.levels.WARN)
			pos = end_idx + 1
			goto continue_loop
		end

		local full_path = vim.fn.fnamemodify(current_path, ":p")

		if is_create then
			local close_s, close_e = content:find("\n>>>>>>> CREATE", end_idx, true)
			if not close_s then
				break
			end

			local create_text = content:sub(end_idx + 1, close_s - 1)

			if vim.fn.filereadable(full_path) == 1 then
				vim.notify(
					"[search_replace.nvim] ⚠️ File exists, skipping CREATE: " .. current_path,
					vim.log.levels.WARN
				)
			else
				vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
				local uv = vim.uv or vim.loop
				local fd = uv.fs_open(full_path, "w", 438)
				if fd then
					uv.fs_write(fd, create_text)
					uv.fs_close(fd)
					vim.notify("[search_replace.nvim] 🌟 Created: " .. current_path, vim.log.levels.INFO)
				else
					vim.notify("[search_replace.nvim] ❌ Failed to create: " .. current_path, vim.log.levels.ERROR)
				end
			end

			pos = close_e + 1
		elseif is_search then
			local div_s, div_e = content:find("\n=======\n", end_idx, true)
			if not div_s then
				break
			end

			local close_s, close_e = content:find("\n>>>>>>> REPLACE", div_e, true)
			if not close_s then
				break
			end

			local search_text = content:sub(end_idx + 1, div_s - 1)
			local replace_text = content:sub(div_e + 1, close_s - 1)

			if vim.fn.filereadable(full_path) == 0 then
				search_text = search_text:gsub("\r", ""):gsub("%s+$", "")
				if search_text == "" then
					vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
					local uv = vim.uv or vim.loop
					local fd = uv.fs_open(full_path, "w", 438)
					if fd then
						uv.fs_write(fd, replace_text)
						uv.fs_close(fd)
						vim.notify(
							"[search_replace.nvim] 🌟 Created (Empty Search): " .. current_path,
							vim.log.levels.INFO
						)
					else
						vim.notify("[search_replace.nvim] ❌ Failed to create: " .. current_path, vim.log.levels.ERROR)
					end
				else
					vim.notify("[search_replace.nvim] ❌ File not found: " .. current_path, vim.log.levels.ERROR)
				end
			else
				-- Read the current state of the file (picks up previous chain replacements)
				local file_text = read_file_or_buffer(full_path)

				if not file_text then
					vim.notify(
						"[search_replace.nvim] Permission denied reading: " .. current_path,
						vim.log.levels.ERROR
					)
				else
					search_text = search_text:gsub("\r", ""):gsub("%s+$", "")
					replace_text = replace_text:gsub("\r", "")

					if search_text == "" then
						vim.notify(
							"[search_replace.nvim] ⚠️ Empty SEARCH block on existing file " .. current_path,
							vim.log.levels.WARN
						)
					else
						local escaped_search = search_text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
						escaped_search = escaped_search:gsub("[ \t]+", "[ \t]+")
						local flex_pattern = escaped_search:gsub("\n", "%%s+")

                        -- Try an exact plain-text match first (faster and avoids "pattern too complex" errors on huge blocks)
                        local exact_start, exact_end = file_text:find(search_text, 1, true)

                        if exact_start then
                            local new_text = file_text:sub(1, exact_start - 1) .. replace_text .. file_text:sub(exact_end + 1)
                            update_file_or_buffer(full_path, new_text)
                            vim.notify("[search_replace.nvim] ✅ Applied (Exact Match): " .. current_path, vim.log.levels.INFO)
                        elseif file_text:find(flex_pattern) then
                            local new_text = file_text:gsub(flex_pattern, function()
                                return replace_text
                            end, 1)

                            update_file_or_buffer(full_path, new_text)
                            vim.notify("[search_replace.nvim] ✅ Applied (Flex Match): " .. current_path, vim.log.levels.INFO)
                        else
                            vim.notify(
                                "[search_replace.nvim] ⚠️ SEARCH block mismatch in " .. current_path,
                                vim.log.levels.WARN
                            )
                        end
					end
				end
			end

			pos = close_e + 1
		end

		::continue_loop::
	end

    if blocks_found == 0 then
        vim.notify("[search_replace.nvim] No blocks found in input.", vim.log.levels.WARN)
    elseif blocks_found > 1 then
        vim.notify("[search_replace.nvim] Processed " .. blocks_found .. " blocks consecutively.", vim.log.levels.INFO)
    end
end

return M
