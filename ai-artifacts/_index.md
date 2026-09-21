---
description: Start here to understand nice-mermaid.nvim's terms, runtime boundaries, execution flow, and test seams.
---

# nice-mermaid.nvim knowledge base

`nice-mermaid.nvim` replaces supported Mermaid fences in an editable Markdown buffer with Unicode terminal art in a separate, read-only preview. The source buffer remains authoritative.

Start with the [rendering context](./CONTEXT.md) when terms such as *source buffer*, *preview buffer*, *render request*, or *stale result* are unclear. Those definitions give the [runtime architecture](./architecture.md) and [execution breakdown](./type-breakdown.md) one shared vocabulary.

Read the [runtime architecture](./architecture.md) to decide where a change belongs. It explains the Neovim, Node, and `grok-mermaid` boundaries, source and preview lifecycle, and failure policy.

Read the [execution breakdown](./type-breakdown.md) before changing a runtime path. It traces `:Mermaid`, automatic rendering, bridge I/O, projection, cleanup, and failure handling through the concrete functions and tests.

## Suggested routes

To change what counts as a Mermaid fence or how Markdown becomes preview text, start with [fence and preview language](./CONTEXT.md#language), then follow [source parsing and projection](./type-breakdown.md#parse-and-project-a-source-buffer).

To change bridge JSON, `grok-mermaid`, or Node failures, start with [bridge and renderer language](./CONTEXT.md#language), then read the [bridge request and response](./type-breakdown.md#cross-the-node-bridge) and its [failure flow](./type-breakdown.md#failure-flow).

To change buffer switching, resizing, or cleanup, read the [source and preview lifecycle](./architecture.md#source-and-preview-buffers) beside the [state and cleanup flow](./type-breakdown.md#maintain-preview-state-and-clean-up).

To change a command, option, health check, package dependency, or test command, use the [change map](./type-breakdown.md#change-map).
