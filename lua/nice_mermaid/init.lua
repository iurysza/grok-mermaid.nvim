local config = require("nice_mermaid.config")

local M = {}

local namespace = vim.api.nvim_create_namespace("nice-mermaid")

local states = {}
local preview_sources = {}
local highlights = {
	border = "Comment",
	text = "Normal",
	edge = "Special",
	edgeLabel = "Comment",
	title = "Title",
	none = "Normal",
}

local function notify(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Mermaid" })
end

local function document_blocks(buffer)
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, "markdown")
	if not ok then
		return nil, "The Markdown Tree-sitter parser is required for :Mermaid"
	end

	local blocks, prose = {}, {}
	local function visit(node)
		if node:type() == "paragraph" then
			local first, column, last, end_column = node:range()
			for row = first + 1, last + (end_column > 0 and 1 or 0) do
				prose[row] = { column = row == first + 1 and column or nil, protected = {} }
			end
		elseif node:type() == "fenced_code_block" then
			local info, content, opening, closing
			for child in node:iter_children() do
				if child:type() == "info_string" then
					info = vim.treesitter.get_node_text(child, buffer)
				elseif child:type() == "code_fence_content" then
					content = vim.treesitter.get_node_text(child, buffer)
				elseif child:type() == "fenced_code_block_delimiter" then
					if opening then
						closing = child
					else
						opening = child
					end
				end
			end
			local language = info and info:match("^%s*(%S+)")
			-- Incomplete fences remain source text rather than losing their last line.
			if language and language:lower() == "mermaid" and closing and content then
				table.insert(blocks, {
					first = opening:range() + 1,
					last = closing:range() + 1,
					source = content,
				})
			end
			return
		end
		for child in node:iter_children() do
			visit(child)
		end
	end
	for _, tree in ipairs(parser:parse(true)) do
		visit(tree:root())
	end
	local literal = {
		code_span = true,
		inline_link = true,
		full_reference_link = true,
		image = true,
		html_tag = true,
		uri_autolink = true,
		email_autolink = true,
	}
	local function protect(node)
		if literal[node:type()] then
			local first, column, last, end_column = node:range()
			if first == last and prose[first + 1] then
				table.insert(prose[first + 1].protected, { first = column + 1, last = end_column })
			elseif first ~= last then
				-- Keep existing multiline inline constructs intact.
				for row = first + 1, last + 1 do
					prose[row] = nil
				end
			end
			return
		end
		for child in node:iter_children() do
			protect(child)
		end
	end
	parser:for_each_tree(function(tree, language)
		if language:lang() == "markdown_inline" then
			protect(tree:root())
		end
	end)
	table.sort(blocks, function(a, b)
		return a.first < b.first
	end)
	return { diagrams = blocks, prose = prose }
end

local function decode_diagrams(result, count)
	if result.code ~= 0 then
		return nil, "Renderer failed: " .. (result.stderr or "")
	end
	local ok, diagrams = pcall(vim.json.decode, result.stdout)
	if not ok or type(diagrams) ~= "table" or not vim.islist(diagrams) or #diagrams ~= count then
		return nil, "Renderer returned an invalid response"
	end
	for _, diagram in ipairs(diagrams) do
		if diagram ~= false then
			if type(diagram) ~= "table" or not vim.islist(diagram) or #diagram == 0 then
				return nil, "Renderer returned an invalid diagram"
			end
			for _, row in ipairs(diagram) do
				if type(row) ~= "table" or not vim.islist(row) then
					return nil, "Renderer returned an invalid diagram row"
				end
				for _, span in ipairs(row) do
					if
						type(span) ~= "table"
						or type(span.text) ~= "string"
						or type(span.cls) ~= "string"
						or span.text:find("[\r\n]")
					then
						return nil, "Renderer returned an invalid diagram span"
					end
				end
			end
		end
	end
	return diagrams
end

