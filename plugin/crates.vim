if exists('g:loaded_crates')
  finish
endif

" curl -s https://crates.io/api/v1/crates/cargo_metadata/versions | jq '.versions[].num'

let s:api = 'https://crates.io/api/v1'

highlight default Crates
      \ ctermfg=white ctermbg=198 cterm=NONE
      \ guifg=#ffffff guibg=#fc3790 gui=NONE

" @return [crate, version]
function! s:cargo_file_parse_line(line) abort
  if a:line =~ '^[a-z\-_]* = "'
    return matchlist(a:line, '^\([a-z\-_]\+\) = "\([0-9.]\+\)"')[1:2]
  elseif a:line =~# 'version'
    return matchlist(a:line, '^\([a-z\-_]\+\) = {.*version = "\([0-9.]\+\)"')[1:2]
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
  let vers_current = self.vers
  let vers_latest  = filter(copy(b:crates[self.crate]), 'v:val !~ "\\a"')[0]
  if s:semver_compare(vers_current, vers_latest) < 0
    call nvim_buf_set_virtual_text(bufnr(''), nvim_create_namespace('crates'),
          \ self.lnum, [[' '. vers_latest .' ', 'Crates']], {})
  endif
endfunction

function! s:build_cmd(crate) abort
  let url = printf('%s/crates/%s/versions', s:api, a:crate)
  return ['curl', '-sL', url]
endfunction

function! s:make_request_sync(crate)
  let result = system(join(s:build_cmd(a:crate)))
  if v:shell_error
    return v:shell_error
  endif
  let b:crates[a:crate] = map(json_decode(result).versions, 'v:val.num')
  return 0
endfunction

function! s:make_request_async(crate, vers, lnum) abort
  call jobstart(s:build_cmd(a:crate), {
        \ 'crate':     a:crate,
        \ 'vers':      a:vers,
        \ 'lnum':      a:lnum,
        \ 'verbose':   &verbose,
        \ 'stdoutbuf': [''],
        \ 'on_stdout': function('s:job_callback_nvim_stdout'),
        \ 'on_exit':   function('s:job_callback_nvim_exit'),
        \ })
endfunction

function! s:semver_normalize(vers) abort
  let vers = split(a:vers, '\.')
  if len(vers) == 1
    return vers + [0, 0]
  elseif len(vers) == 2
    return vers + [0]
  else
    return vers[:2]
  endif
endfunction

function! s:semver_compare(a, b) abort
  let a = s:semver_normalize(a:a)
  let b = s:semver_normalize(a:b)
  for i in range(3)
    if a[i] > b[i] | return  1 | endif
    if a[i] < b[i] | return -1 | endif
  endfor
  return 0
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
  if !exists('b:crates')
    let b:crates = {}
  endif
  let lnum = 0
  let in_dep_section = 0

  for line in getline(1, '$')
    if line =~# '^\[.*dependencies\]$'
      let in_dep_section = 1
    elseif line[0] == '['
      let in_dep_section = 0
    elseif line[0] == '#'
    elseif empty(line)
    elseif in_dep_section
      let [crate, vers] = s:cargo_file_parse_line(line)
      if !empty(crate)
        call s:make_request_async(crate, vers, lnum)
      endif
    endif
    let lnum += 1
  endfor
endfunction

function! s:crates_toggle() abort
  if !exists('b:crates_toggle')
    let b:crates_toggle = 0
  endif
  if b:crates_toggle == 0
    call s:crates()
  else
    call nvim_buf_clear_namespace(bufnr(''), nvim_create_namespace('crates'), 0, -1)
  endif
  let b:crates_toggle = !b:crates_toggle
endfunction

function! s:crates_up() abort
  if !exists('b:crates')
    let b:crates = {}
  endif
  let crate = matchstr(getline('.'), '^[a-z\-_]\+')
  if !has_key(b:crates, crate) && s:make_request_sync(crate) != 0
    return
  endif
  let vers_latest  = filter(copy(b:crates[crate]), 'v:val !~ "\\a"')[0]
  let lnum = line('.')
  let line = getline(lnum)
  if line =~ '^[a-z\-_]* = "'
    let line = substitute(line, '"\zs[0-9\.]\+\ze"', vers_latest, '')
  elseif line =~# 'version'
    let line = substitute(line, 'version\s*=\s*"\zs[0-9\.]\+\ze"', vers_latest, '')
  else
    echomsg 'Failed parsing this line. Create a GitHub issue for it.'
    return
  endif
  call setline(lnum, line)
  call nvim_buf_clear_namespace(bufnr(''), nvim_create_namespace('crates'),
        \ line('.')-1, line('.'))
endfunction

function! s:setup() abort
  set omnifunc=CratesComplete
  command! -bar CratesToggle call s:crates_toggle()
  command! -bar CratesUp     call s:crates_up()
endfunction

augroup crates
  autocmd BufRead Cargo.toml call s:setup()
augroup END

let g:loaded_crates = 1
