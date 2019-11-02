if exists('g:loaded_crates')
  finish
endif

let s:api = 'https://api.github.com/repos/rust-lang/crates.io-index'

let s:crates = {}

" @return [valid_line, crate, version]
function! s:parse_line(line) abort
  let line = getline(a:line)
  if line =~ '^[a-z\-_]* = "'
    return matchlist(line, '^\([a-z\-_]\+\) = "\([0-9.]\+\)"')[1:2]
  else
    return matchlist(line, '^\([a-z\-_]\+\) = {.*version = "\([0-9.]\+\)"')[1:2]
  endif
endfunction

function! s:get_index_path(crate) abort
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

function! s:make_request(crate) abort
  let url = s:api .'/contents/'. s:get_index_path(a:crate)
  let cmd = 'curl -sLH "Accept: application/vnd.github.VERSION.raw" '. url
  return system(cmd)
endfunction

function! s:parse_cargo_file() abort
  let lnum = 1
  let lnums = []
  let in_dep_section = 0

  for line in getline(1, '$')
    if line =~# '^\[.*dependencies\]$'
      let in_dep_section = 1
    elseif empty(line)
      let in_dep_section = 0
    elseif in_dep_section

    endif
    let lnum += 1
  endfor

  return lnums
endfunction

function! s:get_versions(crate) abort
  let s:crates[a:crate] = map(split(s:make_request(a:crate)), 'json_decode(v:val).vers')
  echomsg string(s:crates[a:crate])
endfunction

function! s:crates() abort
  for lnum in s:cargo_dependency_sections_line_numbers()
    echomsg getline(lnum)
    " let [crate, vers] = s:parse_line(line('.'))
    " echomsg crate
  endfor
  " call s:get_versions(crate)

endfunction

command! Crates call s:crates()

let g:loaded_crates = 1
