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
"   3) 更新配置: bash vim-plug.sh config
"      （已有标记块时按标记整块替换为最新内容，块外配置不受影响）
" =============================================================================

" ---------------------------------------------------------------- 插件声明
" 内置插件无需在此声明；只有联网安装的插件才写进下面这段
if !empty(globpath(&runtimepath, 'autoload/plug.vim'))
    call plug#begin()

    " Plug 'preservim/nerdtree'      " 已改为仓库内置，见 pack/vendor/start/nerdtree
    " Plug 'ryanoasis/vim-devicons'  " 文件图标：需要终端字体为 Nerd Font，否则每个文件前显示方块

    call plug#end()
endif

" ---------------------------------------------------------------- 基础设置
" 终端鼠标：点击定位、可视选择、拖动窗口分隔线；VSCode 内置终端同样生效
" 编译时未启用 +mouse 的版本自动跳过，避免报错
if has('mouse')
    set mouse=a
endif

" 右下角显示未完成的命令，例如 <Leader> 后等待输入、输入数字前缀时
set showcmd

" 左侧显示绝对行号；NERDTree 自己会 setlocal nonumber，不受影响
set number

" ---------------------------------------------------------------- 快捷键
" Ctrl+Z 撤销（默认是挂起到后台），与多数编辑器习惯一致；重做仍是 Ctrl+R
nnoremap <C-z> u
inoremap <C-z> <C-o>u
" 可视模式里 u 是转小写，先退出可视再撤销
xnoremap <C-z> <Esc>u

" Ctrl+S 保存；终端若把 Ctrl+S 当流控（界面卡住），在 shell 里执行 stty -ixon
nnoremap <silent> <C-s> :write<CR>
inoremap <silent> <C-s> <C-o>:write<CR>
xnoremap <silent> <C-s> <Esc>:write<CR>

" ---------------------------------------------------------------- 文件树
let NERDTreeShowHidden = 1
let NERDTreeWinSize    = 30
let NERDTreeMinimalUI  = 1
let NERDTreeIgnore     = ['\.git$', 'node_modules$', '__pycache__$', '\.pyc$']

nnoremap <silent> <C-n> :NERDTreeToggle<CR>
nnoremap <silent> <C-f> :NERDTreeFind<CR>

" 无参数启动时自动打开文件树；NERDTree 未安装则退回 netrw
autocmd VimEnter * if argc() == 0 && exists(':NERDTree') == 2 | NERDTree | wincmd p | endif

" ---------------------------------------------------------------- 状态栏
" airline 由 Vim 8 原生 pack 加载，配置需在插件加载前写入；
" 用 packpath 判断是否已 link，未接入时不设置 noshowmode，避免看不到模式
if !empty(globpath(&packpath, 'pack/vendor/start/vim-airline'))
    set noshowmode

    let g:airline_powerline_fonts = 0                  " 终端没装 Nerd Font，用 Unicode 分隔符
    let g:airline_theme = 'dark'                       " airline 自带主题，不需要 vim-airline-themes
    let g:airline#extensions#tabline#enabled = 1       " 顶部 buffer 列表，airline 的招牌功能
    let g:airline#extensions#tabline#formatter = 'unique_tail_improved'
    let g:airline#extensions#whitespace#enabled = 0

    " 默认行号符号是 ㏑ / ≡ / ℅，换成朴素的 1/37:1；
    " 必须先建字典再赋值，此时 g:airline_symbols 还不存在，直接赋值会 E121 中断后续配置
    let g:airline_symbols = get(g:, 'airline_symbols', {})
    let g:airline_symbols.linenr = ''
    let g:airline_symbols.maxlinenr = ''
    let g:airline_symbols.colnr = ':'
endif

" ---------------------------------------------------------------- netrw 兜底
let g:netrw_banner       = 0
let g:netrw_liststyle    = 3
let g:netrw_browse_split = 0
let g:netrw_winsize      = 25
