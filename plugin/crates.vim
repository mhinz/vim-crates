if exists('g:loaded_crates')
  finish
endif

" curl -s https://crates.io/api/v1/crates/cargo_metadata/versions | jq '.versions[].num'
"
" More prone to rate-limiting:
" curl -sH 'Accept: application/vnd.github.VERSION.raw' https://api.github.com/repos/rust-lang/crates.io-index/contents/ca/rg/cargo_metadata | jq '.vers'

let s:api_crates = 'https://crates.io/api/v1'
let s:api_github = 'https://api.github.com/repos/rust-lang/crates.io-index'

let s:ns = nvim_create_namespace('crates')

highlight default Crates
      \ ctermfg=white ctermbg=198 cterm=NONE
      \ guifg=#ffffff guibg=#fc3790 gui=NONE

" @return [crate, version]
function! s:cargo_file_parse_line(line) abort
  if a:line =~ '^[a-z\-_]* = "'
    return matchlist(a:line, '^\([a-z\-_]\+\) = "\([0-9.]\+\)"')[1:2]
  else
    return matchlist(a:line, '^\([a-z\-_]\+\) = {.*version = "\([0-9.]\+\)"')[1:2]
  endif
endfunction

function! s:github_get_index_path(crate) abort
  let len = len(a:crate)
  if len == 1
    return printf('1/%s', a:crate)
  elseif len == 2
    return printf('2/%s', a:crate)
  elseif len == 3
    return printf('3/%s/%s', a:crate[0], a:crate)
  endif
  return printf('%s/%s/%s', a:crate[0:1], a:crate[2:3], a:crate)
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
  call nvim_buf_set_virtual_text(bufnr(''), s:ns, self.lnum,
        \ [[' '. b:crates[self.crate][0] .' ', 'Crates']], {})
endfunction

function! s:make_request(crate, vers, lnum) abort
  let url = printf('%s/crates/%s/versions', s:api_crates, a:crate)
  let cmd = ['curl', '-sL', url]
  let job_id = jobstart(cmd, {
        \ 'crate':     a:crate,
        \ 'vers':      a:vers,
        \ 'lnum':      a:lnum,
        \ 'verbose':   &verbose,
        \ 'stdoutbuf': [''],
        \ 'on_stdout': function('s:job_callback_nvim_stdout'),
        \ 'on_exit':   function('s:job_callback_nvim_exit'),
        \ })
endfunction

function! s:crates() abort
  let b:crates = {}

  let lnum = 0
  let in_dep_section = 0

  for line in getline(1, '$')
    if line =~# '^\[.*dependencies\]$'
      let in_dep_section = 1
    elseif line[0] == '#'
    elseif empty(line)
      let in_dep_section = 0
    elseif in_dep_section
      let [crate, vers] = s:cargo_file_parse_line(line)
      call s:make_request(crate, vers, lnum)
    endif
    let lnum += 1
  endfor
endfunction

command! Crates call s:crates()

let g:loaded_crates = 1
