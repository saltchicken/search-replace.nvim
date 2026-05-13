vim.api.nvim_create_user_command("SearchReplace", function()
	require("search-replace.ui").open_input()
end, {})
