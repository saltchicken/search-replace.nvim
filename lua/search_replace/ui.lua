local M = {}
local logic = require("search_replace.logic")

function M.open_input()
	local buf = vim.api.nvim_create_buf(false, true)
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")
	local win_width = math.floor(width * 0.8)
	local win_height = math.floor(height * 0.8)

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

	vim.api.nvim_win_set_cursor(win, { 3, 0 })

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
