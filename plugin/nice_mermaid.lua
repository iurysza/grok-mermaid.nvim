if vim.g.loaded_nice_mermaid then
	return
end
vim.g.loaded_nice_mermaid = true

vim.api.nvim_create_user_command("Mermaid", function(command)
	local mermaid = require("nice_mermaid")
	mermaid.setup()
	mermaid.command(command.args)
end, {
	nargs = "?",
	complete = function()
		return { "toggle", "render", "source", "clear" }
	end,
	desc = "Render or show Mermaid source",
})
