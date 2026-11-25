<!-- more -->

本文面向已经会用 Vim 基本操作、但没弄明白"插件为什么能被加载"的读者，从磁盘目录、加载时机和命名约定三个角度拆解 Vim 的插件系统，再落到 Vim 8 原生包机制、vim-plug 的实现原理和手写插件的最小骨架。文中示例尽量对应本仓库的 [`vimrc`](../vimrc)、[`vim-plug.sh`](../vim-plug.sh) 与 `pack/vendor/start` 布局。

## 一、 认识 Vim 的插件系统

### 1. 插件到底是什么

#### 1.1 插件的物理形态

Vim 没有统一的插件封装格式，一个插件就是**一个目录**，里面按约定放若干 `.vim` 脚本。最简单的插件只有一个文件：

```text
hello-vim/
└── plugin/hello.vim
```

完整一些的插件会用到多个子目录：

```text
hello-vim/
├── plugin/hello.vim          " 启动即加载：命令、映射、autocmd
├── autoload/hello.vim        " 首次调用 hello#... 时加载
├── ftplugin/markdown.vim     " filetype=markdown 时加载
├── syntax/markdown.vim       " 语法高亮定义
├── doc/hello.txt             " :help hello 的正文
└── after/plugin/hello.vim    " 在其它插件之后执行
```

把这个目录放到 `'runtimepath'` 中任一条目之下，Vim 就会按固定规则找到并执行其中的脚本。`'runtimepath'`（运行时路径，官方短选项名 `rtp`，`:set rtp?`、`&rtp` 中即用此名）是 Vim 的搜索路径，作用类似 shell 的 `PATH`：一个有序的目录列表，Vim 只在其中查找插件、语法、配色和帮助文档。除此之外，不存在注册表、清单文件或二进制接口。

#### 1.2 没有插件 API，只有装载约定

与 VS Code 这类编辑器不同，Vim 不要求插件提供 `package.json` 式的清单，也没有 `activate()` 回调。Vim 与插件之间的"接口"完全由下面三件事构成：

- **目录约定**：`plugin/`、`autoload/`、`ftplugin/`、`syntax/` 等子目录名本身就是回调点。
- **命名约定**：`autoload/foo/bar.vim` 与函数 `foo#bar#baz()` 一一对应，`ftplugin/python.vim` 与 `filetype=python` 一一对应。
- **装载约定**：谁来 source 这个文件、在什么时机 source，由 Vim 内置的装载脚本和事件机制决定。

因此在本系列语境下，三个动作可以这样理解：

（1）"安装插件"：让插件目录出现在 `rtp` 中（或出现在 `packpath` 下等待 `:packadd`）。

（2）"启用插件"：让 Vim 的某个装载器 source 到它，例如启动期扫描 `plugin/`，或首次调用 autoload 函数。

（3）"配置插件"：在脚本被 source 之前或之后，设置它能读到的全局变量、选项或映射。

#### 1.3 插件能力的来源与边界

插件脚本运行在 Vim 自己的解释器里，能做的事情和 `vimrc` 完全一样：

- 定义 Ex 命令、键映射、自动命令；
- 读写选项、全局变量、缓冲区局部变量；
- 定义函数、补全函数（`omnifunc`、`completefunc`）、操作符函数（`operatorfunc`）；
- 定义语法高亮、缩进规则、文件类型检测；
- 通过 `system()`、`job_start()` 调用外部程序，甚至通过 `+python3`、`+lua` 等可选特性嵌入其它语言。

【**一则提醒**】

能力等价也意味着风险等价：插件可以覆盖你的映射、改掉你的选项、拖慢启动，甚至因为一个循环把 Vim 卡死。Vim 没有沙箱，插件质量只能靠作者自律和使用者审阅。

### 2. 支撑插件系统的三个机制

#### 2.1 目录约定：`'runtimepath'` 是唯一入口

前面已经说明，`'runtimepath'`（官方短选项名 `rtp`）是 Vim 的搜索路径。它由多个目录按顺序拼成，每一项都是一个"运行时目录"；Vim 只在这些目录下按固定名字查找子目录，不在列表中的目录根本不会被扫描：

```text
~/.vim/            ← rtp 中的一项
├── plugin/        ← 启动期 source 的目录
├── autoload/      ← 按函数名惰性加载的目录
├── ftplugin/      ← 跟随文件类型加载的目录
└── ...
```

换句话说，**目录名就是 API**：把 `autoload/` 改名为 `lib/`，`hello#greet()` 立刻报 `E117: Unknown function`。

#### 2.2 时机约定：启动批次与事件驱动

同一份脚本放在不同目录，加载时机完全不同：

| 目录 | 加载时机 | 由谁触发 |
| --- | --- | --- |
| `plugin/` | 启动期，读完 vimrc 之后 | Vim 启动流程 |
| `pack/*/start/*/plugin/` | 启动期，普通 `plugin/` 之后 | `:packloadall` |
| `after/plugin/` | 启动期，最后一批 | Vim 启动流程 |
| `autoload/` | 首次调用对应函数 | Vim 的函数查找 |
| `ftplugin/`、`indent/` | `FileType` 事件 | `$VIMRUNTIME/ftplugin.vim` 等装载脚本 |
| `syntax/` | `Syntax` 事件或 `:syntax on` | `$VIMRUNTIME/syntax/synload.vim` |
| `ftdetect/` | `:filetype on` 时 | `$VIMRUNTIME/filetype.vim` |

前几类属于"启动批次"，后几类属于"事件驱动"。理解这张表，就理解了 Vim 插件系统一半的原理。

#### 2.3 命名约定：autoload 的惰性绑定

`autoload` 是 Vim 里最优雅的设计之一。当脚本中出现一个带 `#` 的函数调用：

```vim
" 调用方
call hello#greet('Vim')
```

Vim 在函数名不存在时，会把 `#` 当作路径分隔符，去 `rtp` 中查找 `autoload/hello.vim`，source 它，然后再次查找 `hello#greet`。规则可以总结为：

- 函数名 `a#b#c()` 对应文件 `autoload/a/b.vim`；
- 一个 autoload 文件只需要第一次被加载，之后一直可用；
- 读取一个从未赋值的 autoload 变量（如 `hello#name`）同样会触发文件加载，但给这类变量赋值不会触发；
- 文件被 source 后函数仍不存在，就会抛 `E117`。

这使得插件的绝大部分代码可以推迟到"真正用到"的一刻，`plugin/` 里只留几行命令和映射的声明。

### 3. 启动期的加载流水线

#### 3.1 官方定义的启动顺序

Vim 启动时与插件相关的步骤可以简化为：

（1）读取 vimrc：系统 vimrc → 用户 vimrc → 当前目录的 `.exrc`/`.vimrc`（若允许）。

（2）执行 `:runtime! plugin/**/*.vim`：按 `rtp` 顺序逐个目录扫描，目录内按字母序，递归扫描子目录，**跳过以 `after` 结尾的目录**。

（3）加载 packages：把 `packpath` 下 `pack/*/start/*` 找到的所有包目录加入 `rtp`，然后再 source 这些包里的 `plugin/` 脚本。

