if exists('g:loaded_crates')
  finish
endif

" curl -s https://crates.io/api/v1/crates/cargo_metadata/versions | jq '.versions[].num'

let s:api = 'https://crates.io/api/v1'

highlight default Crates
      \ ctermfg=white ctermbg=198 cterm=NONE
      \ guifg=#ffffff guibg=#fc3790 gui=NONE

" @return [crate, version]
function! s:cargo_file_parse_line(line, lnum) abort
  if a:line =~# '^version'
    " [dependencies.my-crate]
    " version = "1.2.3"
    let vers = matchstr(a:line, '^version = "\zs[0-9.\*]\+\ze')
    if empty(vers)
      break
    endif
    for lnum in reverse(range(1, a:lnum))
      let crate = matchstr(getline(lnum), '^\[.*dependencies\.\zs.*\ze]$')
      if !empty(crate)
        return [crate, vers]
      endif
    endfor
  elseif a:line =~ '^[[:alnum:]\-_]* = "'
    " my-crate = "1.2.3"
    return matchlist(a:line, '^\([[:alnum:]\-_]\+\) = "\([0-9.\*]\+\)"')[1:2]
  elseif a:line =~# 'version'
    " my-crate = { version = "1.2.3" }
    return matchlist(a:line, '^\([[:alnum:]\-_]\+\) = {.*version = "\([0-9.\*]\+\)"')[1:2]
  endif
  if &verbose
    echomsg 'Skipped:' a:line
  endif
  return ['', -1]
endfunction

function! s:job_callback_nvim_stdout(_job_id, data, _event) dict abort
  let self.stdoutbuf[-1] .= a:data[0]
  call extend(self.stdoutbuf, a:data[1:])
endfunction

function! s:job_callback_nvim_exit(_job_id, exitval, _event) dict abort
  call self.callback(a:exitval)
endfunction

function! s:callback_show_latest_version(exitval) dict abort
  if a:exitval
    echomsg "D'oh! Got ". a:exitval
    return
  endif
  let data = json_decode(self.stdoutbuf[0])
  if !has_key(data, 'versions')
    if self.verbose
      echomsg self.crate .': '. string(data)
    endif
    return
  endif
  let b:crates[self.crate] = map(data.versions, 'v:val.num')
  call s:virttext_add_version(self.lnum, self.vers, s:cache(self.crate))
endfunction

function! s:virttext_add_version(lnum, vers_current, vers_latest)
  if s:show(a:vers_current, a:vers_latest)
    call nvim_buf_set_virtual_text(bufnr(''), nvim_create_namespace('crates'),
          \ a:lnum, [[' '. a:vers_latest .' ', 'Crates']], {})
  endif
endfunction

function! s:crates_io_cmd(crate) abort
  let url = printf('%s/crates/%s/versions', s:api, a:crate)
  return ['curl', '-sL', url]
endfunction

function! s:make_request_sync(crate)
  let result = system(join(s:crates_io_cmd(a:crate)))
  if v:shell_error
    return v:shell_error
  endif
  let b:crates[a:crate] = map(json_decode(result).versions, 'v:val.num')
  return 0
endfunction

function! s:make_request_async(cmd, crate, vers, lnum, callback) abort
  call jobstart(a:cmd, {
        \ 'crate':     a:crate,
        \ 'vers':      a:vers,
        \ 'lnum':      a:lnum,
        \ 'callback':  a:callback,
        \ 'verbose':   &verbose,
        \ 'stdoutbuf': [''],
        \ 'on_stdout': function('s:job_callback_nvim_stdout'),
        \ 'on_exit':   function('s:job_callback_nvim_exit'),
        \ })
endfunction

" Show latest version if it's outside of the given requirement.
function! s:show(a, b) abort
  let has_wildcard = match(a:a, '\*') != -1
  let a = split(a:a, '\.')
  let b = split(a:b, '\.')
  return has_wildcard ? s:show_wildcard(a, b) : s:show_caret(a, b)
endfunction

" Handle caret requirements.
" ^1.2.3  :=  >=1.2.3 <2.0.0
" ^1.2    :=  >=1.2.0 <2.0.0
" ^1      :=  >=1.0.0 <2.0.0
" ^0.2.3  :=  >=0.2.3 <0.3.0
" ^0.2    :=  >=0.2.0 <0.3.0
" ^0.0.3  :=  >=0.0.3 <0.0.4
" ^0.0    :=  >=0.0.0 <0.1.0
" ^0      :=  >=0.0.0 <1.0.0
function! s:show_caret(a, b) abort
  for i in range(min([len(a:a), 3]))
    let a = str2nr(a:a[i])
    let b = str2nr(a:b[i])
    if a == 0 && b == 0 | continue | endif
    return a < b ? 1 : 0
  endfor
  return 0
