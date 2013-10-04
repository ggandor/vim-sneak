" sneak.vim - Vertical motion for Vim
" Author:       Justin M. Keyes
" Version:      1.0
" http://www.reddit.com/r/vim/comments/1io1bs/how_do_you_move_around_vertically/
" http://www.reddit.com/r/vim/comments/1j9gm1/serious_question_what_do_you_all_think_is_a/
" TODO: add to VAM pool https://github.com/MarcWeber/vim-addon-manager

if exists('g:loaded_sneak_plugin') || &compatible || v:version < 700
  finish
endif
let g:loaded_sneak_plugin = 1

let s:cpo_save = &cpo
set cpo&vim

let s:notfound = 0

"TODO: put this in autoload/
"      http://learnvimscriptthehardway.stevelosh.com/chapters/53.html
"TODO: document:
"      g:sneak#keys.next
"      g:sneak#keys.prev
"      <Plug>SneakForward
"      <Plug>SneakBackward
"      SneakPluginTarget
"      SneakPluginScope
"      g:sneak#options.nextprev_f
"      g:sneak#options.nextprev_t

let g:sneak#state = {}
let g:sneak#options = { "nextprev_f":1, "nextprev_t":1 }

" http://stevelosh.com/blog/2011/09/writing-vim-plugins/
func! SneakToString(op, s, count, isrepeat, reverse, bounds) range abort
  if empty(a:s) "user canceled
    redraw | echo '' | return
  endif

  if a:isrepeat && g:sneak#state.reset
    exec "norm! ".(a:reverse ? "," : ";")
    return
  endif

  "highlight tasks:
  "  - highlight actual matches at or below (above) the cursor position
  "  - highlight the vertical "tunnel" that the search is scoped-to

  let l:search = escape(a:s, '"\')
  let l:gt_lt = a:reverse ? '<' : '>'
  " [left_bound, right_bound] 
  let l:bounds = deepcopy(a:bounds)
  let l:count = a:count
  " example: highlight string "ab" after line 42, column 5 
  "          matchadd('foo', 'ab\%>42l\%5c', 1)
  let l:match_pattern = ''
  " pattern used to highlight the vertical 'scope'
  let l:scope_pattern = ''
  let l:match_bounds  = ''
  " do not wrap
  let l:searchoptions = 'W'
  " search backwards
  if a:reverse | let l:searchoptions .= 'b' | endif
  " save the jump on the initial invocation, _not_ repeats.
  if !a:isrepeat || s:notfound | let l:searchoptions .= 's' | endif

  if l:count > 0 || max(l:bounds) > 0 "narrow the search to a column of width +/- the specified range (v:count)
    if !empty(a:op)
      echo 'sneak: range not supported in visual mode or operator-pending mode' | return
    endif
    " use provided bounds if any, otherwise derive bounds from range
    if max(l:bounds) <= 0
      "these are the _logical_ bounds highlighted in 'scope' mode
      let l:bounds[0] =  max([0, (virtcol('.') - l:count - 1)])
      let l:bounds[1] =  l:count + virtcol('.') + 1
    endif
    "matches *all* chars in the scope.
    "important: use \%<42v (virtual column) instead of \%<42c (byte column)
    let l:scope_pattern .= '\%>'.l:bounds[0].'v\%<'.l:bounds[1].'v'
  endif

  if max(l:bounds) > 0
    "adjust logical left-bound for the _match_ pattern by -len(s) so that if _any_
    "char is within the logical bounds, it is considered a match.
    let l:leftbound = max([0, (bounds[0] - len(a:s)) + 1])
    let l:match_bounds   = '\%>'.l:leftbound.'v\%<'.l:bounds[1].'v'
    let l:match_pattern .= l:match_bounds
  endif

  if !a:isrepeat
    "this is a new search; set up the repeat mappings.
    "do this even if the search fails, because the _reverse_ direction might have a match.
    let g:sneak#state.reset = 0
    let g:sneak#state.reverse = a:reverse
    let g:sneak#state.count  = l:count
    let g:sneak#state.bounds = l:bounds
    let g:sneak#state.search = l:search
  endif

  if !empty(a:op) && !<sid>isvisualop(a:op) "operator-pending invocation
    let l:histreg = @/
    try
      "until we can find a better way, just invoke / and restore the history immediately after
      let s:last_op = 'norm! '.a:op.(a:reverse ? '?' : '/').'\C\V'.l:search."\<cr>"
      call <sid>perform_last_operation()
    catch E486
      let s:notfound = 1
      echo 'not found: '.a:s | return
    finally
      call histdel("/", histnr("/")) "delete the last search from the history
      let @/ = l:histreg
    endtry
  else "jump to the first match, or exit
    let l:matchpos = searchpos('\C\V'.l:match_pattern.'\zs'.l:search, l:searchoptions)
    if 0 == max(l:matchpos)
      let s:notfound = 1
      if max(l:bounds) > 0
        echo printf('not found (in columns %d-%d): %s', l:bounds[0], l:bounds[1], a:s) | return
      else
        echo 'not found: '.a:s | return
      endif
    endif
  endif
  "search succeeded

  if s:notfound "search succeeded; clear previous 'not found' message (if any).
    let s:notfound = 0
    redraw! | echo a:s
  endif

  "if the user was in visual mode, extend the selection.
  if <sid>isvisualop(a:op)
    norm! gv
    call cursor(l:matchpos[0], l:matchpos[1])
  endif

  call s:removehl()

  "position _after_ completed search
  let l:curlin = string(line('.'))
  let l:curcol = string(virtcol('.') + (a:reverse ? -1 : 1))

  "Might as well scope to window height (+/- 40). TODO: profile this
  let l:top = max([0, line('w0')-40])
  let l:bot = min([line('$'), line('w$')+40])
  let l:restrict_top_bot = '\%'.l:gt_lt.l:curlin.'l\%>'.l:top.'l\%<'.l:bot.'l'
  let l:scope_pattern .= l:restrict_top_bot
  let l:match_pattern .= l:restrict_top_bot
  let l:curln_pattern  = l:match_bounds.'\%'.l:curlin.'l\%'.l:gt_lt.l:curcol.'v'

  if l:count > 0
    "perform the scoped highlight...
    let w:sneak_sc_hl = matchadd('SneakPluginScope', l:scope_pattern, 1, get(w:, 'sneak_sc_hl', -1))
  endif

  augroup SneakPlugin
    autocmd!
    autocmd InsertEnter,WinLeave,BufLeave <buffer> call <sid>removehl() | autocmd! SneakPlugin * <buffer>
    "set up *nested* CursorMoved autocmd to avoid the _first_ CursorMoved event.
    autocmd CursorMoved <buffer> autocmd SneakPlugin CursorMoved <buffer> call <sid>removehl() | autocmd! SneakPlugin * <buffer>
  augroup END

  "perform the match highlight...
  "  - scope to window because matchadd() highlight is per-window.
  "  - re-use w:sneak_hl_id if it exists (-1 lets matchadd() choose).
  let w:sneak_hl_id = matchadd('SneakPluginTarget',
        \ '\C\V'.l:match_pattern.'\zs'.l:search.'\|'.l:curln_pattern.l:search,
        \ 2, get(w:, 'sneak_hl_id', -1))
endf

func! sneak#reset()
  let g:sneak#state.reset = 1
endf

if g:sneak#options.nextprev_f || g:sneak#options.nextprev_t
  func! s:map_reset_key(key)
    "preserve existing mapping
    let maparg = maparg(a:key, "n")
    if empty(maparg) "else, preserve the Vim default behavior
      let maparg = a:key
    endif
    exec "nnoremap <silent> ".a:key." :<c-u>call sneak#reset()\<cr>".maparg
  endf

  "if f/F/t/T are invoked, we want ; and , to work for them instead of sneak.
  if g:sneak#options.nextprev_f
    call s:map_reset_key("f")
    call s:map_reset_key("F")
  endif
  if g:sneak#options.nextprev_t
    call s:map_reset_key("t")
    call s:map_reset_key("T")
  endif
endif

func! s:removehl() "remove highlighting
  silent! call matchdelete(w:sneak_hl_id)
  silent! call matchdelete(w:sneak_sc_hl)
endf

func! s:perform_last_operation()
  exec s:last_op
  silent! call repeat#set("\<Plug>SneakRepeat")
endf
nnoremap <silent> <Plug>SneakRepeat :<c-u>call <sid>perform_last_operation()<cr>

func! s:isvisualop(op)
  return -1 != index(["V", "v", "\<c-v>"], a:op)
endf
func! s:getinputchar()
  let l:c = getchar()
  return type(l:c) == type(0) ? nr2char(l:c) : l:c
endf
func! s:getnextNchars(n)
  let l:s = ''
  redraw | echo '/'
  for i in range(1, a:n)
    let l:c = <sid>getinputchar()
    if -1 != index(["\<esc>", "\<c-c>", "\<backspace>", "\<del>"], l:c)
      return ""
    endif
    let l:s .= l:c
    redraw | echo '/'.l:s
  endfor
  return l:s
endf
func! s:dbgflag(settingname)
  exec 'let value='.a:settingname
  silent echo a:settingname.'='.value
endf
func! s:dbgfeat(featurename)
  exec 'let value=has("'.a:featurename.'")'
  silent echo 'has("'.a:featurename.'")='.value
endf
func! sneak#debugreport()
  redir => output
    call s:dbgfeat('autocmd')
    call s:dbgflag('&buftype')
    call s:dbgflag('&virtualedit')
    silent exec 'verbose map s | map S | map z | map Z'
  redir END
  enew
  silent put=output
  "set nomodified
endf

augroup SneakPluginInit
  autocmd!
  highlight SneakPluginTarget guifg=white guibg=magenta ctermfg=white ctermbg=magenta
  autocmd ColorScheme * highlight SneakPluginTarget guifg=white guibg=magenta ctermfg=white ctermbg=magenta

  if &background ==# 'dark'
    highlight SneakPluginScope guifg=black guibg=white ctermfg=black ctermbg=white
    autocmd ColorScheme * highlight SneakPluginScope guifg=black guibg=white ctermfg=black ctermbg=white
  else
    highlight SneakPluginScope guifg=white guibg=black ctermfg=white ctermbg=black
    autocmd ColorScheme * highlight SneakPluginScope guifg=white guibg=black ctermfg=white ctermbg=black
  endif
augroup END

nnoremap <silent> <Plug>SneakForward   :<c-u>call SneakToString('', <sid>getnextNchars(2), v:count, 0, 0, [0,0])<cr>
nnoremap <silent> <Plug>SneakBackward  :<c-u>call SneakToString('', <sid>getnextNchars(2), v:count, 0, 1, [0,0])<cr>
nnoremap <silent> <Plug>SneakNext      :<c-u>call SneakToString('', g:sneak#state.search, g:sneak#state.count, 1,  g:sneak#state.reverse, g:sneak#state.bounds,)<cr>
nnoremap <silent> <Plug>SneakPrevious  :<c-u>call SneakToString('', g:sneak#state.search, g:sneak#state.count, 1, !g:sneak#state.reverse, g:sneak#state.bounds,)<cr>
xnoremap <silent> <Plug>VSneakNext     :<c-u>call SneakToString(visualmode(), g:sneak#state.search, g:sneak#state.count, 1,  g:sneak#state.reverse, g:sneak#state.bounds)<cr>
xnoremap <silent> <Plug>VSneakPrevious :<c-u>call SneakToString(visualmode(), g:sneak#state.search, g:sneak#state.count, 1, !g:sneak#state.reverse, g:sneak#state.bounds)<cr>
nnoremap <silent> yz     :<c-u>call SneakToString('y',          <sid>getnextNchars(2), v:count, 0, 0, [0,0])<cr>
nnoremap <silent> yZ     :<c-u>call SneakToString('y',          <sid>getnextNchars(2), v:count, 0, 1, [0,0])<cr>
onoremap <silent> z      :<c-u>call SneakToString(v:operator,   <sid>getnextNchars(2), v:count, 0, 0, [0,0])<cr>
onoremap <silent> Z      :<c-u>call SneakToString(v:operator,   <sid>getnextNchars(2), v:count, 0, 1, [0,0])<cr>
xnoremap <silent> s <esc>:<c-u>call SneakToString(visualmode(), <sid>getnextNchars(2), v:count, 0, 0, [0,0])<cr>
xnoremap <silent> Z <esc>:<c-u>call SneakToString(visualmode(), <sid>getnextNchars(2), v:count, 0, 1, [0,0])<cr>

if !hasmapto('<Plug>SneakForward')
  nmap s <Plug>SneakForward
endif
if !hasmapto('<Plug>SneakBackward')
  nmap S <Plug>SneakBackward
endif

if !hasmapto('<Plug>SneakNext')
  nmap ; <Plug>SneakNext
endif
if !hasmapto('<Plug>SneakPrevious')
  if mapleader ==# ','
    nmap \ <Plug>SneakPrevious
  else
    nmap , <Plug>SneakPrevious
  endif
endif

if !hasmapto('<Plug>VSneakNext')
  xmap ; <Plug>VSneakNext
endif
if !hasmapto('<Plug>VSneakPrevious')
  if mapleader ==# ','
    xmap \ <Plug>VSneakPrevious
  else
    xmap , <Plug>VSneakPrevious
  endif
endif


let &cpo = s:cpo_save
unlet s:cpo_save