（4）再次执行与第（2）步相同的扫描，但这次**只处理 `after` 目录**。

（5）读取命令行指定的文件，触发 `BufRead` 等事件，最后触发 `VimEnter`。

写成流程图更直观：

```text
vim 启动
  ├─ 1. 读 vimrc（系统 → 用户 → exrc）
  ├─ 2. source rtp 中所有 plugin/**/*.vim（跳过 after）
  ├─ 3. 加载 pack/*/start：先全部加入 rtp，再 source 其 plugin
  ├─ 4. source rtp 中所有 after/plugin/**/*.vim
  └─ 5. 读文件 → BufRead/BufEnter → 最后 VimEnter
```

【**关键点**】

插件脚本整体晚于 vimrc，早于文件读取。这个次序决定了后面所有的配置写法与踩坑模式。

#### 3.2 三个启动批次

| 批次 | 来源 | 特点 |
| --- | --- | --- |
| 第一批 | `rtp` 中所有 `plugin/`（不含 after） | 数量最多，决定启动耗时 |
| 第二批 | `pack/*/start/*` | 包目录先加入 `rtp`，再加载脚本 |
| 第三批 | 所有 `after/plugin/` | 用户 `~/.vim/after` 通常最后 |

这三批之外，`ftplugin/`、`autoload/` 等并不在启动时执行，它们属于"用到才加载"。

#### 3.3 时序带来的配置约束

由于插件脚本在 vimrc 之后执行，vimrc 中写的设置可能被插件自己的默认值覆盖。常见两类写法：

（1）**配置变量必须早于插件加载**。例如插件在 `plugin/xxx.vim` 里读取 `g:xxx_option`，那么 `let g:xxx_option = 1` 必须写在 vimrc 中插件被 source 之前。使用 vim-plug 时，写在 `plug#end()` 之前即可。

（2）**需要"最后生效"的设置放进 `after/plugin/`**。例如想覆盖某个插件对 `'laststatus'`、高亮组或映射的修改，放在 `~/.vim/after/plugin/myfix.vim` 里最稳妥，因为它属于第三批。

反过来，如果某个设置必须在插件定义映射之前生效（比如先定义 `<Plug>` 映射的替代键位），把它放在 `plugin/` 里反而更早。

#### 3.4 关闭插件加载的方式

| 方式 | 效果 | 典型用途 |
| --- | --- | --- |
| `--noplugin` | 读 vimrc，但不加载任何插件 | 排查插件问题 |
| `--clean` | 不读用户配置，不加载插件，接近默认状态 | 建立干净基线 |
| `-u NONE` | 不读任何 vimrc，也不加载插件 | 最小复现 |
| `set noloadplugins` | 关闭 `'loadplugins'` 选项 | 写在 vimrc 里临时禁用 |
| 编译时无 `+eval` | 所有插件脚本都无法执行 | 精简版 Vim |

【**注意**】

用 `-c 'set noloadplugins'` 关闭插件是无效的，因为命令行上的 `-c` 命令要等启动流程结束后才执行；必须用 `--cmd 'set noloadplugins'`，或直接写进 vimrc。

## 二、 runtimepath 与目录约定

### 1. runtimepath 详解

#### 1.1 选项值与默认值

这个选项的默认值由 Vim 帮助定义，Unix 下的默认列表如下：

```text
$HOME/.vim 或 $XDG_CONFIG_HOME/vim,
$VIM/vimfiles,
$VIMRUNTIME,
$VIM/vimfiles/after,
$HOME/.vim/after
```

其中 `$VIMRUNTIME` 指向 Vim 自带的运行时目录（例如 `/usr/share/vim/vim91`），`$VIM` 是安装前缀。发行版往往会追加自己的目录，例如 Debian 会加入 `/etc/vim` 与 `/var/lib/vim/addons`。因此**不要背默认值，用命令查看**：

```vim
:set runtimepath?
:set packpath?
```

本机（Debian 的 Vim 9.1）普通启动时输出为：

```text
runtimepath=~/.vim,/var/lib/vim/addons,/etc/vim,/usr/share/vim/vimfiles,/usr/share/vim/vim91,/usr/share/vim/vimfiles/after,/etc/vim/after,/var/lib/vim/addons/after,~/.vim/after
```

用 `vim --clean` 启动时 `~/.vim` 会被精简掉，只留系统目录。可见 `rtp` 的实际内容受发行版配置和启动参数影响，**以实际启动下的 `:set rtp?` 为准**。`'packpath'` 的默认值与 `'runtimepath'` 相同，但两个选项相互独立，修改其中一个不会自动影响另一个。

#### 1.2 顺序即优先级

`rtp` 是一个有序列表，顺序决定三件事：

- **执行顺序**：`plugin/` 里的脚本按目录顺序依次 source，越靠前越先执行；
- **查找优先级**：`autoload/`、`colors/`、`doc/` 等"按名字找文件"的场景，只取第一个命中的文件；
- **覆盖关系**：后执行的脚本可以覆盖先执行脚本定义的命令、映射和函数。

列表的头尾尤其重要。默认情况下 `~/.vim` 在开头，`~/.vim/after` 在结尾。由此产生两条实践规则：

（1）`set rtp+=~/myplugin` 是追加到**列表末尾**，也就是排在 `~/.vim/after` 之后。它优先级最低，任何 after 脚本都能覆盖它。

（2）`set rtp^=~/myplugin` 是插到**列表开头**，优先级最高，但会抢在 `~/.vim` 之前，通常只在调试时使用。

#### 1.3 修改 rtp 的正确写法

```vim
" 追加（优先级最低，位于 after 之后）
set runtimepath+=~/src/hello-vim

" 前插（优先级最高）
set runtimepath^=~/src/hello-vim

" 移除某个条目
set runtimepath-=~/src/hello-vim
```

几个容易忽略的细节：

- 路径中有空格或逗号时，需要用反斜杠转义逗号（`\,`），否则会被拆成多项；
- 修改 `rtp` 后不会自动重新加载插件，需要新开 Vim，或手动 `:source` 目标脚本；
- 开发插件时更推荐 `set rtp+=...` 临时挂载源码目录，验证完再做成包或交给插件管理器；
- `rtp` 越长，每次 `:runtime`、`:find`、`autoload` 查找的线性扫描成本越高，启动和运行都会变慢。

### 2. 各子目录的职责与加载时机

先给一张总表，后文逐项展开：

| 目录 | 加载时机 | 匹配方式 |
| --- | --- | --- |
| `plugin/` | 启动期 | 递归匹配所有 `.vim`，全部 source |
| `autoload/` | 首次调用对应函数 | 按函数名定位单个文件，首个命中生效 |
| `ftplugin/` | `FileType` 事件 | `runtime!` 全部匹配，靠 `b:did_ftplugin` 守卫 |
| `indent/` | `FileType` 事件 | 同上，靠 `b:did_indent` 守卫 |
| `syntax/` | `Syntax` 事件 | 全部匹配，靠 `b:current_syntax` 守卫 |
| `ftdetect/` | `:filetype on` 时 | 全部 source，用于注册检测规则 |
| `after/` | 各装载器的最后一批 | 取决于装载器，无独立语法 |

