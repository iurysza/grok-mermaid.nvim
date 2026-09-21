local M = {}

local defaults = {
	auto_render = true,
	filetypes = { "markdown" },
	node = "node",
	bridge = nil,
}

local options = vim.deepcopy(defaults)

local function root()
	local source = debug.getinfo(1, "S").source:sub(2)
	return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

function M.setup(user_options)
	user_options = user_options or {}
	vim.validate({
		auto_render = { user_options.auto_render, "boolean", true },
		filetypes = { user_options.filetypes, "table", true },
		node = { user_options.node, "string", true },
		bridge = { user_options.bridge, "string", true },
	})
	options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_options)
	options.bridge = options.bridge or (root() .. "/bridge/render.mjs")
end

function M.get()
	return options
end

function M.defaults()
	return vim.deepcopy(defaults)
end

return M
