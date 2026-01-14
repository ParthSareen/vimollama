" autoload/ollama.vim - Main plugin logic

let s:state = {}
let s:chat_state = {}

let s:system_prompt = "You are a code editing assistant. The user will provide code and an instruction for how to modify it.\n\nCRITICAL RULES:\n1. Return ONLY the modified code\n2. Wrap your code output in <code></code> tags\n3. Do NOT include explanations, comments about changes, or markdown formatting\n4. Do NOT include the original code - only the modified version\n5. Preserve the original indentation style\n6. If the instruction is unclear, make the most reasonable interpretation\n\nExample response format:\n<code>\nfunction modified() {\n  // your modified code here\n}\n</code>"

let s:chat_system_prompt = "You are a helpful coding assistant. The user has selected some code and wants to discuss it. Answer questions, explain code, suggest improvements. Be concise but helpful."

let s:chat_edit_system_prompt = "You are a code editing assistant. The user has been discussing some code with you and now wants you to modify it.\n\nCRITICAL RULES:\n1. Return ONLY the modified code\n2. Wrap your code output in <code></code> tags (NOT markdown code blocks)\n3. Do NOT include explanations, comments about changes, or markdown formatting\n4. Modify the ORIGINAL code the user selected, not any code from the conversation\n5. Preserve the original indentation style"

" Main entry point - called from visual mode mapping
function! ollama#Edit() abort
  " Check model is configured
  let l:model = get(g:, 'ollama_model', '')
  if empty(l:model)
    echohl ErrorMsg
    echo 'Ollama: Set g:ollama_model first (e.g., let g:ollama_model = "codellama")'
    echohl None
    return
  endif

  " Capture selection before mode changes
  let s:state = s:CaptureSelection()
  if empty(s:state)
    echohl WarningMsg
    echo 'Ollama: No text selected'
    echohl None
    return
  endif

  " Show prompt input
  lua require('ollama').show_prompt_input()
endfunction

" Called from Lua when user submits prompt
function! ollama#OnPromptSubmit(prompt) abort
  if empty(a:prompt)
    return
  endif

  let s:state.prompt = a:prompt

  " Show loading spinner
  lua require('ollama').show_loading()

  " Build the full prompt
  let l:full_prompt = s:BuildPrompt(s:state.original_code, a:prompt)
  let l:model = get(g:, 'ollama_model', '')
  let l:system = get(g:, 'ollama_system_prompt', s:system_prompt)

  " Call Ollama API via Lua
  call luaeval('require("ollama").generate(_A[1], _A[2], _A[3])', [l:model, l:full_prompt, l:system])
endfunction

" Called from Lua on successful API response
function! ollama#OnApiSuccess(response) abort
  " Hide loading spinner
  lua require('ollama').hide_loading()

  let l:code = s:ExtractCode(a:response)
  if empty(l:code)
    echohl WarningMsg
    echo 'Ollama: No <code></code> block in response'
    echohl None
    " Show raw response for debugging
    echomsg 'Raw response: ' . a:response[:200]
    return
  endif

  let s:state.new_code = l:code
  redraw
  echo ''

  " Show preview
  call luaeval('require("ollama").show_preview(_A)', s:state)
endfunction

" Called from Lua on API error
function! ollama#OnApiError(error) abort
  " Hide loading spinner
  lua require('ollama').hide_loading()

  echohl ErrorMsg
  echo 'Ollama: ' . a:error
  echohl None
endfunction

" Called from Lua when user confirms preview
function! ollama#OnConfirm() abort
  call s:ReplaceSelection(s:state)
  echo 'Ollama: Changes applied'
endfunction

" Called from Lua when user cancels preview
function! ollama#OnCancel() abort
  echo 'Ollama: Cancelled'
endfunction

