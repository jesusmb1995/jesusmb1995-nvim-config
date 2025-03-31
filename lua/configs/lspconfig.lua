-- load defaults i.e lua_lsp
require("nvchad.configs.lspconfig").defaults()

local lspconfig = require "lspconfig"

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
  "taplo", -- Toml (Rust)
  "bashls", -- Bash 

  -- Below to be installed by hand on :Mason. Go to line and do "i" key to install.

  -- linters
  --"cpplint",
  --"pylint",
  --"yamllint",
  --"biomejs"
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

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

-- configuring single server, example: typescript
-- lspconfig.ts_ls.setup {
--   on_attach = nvlsp.on_attach,
--   on_init = nvlsp.on_init,
--   capabilities = nvlsp.capabilities,
-- }
