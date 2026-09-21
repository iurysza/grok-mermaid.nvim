.PHONY: test bridge-test nvim-test format format-check health

bridge-test:
	node tests/bridge.mjs

nvim-test:
	nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua

test: bridge-test nvim-test

format:
	stylua lua plugin tests

format-check:
	stylua --check lua plugin tests

health:
	nvim --headless --clean -u tests/minimal_init.lua "+lua require('nice_mermaid').setup({ auto_render = false })" "+checkhealth nice_mermaid" "+qa!"
