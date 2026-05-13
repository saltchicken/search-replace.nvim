vim.api.nvim_create_user_command("SearchReplace", function()
	require("search_replace.ui").open_input()
end, {})
