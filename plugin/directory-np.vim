" https://github.com/tpope/vim-unimpaired/blob/master/plugin/unimpaired.vim

function! s:entries(path) abort
  let path = substitute(a:path,'[\\/]$','','')
  let files = split(glob(path."/.*"),"\n")
  let files += split(glob(path."/*"),"\n")
  call map(files,'substitute(v:val,"[\\/]$","","")')
  call filter(files,'v:val !~# "[\\\\/]\\.\\.\\=$"')

  let filter_suffixes = substitute(escape(&suffixes, '~.*$^'), ',', '$\\|', 'g') .'$'
  call filter(files, 'v:val !~# filter_suffixes')

  return sort(files)
endfunction

function! s:FileByOffset(num) abort
  let file = expand('%:p')
  if empty(file)
    let file = getcwd() . '/'
  endif
  let num = a:num
  while num
    let files = s:entries(fnamemodify(file,':h'))
    if a:num < 0
      call reverse(filter(files,'v:val <# file'))
    else
      call filter(files,'v:val ># file')
    endif
    let temp = get(files,0,'')
    if empty(temp)
      let file = fnamemodify(file,':h')
    else
      let file = temp
      let found = 1
      while isdirectory(file)
        let files = s:entries(file)
        if empty(files)
          let found = 0
          break
        endif
        let file = files[num > 0 ? 0 : -1]
      endwhile
      let num += (num > 0 ? -1 : 1) * found
    endif
  endwhile
  return file
endfunction

function! s:fnameescape(file) abort
  if exists('*fnameescape')
    return fnameescape(a:file)
  else
    return escape(a:file," \t\n*?[{`$\\%#'\"|!<")
  endif
endfunction

function! s:GetWindow() abort
  if exists('*getwininfo') && exists('*win_getid')
    return get(getwininfo(win_getid()), 0, {})
  else
    return {}
  endif
endfunction

function! s:PreviousFileEntry(count) abort
  let window = s:GetWindow()

  if get(window, 'quickfix')
    return 'colder ' . a:count
  elseif get(window, 'loclist')
    return 'lolder ' . a:count
  else
    return 'edit ' . s:fnameescape(fnamemodify(s:FileByOffset(-v:count1), ':.'))
  endif
endfunction

function! s:NextFileEntry(count) abort
  let window = s:GetWindow()

  if get(window, 'quickfix')
    return 'cnewer ' . a:count
  elseif get(window, 'loclist')
    return 'lnewer ' . a:count
  else
    return 'edit ' . s:fnameescape(fnamemodify(s:FileByOffset(v:count1), ':.'))
  endif
endfunction

nnoremap <silent> <Plug>(unimpaired-directory-next)     :<C-U>execute <SID>NextFileEntry(v:count1)<CR>
nnoremap <silent> <Plug>(unimpaired-directory-previous) :<C-U>execute <SID>PreviousFileEntry(v:count1)<CR>
