# Contributing

Start with [the knowledge base](ai-artifacts/_index.md). It routes you to the rendering context, runtime architecture, and execution breakdown before you change behaviour.

## Find the code that owns the behaviour

| If you change | Start here | Cover it with |
| --- | --- | --- |
| `:Mermaid` registration or completion | `plugin/nice_mermaid.lua` | A headless Neovim test if command behaviour changes. |
| Options or the bundled bridge path | `lua/nice_mermaid/config.lua` | A headless Neovim test. |
| Fence discovery, preview state, projection, window switching, or cleanup | `lua/nice_mermaid/init.lua` | `tests/run.lua` or a new headless Neovim test. |
| Node input or output | `bridge/render.mjs` | `tests/bridge.mjs`. |
| Runtime diagnostics | `lua/nice_mermaid/health.lua` | `make health` and any matching headless test. |

Keep the Lua side responsible for buffers, windows, and response validation. Keep `bridge/render.mjs` responsible only for JSON input, `grok-mermaid`, and JSON output.

## Set up the project

```sh
npm ci --prefix bridge --omit=dev
make test
```

Use Neovim 0.10 or newer and Node 18 or newer.

## Before you open a pull request

Run these checks:

```sh
make format-check
make test
nvim --headless --clean -u tests/minimal_init.lua '+helptags doc' '+qa!'
```

Keep the plugin independent from a specific plugin manager, Markdown renderer, terminal, or colourscheme. Do not add automatic dependency downloads while Neovim is rendering a buffer.

## Test changes

Add a bridge contract test when changing `bridge/render.mjs`. Add a headless Neovim test when changing Lua behaviour. Test rendered text and extmarks instead of terminal screenshots.

## Releases

[Release Please](https://github.com/googleapis/release-please) runs on every push to `main`. Conventional Commits determine the next version:

- `fix:` creates a patch release.
- `feat:` creates a minor release.
- `feat!:` or a `BREAKING CHANGE:` footer creates a major release.

It opens or updates a release pull request with the version and changelog. Merge that pull request after CI passes to create the Git tag and GitHub Release. Do not create release tags or GitHub Releases by hand.
