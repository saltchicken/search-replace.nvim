local M = {}

M.setup = function(opts)
	-- Options could include custom keybindings or border styles later
	M.config = vim.tbl_deep_extend("force", {
		mapping = "<leader>ai",
	}, opts or {})

	if M.config.mapping then
		vim.keymap.set("n", M.config.mapping, function()
			require("search-replace.ui").open_input()
		end, { desc = "Open Search Replace Apply Box" })
	end
end

return M