#### 2.1 plugin/：启动即执行

```vim
" plugin/hello.vim
command! Hello echo 'hello'
nnoremap <silent> <Plug>(hello-greet) :<C-U>echo 'hello'<CR>
```

装载规则是 `:runtime! plugin/**/*.vim`：`rtp` 每一项下的 `plugin` 目录都会被扫描，递归进入子目录，目录内按字母序 source，所有匹配文件都会执行，不是"首个命中即停"。

这个目录只适合放**轻量且必须全局生效**的定义：

- 命令、键映射、自动命令；
- 全局默认变量（如 `let g:hello_greeting = get(g:, 'hello_greeting', 'Hello')`）；
- 文件类型检测之外的少量初始化逻辑。

不适合放耗时操作。启动期每个插件都在抢这几十毫秒，把重活放在 `plugin/` 会直接拉长 `vim` 的启动时间；这类逻辑应当下沉到 `autoload/`，由第一次真正使用时加载。

还要注意 `plugin/` 脚本可能被重复 source（手动 `:source`、重新执行 vimrc、叫 `s:reload_plugins` 的管理器）。因此定义命令要用 `command!`，注册自动命令要用 `augroup` + `autocmd!`，否则会叠加出重复行为。

#### 2.2 autoload/：按名字惰性加载

```vim
" autoload/hello.vim
function! hello#greet(name) abort
  echo printf('Hello, %s!', a:name)
endfunction
```

```vim
" plugin/hello.vim
command! -nargs=1 Hello call hello#greet(<f-args>)
```

只有第一次执行 `:Hello` 时，Vim 才会去 `rtp` 中查找 `autoload/hello.vim` 并 source。加载后 `:scriptnames` 才会出现这一项。

这个机制带来两个直接收益：

（1）启动时零成本：几千行插件代码可以完全推迟到第一次使用；

（2）命名空间天然隔离：`foo#`、`bar#` 前缀避免函数名冲突，也避免了全局函数污染。

常见的失败原因是命名不一致，例如把 `hello#say_hi()` 定义在 `autoload/say.vim` 中（正确位置应是 `autoload/hello.vim`），或者文件里中途 `finish` 导致函数没定义，最终都会得到 `E117`。排查时用 `:verbose function hello#greet` 与 `:scriptnames` 对照即可。

#### 2.3 ftplugin/、indent/、syntax/：跟随文件类型

这三类目录都不在启动期加载，而是由 `FileType` 事件驱动。链路如下：

（1）`ftdetect/` 中的规则根据文件名或内容设置 `'filetype'`；

（2）Vim 触发 `FileType` 事件；

（3）`$VIMRUNTIME/ftplugin.vim` 注册的自动命令执行 `runtime! ftplugin/<ft>.vim ftplugin/<ft>_*.vim ftplugin/<ft>/*.vim`；

（4）`$VIMRUNTIME/indent.vim` 同理加载 `indent/<ft>.vim`；

（5）语法高亮由 `Syntax` 事件加载 `syntax/<ft>.vim`。

要启用这些装载器，`vimrc` 中必须有：

```vim
filetype plugin indent on
syntax on
```

`filetype plugin on` 与 `filetype indent on` 会顺带打开文件类型检测；`syntax on` 则安装语法高亮的自动命令并立即高亮当前缓冲区。

由于装载器使用 `runtime!`（加载所有匹配），同一文件类型的多个实现会**按 rtp 顺序全部尝试 source**，官方模板用守卫变量让第一个真正生效：

```vim
" ftplugin/markdown.vim
if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal wrap linebreak
let b:undo_ftplugin = 'setlocal wrap< linebreak<'
```

`b:undo_ftplugin` 记录撤销命令，当缓冲区切换文件类型时，装载器会先执行它，把上一套设置恢复干净。`indent/` 使用同样的 `b:did_indent` 与 `b:undo_indent` 机制，`syntax/` 则使用 `b:current_syntax`。

`after/ftplugin/` 目录因为位于 `rtp` 末尾，会在普通 `ftplugin/` 之后被 source；典型用法是不写守卫、直接追加设置，用来覆盖官方或插件的默认值。

#### 2.4 ftdetect/：文件类型识别的第一站

```vim
" ftdetect/hello.vim
augroup filetypedetect
  autocmd BufRead,BufNewFile *.hello setfiletype hello
augroup END
```

`ftdetect/` 下的脚本在 `:filetype on` 时被 source，作用只是注册自动命令。之后打开文件时，这些命令根据文件名或内容决定 `'filetype'`。

有两点需要注意：

- 必须使用 `augroup filetypedetect`，否则重复加载会叠加规则；
- `ftdetect/` 不能懒加载。文件类型识别必须发生在任何 `ftplugin/` 逻辑之前，所以即使插件本身按需加载，它的 `ftdetect/` 也要提前执行。vim-plug 的 `for` 选项就是专门为解决这个问题而设计的。

#### 2.5 doc/、colors/、compiler/ 等外围目录

| 目录 | 用途 | 触发方式 |
| --- | --- | --- |
| `doc/` | `:help` 正文与标签 | `:helptags` 生成 `doc/tags` |
| `colors/` | 配色方案 | `:colorscheme <name>` |
| `compiler/` | 编译器配置（`makeprg`、`errorformat`） | `:compiler <name>` |
| `keymap/` | 非拉丁键盘布局 | 设置 `'keymap'` 选项时加载 |
| `lang/` | 菜单与消息翻译 | 由 `bindtextdomain()` 定位 |
| `import/` | Vim9 的 `:import` 模块（非 autoload） | 首次执行 `import` 时 |
| `lua/` | Neovim 的 Lua 模块 | `require()` 时 |

`doc/` 值得单独说明：`:help` 依赖 `doc/tags` 索引文件，它不会自动生成。插件作者通常随包提交生成好的 `doc/tags`；通过 git 安装的插件则需要安装器执行 `:helptags`，vim-plug 的 `plug#helptags()` 就是做这件事的。

#### 2.6 after/：压轴覆盖

`after/` 没有任何特殊语法，它之所以"最后生效"，唯一原因是它位于 `rtp` 中靠后的位置（默认 `~/.vim/after` 是最后一项）。装载器按 `rtp` 顺序执行，自然最后轮到它。

它适合覆盖三类内容：

- `after/plugin/`：覆盖插件对选项、映射、自动命令的设置；
- `after/ftplugin/`：在官方 `ftplugin` 之后追加或修正设置；
- `after/syntax/`：在高亮定义之后追加高亮规则。

它**不适合**覆盖 `autoload/`。原因在于 `autoload` 是"按函数名找文件，首个命中即停"，而 `after/autoload` 排在最后，永远轮不到它。想替换 autoload 函数，只能使用同名函数覆盖（`function!`）或在加载前修改 `rtp` 顺序。

### 3. 加载顺序与覆盖规则

#### 3.1 三层顺序

