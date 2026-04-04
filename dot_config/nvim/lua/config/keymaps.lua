-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Git blame current line
vim.keymap.set("n", "<leader>gb", "<cmd>Gitsigns blame_line<cr>", { desc = "Blame line" })

-- Show full blame in floating window
vim.keymap.set("n", "<leader>gB", function()
  require("gitsigns").blame_line({ full = true })
end, { desc = "Blame line (full)" })

-- Toggle inline blame for all lines
vim.keymap.set("n", "<leader>gtb", "<cmd>Gitsigns toggle_current_line_blame<cr>", { desc = "Toggle line blame" })
