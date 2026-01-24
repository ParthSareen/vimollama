-- lua/ollama/chat.lua - Chat window UI

local M = {}

local chat_buf = nil
local chat_win = nil
local input_buf = nil
local input_win = nil
local state = nil
local loading_line = nil

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_idx = 1
local spinner_timer = nil

-- Streaming state
local stream_start_line = nil
local stream_in_thinking = false
local stream_thinking_content = ""
local stream_response_content = ""
local stream_thinking_done = false

-- Show the chat window
function M.show_chat(chat_state)
  state = chat_state

  -- Calculate window dimensions
  local width = math.floor(vim.o.columns * 0.5)
  local height = math.floor(vim.o.lines * 0.5)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create main chat buffer
  chat_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[chat_buf].buftype = "nofile"
  vim.bo[chat_buf].bufhidden = "wipe"
  vim.bo[chat_buf].swapfile = false

  -- Build initial content with code context
  local lines = {}
  table.insert(lines, "┌─ Code Context ─────────────────────────────────────────")
  for _, line in ipairs(vim.split(state.code_context, "\n")) do
    table.insert(lines, "│ " .. line)
  end
  table.insert(lines, "└────────────────────────────────────────────────────────")
  table.insert(lines, "")
  table.insert(lines, "Type your message below. Use /edit <instruction> to modify the code.")
  table.insert(lines, "Press Esc or q to close.")
  table.insert(lines, "")
  table.insert(lines, string.rep("─", width - 4))
  table.insert(lines, "")

  vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, lines)

  -- Apply highlights for code context
  local ns = vim.api.nvim_create_namespace("ollama_chat")
  for i = 1, #vim.split(state.code_context, "\n") + 2 do
    vim.api.nvim_buf_add_highlight(chat_buf, ns, "OllamaChatCode", i - 1, 0, -1)
  end

  -- Open main chat window
  chat_win = vim.api.nvim_open_win(chat_buf, true, {
    relative = "editor",
    width = width,
    height = height - 3,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Ollama Chat ",
    title_pos = "center",
  })

  vim.wo[chat_win].wrap = true
  vim.wo[chat_win].linebreak = true

  -- Create input buffer
  input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype = "prompt"
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[input_buf].swapfile = false
  vim.fn.prompt_setprompt(input_buf, "> ")

  -- Open input window below chat
  input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    width = width,
    height = 1,
    row = row + height - 2,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  -- Set up prompt callback
  vim.fn.prompt_setcallback(input_buf, function(text)
    if text and text ~= "" then
      vim.fn["ollama#OnChatSubmit"](text)
    end
  end)

  -- Start insert mode and clear any pre-filled text
  vim.cmd("startinsert!")
  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-u>", true, false, true), "n", false)
  end)

  -- Keymaps for input buffer
  local opts = { buffer = input_buf, nowait = true }

  vim.keymap.set("i", "<Esc>", function()
    M.close_chat()
  end, opts)

  vim.keymap.set("i", "<C-c>", function()
    M.close_chat()
  end, opts)

  -- Shift+Enter to submit (alternative to Enter)
  vim.keymap.set("i", "<S-CR>", function()
    local text = vim.fn.getline("."):gsub("^> ", "")
    if text ~= "" then
      vim.fn["ollama#OnChatSubmit"](text)
      vim.fn.setline(".", "> ")
      vim.cmd("startinsert!")
    end
  end, opts)

  -- Paste from system clipboard
  vim.keymap.set("i", "<C-v>", function()
    local clipboard = vim.fn.getreg("+")
    if clipboard ~= "" then
      vim.api.nvim_put({ clipboard }, "c", true, true)
    end
  end, opts)

  -- Paste from unnamed register
  vim.keymap.set("i", "<C-r><C-r>", function()
    local reg = vim.fn.getreg('"')
    if reg ~= "" then
      vim.api.nvim_put({ reg }, "c", true, true)
    end
  end, opts)

  -- Keymaps for chat buffer (when browsing history)
  local chat_opts = { buffer = chat_buf, nowait = true }

  vim.keymap.set("n", "q", function()
    M.close_chat()
  end, chat_opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close_chat()
  end, chat_opts)

  vim.keymap.set("n", "i", function()
    if input_win and vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_set_current_win(input_win)
      vim.cmd("startinsert!")
    end
  end, chat_opts)
end

-- Append a message to the chat
function M.append_message(role, content)
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return
  end

  local lines = {}
  local prefix = ""
  local hl_group = ""

  if role == "user" then
    prefix = "You: "
    hl_group = "OllamaChatUser"
  elseif role == "assistant" then
    prefix = "Assistant: "
    hl_group = "OllamaChatAssistant"
  elseif role == "error" then
    prefix = "Error: "
    hl_group = "ErrorMsg"
  end

  local content_lines = vim.split(content, "\n")
  for i, line in ipairs(content_lines) do
    if i == 1 then
      table.insert(lines, prefix .. line)
    else
      table.insert(lines, string.rep(" ", #prefix) .. line)
    end
  end
  table.insert(lines, "")

  vim.bo[chat_buf].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(chat_buf)
  vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, lines)
  vim.bo[chat_buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("ollama_chat")
  for i = 0, #lines - 2 do
    vim.api.nvim_buf_add_highlight(chat_buf, ns, hl_group, line_count + i, 0, -1)
  end

  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    local new_count = vim.api.nvim_buf_line_count(chat_buf)
    vim.api.nvim_win_set_cursor(chat_win, { new_count, 0 })
  end

  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_set_current_win(input_win)
    vim.cmd("startinsert!")
  end
end

-- Show loading indicator in chat
function M.show_loading()
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return
  end

  vim.bo[chat_buf].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(chat_buf)
  vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, { spinner_frames[1] .. " Thinking..." })
  loading_line = line_count
  vim.bo[chat_buf].modifiable = false

  spinner_idx = 1
  spinner_timer = vim.loop.new_timer()
  spinner_timer:start(0, 80, vim.schedule_wrap(function()
    if chat_buf and vim.api.nvim_buf_is_valid(chat_buf) and loading_line then
      spinner_idx = (spinner_idx % #spinner_frames) + 1
      vim.bo[chat_buf].modifiable = true
      vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false,
        { spinner_frames[spinner_idx] .. " Thinking..." })
      vim.bo[chat_buf].modifiable = false
    end
  end))

  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    local new_count = vim.api.nvim_buf_line_count(chat_buf)
    vim.api.nvim_win_set_cursor(chat_win, { new_count, 0 })
  end
end

-- Hide loading indicator
function M.hide_loading()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end

  if loading_line and chat_buf and vim.api.nvim_buf_is_valid(chat_buf) then
    vim.bo[chat_buf].modifiable = true
    vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, {})
    vim.bo[chat_buf].modifiable = false
    loading_line = nil
  end
