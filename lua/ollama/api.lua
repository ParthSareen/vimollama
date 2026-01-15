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

      -- Chat API returns message.content and optionally message.thinking
      local content = ""
      local thinking = ""
      if response.message then
        content = response.message.content or ""
        thinking = response.message.thinking or ""
      end

      on_success(content, thinking)
    end)
  end)
end

-- Streaming chat API for real-time responses
function M.chat_stream(model, messages, system_prompt, on_chunk, on_done, on_error)
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
    stream = true,
  })

  local full_content = ""
  local buffer = ""

  local cmd = {
    "curl",
    "-s",
    "-N",  -- no buffering
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", body,
    endpoint,
  }

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      for _, line in ipairs(data) do
        if line and line ~= "" then
          -- Handle partial JSON lines
          buffer = buffer .. line

          -- Try to parse each complete line
          local ok, response = pcall(vim.fn.json_decode, buffer)
          if ok then
            buffer = ""
            if response.error then
              vim.schedule(function()
                on_error(response.error)
              end)
              return
            end

            -- Handle thinking field (streamed separately by Ollama)
            if response.message then
              local thinking = response.message.thinking or nil
              local content = response.message.content or ""

              if thinking then
                vim.schedule(function()
                  on_chunk(thinking, full_content, true)  -- true = is_thinking
                end)
              end

              if content and content ~= "" then
                full_content = full_content .. content
                vim.schedule(function()
                  on_chunk(content, full_content, false)  -- false = not thinking
                end)
              end
            end

            if response.done then
              vim.schedule(function()
                on_done(full_content)
              end)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      local err = table.concat(data, "\n")
      if err and err ~= "" then
        vim.schedule(function()
          if err:match("Connection refused") then
            on_error("Cannot connect to Ollama. Is it running? Try: ollama serve")
          else
            on_error("HTTP request failed: " .. err)
          end
        end)
      end
    end,
    on_exit = function(_, code, _)
      if code ~= 0 and full_content == "" then
        vim.schedule(function()
          on_error("Request failed with code " .. code)
        end)
      end
    end,
  })
end

return M
