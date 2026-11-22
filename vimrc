" =============================================================================
" my-vim 基础配置片段
" 作者: 苏木
" 说明: 依赖 vim-plug，插件声明区写在下方，首次使用需执行 :PlugInstall
"
" 用法:
"   1) 单独使用: cp vimrc ~/.vimrc
"   2) 追加使用: bash vim-plug.sh --vim --with-config
"      （脚本会在本文件内容前后加标记，卸载时按标记整块删除）
" =============================================================================

" ---------------------------------------------------------------- 插件声明
" 插件目录默认: Vim 为 ~/.vim/plugged，Neovim 为 ~/.local/share/nvim/plugged
call plug#begin()

Plug 'preservim/nerdtree'
" Plug 'ryanoasis/vim-devicons'   " 文件图标：需要终端字体为 Nerd Font，否则每个文件前显示方块，按需启用

call plug#end()

" ---------------------------------------------------------------- 文件树
let NERDTreeShowHidden = 1
let NERDTreeWinSize    = 30
let NERDTreeMinimalUI  = 1
let NERDTreeIgnore     = ['\.git$', 'node_modules$', '__pycache__$', '\.pyc$']

nnoremap <silent> <C-n> :NERDTreeToggle<CR>
nnoremap <silent> <C-f> :NERDTreeFind<CR>

" 无参数启动时自动打开文件树；NERDTree 未安装则退回 netrw
autocmd VimEnter * if argc() == 0 && exists(':NERDTree') == 2 | NERDTree | wincmd p | endif

" ---------------------------------------------------------------- netrw 兜底
let g:netrw_banner       = 0
let g:netrw_liststyle    = 3
let g:netrw_browse_split = 0
let g:netrw_winsize      = 25