local function wrap_prose(line, paragraph, width)
	if not paragraph or vim.fn.strdisplaywidth(line) <= width then
		return { line }
	end
	local column = paragraph.column or #(line:match("^[%s>]*") or "")
	local prefix = line:sub(1, column)
	local continuation = prefix:gsub("[^%s>]", " ")
	local lines, current, gap, has_word = {}, prefix, "", false
	local function append(word)
		if word == "" then
			return
		end
		local candidate = current .. gap .. word
		-- Do not turn a word inside prose into a new heading, list, or quote.
		local block_marker = word:match("^[#>*+%-]+$") or word:match("^%d+[.)]$")
		if has_word and not block_marker and vim.fn.strdisplaywidth(candidate) > width then
			table.insert(lines, current)
			current = continuation .. word
		else
			current = candidate
		end
		has_word = true
	end
	local start = column + 1
	for first, spaces, after in line:gmatch("()([ \t]+)()") do
		if first >= start then
			local protected = false
			for _, span in ipairs(paragraph.protected) do
				if first >= span.first and first <= span.last then
					protected = true
					break
				end
			end
			if not protected then
				append(line:sub(start, first - 1))
				gap, start = spaces, after
			end
		end
	end
	if start <= #line then
		append(line:sub(start))
	else
		current = current .. gap -- Preserve Markdown's trailing-space hard breaks.
	end
	table.insert(lines, current)
	return lines
end

