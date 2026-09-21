local M = {}

function M.check()
	local health = vim.health
	health.start("nice-mermaid.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim " .. vim.version().major .. "." .. vim.version().minor)
	else
		health.error("Neovim 0.10 or newer is required")
	end

	local options = require("nice_mermaid").health()
	if vim.fn.executable(options.node) == 1 then
		local result = vim.system({ options.node, "--version" }, { text = true }):wait()
		if result.code == 0 then
			health.ok("Node " .. vim.trim(result.stdout))
		else
			health.error("Node is installed but cannot run", { vim.trim(result.stderr) })
		end
	else
		health.error("Node was not found", { "Install Node 18 or newer, or set opts.node." })
	end

	if vim.uv.fs_stat(options.bridge) then
		health.ok("Bridge found at " .. options.bridge)
	else
		health.error("Bridge was not found", { "Set opts.bridge or reinstall the plugin." })
	end

	local package_result = vim
		.system({ options.node, "--input-type=module", "--eval", 'import("grok-mermaid")' }, {
			cwd = vim.fs.dirname(options.bridge),
			text = true,
		})
		:wait()
	if package_result.code == 0 then
		health.ok("grok-mermaid is installed")
	else
		health.error("grok-mermaid is not installed", {
			"Run npm ci --omit=dev in the plugin's bridge directory.",
			vim.trim(package_result.stderr),
		})
	end

	if pcall(vim.treesitter.language.add, "markdown") then
		health.ok("Markdown Tree-sitter parser found")
	else
		health.warn("Markdown Tree-sitter parser was not found", { "Run :TSInstall markdown." })
	end
end

return M
