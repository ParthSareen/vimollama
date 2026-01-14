# ollama-vim

A Neovim plugin for AI-assisted code editing using [Ollama](https://ollama.ai). Cursor-style `cmd+k` experience in your terminal.

## Features

- **Edit Mode** (`<leader>k`): Select code, describe changes, preview diff, apply
- **Chat Mode** (`<leader>c`): Multi-turn conversation about selected code with `/edit` command to apply changes

## Requirements

- Neovim 0.10+ (uses `vim.system` for async HTTP)
- [Ollama](https://ollama.ai) running locally (`ollama serve`)
- A model available (e.g., `qwen3-coder:480b-cloud` or `glm-4.7:cloud`)

## Installation

### lazy.nvim

```lua
{
  "ParthSareen/vimollama",
  config = function()
    vim.g.ollama_model = "qwen3-coder:480b-cloud"  -- required
  end,
  keys = {
    { "<leader>k", mode = "v", desc = "Ollama Edit" },
    { "<leader>c", mode = "v", desc = "Ollama Chat" },
  },
}
```

### vim-plug

```vim
Plug 'ParthSareen/vimollama'
let g:ollama_model = 'qwen3-coder:480b-cloud'
```

### Manual

Clone to your Neovim packages directory:
```bash
git clone https://github.com/ParthSareen/vimollama ~/.local/share/nvim/site/pack/plugins/start/ollama-vim
```

## Usage

### Edit Mode (`<leader>k`)

1. Select code in visual mode
2. Press `<leader>k`
3. Type your edit instruction (e.g., "add error handling")
4. Review the diff preview
5. Press `Enter` or `y` to apply, `Esc` or `q` to cancel

### Chat Mode (`<leader>c`)

1. Select code in visual mode
2. Press `<leader>c`
3. Ask questions about the code
4. Continue the conversation (history is maintained)
5. Type `/edit <instruction>` to modify the code
6. Review and apply changes
7. Press `Esc` or `q` to close chat

## Configuration

```lua
-- Required: specify your Ollama model
vim.g.ollama_model = "qwen3-coder:480b-cloud"

-- Optional: customize keymaps (defaults shown)
vim.g.ollama_keymap = "<leader>k"       -- edit mode
vim.g.ollama_chat_keymap = "<leader>c"  -- chat mode

-- Optional: custom Ollama endpoint (default: localhost:11434)
vim.g.ollama_endpoint = "http://localhost:11434/api/generate"
vim.g.ollama_chat_endpoint = "http://localhost:11434/api/chat"

-- Optional: custom system prompts
vim.g.ollama_system_prompt = "Your custom edit prompt..."
vim.g.ollama_chat_system_prompt = "Your custom chat prompt..."
vim.g.ollama_chat_edit_system_prompt = "Your custom chat-edit prompt..."
```

## Commands

- `:OllamaEdit` - Start edit mode (visual mode)
- `:OllamaChat` - Start chat mode (visual mode)

## Highlight Groups

Customize the appearance by setting these highlight groups:

```lua
vim.api.nvim_set_hl(0, "OllamaPreviewAdd", { fg = "#a6e3a1" })    -- added lines
vim.api.nvim_set_hl(0, "OllamaPreviewDel", { fg = "#f38ba8" })    -- deleted lines
vim.api.nvim_set_hl(0, "OllamaPreviewHeader", { fg = "#89b4fa" }) -- diff headers
vim.api.nvim_set_hl(0, "OllamaChatCode", { fg = "#6c7086" })      -- code context
vim.api.nvim_set_hl(0, "OllamaChatUser", { fg = "#89b4fa" })      -- user messages
vim.api.nvim_set_hl(0, "OllamaChatAssistant", { fg = "#a6e3a1" }) -- assistant messages
```

## License

MIT
