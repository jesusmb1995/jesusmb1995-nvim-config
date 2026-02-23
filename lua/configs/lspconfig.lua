-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

-- EXAMPLE
local servers = {
  "html",
  "cssls",
  "clangd",        -- C/C++
  "rust_analyzer", -- Rust
  "pyright",       -- Python
  "yamlls",        -- YAML
  "jsonls",        -- JSON
  "marksman",      -- Markdown
  "ts_ls",         -- Javascript and Typescript
  "cmake",
  "taplo",         -- Toml (Rust)
  "bashls",        -- Bash
  "dockerls",

  -- Below to be installed by hand on :Mason. Go to line and do "i" key to install.

  -- linters
  --"cpplint",
  --"pylint",
  --"yamllint",
  --"biomejs"
  --"standardjs"
  --"shellcheck"

  -- formatters
  --"clang-format", -- C/C++ (but also java and js)
  --"rustfmt",
  --"black", -- python
  --"yamlfmt",
  --"prettier"
  --"cmakelang"
  --"beautysh"
}
local nvlsp = require "nvchad.configs.lspconfig"

local function with_defaults(opts)
  return vim.tbl_deep_extend("force", {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }, opts or {})
end

-- Use vim.lsp.config (Neovim 0.11+). Do not require("lspconfig") to avoid deprecation.
vim.lsp.config("jinja_lsp", with_defaults {
  filetypes = { "jinja", "njk" }, -- Add support for .njk files
})
vim.lsp.enable "jinja_lsp"

for _, lsp in ipairs(servers) do
  vim.lsp.config(lsp, with_defaults())
  vim.lsp.enable(lsp)
end

-- configuring single server, example: typescript
-- lspconfig.ts_ls.setup {
--   on_attach = nvlsp.on_attach,
--   on_init = nvlsp.on_init,
--   capabilities = nvlsp.capabilities,
-- }
