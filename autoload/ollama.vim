" autoload/ollama.vim - Main plugin logic

let s:state = {}
let s:chat_state = {}

" Default models for switcher
let s:default_models = ['qwen3-coder:480b-cloud', 'glm-4.7:cloud', 'qwen3-coder', 'gpt-oss:20b']

" Default number of context lines to include before/after selection
let s:default_context_lines = 20

let s:system_prompt = "You are a code editing assistant. The user will provide code with context and an instruction for how to modify it.\n\nThe code will be provided in XML tags:\n- <previous_lines>: Code BEFORE the selection (for context only, do NOT modify)\n- <user_selected_text>: The code the user selected (THIS is what you should modify)\n- <after_lines>: Code AFTER the selection (for context only, do NOT modify)\n\nCRITICAL RULES:\n1. Return ONLY the modified <user_selected_text> content\n2. Wrap your code output in <code></code> tags\n3. Do NOT include explanations, comments about changes, or markdown formatting\n4. Do NOT include the context lines - only the modified selected code\n5. Preserve the original indentation style\n6. If the instruction is unclear, make the most reasonable interpretation\n\nExample response format:\n<code>\nfunction modified() {\n  // your modified code here\n}\n</code>"

let s:chat_system_prompt = "You are a helpful coding assistant. The user has selected some code and wants to discuss it.\n\nThe code is provided in XML tags:\n- <previous_lines>: Code before the selection (context)\n- <user_selected_text>: The code the user selected\n- <after_lines>: Code after the selection (context)\n\nAnswer questions, explain code, suggest improvements. Be concise but helpful."

let s:chat_edit_system_prompt = "You are a code editing assistant. The user has been discussing some code with you and now wants you to modify it.\n\nThe code was provided in XML tags:\n- <previous_lines>: Code before the selection (context only, do NOT modify)\n- <user_selected_text>: The code the user selected (THIS is what you should modify)\n- <after_lines>: Code after the selection (context only, do NOT modify)\n\nCRITICAL RULES:\n1. Return ONLY the modified <user_selected_text> content\n2. Wrap your code output in <code></code> tags (NOT markdown code blocks)\n3. Do NOT include explanations, comments about changes, or markdown formatting\n4. Do NOT include the context lines - only the modified selected code\n5. Preserve the original indentation style"

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

  " Build the full prompt with context
  let l:full_prompt = s:BuildPrompt(s:state, a:prompt)
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

" Capture visual selection with position info and context
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

  " Get context lines before and after selection
  let l:context_lines = get(g:, 'ollama_context_lines', s:default_context_lines)
  let l:total_lines = line('$')

  " Previous lines (before selection)
  let l:prev_start = max([1, l:start_line - l:context_lines])
  let l:prev_end = max([1, l:start_line - 1])
  let l:previous_lines = ''
  if l:prev_end >= l:prev_start
    let l:previous_lines = join(getline(l:prev_start, l:prev_end), "\n")
  endif

  " After lines (after selection)
  let l:after_start = min([l:total_lines, l:end_line + 1])
  let l:after_end = min([l:total_lines, l:end_line + l:context_lines])
  let l:after_lines = ''
  if l:after_end >= l:after_start
    let l:after_lines = join(getline(l:after_start, l:after_end), "\n")
  endif

  return {
        \ 'bufnr': bufnr('%'),
        \ 'start_line': l:start_line,
        \ 'end_line': l:end_line,
        \ 'original_code': l:original_code,
        \ 'previous_lines': l:previous_lines,
        \ 'after_lines': l:after_lines,
        \ 'filetype': &filetype,
        \ }
endfunction

" Build the prompt for the model with context
function! s:BuildPrompt(state, instruction) abort
  let l:parts = []

  " Add context before selection if available
  if !empty(a:state.previous_lines)
    call add(l:parts, "<previous_lines>\n" . a:state.previous_lines . "\n</previous_lines>")
  endif

  " Add the selected code
  call add(l:parts, "<user_selected_text>\n" . a:state.original_code . "\n</user_selected_text>")

  " Add context after selection if available
  if !empty(a:state.after_lines)
    call add(l:parts, "<after_lines>\n" . a:state.after_lines . "\n</after_lines>")
  endif

  let l:context = join(l:parts, "\n\n")

  return printf("Here is the code context:\n\n%s\n\nInstruction: %s\n\nModify ONLY the code within <user_selected_text>. Provide only the modified code in <code></code> tags.", l:context, a:instruction)
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
" Debug
" ============================================================================

