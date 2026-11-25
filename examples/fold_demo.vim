" 用于验证 Vim 语法折叠：function、augroup
" 注意：Vim 的语法折叠不覆盖 if/for 块，只折函数、augroup 等

if exists('g:loaded_fold_demo')
  finish
endif
let g:loaded_fold_demo = 1

function! s:sum_even(values) abort
  let total = 0

  for value in a:values
    if value % 2 != 0
      continue
    endif

    let total += value
  endfor

  return total
endfunction

function! s:classify(value) abort
  if a:value < 0
    return 'negative'
  elseif a:value == 0
    return 'zero'
  else
    return 'positive'
  endif
endfunction

function! FoldDemoPrint() abort
  let values = [1, 2, 3, 4, 5, 6, 7, 8]

  echo 'sum of even values: ' . s:sum_even(values)
  echo 'classify(-1) = ' . s:classify(-1)
  echo 'classify(0)  = ' . s:classify(0)
endfunction

augroup fold_demo
  autocmd!
  autocmd VimEnter * echo 'fold demo loaded'
augroup END
