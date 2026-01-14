-- lua/ollama/api.lua - Async HTTP client for Ollama API

local M = {}

local DEFAULT_ENDPOINT = "http://localhost:11434/api/generate"
local DEFAULT_CHAT_ENDPOINT = "http://localhost:11434/api/chat"

function M.generate(model, prompt, system_prompt, on_success, on_error)
  local endpoint = vim.g.ollama_endpoint or DEFAULT_ENDPOINT

  local body = vim.fn.json_encode({
    model = model,
    prompt = prompt,
    system = system_prompt,
    stream = false,
  })

  -- Use vim.system for async HTTP (Neovim 0.10+)
  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", body,
    endpoint,
  }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err_msg = result.stderr or "Unknown error"
        if err_msg:match("Connection refused") then
          on_error("Cannot connect to Ollama. Is it running? Try: ollama serve")
        else
          on_error("HTTP request failed: " .. err_msg)
        end
        return
      end

      if not result.stdout or result.stdout == "" then
        on_error("Empty response from Ollama")
        return
      end

      local ok, response = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        on_error("Failed to parse JSON: " .. result.stdout:sub(1, 100))
        return
      end

      if response.error then
        on_error(response.error)
        return
      end

      on_success(response.response or "")
    end)
  end)
end

-- Chat API for multi-turn conversations
function M.chat(model, messages, system_prompt, on_success, on_error)
  local endpoint = vim.g.ollama_chat_endpoint or DEFAULT_CHAT_ENDPOINT

  -- Prepend system message
  local all_messages = {
    { role = "system", content = system_prompt }
  }
  for _, msg in ipairs(messages) do
    table.insert(all_messages, msg)
  end

  local body = vim.fn.json_encode({
    model = model,
    messages = all_messages,
    stream = false,
  })

  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", body,
    endpoint,
  }

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local err_msg = result.stderr or "Unknown error"
        if err_msg:match("Connection refused") then
          on_error("Cannot connect to Ollama. Is it running? Try: ollama serve")
        else
          on_error("HTTP request failed: " .. err_msg)
        end
        return
      end

      if not result.stdout or result.stdout == "" then
        on_error("Empty response from Ollama")
        return
      end

      local ok, response = pcall(vim.fn.json_decode, result.stdout)
      if not ok then
        on_error("Failed to parse JSON: " .. result.stdout:sub(1, 100))
        return
      end

      if response.error then
        on_error(response.error)
        return
      end

      -- Chat API returns message.content
      local content = ""
      if response.message and response.message.content then
        content = response.message.content
      end

      on_success(content)
    end)
  end)
end

return M
