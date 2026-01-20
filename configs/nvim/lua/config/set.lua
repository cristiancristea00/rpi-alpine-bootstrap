-- Disable cursor style changes
vim.opt.guicursor = ""

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Indentation settings
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.autoindent = true

-- Line wrapping
vim.opt.wrap = false
vim.opt.linebreak = true  -- Wrap at word boundaries if wrap is enabled

-- Search settings
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true  -- Case sensitive if search contains uppercase

-- Colors
vim.opt.termguicolors = true

-- Scrolling
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Performance
vim.opt.updatetime = 50
vim.opt.timeoutlen = 300

-- Visual guides
vim.opt.colorcolumn = "80"
vim.opt.cursorline = true  -- Highlight current line

-- Split behavior
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Better command line completion
vim.opt.wildmode = "longest:full,full"
vim.opt.completeopt = "menuone,noselect"

-- Set leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "
