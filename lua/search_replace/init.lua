local M = {}

M.setup = function(opts)
	M.config = vim.tbl_deep_extend("force", {}, opts or {})
end

return M
