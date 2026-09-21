local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>:p"), ":h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root)
