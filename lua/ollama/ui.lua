-- lua/ollama/ui.lua - Floating window UI components

local M = {}

local prompt_buf = nil
local prompt_win = nil
local preview_buf = nil
local preview_win = nil
local loading_buf = nil
local loading_win = nil
local loading_timer = nil
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_idx = 1

-- Show floating input for prompt
function M.show_prompt_input()
  -- Create buffer
  prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype = "prompt"
  vim.bo[prompt_buf].bufhidden = "wipe"
  vim.fn.prompt_setprompt(prompt_buf, "Edit instruction: ")

  -- Calculate centered position
  local width = math.floor(vim.o.columns * 0.6)
  local height = 1
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Open floating window
  prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Ollama Edit ",
    title_pos = "center",
  })

  -- Set up callback when user presses Enter
  vim.fn.prompt_setcallback(prompt_buf, function(text)
    M.close_prompt()
    vim.fn["ollama#OnPromptSubmit"](text)
  end)

  -- Clear registers and buffer, then start insert mode
  vim.fn.setreg('"', '')
  vim.fn.setreg('0', '')
  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, {""})
  vim.cmd("startinsert!")

  -- Escape to cancel
  vim.keymap.set("i", "<Esc>", function()
    M.close_prompt()
    vim.fn["ollama#OnCancel"]()
  end, { buffer = prompt_buf, nowait = true })

  -- Also handle Ctrl-C
  vim.keymap.set("i", "<C-c>", function()
    M.close_prompt()
    vim.fn["ollama#OnCancel"]()
  end, { buffer = prompt_buf, nowait = true })
end

-- Simple diff: compute line-by-line differences
local function compute_diff(old_text, new_text)
  local old_lines = vim.split(old_text, "\n")
  local new_lines = vim.split(new_text, "\n")
  local result = {}

  -- Use vim.diff for unified diff output
  local ok, diff_text = pcall(vim.diff, old_text .. "\n", new_text .. "\n", {
    result_type = "unified",
    context = 3,
  })

  if ok and diff_text and diff_text ~= "" then
    -- Parse unified diff output, skip header lines
    local diff_lines = vim.split(diff_text, "\n")
    local started = false
    for _, line in ipairs(diff_lines) do
      -- Skip the --- and +++ header lines
      if line:match("^@@") then
        started = true
        table.insert(result, { text = line, type = "hunk" })
      elseif started then
        if line:match("^%-") then
          table.insert(result, { text = line, type = "del" })
        elseif line:match("^%+") then
          table.insert(result, { text = line, type = "add" })
        elseif line ~= "" or #result > 0 then
          table.insert(result, { text = " " .. line:sub(2), type = "context" })
        end
      end
    end
  else
    -- Fallback: show all old as deleted, all new as added
    for _, line in ipairs(old_lines) do
      table.insert(result, { text = "-" .. line, type = "del" })
    end
    for _, line in ipairs(new_lines) do
      table.insert(result, { text = "+" .. line, type = "add" })
    end
  end

  return result
end

-- Show preview window with original and new code
function M.show_preview(state)
  preview_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].modifiable = true

  -- Compute diff
  local diff_result = compute_diff(state.original_code, state.new_code)

  -- Build preview content
  local lines = {}
  local line_types = {}

  table.insert(lines, "Preview Changes:")
  table.insert(line_types, "header")
  table.insert(lines, "")
  table.insert(line_types, "")

  for _, item in ipairs(diff_result) do
    table.insert(lines, item.text)
    table.insert(line_types, item.type)
  end

  table.insert(lines, "")
  table.insert(line_types, "")
  table.insert(lines, "[Enter/y] Apply  |  [Esc/q/n] Cancel")
  table.insert(line_types, "footer")

  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  vim.bo[preview_buf].modifiable = false

  -- Apply highlights based on line types
  M.apply_preview_highlights(preview_buf, line_types)

  -- Window size - adaptive to content
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  preview_win = vim.api.nvim_open_win(preview_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Preview Changes ",
    title_pos = "center",
  })

  -- Keymaps
  local opts = { buffer = preview_buf, nowait = true }

  vim.keymap.set("n", "<CR>", function()
    M.close_preview()
    vim.fn["ollama#OnConfirm"]()
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close_preview()
    vim.fn["ollama#OnCancel"]()
  end, opts)

  vim.keymap.set("n", "q", function()
    M.close_preview()
    vim.fn["ollama#OnCancel"]()
  end, opts)

  -- Also y/n as alternatives
  vim.keymap.set("n", "y", function()
    M.close_preview()
    vim.fn["ollama#OnConfirm"]()
  end, opts)

  vim.keymap.set("n", "n", function()
    M.close_preview()
    vim.fn["ollama#OnCancel"]()
  end, opts)
end

function M.apply_preview_highlights(buf, line_types)
  local ns = vim.api.nvim_create_namespace("ollama_preview")
  for i, ltype in ipairs(line_types) do
    local lnum = i - 1 -- 0-indexed
    if ltype == "header" or ltype == "footer" or ltype == "hunk" then
      vim.api.nvim_buf_add_highlight(buf, ns, "OllamaPreviewHeader", lnum, 0, -1)
    elseif ltype == "del" then
      vim.api.nvim_buf_add_highlight(buf, ns, "OllamaPreviewDel", lnum, 0, -1)
    elseif ltype == "add" then
      vim.api.nvim_buf_add_highlight(buf, ns, "OllamaPreviewAdd", lnum, 0, -1)
    end
    -- context lines stay default color
  end
end

function M.close_prompt()
  if prompt_win and vim.api.nvim_win_is_valid(prompt_win) then
    vim.api.nvim_win_close(prompt_win, true)
  end
  prompt_win = nil
  prompt_buf = nil
end

function M.close_preview()
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

-- Show loading spinner
function M.show_loading()
  loading_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[loading_buf].buftype = "nofile"
  vim.bo[loading_buf].bufhidden = "wipe"

  local text = spinner_frames[1] .. " Generating..."
  vim.api.nvim_buf_set_lines(loading_buf, 0, -1, false, { text })

  local width = 20
  local height = 1
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  loading_win = vim.api.nvim_open_win(loading_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    focusable = false,
  })

  -- Start spinner animation
  spinner_idx = 1
  loading_timer = vim.loop.new_timer()
  loading_timer:start(0, 80, vim.schedule_wrap(function()
    if loading_buf and vim.api.nvim_buf_is_valid(loading_buf) then
      spinner_idx = (spinner_idx % #spinner_frames) + 1
      local new_text = spinner_frames[spinner_idx] .. " Generating..."
      vim.api.nvim_buf_set_lines(loading_buf, 0, -1, false, { new_text })
    end
  end))
end

-- Hide loading spinner
function M.hide_loading()
  if loading_timer then
    loading_timer:stop()
    loading_timer:close()
    loading_timer = nil
  end
  if loading_win and vim.api.nvim_win_is_valid(loading_win) then
    vim.api.nvim_win_close(loading_win, true)
  end
  loading_win = nil
  loading_buf = nil
end

return M