-- The preview contains real text rows, not decorations on hidden source rows.
-- Both row maps keep :Mermaid near the same content when switching views.
local function project(source_lines, blocks, diagrams, prose, width)
	local result = { lines = {}, marks = {}, to_source = {}, to_preview = {} }
	local source_row = 1
	local function copy_line()
		result.to_preview[source_row] = #result.lines + 1
		for _, line in ipairs(wrap_prose(source_lines[source_row], prose[source_row], width)) do
			table.insert(result.lines, line)
			result.to_source[#result.lines] = source_row
		end
		source_row = source_row + 1
	end

	for index, block in ipairs(blocks) do
		while source_row < block.first do
			copy_line()
		end
		if diagrams[index] == false then
			while source_row <= block.last do
				copy_line()
			end
		else
			-- Indented code keeps labels literal without adding visible code fences.
			-- Blank separators keep adjacent prose out of the diagram's code block.
			if #result.lines > 0 and result.lines[#result.lines]:find("%S") then
				table.insert(result.lines, "")
				result.to_source[#result.lines] = block.first
			end
			local preview_row = #result.lines + 1
			for _, row in ipairs(diagrams[index]) do
				local text, column = { "    " }, 4
				for _, span in ipairs(row) do
					table.insert(text, span.text)
					table.insert(result.marks, {
						row = #result.lines,
						first = column,
						last = column + #span.text,
						group = highlights[span.cls] or "Normal",
					})
					column = column + #span.text
				end
				table.insert(result.lines, table.concat(text))
				result.to_source[#result.lines] = block.first
			end
			while source_row <= block.last do
				result.to_preview[source_row] = preview_row
				source_row = source_row + 1
			end
			if source_lines[source_row] and source_lines[source_row]:find("%S") then
				table.insert(result.lines, "")
				result.to_source[#result.lines] = block.last
			end
		end
	end
	while source_row <= #source_lines do
		copy_line()
	end
	return result
end

local function switch_windows(from, to, rows)
	for _, window in ipairs(vim.fn.win_findbuf(from)) do
		vim.api.nvim_win_call(window, function()
			local view = vim.fn.winsaveview()
			view.lnum = rows[view.lnum] or 1
			view.topline = rows[view.topline] or 1
			view.topfill, view.skipcol, view.leftcol = 0, 0, 0
			-- :hide preserves unsaved edits even when the user's 'hidden' is off.
			vim.cmd("keepalt keepjumps hide buffer " .. to)
			local line = vim.api.nvim_buf_get_lines(to, view.lnum - 1, view.lnum, false)[1] or ""
			view.col = math.min(view.col, #line)
			vim.fn.winrestview(view)
		end)
	end
	if preview_sources[to] then
		local ok, markdown = pcall(require, "render-markdown")
		if ok then
			markdown.render({ buf = to })
		end
	end
end

local function show_source(buffer, state)
	state.view = "source"
	state.generation = state.generation + 1
	state.pending_tick = nil
	if state.preview and vim.api.nvim_buf_is_valid(state.preview) then
		switch_windows(state.preview, buffer, state.to_source)
	end
end

local function update_preview(buffer, state, projection)
	if not state.preview or not vim.api.nvim_buf_is_valid(state.preview) then
		local preview = vim.api.nvim_create_buf(false, true)
		state.preview = preview
		preview_sources[preview] = buffer
		vim.api.nvim_buf_set_name(
			preview,
			"mermaid://" .. buffer .. "/" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buffer), ":t")
		)
		vim.bo[preview].bufhidden = "hide"
		vim.bo[preview].swapfile = false
		vim.bo[preview].modeline = false
	end

	local preview = state.preview
	vim.bo[preview].readonly = false
	vim.bo[preview].modifiable = true
	vim.api.nvim_buf_set_lines(preview, 0, -1, false, projection.lines)
	vim.api.nvim_buf_clear_namespace(preview, namespace, 0, -1)
	for _, mark in ipairs(projection.marks) do
		if mark.last > mark.first then
			vim.api.nvim_buf_set_extmark(preview, namespace, mark.row, mark.first, {
				end_col = mark.last,
				hl_group = mark.group,
				priority = 200,
			})
		end
	end
	vim.bo[preview].modified = false
	vim.bo[preview].modifiable = false
	vim.bo[preview].readonly = true
	if vim.bo[preview].filetype ~= "mermaid-preview" then
		vim.bo[preview].filetype = "mermaid-preview"
		vim.treesitter.start(preview, "markdown")
	end
	state.to_source, state.to_preview = projection.to_source, projection.to_preview
end

local function preview_width(buffer, state)
	local windows = vim.fn.win_findbuf(buffer)
	if state.preview then
		vim.list_extend(windows, vim.fn.win_findbuf(state.preview))
	end
	local width
	for _, window in ipairs(windows) do
		local info = vim.fn.getwininfo(window)[1]
		local available = math.max(1, info.width - info.textoff)
		width = width and math.min(width, available) or available
	end
	return width or vim.api.nvim_win_get_width(0)
end

local function layout_preview(buffer, state, width)
	local views = {}
	if state.preview then
		for _, window in ipairs(vim.fn.win_findbuf(state.preview)) do
			local view = vim.api.nvim_win_call(window, vim.fn.winsaveview)
			view.lnum = state.to_source[view.lnum] or 1
			view.topline = state.to_source[view.topline] or 1
			views[window] = view
		end
	end
	local content = state.content
	update_preview(buffer, state, project(content.lines, content.blocks, content.diagrams, content.prose, width))
	state.width = width
	for window, view in pairs(views) do
		view.lnum = state.to_preview[view.lnum] or 1
		view.topline = state.to_preview[view.topline] or 1
		view.col, view.topfill, view.skipcol, view.leftcol = 0, 0, 0, 0
		vim.api.nvim_win_call(window, function()
			vim.fn.winrestview(view)
		end)
	end
end

local function render_buffer(buffer, state)
	if not vim.api.nvim_buf_is_loaded(buffer) or state.view ~= "rendered" then
		return
	end
	local tick = vim.api.nvim_buf_get_changedtick(buffer)
	if state.tick == tick and state.preview and vim.api.nvim_buf_is_valid(state.preview) then
		local width = preview_width(buffer, state)
		if state.width ~= width then
			layout_preview(buffer, state, width)
		end
		switch_windows(buffer, state.preview, state.to_preview)
		return
	end
	if state.pending_tick == tick then
		return
	end

	local document, error_message = document_blocks(buffer)
	if not document then
		notify(error_message)
		return
	end
	local blocks = document.diagrams
	if #blocks == 0 then
		show_source(buffer, state)
		return
	end

	local sources = {}
	for _, block in ipairs(blocks) do
		table.insert(sources, block.source)
	end
	local source_lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
	state.generation = state.generation + 1
	state.pending_tick = tick
	local generation = state.generation
	local ok, spawn_error = pcall(
		vim.system,
		{ config.get().node, config.get().bridge },
		{ text = true, stdin = vim.json.encode(sources) },
		function(result)
			vim.schedule(function()
				if states[buffer] ~= state or state.generation ~= generation then
					return
				end
				state.pending_tick = nil
				if
					not vim.api.nvim_buf_is_loaded(buffer)
					or state.view ~= "rendered"
					or vim.api.nvim_buf_get_changedtick(buffer) ~= tick
				then
					return
				end
				local diagrams, error = decode_diagrams(result, #blocks)
				if not diagrams then
					notify(error)
					return
				end
				state.content = { lines = source_lines, blocks = blocks, diagrams = diagrams, prose = document.prose }
				layout_preview(buffer, state, preview_width(buffer, state))
				state.tick = tick
				switch_windows(buffer, state.preview, state.to_preview)
			end)
		end
	)
	if not ok then
		state.pending_tick = nil
		notify("Cannot start Node renderer: " .. tostring(spawn_error))
	end
end

local function get_state(buffer)
	if
		preview_sources[buffer]
		or not vim.tbl_contains(config.get().filetypes, vim.bo[buffer].filetype)
		or vim.bo[buffer].buftype ~= ""
	then
		return nil
	end
	if not states[buffer] then
		states[buffer] = { view = "rendered", generation = 0 }
	end
	return states[buffer]
end

local function auto_render(buffer)
	-- FileType and BufWinEnter must finish before switching their window's buffer.
	vim.schedule(function()
		if not vim.api.nvim_buf_is_loaded(buffer) then
			return
		end
		local state = get_state(buffer)
		if state and state.view == "rendered" and #vim.fn.win_findbuf(buffer) > 0 then
			render_buffer(buffer, state)
		end
	end)
end

local configured = false

function M.setup(user_options)
	if configured and user_options == nil then
		return
	end
	config.setup(user_options)
	configured = true
	vim.treesitter.language.register("markdown", "mermaid-preview")
	local group = vim.api.nvim_create_augroup("GrokMermaid", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = config.get().filetypes,
		callback = function(event)
			if config.get().auto_render then
				auto_render(event.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(event)
			if preview_sources[event.buf] then
				vim.wo.wrap = false
				vim.wo.foldenable = false
				local source = preview_sources[event.buf]
				vim.schedule(function()
					if states[source] then
						render_buffer(source, states[source])
					end
				end)
			elseif config.get().auto_render then
				auto_render(event.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			vim.schedule(function()
				for buffer, state in pairs(states) do
					if state.preview and #vim.fn.win_findbuf(state.preview) > 0 then
						render_buffer(buffer, state)
					end
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			local source = preview_sources[event.buf]
			if source then
				preview_sources[event.buf] = nil
				if states[source] then
					states[source].preview = nil
					states[source].view = "source"
				end
			elseif states[event.buf] then
				local preview = states[event.buf].preview
				states[event.buf] = nil
				if preview then
					preview_sources[preview] = nil
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(preview) then
							vim.api.nvim_buf_delete(preview, { force = true })
						end
					end)
				end
			end
		end,
	})

	if config.get().auto_render then
		for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
			auto_render(buffer)
		end
	end
end

function M.command(action)
	M.setup()
	local current = vim.api.nvim_get_current_buf()
	local buffer = preview_sources[current] or current
	local state = get_state(buffer)
	if not state then
		notify(":Mermaid only works in configured Markdown buffers")
		return
	end
	action = action == "" and "toggle" or action
	if action == "source" or action == "clear" then
		show_source(buffer, state)
	elseif action == "render" then
		state.tick = nil
		state.view = "rendered"
		render_buffer(buffer, state)
	elseif action == "toggle" then
		if preview_sources[current] or state.pending_tick then
			show_source(buffer, state)
		else
			state.view = "rendered"
			render_buffer(buffer, state)
		end
	else
		notify("Unknown :Mermaid action: " .. action)
	end
end

function M.health()
	return config.get()
end

return M