endfunction

" Handle wildcard requirements.
" *     := >=0.0.0
" 1.*   := >=1.0.0 <2.0.0
" 1.2.* := >=1.2.0 <1.3.0
function! s:show_wildcard(a, b) abort
  for i in range(min([len(a:a), 3]))
    if a:a[i] == '*' | break | endif
    let a = str2nr(a:a[i])
    let b = str2nr(a:b[i])
    if a < b | return 1 | endif
  endfor
  return 0
endfunction

function! s:cache(crate) abort
  return filter(copy(b:crates[a:crate]), 'v:val !~ "\\a"')[0]
endfunction

function! g:CratesComplete(findstart, base)
  if a:findstart
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '[0-9.]'
      let start -= 1
    endwhile
    return start
  else
    let crate = matchstr(getline('.'), '^[a-z\-_]\+')
    if !exists('b:crates')
      let b:crates = {}
    endif
    if !has_key(b:crates, crate)
      if s:make_request_sync(crate) != 0
        return []
      endif
    endif
    return filter(copy(b:crates[crate]), 'v:val =~ "^'.a:base.'"')
  endif
endfunction

function! s:crates() abort
  if !has('nvim')
    echomsg 'Sorry, this is a Nvim-only feature.'
    return
  endif
  call s:virttext_clear('crates')
  if !exists('b:crates')
    let b:crates = {}
  endif
  let lnum = 0
  let in_dep_section = 0

  for line in getline(1, '$')
    if line =~# '^\[.*dependencies.*\]$'
      let in_dep_section = 1
    elseif line[0] == '['
      let in_dep_section = 0
    elseif line[0] == '#'
    elseif empty(line)
    elseif in_dep_section
      try
        let [crate, vers] = s:cargo_file_parse_line(line, lnum)
      catch
        if &verbose
          echomsg 'Failed parsing line:' line
        endif
        let lnum += 1
        continue
      endtry
      if !empty(crate)
        if has_key(b:crates, crate)
          call s:virttext_add_version(lnum, vers, s:cache(crate))
        else
          call s:make_request_async(s:crates_io_cmd(crate), crate, vers, lnum,
                \ function('s:callback_show_latest_version'))
        endif
      endif
    endif
    let lnum += 1
  endfor
endfunction

function! s:virttext_clear(ns) abort
  call nvim_buf_clear_namespace(bufnr(''), nvim_create_namespace(a:ns), 0, -1)
endfunction

function! crates#toggle() abort
  if !exists('b:crates_toggle')
    let b:crates_toggle = 0
  endif
  if b:crates_toggle == 0
    call s:crates()
    " By now all the latest versions are cached, so updating the virttext on
    " each save is a very fast operation.
    augroup crates_toggle
      autocmd BufWritePost <buffer> call s:crates()
    augroup END
  else
    call s:virttext_clear('crates')
    autocmd! crates_toggle
  endif
  let b:crates_toggle = !b:crates_toggle
endfunction

function! crates#up() abort
  if !exists('b:crates')
    let b:crates = {}
  endif
  let lnum = line('.')
  let line = getline('.')
  let [crate, vers] = s:cargo_file_parse_line(line, lnum)
  if empty(crate)
    echomsg 'No version on this line.'
    return
  endif
  if !has_key(b:crates, crate) && s:make_request_sync(crate) != 0
    echomsg 'curl failed!'
    return
  endif
  let vers_latest = s:cache(crate)
  if line =~# 'version\s*='
    let line = substitute(line, 'version\s*=\s*"\zs[0-9\.\*]\+\ze"', vers_latest, '')
  else
    let line = substitute(line, '"\zs[0-9\.\*]\+\ze"', vers_latest, '')
  endif
  call setline(lnum, line)
  call nvim_buf_clear_namespace(bufnr(''), nvim_create_namespace('crates'),
        \ line('.')-1, line('.'))
endfunction

function! s:setup() abort
  setlocal completefunc=CratesComplete
  command! -bar CratesToggle call crates#toggle()
  command! -bar CratesUp     call crates#up()
endfunction

augroup crates
  autocmd BufRead Cargo.toml call s:setup()
augroup END

let g:loaded_crates = 1
