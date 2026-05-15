-- lua/search_replace/logic.lua
local M = {}

-- Helper to read from buffer, ensuring the file is loaded into Neovim
-- (Crucial for chained blocks and ensuring the undo history captures all subsequent writes)
local function read_file_or_buffer(full_path)
    if vim.fn.filereadable(full_path) == 0 then
        return nil
    end

    local target_buf = vim.fn.bufadd(full_path)
    if not vim.api.nvim_buf_is_loaded(target_buf) then
        vim.fn.bufload(target_buf)
    end
    
    vim.api.nvim_set_option_value("buflisted", true, { buf = target_buf })
    return table.concat(vim.api.nvim_buf_get_lines(target_buf, 0, -1, false), "\n")
end

-- Helper to update the buffer, enforcing buffer usage to preserve undo history
local function update_file_or_buffer(full_path, new_text)
    local target_buf = vim.fn.bufadd(full_path)
    if not vim.api.nvim_buf_is_loaded(target_buf) then
        vim.fn.bufload(target_buf)
    end
    
    vim.api.nvim_set_option_value("buflisted", true, { buf = target_buf })

    local lines = vim.split(new_text, "\n")
    if lines[#lines] == "" then
        table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(target_buf, function() vim.cmd("silent! write") end)
end

-- Helper to ensure the target path strictly resides within the current project root
local function is_safe_path(full_path)
    local cwd = vim.fn.getcwd()
    local sep = package.config:sub(1, 1)
    if cwd:sub(-1) ~= sep then
        cwd = cwd .. sep
    end
    return vim.startswith(full_path, cwd)
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
        local delete_s, delete_e = content:find("<<<<<<< DELETE\n", pos, true)
        local move_s, move_e = content:find("<<<<<<< MOVE\n", pos, true)

        local blocks = {}
        if search_s then table.insert(blocks, { type = "search", s = search_s, e = search_e }) end
        if create_s then table.insert(blocks, { type = "create", s = create_s, e = create_e }) end
        if delete_s then table.insert(blocks, { type = "delete", s = delete_s, e = delete_e }) end
        if move_s then table.insert(blocks, { type = "move", s = move_s, e = move_e }) end

        if #blocks == 0 then
            break
        end

        table.sort(blocks, function(a, b) return a.s < b.s end)
        local first_block = blocks[1]

        local is_search = first_block.type == "search"
        local is_create = first_block.type == "create"
        local is_delete = first_block.type == "delete"
        local is_move = first_block.type == "move"

        blocks_found = blocks_found + 1

        local start_idx = first_block.s
        local end_idx = first_block.e

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

        if not is_safe_path(full_path) then
            vim.notify("[search_replace.nvim] Skipping block: Path outside project root (" .. current_path .. ").", vim.log.levels.ERROR)
            pos = end_idx + 1
            goto continue_loop
        end

        if is_create then
			local close_s, close_e = content:find("\n>>>>>>> CREATE", end_idx, true)
			if not close_s then
				break
			end

			local create_text = content:sub(end_idx + 1, close_s - 1)

            if vim.fn.filereadable(full_path) == 1 then
                local choice = vim.fn.confirm("File exists: " .. current_path .. "\nOverwrite?", "&Yes\n&No", 2)
                if choice == 1 then
                    update_file_or_buffer(full_path, create_text)
                    vim.notify(
                        "[search_replace.nvim] ⚠️ File existed, overwritten by CREATE: " .. current_path,
                        vim.log.levels.WARN
                    )
                else
                    vim.notify(
                        "[search_replace.nvim] ⏭️ Skipped CREATE (User rejected overwrite): " .. current_path,
                        vim.log.levels.INFO
                    )
                end
            else
                vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
                update_file_or_buffer(full_path, create_text)
                vim.notify("[search_replace.nvim] 🌟 Created: " .. current_path, vim.log.levels.INFO)
            end

            pos = close_e + 1
        elseif is_delete then
            local close_s, close_e = content:find("\n>>>>>>> DELETE", end_idx, true)
            if not close_s then
                break
            end

            if vim.fn.filereadable(full_path) == 1 then
                local choice = vim.fn.confirm("Delete file: " .. current_path .. "?", "&Yes\n&No", 2)
                if choice == 1 then
                    if vim.fn.delete(full_path) == 0 then
                        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                            if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
                                vim.api.nvim_buf_delete(buf, { force = true })
                                break
                            end
                        end
                        vim.notify("[search_replace.nvim] 🗑️ Deleted: " .. current_path, vim.log.levels.INFO)
                    else
                        vim.notify("[search_replace.nvim] ❌ Failed to delete: " .. current_path, vim.log.levels.ERROR)
                    end
                else
                    vim.notify("[search_replace.nvim] ⏭️ Skipped DELETE (User rejected): " .. current_path, vim.log.levels.INFO)
                end
            else
                vim.notify("[search_replace.nvim] ❌ File not found for DELETE: " .. current_path, vim.log.levels.ERROR)
            end

            pos = close_e + 1
        elseif is_move then
            local close_s, close_e = content:find("\n>>>>>>> MOVE", end_idx, true)
            if not close_s then
                break
            end

            local new_path_raw = vim.trim(content:sub(end_idx + 1, close_s - 1))
            local new_full_path = vim.fn.fnamemodify(new_path_raw, ":p")

            if not is_safe_path(new_full_path) then
                vim.notify("[search_replace.nvim] Skipping MOVE: Destination outside project root (" .. new_path_raw .. ").", vim.log.levels.ERROR)
                pos = close_e + 1
                goto continue_loop
            end

            if vim.fn.filereadable(full_path) == 1 then
                vim.fn.mkdir(vim.fn.fnamemodify(new_full_path, ":h"), "p")
                if vim.fn.rename(full_path, new_full_path) == 0 then
                    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                        if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
                            vim.api.nvim_buf_set_name(buf, new_full_path)
                            vim.api.nvim_buf_call(buf, function() vim.cmd("silent! write") end)
                            break
                        end
                    end
                    vim.notify("[search_replace.nvim] 🚚 Moved: " .. current_path .. " -> " .. new_path_raw, vim.log.levels.INFO)
                else
                    vim.notify("[search_replace.nvim] ❌ Failed to move: " .. current_path, vim.log.levels.ERROR)
                end
            else
                vim.notify("[search_replace.nvim] ❌ File not found for MOVE: " .. current_path, vim.log.levels.ERROR)
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
                        update_file_or_buffer(full_path, replace_text)
                        vim.notify(
                            "[search_replace.nvim] 🌟 Created (Empty Search): " .. current_path,
                            vim.log.levels.INFO
                        )
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
