" =============================================================================
" my-vim 基础配置片段
" 作者: 苏木
" 说明:
"   - NERDTree 已内置在仓库 pack/vendor/start/ 下，执行 ./vim-plug.sh link 后
"     由 Vim 8 原生 pack 机制自动加载，离线可用，不需要 :PlugInstall
"   - vim-plug 仅用于以后联网安装其他插件，未安装时本文件也能正常启动
"
" 用法:
"   1) 单独使用: cp vimrc ~/.vimrc
"   2) 追加使用: bash vim-plug.sh --vim --with-config
"      （脚本会在本文件内容前后加标记，卸载时按标记整块删除）
" =============================================================================

" ---------------------------------------------------------------- 插件声明
" 内置插件无需在此声明；只有联网安装的插件才写进下面这段
if !empty(globpath(&runtimepath, 'autoload/plug.vim'))
    call plug#begin()

    " Plug 'preservim/nerdtree'      " 已改为仓库内置，见 pack/vendor/start/nerdtree
    " Plug 'ryanoasis/vim-devicons'  " 文件图标：需要终端字体为 Nerd Font，否则每个文件前显示方块

    call plug#end()
endif

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
