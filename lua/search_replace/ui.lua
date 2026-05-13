local M = {}
local logic = require("search_replace.logic")

function M.open_input()
	local buf = vim.api.nvim_create_buf(false, true)

	-- Ensure the buffer cleans up after itself
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

	local width = vim.api.nvim_get_option_value("columns", {})
	local height = vim.api.nvim_get_option_value("lines", {})
	local win_width = math.floor(width * 0.8)
	local win_height = math.floor(height * 0.8)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"-- PASTE SEARCH/REPLACE BLOCKS --",
		"-- <CR> to Apply | q to Cancel --",
		"",
	})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"-- PASTE SEARCH/REPLACE BLOCKS --",
		"-- <CR> to Apply | q to Cancel --",
		"",
	})

	local win = vim.api.nvim_open_win(buf, true, {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = math.floor((height - win_height) / 2),
		col = math.floor((width - win_width) / 2),
		border = "rounded",
		title = "Search Replace",
		title_pos = "center",
	})

	-- Put cursor inside the SEARCH block
	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	-- Automatically start in insert mode to make pasting faster
	vim.cmd("startinsert")

	vim.keymap.set("n", "<CR>", function()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		vim.api.nvim_win_close(win, true)
		logic.apply_blocks(table.concat(lines, "\n"))
	end, { buffer = buf })

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, { buffer = buf })
end

return M
