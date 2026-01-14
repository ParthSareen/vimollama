" ollama.vim - Cursor-style code editing with Ollama
" Maintainer: Parth
" License: MIT

if exists('g:loaded_ollama')
  finish
endif
let g:loaded_ollama = 1

" Require Neovim 0.10+ for vim.system()
if !has('nvim-0.10')
  echohl ErrorMsg
  echomsg 'ollama.vim requires Neovim 0.10 or later'
  echohl None
  finish
endif

" Commands
command! -range OllamaEdit call ollama#Edit()
command! -range OllamaChat call ollama#Chat()

" Plug mappings
xnoremap <silent> <Plug>(ollama-edit) :<C-u>call ollama#Edit()<CR>
xnoremap <silent> <Plug>(ollama-chat) :<C-u>call ollama#Chat()<CR>

" Default mappings (visual mode) - configurable via g:ollama_keymap / g:ollama_chat_keymap
if !get(g:, 'ollama_no_maps', 0)
  let s:keymap = get(g:, 'ollama_keymap', '<leader>k')
  execute 'xmap ' . s:keymap . ' <Plug>(ollama-edit)'

  let s:chat_keymap = get(g:, 'ollama_chat_keymap', '<leader>c')
  execute 'xmap ' . s:chat_keymap . ' <Plug>(ollama-chat)'
endif

" Highlight groups for preview window
highlight default OllamaPreviewAdd guifg=#98c379 ctermfg=114
highlight default OllamaPreviewDel guifg=#e06c75 ctermfg=204
highlight default OllamaPreviewHeader guifg=#61afef ctermfg=75 gui=bold cterm=bold

" Highlight groups for chat window
highlight default OllamaChatUser guifg=#61afef ctermfg=75 gui=bold cterm=bold
highlight default OllamaChatAssistant guifg=#98c379 ctermfg=114
highlight default OllamaChatCode guifg=#abb2bf ctermfg=249 gui=italic cterm=italic
