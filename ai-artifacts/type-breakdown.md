---
description: Traces nice-mermaid.nvim commands, rendering, projection, cleanup, and failures through concrete functions and tests.
---

# nice-mermaid.nvim execution breakdown

This reference maps the paths that turn a Markdown buffer into a Mermaid preview. Read the [rendering context](./CONTEXT.md) for the meaning of *source buffer*, *preview buffer*, *render request*, and *stale result*. Read the [runtime architecture](./architecture.md) for the boundaries and lifecycle policy.

Lua does not declare static interfaces, so this document records the state tables, function inputs, outputs, side effects, and validation boundaries that the source implements.

## Execution tree

### Run `:Mermaid`

```text
plugin/nice_mermaid.lua
  -> user command callback
  -> require("nice_mermaid").setup()
  -> M.command(command.args)

M.command(action) in lua/nice_mermaid/init.lua
  input:  optional action string
  state:  current Neovim buffer, states, preview_sources
  output: source view, rendered view, or warning

  -> resolve the source buffer when the current buffer is a preview
  -> get_state(source)
  -> show_source() for source or clear
  -> render_buffer() for render
  -> toggle between those paths for toggle or no action
```

`get_state` admits only normal buffers whose filetype appears in `config.get().filetypes`. It rejects preview buffers and special buffers. A newly eligible source starts in `rendered` mode with generation `0`.

`M.command` calls `M.setup()` first. A first command therefore applies defaults and registers the autocmds. An unknown action warns instead of changing a buffer.

### Render automatically

```text
M.setup(user_options)
  -> config.setup(user_options)
  -> FileType autocmd for configured filetypes
  -> BufWinEnter autocmd
  -> WinResized autocmd
  -> BufWipeout autocmd

FileType or BufWinEnter
  -> auto_render(buffer)
  -> vim.schedule(...)
  -> get_state(buffer)
  -> render_buffer(buffer, state)
```

`auto_render` waits until the triggering autocmd completes before switching a window's buffer. `WinResized` only revisits source states whose preview is visible. A changed width can reproject accepted content without starting a new Node process.

## Parse and project a source buffer

```text
render_buffer(source, state)
  -> document_blocks(source)
  -> complete Mermaid fences + prose metadata
  -> source strings for every fence
  -> Node bridge request
  -> decode_diagrams(result, fence count)
  -> layout_preview(source, state, width)
      -> project(source lines, blocks, diagrams, prose, width)
      -> update_preview(source, state, projection)
      -> switch_windows(source, preview, source-to-preview map)
```

`document_blocks` asks Neovim for the Markdown Tree-sitter parser. It accepts a fenced block only when it has an opening delimiter, Mermaid info string, content node, and closing delimiter. The first info-string word must be `mermaid`, ignoring case. Incomplete fences remain source text.

The function also records paragraph ranges and inline literal ranges. `wrap_prose` uses that metadata to wrap ordinary paragraph text for the narrowest visible window without splitting inline code, links, images, HTML tags, or autolinks. It leaves multiline inline constructs unchanged.

`project` has two paths for each Mermaid fence:

- A `false` diagram result copies the original fence into the preview.
- A styled diagram result replaces the fence with indented Unicode rows, adds highlight extmarks, and records source-to-preview and preview-to-source rows.

The function adds blank separators around rendered diagrams when needed. It never writes into the source buffer.

## Cross the Node bridge

```text
Lua source strings
  -> vim.json.encode(sources)
  -> vim.system({ node, bridge }, { stdin = JSON, text = true })
  -> bridge/render.mjs reads all stdin
  -> JSON.parse(input)
  -> grok-mermaid render(source) for each item
  -> JSON.stringify(styled rows or false)
  -> Lua decode_diagrams()
```

`render_buffer` sends every complete Mermaid fence from one source buffer in one request. It captures the source's `changedtick`, source lines, and a new `generation` before starting `vim.system`.

`bridge/render.mjs` accepts only a JSON array of strings. It returns one item per string. A rendered item is `art.styled`. A `null` renderer result becomes `false`. The bridge writes errors to standard error and exits nonzero when JSON parsing, request validation, or rendering throws.

`decode_diagrams` treats the Node output as untrusted. It accepts the response only when the process succeeds, JSON decodes to a list with the expected number of items, every rendered diagram has at least one row, and every span has string `text` and `cls` fields without a carriage return or newline. A malformed rendered item rejects the complete batch.

The Node bridge has no persistent state. Each render request starts a process, receives a complete batch response, and exits.

## Maintain preview state and clean up

