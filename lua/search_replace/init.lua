local M = {}

M.setup = function(opts)
	M.config = vim.tbl_deep_extend("force", {
		-- defaults go here
	}, opts or {})

	vim.api.nvim_create_user_command("SearchReplace", function()
		require("search_replace.ui").open_input()
	end, { desc = "Open Search Replace UI" })
end

return M