```text
第一层：rtp 列表顺序（~/.vim → $VIMRUNTIME → ... → ~/.vim/after）
第二层：每个目录内部的字母序（plugin/a.vim 先于 plugin/b.vim）
第三层：同一加载器的多轮扫描（普通目录 → after 目录）
```

三层叠加后，最终的执行顺序是确定的，但不再直观。排查时以 `:scriptnames` 的实际编号为准，不要凭直觉推断。

#### 3.2 同名定义的覆盖行为

| 定义方式 | 覆盖规则 | 说明 |
| --- | --- | --- |
| `command Foo` | 后定义者覆盖，但需要用 `command!` | 不加 `!` 会报 `E174` |
| `nnoremap` | 后定义者覆盖 | 映射无"重复"报错 |
| `function!` | 后定义者覆盖 | 不加 `!` 重定义会报 `E122` |
| `autoload` 文件 | 首个命中生效 | `after/autoload` 不会覆盖 |
| `ftplugin` 文件 | 全部 source，靠 `b:did_ftplugin` 守卫生效 | after 版本通常不设守卫 |
| `syntax` 文件 | 全部 source，靠 `b:current_syntax` 守卫生效 | after 版本追加规则 |

#### 3.3 用 after/ 覆盖的正确姿势

```vim
" ~/.vim/after/plugin/myfix.vim
" 该文件在第三批加载，可以稳定覆盖前两批的设置
set laststatus=2
highlight Comment ctermfg=gray
```

如果覆盖不生效，先用 `:scriptnames` 确认该文件确实被加载，再用 `:verbose set laststatus?` 查看"最后设置者"是否另有其人。

## 三、 Vim 8 原生包管理（packages）

### 1. 包与插件的区别

Vim 8 引入的 package（包）不是新格式，只是"装插件的目录约定"：

- 一个包是一个独立目录，可以包含一个或多个插件；
- 整个包可以是一个 git 仓库，更新时 `git pull` 即可；
- 包内的多个插件可以相互依赖；
- 包可以同时包含"启动即加载"和"按需加载"的插件。

它解决的是"插件文件混在 `~/.vim` 根目录、难以更新和卸载"的问题，而不是加载机制本身。

### 2. 目录布局与 packpath

```text
~/.vim/pack/<包组>/start/<插件>/     " 启动时自动加载
~/.vim/pack/<包组>/opt/<插件>/       " 手动 :packadd 才加载
```

- `<包组>` 是任意名字，只用于分组，例如 `vendor`、`themes`、`lsp`；
- `'packpath'` 决定去哪里找 `pack` 目录，默认与 `rtp` 相同；
- Vim 自带一批可选包，位于 `$VIMRUNTIME/pack/dist/opt`（例如 `comment`、`editorconfig`），需要用 `:packadd` 手动加载。

一个典型布局：

```text
~/.vim/pack/vendor/start/nerdtree/plugin/NERD_tree.vim
~/.vim/pack/vendor/start/vim-airline/plugin/airline.vim
~/.vim/pack/themes/opt/onedark/colors/onedark.vim
```

### 3. start 包的自动加载

#### 3.1 两步加载：先加 rtp，再 source

启动流程中的 packages 阶段分两步执行：

（1）扫描 `packpath` 下所有 `pack/*/start/*` 目录，把它们**全部**加入 `rtp`；

（2）再 source 这些目录里的 `plugin/**/*.vim`。

官方把这称为两步加载（packload-two-steps）。两步之间留出的窗口，让 A 包的 `plugin/` 脚本可以调用 B 包的 autoload 函数——此时 B 包的目录已经在 `rtp` 里了，即使 B 包的 `plugin/` 还没执行。

#### 3.2 包内 autoload 依赖为何能成立

假设 `foo` 包的插件脚本里写了：

```vim
" pack/foo/start/foo/plugin/foo.vim
call bar#init()
```

而 `bar#init()` 定义在另一个包的 `pack/bar/start/bar/autoload/bar.vim` 中。由于第一步已经把所有 start 目录加入 `rtp`，`autoload/bar.vim` 可以被查找到并加载，不依赖于 `bar` 包的 `plugin/` 脚本是否已经执行。

#### 3.3 加载顺序

实测（Vim 9.1，`rtp` 为 `~/.vim,$VIMRUNTIME,~/.vim/after`）包加载后的顺序是：

```text
~/.vim
~/.vim/pack/demo/start/foo
/usr/share/vim/vim91
~/.vim/pack/demo/start/foo/after
~/.vim/after
```

由此可以得出：

- 包目录被插入到 `rtp` 前部（`$VIMRUNTIME` 之前），因此包可以覆盖 Vim 自带的运行时文件；
- 包自带的 `after` 目录排在用户 `~/.vim/after` 之前，所以用户的 after 仍然拥有最终决定权；
- 启动时先执行 `~/.vim/plugin`，再执行包内 `plugin`，最后统一执行所有 after 脚本。

Vim 帮助提到包的 `after` 目录"通常没有用处"（但并未禁止），它更适合作为包内多个插件之间的统一收尾。

### 4. opt 包与 :packadd

#### 4.1 packadd 做了什么

```vim
:packadd onedark
```

该命令按以下步骤工作：

（1）在 `packpath` 下的 `pack/*/opt/<name>` 中查找目录（若启动时跳过了 start 包加载，则先找 `pack/*/start/<name>`）；

（2）若目录还不在 `rtp` 中，把它加入；若存在 `<name>/after`，则追加到 `rtp` 末尾；

（3）source 该目录下所有 `plugin/**/*.vim`。

#### 4.2 packadd! 与重复调用

- `:packadd! <name>` 只把目录加入 `rtp`，不 source 插件脚本，适合"先让 autoload 可见，稍后真正加载"的场景；
- `:packadd` 不会重复添加同一个 `rtp` 条目，但**每次调用都会重新 source 插件脚本**。实测对同一 opt 包执行两次 `:packadd`，`plugin/` 脚本中的计数器会变成 2。因此不要在 `CursorHold` 这类高频自动命令里无条件 `packadd`，应加状态守卫或使用 `++once`。

#### 4.3 用 packadd 实现懒加载

原生包机制已经足够做懒加载，只是需要自己写触发条件：

```vim
" 启动后再加载，避免拖慢启动
augroup my_lazy
  autocmd!
  autocmd VimEnter * ++nested packadd onedark
augroup END
```

```vim
" 第一次使用某命令时加载
command! -nargs=0 -bar Theme packadd onedark | colorscheme onedark
```

```vim
" 打开特定文件类型时加载
augroup my_lazy_ft
  autocmd!
  autocmd FileType rust ++once packadd rust-vim
augroup END
```

`packadd` 之后，`ftplugin/`、`syntax/` 等由事件驱动的脚本需要重新触发事件才会执行，例如 `:doautocmd FileType rust` 或重新 `:setfiletype`。这正是插件管理器懒加载逻辑要额外处理的地方。

### 5. 本仓库的离线包实践

本仓库没有把插件装进 `~/.vim/plugged`，而是直接内置了符合 Vim 8 包结构的目录：

```text
pack/vendor/start/nerdtree/
pack/vendor/start/vim-airline/
```

首次使用时执行：