A source state in `states[source_buffer]` can contain these values:

| Value | Meaning |
| --- | --- |
| `view` | `source` or `rendered`. |
| `generation` | Monotonic guard for render requests and source switches. |
| `pending_tick` | The source revision that has an active request. |
| `tick` | The source revision used by the accepted preview. |
| `content` | Accepted source lines, Mermaid blocks, diagram results, and prose metadata. |
| `width` | The width used for the accepted projection. |
| `preview` | The scratch preview buffer, if it exists. |
| `to_source`, `to_preview` | Row maps used by window switching and re-layout. |

`update_preview` creates a scratch buffer only after the plugin accepts a result. The buffer is unlisted, read-only, non-modifiable, hidden on close, has no swapfile or modeline, and uses the `mermaid-preview` filetype. The source buffer keeps its text and modified state.

`switch_windows` updates every window that displays the buffer being replaced. It maps cursor and top lines, clears horizontal offsets, uses `:hide` to preserve unsaved source edits, then clamps the destination cursor column.

`BufWipeout` owns cleanup. When a preview buffer disappears, the plugin removes the reverse mapping and leaves its source in source mode. When a source buffer disappears, the plugin clears its state and schedules deletion of the associated preview.

## Guard asynchronous results

```text
start render
  -> state.generation += 1
  -> state.pending_tick = source changedtick
  -> Node callback
  -> vim.schedule(callback)
  -> accept only when state, generation, mode, source load state, and changedtick still match
```

A matching accepted `tick` and valid preview skips Node rendering. If the width changed, `layout_preview` projects the stored content again before switching windows.

A callback becomes stale if another render started, the user switched to source, the source changed, the source unloaded, or the state table no longer belongs to the source buffer. The scheduled callback returns without modifying buffers. The plugin does not cancel the Node process.

## Failure flow

```text
missing Markdown parser
  -> document_blocks() returns an error
  -> render_buffer() warns
  -> source or existing preview remains

no complete Mermaid fence
  -> show_source()

vim.system cannot start Node
  -> pcall() fails
  -> pending_tick clears
  -> warning

Node exits nonzero or returns malformed JSON
  -> decode_diagrams() rejects the batch
  -> warning
  -> accepted preview remains unchanged

one renderer result is false
  -> project() copies only that source fence
  -> other valid diagrams still render

callback is stale
  -> scheduled callback returns
  -> no warning and no buffer change
```

The health check has a separate diagnostic path. `lua/nice_mermaid/health.lua` checks Neovim, the configured Node executable, bridge path, `grok-mermaid` import, and the Markdown Tree-sitter parser. It does not render a buffer.

## Tests

| Test command | Evidence |
| --- | --- |
| `node tests/bridge.mjs` | The bridge emits one rendered diagram and one `false` item, then rejects a non-array request. |
| `nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua` | A valid fence opens a read-only preview, source text remains unchanged, an unsupported fence remains visible, and invalid options fail. |
| `make test` | Runs both test commands. |
| `make format-check` | Checks Lua formatting with Stylua. |
| `make health` | Runs `:checkhealth nice_mermaid` in a headless Neovim process. |

## Change map

| Change | Primary owner | Also inspect |
| --- | --- | --- |
| `:Mermaid` actions or completion | `plugin/nice_mermaid.lua` and `M.command` | `doc/nice-mermaid.txt`, `tests/run.lua` |
| Defaults, option validation, or bridge selection | `lua/nice_mermaid/config.lua` | `README.md`, `doc/nice-mermaid.txt`, `lua/nice_mermaid/health.lua` |
| Fence discovery, response validation, preview layout, window switching, or cleanup | `lua/nice_mermaid/init.lua` | `tests/run.lua`, `ai-artifacts/architecture.md` |
| Bridge request or response JSON | `bridge/render.mjs` | `tests/bridge.mjs`, `lua/nice_mermaid/init.lua` |
| `grok-mermaid` version | `bridge/package.json` and `bridge/package-lock.json` | `tests/bridge.mjs`, README requirements |
| Lazy.nvim installation | `lazy.lua` | README and help setup examples |
| Headless Neovim test runtime | `tests/minimal_init.lua` | `Makefile` |
| Validation and release automation | `.github/workflows/` and release configuration | Keep runtime documentation separate from release policy |

The current tests do not cover multiple windows, stale callbacks, wrapping, cursor maps, resize reuse, buffer cleanup, health failures, or the optional `render-markdown.nvim` integration. Preserve these gaps as known behaviour until a test covers them.