" Capture visual selection with position info
function! s:CaptureSelection() abort
  let [l:_, l:start_line, l:start_col, l:_] = getpos("'<")
  let [l:_, l:end_line, l:end_col, l:_] = getpos("'>")

  " Handle visual mode quirks
  let l:end_col = l:end_col == 2147483647 ? col([l:end_line, '$']) - 1 : l:end_col

  let l:lines = getline(l:start_line, l:end_line)
  if empty(l:lines)
    return {}
  endif

  " Get the full lines for linewise replacement
  let l:original_code = join(l:lines, "\n")

  return {
        \ 'bufnr': bufnr('%'),
        \ 'start_line': l:start_line,
        \ 'end_line': l:end_line,
        \ 'original_code': l:original_code,
        \ 'filetype': &filetype,
        \ }
endfunction

" Build the prompt for the model
function! s:BuildPrompt(code, instruction) abort
  return printf("Here is the code to modify:\n\n```\n%s\n```\n\nInstruction: %s\n\nProvide only the modified code in <code></code> tags.", a:code, a:instruction)
endfunction

" Extract code from <code></code> tags
function! s:ExtractCode(response) abort
  " Match content between <code> and </code> tags
  let l:pattern = '<code>\s*\n\?\(\_.\{-}\)\n\?<\/code>'
  let l:matches = matchlist(a:response, l:pattern)
  if len(l:matches) > 1
    " Trim leading/trailing whitespace
    return substitute(l:matches[1], '^\s*\n\|\n\s*$', '', 'g')
  endif
  return ''
endfunction

" Replace the original selection with new code
function! s:ReplaceSelection(state) abort
  " Split new code into lines
  let l:new_lines = split(a:state.new_code, "\n", 1)

  " Replace the lines using buffer-specific functions (no window switching needed)
  call deletebufline(a:state.bufnr, a:state.start_line, a:state.end_line)
  call appendbufline(a:state.bufnr, a:state.start_line - 1, l:new_lines)

  " Now switch to the buffer to position cursor
  let l:win_id = bufwinid(a:state.bufnr)
  if l:win_id != -1
    call win_gotoid(l:win_id)
  else
    " Buffer not visible, switch to it (use ! to avoid save prompt)
    execute 'buffer! ' . a:state.bufnr
  endif

  " Position cursor at the start of the change
  call cursor(a:state.start_line, 1)
endfunction

" ============================================================================
" Chat Mode
" ============================================================================

" Chat entry point - called from visual mode mapping
function! ollama#Chat() abort
  " Check model is configured
  let l:model = get(g:, 'ollama_model', '')
  if empty(l:model)
    echohl ErrorMsg
    echo 'Ollama: Set g:ollama_model first (e.g., let g:ollama_model = "codellama")'
    echohl None
    return
  endif

  " Capture selection before mode changes
  let l:selection = s:CaptureSelection()
  if empty(l:selection)
    echohl WarningMsg
    echo 'Ollama: No text selected'
    echohl None
    return
  endif

  " Initialize chat state
  let s:chat_state = {
        \ 'bufnr': l:selection.bufnr,
        \ 'start_line': l:selection.start_line,
        \ 'end_line': l:selection.end_line,
        \ 'code_context': l:selection.original_code,
        \ 'filetype': l:selection.filetype,
        \ 'history': [],
        \ }

  " Show chat window
  call luaeval('require("ollama").show_chat(_A)', s:chat_state)
endfunction

" Called from Lua when user sends a chat message
function! ollama#OnChatSubmit(message) abort
  if empty(a:message)
    return
  endif

  " Check for /edit command
  let l:is_edit = a:message =~# '^/edit\s*'
  let l:edit_instruction = l:is_edit ? substitute(a:message, '^/edit\s*', '', '') : ''

  " Add user message to history
  call add(s:chat_state.history, {'role': 'user', 'content': a:message})

  " Update UI with user message
  call luaeval('require("ollama").append_chat_message("user", _A)', a:message)

  " Show loading
  call luaeval('require("ollama").show_chat_loading()')

  " Build messages for API
  let l:model = get(g:, 'ollama_model', '')

  if l:is_edit
    " For edit mode, use simplified prompt with just the code and instruction
    let l:messages = s:BuildEditMessages(s:chat_state, l:edit_instruction)
    let l:system = get(g:, 'ollama_chat_edit_system_prompt', s:chat_edit_system_prompt)
  else
    " For chat mode, include full conversation history
    let l:messages = s:BuildChatMessages(s:chat_state, 0)
    let l:system = get(g:, 'ollama_chat_system_prompt', s:chat_system_prompt)
  endif

  " Call Ollama API
  call luaeval('require("ollama").chat(_A[1], _A[2], _A[3], _A[4])', [l:model, l:messages, l:system, l:is_edit ? 1 : 0])
