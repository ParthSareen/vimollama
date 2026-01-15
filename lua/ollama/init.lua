-- lua/ollama/init.lua - Module entry point

local M = {}

local api = require("ollama.api")
local ui = require("ollama.ui")
local chat_ui = require("ollama.chat")

-- Generate code via Ollama API
-- Called from VimL with model, prompt, and system_prompt
function M.generate(model, prompt, system_prompt)
  api.generate(
    model,
    prompt,
    system_prompt,
    function(response)
      vim.fn["ollama#OnApiSuccess"](response)
    end,
    function(error)
      vim.fn["ollama#OnApiError"](error)
    end
  )
end

-- Chat via Ollama API (non-streaming, used for /edit)
-- Called from VimL with model, messages, system_prompt, is_edit
function M.chat(model, messages, system_prompt, is_edit)
  -- Ensure is_edit is a proper number for VimL
  local edit_flag = (is_edit and is_edit ~= 0) and 1 or 0

  api.chat(
    model,
    messages,
    system_prompt,
    function(response, thinking)
      vim.fn["ollama#OnChatResponse"](response, edit_flag, thinking or "")
    end,
    function(error)
      vim.fn["ollama#OnChatError"](error)
    end
  )
end

-- Streaming chat via Ollama API
-- Called from VimL with model, messages, system_prompt
function M.chat_stream(model, messages, system_prompt)
  -- Initialize streaming state in chat UI
  chat_ui.start_streaming()

  api.chat_stream(
    model,
    messages,
    system_prompt,
    function(chunk, full_content, is_thinking)
      -- Update chat UI with new chunk
      chat_ui.stream_chunk(chunk, full_content, is_thinking)
    end,
    function(full_content)
      -- Streaming complete
      chat_ui.end_streaming(full_content)
      vim.fn["ollama#OnChatStreamDone"](full_content)
    end,
    function(error)
      chat_ui.end_streaming("")
      vim.fn["ollama#OnChatError"](error)
    end
  )
end

-- UI functions (edit mode)
M.show_prompt_input = ui.show_prompt_input
M.show_preview = ui.show_preview
M.close_preview = ui.close_preview
M.show_loading = ui.show_loading
M.hide_loading = ui.hide_loading

-- Chat UI functions
M.show_chat = chat_ui.show_chat
M.close_chat = chat_ui.close_chat
M.append_chat_message = chat_ui.append_message
M.show_chat_loading = chat_ui.show_loading
M.hide_chat_loading = chat_ui.hide_loading

-- Model picker using vim.ui.select (integrates with telescope/dressing.nvim)
function M.show_model_picker(models, current)
  vim.ui.select(models, {
    prompt = "Select Ollama model:",
    format_item = function(item)
      if item == current then
        return item .. " (current)"
      end
      return item
    end,
  }, function(selected)
    if selected then
      vim.fn["ollama#OnModelSelect"](selected)
    end
  end)
end

return M
