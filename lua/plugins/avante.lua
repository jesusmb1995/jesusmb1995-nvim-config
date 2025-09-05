local OPENROUTER_BASE = {
  __inherited_from = "openai",
  api_key_name = "OPENROUTER_API_KEY",
  endpoint = "https://openrouter.ai/api/v1",
}
function add_openrouter(new_model)
  return vim.tbl_extend("force", {}, OPENROUTER_BASE, { model = new_model })
end

local function get_config()
  if vim.env.AI_REMOTE == nil then
    return {
      -- add any opts here
      -- for example
      provider = "openai",
      -- openai = { -- Kobalt api proxy
      --   endpoint = "http://127.0.0.1:8001/v1",
      --   model = "Qwen2.5-Coder-32B-Instruct",
      --   disable_tools = true,
      --   max_tokens = 4096,
      --   timeout = 300,
      -- },
    }
  end
  return {
    -- add any opts here
    -- for example
    provider = "openrouter",
    -- openai = {
    --   endpoint = "https://api.openai.com/v1",
    --   model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
    --   timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
    --   temperature = 0,
    --   max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
    --   --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
    --   disable_tools = true, -- R1 needs it disabled
    -- },
    vendors = {
      -- use <leader> a? to change model
      -- Best free model for now is R1 for coding: https://openrouter.ai/rankings/programming?view=month
      -- However V3 is faster
      -- For coding grok3 > deepseek-r1 > deepseek-v3 ... may others
      -- No API tools for g3 dsr1 yet (free)
      openrouter = add_openrouter "deepseek/deepseek-r1:free",
      openrouter_v3 = add_openrouter "deepseek/deepseek-chat:free",
      openrouter_v3_0324 = add_openrouter "deepseek/deepseek-chat:free",
      openrouter_gemini = add_openrouter "google/gemini-2.5-pro-exp-03-25:free",
      openrouter_qwen_coder = add_openrouter "qwen/qwen-2.5-coder-32b-instruct:free",
    },
  }
end

return {
  "yetone/avante.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  event = "VeryLazy",
  version = false, -- Never set this value to "*"! Never!
  opts = get_config(),
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  build = "make",
  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below dependencies are optional,
    "echasnovski/mini.pick", -- for file_selector provider mini.pick
    "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
    "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
    "ibhagwan/fzf-lua", -- for file_selector provider fzf
    "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
    "zbirenbaum/copilot.lua", -- for providers='copilot'
    {
      -- support for image pasting
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      "MeanderingProgrammer/render-markdown.nvim",
      opts = {
        file_types = { "markdown", "Avante" },
      },
      ft = { "markdown", "Avante" },
    },
  },
}
