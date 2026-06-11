local map = vim.keymap.set

map("n", "<leader>X", ":tabclose | bdelete<CR>", { desc = "Close current tab and its buffers" })

map("n", "<leader>B", ":tabnew %<CR>", { desc = "Open current buffer window in new tab" })
map("n", "<leader>T", ":tabnew<CR>", { desc = "Open new tab" })

map("n", "<F4>", ":%bd|e#<CR>", { desc = "Close all buffers except current" })

-- TODO shorcut close all windows except :only the editor ones
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
