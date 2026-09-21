local function test(name, callback)
	local ok, error_message = xpcall(callback, debug.traceback)
	if not ok then
		error(name .. ":\n" .. error_message)
	end
	print("PASS " .. name)
end

local plugin = require("nice_mermaid")

local function reset_buffer(lines)
	local buffer = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buffer)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
	vim.bo[buffer].filetype = "markdown"
	return buffer
end

test("renders a Mermaid block in a read-only preview", function()
	local source = reset_buffer({
		"# Diagram",
		"",
		"```mermaid",
		"flowchart LR",
		"  A[Start] --> B[Finish]",
		"```",
	})
	plugin.setup({ auto_render = false })
	plugin.command("render")
	assert(
		vim.wait(5000, function()
			return vim.bo.filetype == "mermaid-preview"
		end),
		"rendered preview did not open"
	)
	local preview = vim.api.nvim_get_current_buf()
	local text = table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), "\n")
	assert(text:find("Start", 1, true), "diagram label is missing")
	assert(not text:find("```", 1, true), "Mermaid source leaked into preview")
	assert(vim.bo[preview].readonly and not vim.bo[preview].modifiable, "preview is editable")

	plugin.command("source")
	assert(vim.api.nvim_get_current_buf() == source, "source buffer did not return")
	assert(vim.api.nvim_buf_get_lines(source, 3, 4, false)[1] == "flowchart LR", "source changed")
end)

test("leaves unsupported Mermaid as source", function()
	reset_buffer({ "```mermaid", "invalid diagram", "```" })
	plugin.command("render")
	assert(
		vim.wait(5000, function()
			return vim.bo.filetype == "mermaid-preview"
		end),
		"preview did not open"
	)
	local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	assert(text:find("invalid diagram", 1, true), "unsupported source was removed")
end)

test("rejects invalid options", function()
	local ok = pcall(plugin.setup, { auto_render = "yes" })
	assert(not ok, "invalid options were accepted")
end)

vim.cmd("qa!")
