" ollama.vim - Cursor-style code editing with Ollama
" Maintainer: Parth
" License: MIT

let g:ollama_plugin_path = expand('<sfile>:p')
let g:ollama_autoload_path = fnamemodify(g:ollama_plugin_path, ':h:h') . '/autoload/ollama.vim'
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

" Load saved model preference from ~/.vimollama
call ollama#LoadSavedModel()

" Commands
" Edit selected text with Ollama
command! -range OllamaEdit call ollama#Edit()
" Start a chat session with Ollama
command! -range OllamaChat call ollama#Chat()
" Switch between different Ollama models
command! OllamaModel call ollama#SwitchModel()
" Debug Ollama integration issues
command! -range OllamaDebug call ollama#Debug()
" Reload the Ollama plugin configuration
command! OllamaReload unlet! g:loaded_ollama | execute 'source' g:ollama_autoload_path | execute 'source' g:ollama_plugin_path | echo "Ollama reloaded"

" Plug mappings
xnoremap <silent> <Plug>(ollama-edit) :<C-u>call ollama#Edit()<CR>
xnoremap <silent> <Plug>(ollama-chat) :<C-u>call ollama#Chat()<CR>
nnoremap <silent> <Plug>(ollama-model) :<C-u>call ollama#SwitchModel()<CR>

" Default mappings - configurable via g:ollama_*_keymap
if !get(g:, 'ollama_no_maps', 0)
  let s:keymap = get(g:, 'ollama_keymap', '<leader>k')
  execute 'xmap ' . s:keymap . ' <Plug>(ollama-edit)'

  let s:chat_keymap = get(g:, 'ollama_chat_keymap', '<leader>K')
  execute 'xmap ' . s:chat_keymap . ' <Plug>(ollama-chat)'

  let s:model_keymap = get(g:, 'ollama_model_keymap', '<leader>M')
  execute 'nmap ' . s:model_keymap . ' <Plug>(ollama-model)'
endif

" Highlight groups for preview window
highlight default OllamaPreviewAdd guifg=#98c379 ctermfg=114
highlight default OllamaPreviewDel guifg=#e06c75 ctermfg=204
highlight default OllamaPreviewHeader guifg=#61afef ctermfg=75 gui=bold cterm=bold

" Highlight groups for chat window
highlight default OllamaChatUser guifg=#61afef ctermfg=75 gui=bold cterm=bold
highlight default OllamaChatAssistant guifg=#98c379 ctermfg=114
highlight default OllamaChatCode guifg=#abb2bf ctermfg=249 gui=italic cterm=italic
highlight default OllamaChatThinking guifg=#5c6370 ctermfg=241 gui=italic cterm=italic
