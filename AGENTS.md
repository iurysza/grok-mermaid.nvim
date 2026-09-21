# AGENTS.md

Map for coding agents working on `nice-mermaid.nvim`.

## Purpose

Neovim plugin that renders Mermaid fences as Unicode terminal art in a read-only Markdown preview. `:Mermaid` toggles source and preview. The source buffer stays authoritative, including unsaved edits.

## ai-artifacts

Docs live under `ai-artifacts/`. Start at [`ai-artifacts/_index.md`](ai-artifacts/_index.md). Point; do not paste those docs here.

| File | Use it for |
| --- | --- |
| [`ai-artifacts/_index.md`](ai-artifacts/_index.md) | Entry point and suggested routes |
| [`ai-artifacts/CONTEXT.md`](ai-artifacts/CONTEXT.md) | Terms: source buffer, preview, render request, stale result |
| [`ai-artifacts/architecture.md`](ai-artifacts/architecture.md) | Neovim / Node / `grok-mermaid` boundaries and lifecycle |
| [`ai-artifacts/type-breakdown.md`](ai-artifacts/type-breakdown.md) | Function-level flows and the change map |

Keep `ai-artifacts/` current when how the project works changes (boundaries, commands, render path, tests). Update the matching page; do not dump architecture into this file.

Code ownership (details in the change map):

| Change | Start here |
| --- | --- |
| `:Mermaid` | `plugin/nice_mermaid.lua` |
| Options / bridge path | `lua/nice_mermaid/config.lua` |
| Fences, preview, windows, cleanup | `lua/nice_mermaid/init.lua` |
| Bridge JSON / `grok-mermaid` | `bridge/render.mjs` |
| Health | `lua/nice_mermaid/health.lua` |

## Closed loop

1. Research: `ai-artifacts/_index.md` → README.md → CONTRIBUTING.md.
2. Change the owning file from the map above. Lua owns buffers, windows, and response validation. `bridge/render.mjs` owns JSON in/out and `grok-mermaid` only.
3. `make format-check` (or `make format` first).
4. `make test`.
5. `make health`.
6. If behaviour, boundaries, or test seams changed, update the matching `ai-artifacts/` page.

Do not download packages while rendering. Do not couple the plugin to a specific plugin manager, Markdown renderer, terminal, or colourscheme.

## Commands

Requirements: Neovim 0.10+, Node 18+, Stylua (CI pins `2.1.0`).

```sh
npm ci --omit=dev          # run in bridge/
make format                # stylua lua plugin tests
make format-check
make test                  # bridge-test + nvim-test
make bridge-test           # node tests/bridge.mjs
make nvim-test             # nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua
make health                # :checkhealth nice_mermaid
```

`npm ci --prefix bridge --omit=dev` is the same install from the repo root.

Before a PR, also generate help tags (CI does this):

```sh
nvim --headless --clean -u NONE "+helptags doc" "+qa!"
```

Add a bridge contract test when changing `bridge/render.mjs`. Add a headless Neovim test when changing Lua behaviour. Assert rendered text and extmarks, not screenshots.

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on `main` and pull requests, matrix Neovim `v0.10.4`/`stable` × Node `18`/`22`:

1. `npm ci --omit=dev` in `bridge/`
2. `make format-check`
3. `make test`
4. `nvim --headless --clean -u NONE "+helptags doc" "+qa!"`

Match those targets locally before pushing.

[`.github/workflows/release-please.yml`](.github/workflows/release-please.yml) versions `main` from Conventional Commits (`fix:`, `feat:`, `feat!:` / `BREAKING CHANGE:`). Do not create release tags or GitHub Releases by hand. See CONTRIBUTING.md.

## Git commits

Never include Cursor (or any Cursor agent/bot) as git author, committer, or `Co-authored-by` / similar trailer.
