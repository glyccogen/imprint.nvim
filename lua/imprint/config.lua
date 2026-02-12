local M = {}

M.defaults = {
	default_title = nil,
	required_title_by_default = true,
	copy_to_clipboard = false,
	output_dir = nil,
	background = "#A5A6F6",
	line_numbers = "absolute_from_1",
	highlight_current_line = false,
	diagnostics_on = false,
	icons_on = true,
}

M.opts = {}

function M.setup(user_opts)
	M.opts = vim.tbl_deep_extend("force", {}, M.defaults, user_opts or {})
end

return M