" Debug function to inspect captured selection and context
function! ollama#Debug() abort
  let l:state = s:CaptureSelection()
  if empty(l:state)
    echo "No selection captured"
    return
  endif

  echo "=== Ollama Debug ==="
  echo "Lines: " . l:state.start_line . " - " . l:state.end_line
  echo "Context lines setting: " . get(g:, 'ollama_context_lines', s:default_context_lines)
  echo ""
  echo "--- previous_lines (" . len(split(l:state.previous_lines, "\n")) . " lines) ---"
  echo l:state.previous_lines
  echo ""
  echo "--- user_selected_text ---"
  echo l:state.original_code
  echo ""
  echo "--- after_lines (" . len(split(l:state.after_lines, "\n")) . " lines) ---"
  echo l:state.after_lines
  echo "=== End Debug ==="
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
        \ 'previous_lines': l:selection.previous_lines,
        \ 'after_lines': l:selection.after_lines,
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

  " Build messages for API
  let l:model = get(g:, 'ollama_model', '')

  if l:is_edit
    " For edit mode, use streaming API with edit flag
    let s:pending_edit = 1
    let l:messages = s:BuildEditMessages(s:chat_state, l:edit_instruction)
    let l:system = get(g:, 'ollama_chat_edit_system_prompt', s:chat_edit_system_prompt)
    call luaeval('require("ollama").chat_stream(_A[1], _A[2], _A[3])', [l:model, l:messages, l:system])
  else
    " For chat mode, use streaming API
    let s:pending_edit = 0
    let l:messages = s:BuildChatMessages(s:chat_state, 0)
    let l:system = get(g:, 'ollama_chat_system_prompt', s:chat_system_prompt)
    call luaeval('require("ollama").chat_stream(_A[1], _A[2], _A[3])', [l:model, l:messages, l:system])
  endif
endfunction

" Called from Lua on successful chat response
function! ollama#OnChatResponse(response, is_edit, ...) abort
  " Hide loading
  lua require('ollama').hide_chat_loading()

  " Get thinking content (optional 3rd argument)
  let l:thinking = get(a:, 1, '')

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
    " Show thinking collapsed in chat if present
    if !empty(l:thinking)
      call luaeval('require("ollama").append_chat_message("assistant", "💭 [Thinking collapsed]")')
    endif

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
    " Regular chat response (shouldn't happen - regular chat uses streaming now)
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

" Called from Lua when streaming chat completes
function! ollama#OnChatStreamDone(response) abort
  " Safety check - ensure chat state exists
  if !exists('s:chat_state') || type(s:chat_state) != v:t_dict || !has_key(s:chat_state, 'history')
    return
  endif

  " Add assistant response to history
  call add(s:chat_state.history, {'role': 'assistant', 'content': a:response})

  " Check if this was an edit request
  if get(s:, 'pending_edit', 0)
    let s:pending_edit = 0

    " Extract code and show preview
    let l:code = s:ExtractCode(a:response)
    if empty(l:code)
      " No code block found, just leave the chat open
      return
    endif

    " Build preview state
    let s:state = {
          \ 'bufnr': s:chat_state.bufnr,
          \ 'start_line': s:chat_state.start_line,
          \ 'end_line': s:chat_state.end_line,
          \ 'original_code': s:chat_state.code_context,
          \ 'new_code': l:code,
          \ 'filetype': s:chat_state.filetype,
          \ }

    " Close chat and show preview
    lua require('ollama').close_chat()
    call luaeval('require("ollama").show_preview(_A)', s:state)
  endif
endfunction

" Build messages array for chat API
function! s:BuildChatMessages(state, is_edit) abort
  let l:messages = []

  " Build code context with surrounding lines
  let l:context_parts = []
  if !empty(a:state.previous_lines)
    call add(l:context_parts, "<previous_lines>\n" . a:state.previous_lines . "\n</previous_lines>")
  endif
  call add(l:context_parts, "<user_selected_text>\n" . a:state.code_context . "\n</user_selected_text>")
  if !empty(a:state.after_lines)
    call add(l:context_parts, "<after_lines>\n" . a:state.after_lines . "\n</after_lines>")
  endif

  let l:context_msg = "Here is the code I'm working with:\n\n" . join(l:context_parts, "\n\n")
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

  " Build code context with surrounding lines
  let l:context_parts = []
  if !empty(a:state.previous_lines)
    call add(l:context_parts, "<previous_lines>\n" . a:state.previous_lines . "\n</previous_lines>")
  endif
  call add(l:context_parts, "<user_selected_text>\n" . a:state.code_context . "\n</user_selected_text>")
  if !empty(a:state.after_lines)
    call add(l:context_parts, "<after_lines>\n" . a:state.after_lines . "\n</after_lines>")
  endif

  let l:context_msg = "Here is the code I'm working with:\n\n" . join(l:context_parts, "\n\n")
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
  let l:edit_msg = "Now please edit the code within <user_selected_text>: " . a:instruction . "\n\nRespond with ONLY the modified code wrapped in <code></code> tags. No explanations."
  call add(l:messages, {'role': 'user', 'content': l:edit_msg})

  return l:messages
endfunction

" ============================================================================
" Model Switcher
" ============================================================================

" Switch between configured models
function! ollama#SwitchModel() abort
  let l:models = get(g:, 'ollama_models', s:default_models)
  let l:current = get(g:, 'ollama_model', '')

  call luaeval('require("ollama").show_model_picker(_A[1], _A[2])', [l:models, l:current])
endfunction

" Called from Lua when user selects a model
function! ollama#OnModelSelect(model) abort
  let g:ollama_model = a:model
  call s:SaveModel(a:model)
  echo 'Ollama: Model set to ' . a:model
endfunction

" Save model choice to ~/.vimollama
function! s:SaveModel(model) abort
  call writefile([a:model], expand('~/.vimollama'))
endfunction

" Load saved model from ~/.vimollama (overrides config default)
function! ollama#LoadSavedModel() abort
  let l:file = expand('~/.vimollama')
  if filereadable(l:file)
    let l:lines = readfile(l:file)
    if len(l:lines) > 0 && !empty(l:lines[0])
      let g:ollama_model = l:lines[0]
    endif
  endif
endfunction