endfunction

" Called from Lua on successful chat response
function! ollama#OnChatResponse(response, is_edit) abort
  " Hide loading
  lua require('ollama').hide_chat_loading()

  " Safety check - ensure chat state exists
  if !exists('s:chat_state') || type(s:chat_state) != v:t_dict || !has_key(s:chat_state, 'history')
    echohl ErrorMsg
    echo 'Ollama: Chat state lost'
    echohl None
    return
  endif

  " Add assistant message to history
  call add(s:chat_state.history, {'role': 'assistant', 'content': a:response})

  if a:is_edit
    " Extract code and show preview
    let l:code = s:ExtractCode(a:response)
    if empty(l:code)
      " No code block, show as regular message
      call luaeval('require("ollama").append_chat_message("assistant", _A)', a:response)
      return
    endif

    " Build preview state BEFORE closing chat (close_chat clears s:chat_state)
    " Also set s:state so ollama#OnConfirm can use it
    let s:state = {
          \ 'bufnr': s:chat_state.bufnr,
          \ 'start_line': s:chat_state.start_line,
          \ 'end_line': s:chat_state.end_line,
          \ 'original_code': s:chat_state.code_context,
          \ 'new_code': l:code,
          \ 'filetype': s:chat_state.filetype,
          \ }

    " Now close chat (this clears s:chat_state)
    lua require('ollama').close_chat()

    " Show preview
    call luaeval('require("ollama").show_preview(_A)', s:state)
  else
    " Regular chat response
    call luaeval('require("ollama").append_chat_message("assistant", _A)', a:response)
  endif
endfunction

" Called from Lua on chat API error
function! ollama#OnChatError(error) abort
  call luaeval('require("ollama").hide_chat_loading()')
  call luaeval('require("ollama").append_chat_message("error", _A)', a:error)
endfunction

" Called from Lua when chat is closed
function! ollama#OnChatClose() abort
  " Clear chat state (ephemeral history)
  let s:chat_state = {}
endfunction

" Build messages array for chat API
function! s:BuildChatMessages(state, is_edit) abort
  let l:messages = []

  " Add code context as first message
  let l:context_msg = "Here is the code I'm working with:\n\n```" . a:state.filetype . "\n" . a:state.code_context . "\n```"
  call add(l:messages, {'role': 'user', 'content': l:context_msg})
  call add(l:messages, {'role': 'assistant', 'content': "I can see the code. How can I help you with it?"})

  " Add conversation history
  for l:msg in a:state.history
    call add(l:messages, l:msg)
  endfor

  return l:messages
endfunction

" Build messages for edit mode - includes conversation history for context
function! s:BuildEditMessages(state, instruction) abort
  let l:messages = []

  " Add code context as first message
  let l:context_msg = "Here is the code I'm working with:\n\n```" . a:state.filetype . "\n" . a:state.code_context . "\n```"
  call add(l:messages, {'role': 'user', 'content': l:context_msg})
  call add(l:messages, {'role': 'assistant', 'content': "I can see the code. How can I help you with it?"})

  " Add conversation history (excluding the /edit message we just added)
  let l:history_len = len(a:state.history)
  if l:history_len > 1
    " Add all but the last message (which is the /edit command)
    for l:i in range(l:history_len - 1)
      call add(l:messages, a:state.history[l:i])
    endfor
  endif

  " Add the edit instruction as final user message
  let l:edit_msg = "Now please edit the code: " . a:instruction . "\n\nRespond with ONLY the modified code wrapped in <code></code> tags. No explanations."
  call add(l:messages, {'role': 'user', 'content': l:edit_msg})

  return l:messages
endfunction