end

-- Close the chat window
function M.close_chat()
  M.hide_loading()

  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_win_close(input_win, true)
  end
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_win_close(chat_win, true)
  end

  input_win = nil
  input_buf = nil
  chat_win = nil
  chat_buf = nil
  state = nil

  vim.fn["ollama#OnChatClose"]()
end

-- ============================================================================
-- Streaming Support
-- ============================================================================

-- Start streaming response
function M.start_streaming()
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return
  end

  -- Reset streaming state
  stream_in_thinking = false
  stream_thinking_content = ""
  stream_response_content = ""
  stream_thinking_done = false

  -- Add "Assistant: " line
  vim.bo[chat_buf].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(chat_buf)
  vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, { "Assistant: " })
  stream_start_line = line_count
  vim.bo[chat_buf].modifiable = false

  -- Apply highlight
  local ns = vim.api.nvim_create_namespace("ollama_chat")
  vim.api.nvim_buf_add_highlight(chat_buf, ns, "OllamaChatAssistant", stream_start_line, 0, -1)

  -- Scroll to bottom
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_win_set_cursor(chat_win, { line_count + 1, 0 })
  end
end

-- Process streaming chunk
-- is_thinking: true if this chunk is from the thinking field
function M.stream_chunk(chunk, full_content, is_thinking)
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return
  end

  -- Track thinking vs response content
  if is_thinking then
    stream_in_thinking = true
    stream_thinking_content = stream_thinking_content .. chunk
  else
    -- Once we get non-thinking content, thinking is done
    if stream_in_thinking then
      stream_in_thinking = false
      stream_thinking_done = true
    end
    stream_response_content = full_content
  end

  -- Build display content
  local lines = {}
  local prefix = "Assistant: "

  if stream_in_thinking then
    -- Show thinking with indicator (live)
    local thinking_lines = vim.split("💭 " .. stream_thinking_content, "\n")
    for i, line in ipairs(thinking_lines) do
      if i == 1 then
        table.insert(lines, prefix .. line)
      else
        table.insert(lines, string.rep(" ", #prefix) .. line)
      end
    end
  elseif stream_thinking_done then
    -- Thinking done, show collapsed + response
    table.insert(lines, prefix .. "💭 [Thinking collapsed]")
    if stream_response_content ~= "" then
      local response_lines = vim.split(stream_response_content, "\n")
      for i, line in ipairs(response_lines) do
        if i == 1 then
          table.insert(lines, string.rep(" ", #prefix) .. line)
        else
          table.insert(lines, string.rep(" ", #prefix) .. line)
        end
      end
    end
  else
    -- No thinking, just show content
    local content_lines = vim.split(full_content, "\n")
    for i, line in ipairs(content_lines) do
      if i == 1 then
        table.insert(lines, prefix .. line)
      else
        table.insert(lines, string.rep(" ", #prefix) .. line)
      end
    end
  end

  -- Update buffer
  vim.bo[chat_buf].modifiable = true
  local end_line = vim.api.nvim_buf_line_count(chat_buf)
  vim.api.nvim_buf_set_lines(chat_buf, stream_start_line, end_line, false, lines)
  vim.bo[chat_buf].modifiable = false

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("ollama_chat")
  for i = 0, #lines - 1 do
    local hl = "OllamaChatAssistant"
    if stream_in_thinking or (lines[i + 1] and lines[i + 1]:match("💭")) then
      hl = "OllamaChatThinking"
    end
    vim.api.nvim_buf_add_highlight(chat_buf, ns, hl, stream_start_line + i, 0, -1)
  end

  -- Scroll to bottom
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    local new_count = vim.api.nvim_buf_line_count(chat_buf)
    vim.api.nvim_win_set_cursor(chat_win, { new_count, 0 })
  end
end

-- End streaming response
function M.end_streaming(full_content)
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    return
  end

  -- Add blank line after response
  vim.bo[chat_buf].modifiable = true
  local line_count = vim.api.nvim_buf_line_count(chat_buf)
  vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, { "" })
  vim.bo[chat_buf].modifiable = false

  -- Reset state
  stream_start_line = nil
  stream_in_thinking = false
  stream_thinking_content = ""
  stream_response_content = ""
  stream_thinking_done = false

  -- Return focus to input
  if input_win and vim.api.nvim_win_is_valid(input_win) then
    vim.api.nvim_set_current_win(input_win)
    vim.cmd("startinsert!")
  end
end

return M