```bash
./vim-plug.sh link
```

脚本会把上述目录软链到 `~/.vim/pack/vendor/start/`（变量 `VIM_PACK_DEST` 定义在 [`vim-plug.sh`](../vim-plug.sh#L77)），Vim 启动时按原生包机制自动加载，因此**不需要联网，也不需要 `:PlugInstall`**。

配置侧也有配套判断。例如 [`vimrc`](../vimrc#L43) 用 `globpath(&packpath, 'pack/vendor/start/vim-airline')` 检测 airline 是否已接入，未接入就不设置 `'noshowmode'`，避免状态栏只剩空白：

```vim
" vimrc
if !empty(globpath(&packpath, 'pack/vendor/start/vim-airline'))
  set noshowmode
endif
```

验证方式：

```vim
:scriptnames          " 应能看到 pack/vendor/start/.../plugin/... 的条目
:set runtimepath?     " 应能看到包目录被加入
```

由于用的是软链接，链接悬空时插件会静默不加载，`./vim-plug.sh status` 可以检查悬空与缺失的链接。

## 四、 插件管理器的原理（以 vim-plug 为例）

### 1. 管理器要解决的四个问题

（1）**获取与更新**：从 git 仓库克隆、拉取、切换分支与提交。

（2）**装载编排**：把插件目录按确定顺序插入 `rtp`，并区分 after。

（3）**按需加载**：声明哪些插件在什么条件下才 source，避免启动期全部加载。

（4）**辅助工作**：生成 `doc/tags`、清理未声明目录、展示安装状态与差异、快照。

vim-plug 用单文件 `plug.vim` 实现了这四件事，因此非常适合学习原理。

### 2. 声明阶段

#### 2.1 声明入口做了哪些初始化

`plug#begin()` 做三件事：

- 确定插件安装根目录：优先使用参数传入的路径；否则读 `g:plug_home`；再否则 Neovim 用 `stdpath('data')/plugged`，Vim 用 `rtp` 第一项加 `/plugged`（默认即 `~/.vim/plugged`）；
- 初始化 `g:plugs`（插件名到配置的字典）与 `g:plugs_order`（声明顺序列表）；
- 定义 `:Plug`、`:PlugInstall`、`:PlugUpdate`、`:PlugClean`、`:PlugUpgrade`、`:PlugStatus`、`:PlugDiff`、`:PlugSnapshot` 等命令。

注意此时**没有下载任何插件，也没有修改 `rtp`**。

#### 2.2 Plug 命令只是登记

```vim
Plug 'tpope/vim-fugitive'
Plug 'rust-lang/rust.vim', { 'for': 'rust' }
Plug 'preservim/nerdtree', { 'on': '<Plug>(NERDTreeToggle)' }
```

每一行 `Plug` 只做解析与登记：

- 从仓库地址推导插件名（默认取最后一段并去掉 `.git`）；
- 计算安装目录 `g:plug_home/<name>`；
- 把 `{ 'on': ..., 'for': ... }` 等选项解析成字典，存入 `g:plugs`。

声明阶段是纯数据收集：`Plug` 只把条目登记进 `g:plugs`，不下载、不加载。因此这段区间里不要写耗时逻辑，只需保证所有 `Plug` 声明在 `plug#end()` 之前被执行到即可（放在 `if` 里按条件声明是允许的）。

#### 2.3 安装目录的推导

默认安装路径是 `~/.vim/plugged/<插件名>`。也可以显式指定：

```vim
call plug#begin('~/.vim/plugged')
```

若 `rtp` 第一项不是 `~/.vim`（例如某些发行版把 `~/.vim` 去掉了），vim-plug 会把第一项当作根，可能导致插件装到意外位置，此时应显式传入路径。

### 3. 收尾阶段

`plug#end()` 是 vim-plug 的核心，它做四件事。

#### 3.1 注册懒加载触发器

对带 `on` 或 `for` 选项的插件，`plug#end()` 会：

- 为 `on` 中的命令创建同名占位命令（`command! -nargs=* -range -bang ...`），首次调用时先加载插件；
- 为 `on` 中的 `<Plug>` 映射创建占位映射，首次按键时先加载插件；
- 为 `for` 中的文件类型注册 `autocmd FileType`，并**立即 source 该插件的 `ftdetect/`**，保证文件类型能被识别出来。

其中 `for` 的占位自动命令登记在 `PlugLOD` 组，`plug#end()` 开头会先清空该组；命令与映射占位则在触发时由 `s:remove_triggers()` 删除，两者都保证重复调用不会叠加。

#### 3.2 重排 runtimepath

未声明懒加载的插件会被标记为已加载，然后 [`s:reorg_rtp()`](../vendor/plug.vim#L539) 把 `rtp` 重排为：

```text
rtp 第一项（通常是 ~/.vim）
  → 已加载插件的目录
  → 原有 rtp 的其余部分（含 $VIMRUNTIME）
  → 已加载插件的 after 目录
  → rtp 最后一项（通常是 ~/.vim/after）
```

这解释了 vim-plug 插件为什么能覆盖 Vim 自带运行时，而用户的 `after` 又能覆盖所有插件。另外，对非懒加载插件，`plug#end()` 在调用时就把目录放进了 `rtp`，所以**启动期真正的 source 仍由 Vim 的启动流程完成，vim-plug 并没有自己 source 这些插件**。

#### 3.3 打开 filetype 与 syntax

```vim
" vendor/plug.vim
call s:reorg_rtp()
filetype plugin indent on
if has('vim_starting')
  if has('syntax') && !exists('g:syntax_on')
    syntax enable
  endif
else
  call s:reload_plugins()
endif
```

因此在 vimrc 中使用 vim-plug 后，不需要再手写 `filetype plugin indent on` 与 `syntax on`。`has('vim_starting')` 用于区分"启动期调用"与"运行期重新 source vimrc"：后者需要 vim-plug 手动重新 source 插件脚本。

#### 3.4 启动期与运行期的分叉

| 场景 | `plug#end()` 行为 |
| --- | --- |
| 启动期（vimrc 中） | 只调整 `rtp`，插件由 Vim 启动流程加载 |
| 运行期（手动 source） | 调用 `s:reload_plugins()` 逐个 source |

这个区别是理解"为什么在 vimrc 里 `plug#end()` 之后 `:scriptnames` 还看不到插件"的关键：那时插件目录刚进 `rtp`，启动流程尚未执行到插件加载阶段。

### 4. 安装与更新流程

#### 4.1 克隆与拉取

- `:PlugInstall` 对未安装的插件执行 `git clone`，已安装的跳过；
- `:PlugUpdate` 执行 `git pull`（或 fetch + merge），并展示提交差异；
- `:PlugClean` 删除 `g:plugs` 中不再声明、但仍存在于安装目录的插件；
- `:PlugDiff` 查看上次更新以来的变更，`:PlugSnapshot` 生成可回滚的脚本；
- 安装过程使用 `job`/并行机制，多个插件可同时下载。

#### 4.2 生成帮助标签

安装或更新后，vim-plug 会遍历所有插件的 `doc/` 目录执行 `:helptags`（即 `plug#helptags()`），这样 `:help <插件>` 才能命中。手动安装的包不会自动生成，需要自己执行：

```vim
:helptags ~/.vim/pack/vendor/start/foo/doc
```

#### 4.3 内置 vim-plug 的引导方式

本仓库把 vim-plug 本体放在 `vendor/plug.vim`，由 [`vim-plug.sh`](../vim-plug.sh) 复制到 `~/.vim/autoload/plug.vim`（优先使用仓库内置副本，失败再联网下载）。`vimrc` 在使用前先检测：

```vim
" vimrc
if !empty(globpath(&runtimepath, 'autoload/plug.vim'))
  call plug#begin()
  " ...
  call plug#end()
endif
```

这样可以保证：未安装 vim-plug 时配置依然能启动，只是联网插件不生效；内置的 NERDTree 与 airline 走原生包机制，不受影响。

### 5. 懒加载的实现原理

#### 5.1 按命令加载（on）

```vim
Plug 'tpope/vim-fugitive', { 'on': 'Git' }
```

`plug#end()` 发现 `Git` 命令尚不存在，于是创建一条等价于下面的占位命令（实际代码带版本分支，略）：

```vim
" vendor/plug.vim
command! -nargs=* -range -bang -complete=file Git call s:lod_cmd('Git', '<bang>', <line1>, <line2>, <q-args>, <q-mods>, ['vim-fugitive'])
```

用户第一次执行 `:Git` 时，`s:lod_cmd()` 依次：

（1）`s:lod()`：删除占位命令、把插件标记为已加载、重排 `rtp`、source 插件的 `ftdetect/`、`after/ftdetect/`、`plugin/`、`after/plugin/` 脚本；

（2）`s:dobufread()`：对当前缓冲区重新触发 `BufRead`，让刚加载的 `ftdetect/` 生效；

（3）用原始参数重新执行真正的 `:Git` 命令。

因此占位命令必须保留 `-nargs`、`-range`、`-bang` 等属性，否则第一次调用就会在参数解析阶段失败；`-complete=file` 只是让补全至少可用，不一定与插件真实命令一致。

#### 5.2 按键加载（on + `<Plug>`）

```vim
Plug 'preservim/nerdtree', { 'on': '<Plug>(NERDTreeToggle)' }

" 用户侧仍然要自己映射
nmap <C-n> <Plug>(NERDTreeToggle)
```

`plug#end()` 为 `<Plug>(NERDTreeToggle)` 创建一个 `<silent>` 占位映射。按下 `<C-n>` 后，占位映射触发插件加载，加载完成后用 `feedkeys()` 回放原始按键，让插件自己定义的 `<Plug>` 映射接手。

细节上，vim-plug 会为不同模式生成不同的占位映射：普通、可视、操作符模式保留 count、寄存器和操作符前缀，可视模式还会用 `gv` 恢复选区，插入模式则借助 `<C-\><C-O>` 临时切回普通模式。这些处理都是为了让"第一次按键"和"后续按键"行为一致。

如果插件没有定义对应的 `<Plug>` 映射，而只提供了普通函数，那么加载完成后回放的按键找不到映射，表现为"按了没反应"，这是最常见的懒加载失效原因。

#### 5.3 按文件类型加载（for）

```vim
Plug 'rust-lang/rust.vim', { 'for': 'rust' }
```

`for` 的实现有一个关键前置动作：`plug#end()` 会**立即** source 该插件的 `ftdetect/**/*.vim`。否则文件类型检测规则不存在，`.rs` 文件根本不会被识别成 `rust`，`FileType` 事件也就不会触发。

之后，`plug#end()` 注册：

```vim
" vendor/plug.vim
autocmd FileType rust call s:lod_ft('rust', ['rust-vim'])
```

第一次打开 `filetype=rust` 的缓冲区时，占位处理函数会：

（1）source 插件的 `plugin/`、`after/plugin/` 与 `syntax/rust.vim`、`after/syntax/rust.vim`；

（2）删除自己的 `FileType` 占位自动命令；

（3）触发 `filetypeplugin` 与 `filetypeindent` 的 `FileType` 自动命令，让 `ftplugin/`、`indent/` 也加载。

所以 `for` 不仅延迟了 `plugin/`，还顺带解决了"文件类型已设置、但 ftplugin 需要补触发"的问题。

#### 5.4 plug#load()

`plug#load()` 是 vim-plug 暴露的手动懒加载入口，该函数在 [`vendor/plug.vim`](../vendor/plug.vim#L590) 文件中声明：

```vim
" vendor/plug.vim
function! plug#load(...)
```

【**函数作用**】

手动加载一个或多个已声明但尚未加载的插件：调整 `rtp`、source 插件脚本，并对当前缓冲区重新触发 `BufRead`

【**参数含义**】

- `...`：插件名；可以传一个字符串、多个字符串，或一个字符串列表

【**返回值**】

插件本次被加载时返回 1；插件已经加载时返回 0；插件名不存在或未调用 `plug#begin()` 时打印错误信息并返回 0

典型用法是配合自定义触发条件：

```vim
augroup my_plug_lazy
  autocmd!
  autocmd BufReadPre *.rs call plug#load('rust-vim')
augroup END
```

#### 5.5 懒加载的代价与边界

| 触发器 | 适用对象 | 主要限制 |
| --- | --- | --- |
| `on` + 命令 | 以命令为入口的插件 | 占位命令补全固定为 `-complete=file`，且同名命令会被覆盖 |
| `on` + `<Plug>` | 以 `<Plug>` 映射为入口的插件 | 用户必须真的把键位映射到该 `<Plug>` |
| `for` | 提供 `ftdetect` 与 `ftplugin` 的插件 | 文件类型拼写必须与 `:set ft?` 一致 |

此外还要注意：

- 有全局副作用的插件（配色、状态栏、自动命令类）不适合懒加载，否则"没生效"是必然结果；
- 懒加载只减少启动期的 source 数量，不减少 `rtp` 查找成本；
- 首次触发会有一次可感知的加载延迟，因此不要把最敏感的按键用作触发器；
- 占位命令如果最终没有对应真实命令，会报 `E492: Not an editor command`。

### 6. 与其他管理器的对比

| 管理器 | 平台 | 实现语言 | 懒加载粒度 | 安装位置 |
| --- | --- | --- | --- | --- |
| vim-plug | Vim / Neovim | Vim script | 命令、`<Plug>` 映射、文件类型 | `~/.vim/plugged` |
| 原生 packages | Vim 8+ | 无 | `:packadd` 手动触发 | `~/.vim/pack/*` |
| minpac | Vim 8+ | Vim script | 基于 `:packadd` | `~/.vim/pack/*` |
| dein.vim | Vim / Neovim | Vim script | 命令、映射、文件类型、事件 | 自定义 |
| packer.nvim | Neovim | Lua | 模块、命令、事件、文件类型 | 自定义 |
| lazy.nvim | Neovim | Lua | 模块、事件、命令、键位、文件类型 | 自定义 |

这些管理器的差异主要在声明方式与懒加载粒度，底层原理完全一致：

（1）把插件目录放进 `rtp`；

（2）在合适的时机 source 对应脚本；

（3）事件触发后，补齐因延迟加载而错过的文件类型相关事件。

理解了 `rtp` 与装载时机，换任何管理器都只是换一层语法糖。选择建议也很直接：

- 只用 Vim、追求零依赖：原生 packages 足够；
- Vim/Neovim 双端共用配置：vim-plug 兼容性最好；
- 只用 Neovim、需要复杂懒加载与锁文件：lazy.nvim 更现代。

## 五、 从零写一个插件

### 1. 最小骨架

```text
hello-vim/
├── plugin/hello.vim
├── autoload/hello.vim
├── ftplugin/markdown.vim
└── doc/hello.txt
```

`plugin/hello.vim` 负责入口与幂等保护：

```vim
" plugin/hello.vim
if exists('g:loaded_hello')
  finish
endif
let g:loaded_hello = 1

let g:hello_greeting = get(g:, 'hello_greeting', 'Hello')

command! -nargs=? -complete=file Hello call hello#greet(<f-args>)

nnoremap <silent> <Plug>(hello-greet) :<C-U>call hello#greet()<CR>
```

`autoload/hello.vim` 存放真正逻辑：

```vim
" autoload/hello.vim
function! hello#greet(...) abort
  let name = a:0 ? a:1 : 'Vim'
  echo printf('%s, %s!', g:hello_greeting, name)
endfunction
```

`ftplugin/markdown.vim` 做文件类型相关的设置：

```vim
" ftplugin/markdown.vim
if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

setlocal wrap linebreak
let b:undo_ftplugin = 'setlocal wrap< linebreak<'
```

把这个目录放进任意 `rtp` 覆盖的位置（或软链进 `~/.vim/pack/vendor/start/`），插件就能工作。

### 2. autoload 函数

autoload 函数的命名必须与路径一致：

```text
autoload/hello.vim          →  hello#greet()
autoload/hello/utils.vim    →  hello#utils#trim()
autoload/hello/utils.vim    →  hello#utils#split()
```

几个编写要点：

- 函数名一律带 `#` 前缀，避免与用户或其它插件冲突；
- 函数定义加 `abort`，出错时立即停止，避免错误被吞掉后继续执行；
- 对外暴露的函数不要使用 `s:` 前缀，`s:` 函数只能在定义它的脚本内通过 `<SID>` 调用；
- 文件不要在中途 `finish` 掉函数定义，否则调用方会收到 `E117`。

### 3. 定义命令与 `<Plug>` 映射

#### 3.1 命令定义

```vim
command! -nargs=? -complete=file Hello call hello#greet(<f-args>)
```

常用属性：

- `-nargs=?`：0 或 1 个参数，`-nargs=*` 表示任意个，`-nargs=1` 表示恰好 1 个；
- `-range`、`-bang`：支持范围与 `!`；
- `-complete=file`：参数补全为文件路径；
- `-bar`：允许用 `|` 连接后续命令；
- `<f-args>`：把参数按空白拆分后依次作为函数实参传入；`<q-args>` 则把整串参数当成一个字符串，适合只接收单个参数的命令；
- 命令名必须大写开头，这是 Vim 的硬性规则。

#### 3.2 `<Plug>` 映射的约定

```vim
" 插件侧：只定义 <Plug>，不占用用户键位
nnoremap <silent> <Plug>(hello-greet) :<C-U>call hello#greet()<CR>

" 用户侧：自行决定键位
nmap <Leader>hg <Plug>(hello-greet)
```

这样设计有三个好处：

- 插件不污染用户键位，用户可按需启用；
- 用户可以安全地覆盖默认映射，而不会破坏插件功能；
- `<Plug>` 映射可以被 vim-plug 的 `on` 选项用作懒加载触发器。

命名建议使用 `<Plug>(插件名-动作名)` 形式，括号能避免不同插件的 `<Plug>` 前缀冲突。

#### 3.3 `<SID>` 与 `<script>`

映射里不能直接写 `s:helper()`，因为 `s:` 是脚本作用域，映射执行时并不在脚本上下文中。正确写法是用 `<SID>`：

```vim
function! s:greet() abort
  echo 'hello'
endfunction

nnoremap <silent> <Plug>(hello-greet) :<C-U>call <SID>greet()<CR>
```

`<SID>` 会被展开成 `<SNR>12_` 形式，指向当前脚本的命名空间。

`<script>` 则用于限制右侧按键的重映射范围：

```vim
nnoremap <silent> <script> <Plug>(hello-greet) :<C-U>call <SID>greet()<CR>
```

加上 `<script>` 后，右侧的按键只在脚本内定义的映射中查找，用户全局定义的干扰映射不会劫持它。

### 4. 自动命令的正确写法

```vim
" plugin/hello.vim
augroup hello_autosave
  autocmd!
  autocmd BufWritePre *.hello call hello#format()
augroup END
```

要点：

- 必须使用具名 `augroup`，并在组内先 `autocmd!` 清空，保证重复 source 不会叠加；
- 事件名大小写敏感，`BufWritePre` 与 `Bufwritepre` 不是一回事；
- 需要读取触发文件时用 `expand('<afile>')`，不要依赖当前缓冲区；
- 只执行一次的自动命令加 `++once`，需要嵌套触发其它事件时加 `++nested`；
- 临时禁用自动命令用 `noautocmd`，而不是全局修改 `'eventignore'`。

### 5. 帮助文档与 tags

`doc/hello.txt` 使用 Vim 的帮助格式：

```text
*hello.txt*  一个演示插件                                *hello*

                                                            *hello-greet()*
hello#greet([{name}])
    向 {name} 打招呼，缺省为 Vim。
```

要点：

- 文件名与标签用 `*...*` 标记，`:help hello` 依赖 `*hello*` 这个标签；
- 函数帮助标签约定为 `*hello-greet()*`，便于 `:help hello-greet()`；
- 生成索引：

```vim
:helptags ~/.vim/pack/vendor/start/hello-vim/doc
```

`doc/tags` 是可生成的索引，不建议手工编辑；随包分发时提交生成结果即可。

### 6. Vim9script 与 Lua 插件

#### 6.1 Vim9script

Vim 9 引入了新的脚本语法，文件首行声明 `vim9script`：

```vim
" autoload/hello.vim（Vim9）
vim9script

export def Greet(name: string = 'Vim'): void
  echo 'Hello, ' .. name .. '!'
enddef
```

其它脚本可以按模块导入：

```vim
" plugin/hello.vim（Vim9）
vim9script
import autoload 'hello.vim'

hello.Greet('Vim9')
```

区别与注意点：

- Vim9 函数默认是脚本局部的，对外暴露要写 `export`；
- 类型检查、编译执行带来性能优势；
- 旧插件（legacy script）与新脚本可以共存，但一个文件内不能混用两种语法；
- Vim9 用 `import` 显式引入模块，调用时写成 `hello.Greet()`，不再手写 `hello#greet()` 形式的函数名。

#### 6.2 Lua（Neovim）

Neovim 插件通常把逻辑放在 `lua/<模块>/init.lua`：

```lua
-- lua/hello/init.lua
local M = {}

function M.greet(name)
  print(('Hello, %s!'):format(name or 'Neovim'))
end

return M
```

入口脚本注册命令：

```lua
vim.api.nvim_create_user_command('Hello', function(opts)
  require('hello').greet(opts.args)
end, { nargs = '?' })
```

要点：

- `require()` 自带模块缓存，效果等价于 autoload 的"只加载一次"；
- `lua/` 目录在 Neovim 的 `rtp` 中同样生效；
- Lua 支持取决于编译特性（`+lua`），多数发行版的默认包未启用，Lua 插件主要面向 Neovim。

### 7. 编写健壮插件的清单

- 入口文件用 `g:loaded_xxx` 守卫，避免重复初始化；
- 默认值用 `get(g:, 'xxx_option', default)`，不要直接假设变量存在；
- 可选依赖用 `exists(':Cmd')`、`has('feature')`、`globpath()` 判断后再使用；
- 修改 `'cpoptions'` 等全局选项前后要保存恢复，不要把用户的配置永久改坏；
- 脚本首行加 `scriptencoding utf-8`（legacy 脚本），避免非 ASCII 字符乱码；
- 自动命令统一用 `augroup` + `autocmd!`；
- `ftplugin` 使用 `b:did_ftplugin` 与 `b:undo_ftplugin`；
- 对外暴露 `<Plug>` 映射而不是硬编码键位；
- 提供 `doc/` 帮助并生成 tags；
- 在 README 中写清最低 Vim 版本与可选依赖。

## 六、 调试、排障与性能

### 1. 观测插件加载状态

#### 1.1 :scriptnames

```vim
:scriptnames
```

输出按加载顺序编号列出所有已 source 的脚本：

```text
  1: /etc/vim/vimrc
  2: ~/.vimrc
  3: /usr/share/vim/vim91/plugin/getscriptPlugin.vim
  ...
 28: ~/.vim/pack/vendor/start/nerdtree/plugin/NERD_tree.vim
 29: ~/.vim/pack/vendor/start/vim-airline/plugin/airline.vim
```

三个用法：

- 确认某插件是否被加载：搜索插件路径；
- 确认加载顺序：编号越小越早；
- 确认 autoload 是否被触发：调用前不存在、调用后出现，说明惰性加载生效。

#### 1.2 :verbose 定位最后修改者

```vim
:verbose set shiftwidth?
:verbose set runtimepath?
:verbose map <Leader>f
:verbose command Foo
:verbose autocmd FileType
```

`verbose` 会在结果后追加"Last set from ..."，直接指出是哪个脚本改的。这是排查"设置被谁覆盖"的最快手段。

#### 1.3 其它常用命令

| 命令 | 用途 |
| --- | --- |
| `:set rtp?` | 查看运行时路径及顺序 |
| `:set packpath?` | 查看包搜索路径 |
| `:echo &loadplugins` | 确认插件加载是否开启 |
| `:messages` | 查看启动期报错与被吞掉的提示 |
| `:runtime! plugin/**/*.vim` | 手动重新加载 `rtp` 中的 `plugin/`（会重复执行） |
| `:source %` | 重新加载当前脚本（调试用） |

### 2. 典型故障与定位

#### 2.1 插件根本没加载

按以下顺序排查：

（1）**目录层级**：`~/.vim/pack/vendor/start/foo/plugin/foo.vim` 是正确层级；少一层 `start` 或多一层 `foo` 都不会被扫描。

（2）**是否在 rtp 中**：`:set rtp?` 看目录是否存在；原生包则看 `:set packpath?` 与 `pack/*/start` 结构。

（3）**加载是否被关闭**：`--noplugin`、`--clean`、`-u NONE`、`set noloadplugins` 都会导致插件不加载。

（4）**软链是否悬空**：本仓库用软链接入包，`readlink -f ~/.vim/pack/vendor/start/nerdtree` 应指向仓库内目录；悬空时 Vim 静默跳过。

（5）**文件类型相关目录是否被启用**：`ftplugin/` 需要 `filetype plugin on`，`syntax/` 需要 `syntax on`，否则事件装载器根本不存在。

#### 2.2 配置被插件覆盖

现象是 vimrc 里明明写了 `set`，启动后却是别的值。定位步骤：

（1）`:verbose set <option>?` 查看最后设置者；

（2）若设置者是插件，把自己的设置移入 `~/.vim/after/plugin/`；

（3）若是插件读取的全局变量，确认赋值发生在插件 source 之前（vim-plug 场景写在 `plug#end()` 之前）。

#### 2.3 映射与命令冲突

```vim
:verbose map <Leader>f
:verbose command Foo
:scriptnames
```

- 映射冲突看最后定义者，必要时用 `<Plug>` 或 `maparg()` 检查；
- 命令冲突通常是两个插件定义了同名命令，后加载者生效，可用 `command!` 覆盖为自己的实现；
- 自动命令重复触发用 `:autocmd <group>` 或 `:autocmd FileType` 列出，检查是否缺少 `autocmd!`。

#### 2.4 懒加载不生效

| 现象 | 原因 |
| --- | --- |
| `:Git` 报未定义 | `on` 中写的命令名与插件实际命令不一致，或大小写不符 |
| 按了映射没反应 | 插件没有定义该 `<Plug>` 映射，或占位映射被覆盖 |
| 文件类型插件不加载 | `for` 的 filetype 与 `:set ft?` 不一致，或 `ftdetect` 未被提前加载 |
| 首次触发报错 | 插件依赖的全局变量在加载时才被读取，而用户设置写在触发之后 |

### 3. 启动性能分析

```bash
vim --startuptime /tmp/vim-start.log -c q
```

日志会按阶段与脚本列出耗时（毫秒），重点看：

- `sourcing ~/.vimrc`：配置本身是否过重；
- `loading plugins`：哪些 `plugin/` 脚本最慢；
- `VimEnter` 前后的差异：`autocmd VimEnter` 里是否藏了重活。

单函数级别的性能用 `:profile`：

```vim
:profile start /tmp/vim-profile.log
:profile func *
:profile file *
" 执行可疑操作
:profile pause
```

结论通常会指向三类问题：`plugin/` 里做了本应放到 autoload 的重活、启动期执行了外部命令、`rtp` 过长导致查找变慢。

### 4. 最小复现与二分排查

当问题无法在复杂配置中定位时，用基线对照：

（1）`vim --clean`：默认配置、无插件，确认问题是否由配置引起。

（2）`vim -u NONE -N`：完全裸启动，排除所有 vimrc 与插件。

（3）`vim -u min.vim`：只保留怀疑的插件与最小配置，逐步加回。

（4）二分 `rtp`：把插件目录一半一半地禁用，快速缩小范围。

（5）`vim -V15/tmp/vimlog`：输出详细日志，观察 source 了哪些脚本、在哪一步报错。

【**经验法则**】

能稳定复现的最小配置，比任何"看起来相关"的猜测都更有价值；先缩小范围，再读源码。

---

*本文档由 markdowncli 技能辅助生成*
