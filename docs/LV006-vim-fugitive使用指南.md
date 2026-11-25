<!-- more -->

本文基于本仓库内置的 vim-fugitive `3b753cf`（2026-03-07），系统整理它的命令、状态窗口、diff、三方冲突、日志、blame、写操作与排障。示例默认运行在 Vim 9.1、仓库根目录为当前工作目录；文中的 `:Git` 命令都要求当前缓冲区属于一个 Git 仓库。

## 一、 认识 vim-fugitive

### 1. 定位与能力边界

#### 1.1 它是什么

vim-fugitive 是一个**纯 Vimscript 的 Git 前端**：它不自己实现 Git，而是把 Vim 的缓冲区、窗口、quickfix、diff 机制接到 git 命令上。核心能力包括：

- 用 `:Git` 透传任意 git 子命令，并把输出放进 Vim 缓冲区；
- 提供状态窗口，完成暂存、取消暂存、丢弃改动、提交；
- 用 Vim 原生 diff 模式做左右/上下对照，并按 hunk 暂存或还原；
- 浏览提交历史、查看某个历史版本的文件、逐行 blame；
- 在合并冲突时提供三方 diff 与 `d2o`/`d3o` 取用；
- 通过对象语法直接编辑 `HEAD:path`、`:path`、`@~2:%` 这类 Git 对象。

它适合"不想离开 Vim 又需要做完整 Git 操作"的场景。日常的 `git status`、`git diff`、`git add -p`、`git commit`、`git log`、`git blame` 都能在 Vim 内完成。

#### 1.2 它不是什么

- **不是插件管理器**：插件安装由 vim-plug 或本仓库的 `pack/vendor` 机制负责，fugitive 只操作 Git 仓库。
- **不是 diff 算法**：左右对照用的是 Vim 内置 diff 模式，算法由 `'diffopt'` 控制。
- **不是 GitHub/GitLab 客户端**：`:GBrowse` 只负责拼 URL，GitHub 支持需要额外安装 `vim-rhubarb`。
- **不是异步任务框架**：`:Git` 默认同步执行并占用 Vim，`:Git!` 才会在后台跑并把输出流到 preview 窗口。

### 2. 工作原理

#### 2.1 仓库发现与命令注册

打开文件时，fugitive 会从文件路径逐级向上查找 `.git`（也识别 worktree 的 `.git` 文件），找到后把当前缓冲区标记为"属于某个仓库"。命令本身在插件加载后就可以调用，但只有属于仓库的缓冲区才会真正执行；在 NERDTree 或普通临时缓冲区里执行 `:Git` 不会打开状态窗口，通常会提示当前不在仓库中。

判断当前缓冲区是否在仓库中，可以用公开 API：

```vim
:echo FugitiveGitDir()     " 通常是 /path/repo/.git
:echo FugitiveWorkTree()   " 工作树根目录 /path/repo
```

`FugitiveGitDir()` 返回空字符串表示当前缓冲区不在 Git 仓库中。

#### 2.2 `:Git` 的执行链路

`:Git` 不是简单地把参数拼给 shell，它还要决定输出放在哪里、是否等待交互。可以简化为：

```text
:Git <args>
    │
    ├─ 解析参数，定位仓库与当前文件
    │
    ├─ 选择输出通道
    │    ├─ 普通命令：输出进临时缓冲区
    │    ├─ 分页命令：写入临时文件，再 :split
    │    └─ 交互命令：打开临时文件（如提交信息），关闭后继续执行
    │
    └─ 启动 git 子进程
         ├─ Unix：使用 pty，进度条、颜色、交互提示可用
         └─ 其它平台：使用管道，进度条等行为会有差异
```

由此可以解释三个常见现象：

（1）`:Git log` 会打开一个临时文件缓冲区，而不是把输出直接 echo 到命令行；

（2）`:Git commit` 会打开提交信息缓冲区，写完关闭才真正提交；

（3）`:Git` 执行期间 Vim 被占用，长命令可以改用 `:Git!` 或 `:Git --paginate`。

#### 2.3 三类 fugitive 缓冲区

| 类型 | 典型入口 | 用途 |
|:--|:--|:--|
| summary 缓冲区 | `:Git` 无参数 | 仓库状态总览，暂存/提交/跳转 |
| object 缓冲区 | `:Gedit @^:file`、`:Gedit :file` | 查看或编辑提交、树、blob、索引版本 |
| 临时输出缓冲区 | `:Git log`、`:Git --paginate`、`-` 对象 | 承载 git 命令输出 |

summary 缓冲区里按 `g?` 可以查看当前可用的映射；object 缓冲区里按 `g?` 同样能看到上下文相关的帮助。

### 3. 本仓库中的安装与验证

#### 3.1 内置位置与加载方式

vim-fugitive 以原生 Vim 8 package 的形式内置在：

```text
pack/vendor/start/vim-fugitive/
```

包含上游完整的 12 个文件（`plugin/`、`autoload/`、`doc/`、`ftdetect/`、`ftplugin/`、`syntax/`，以及 `README.markdown`、`CONTRIBUTING.markdown`、`.gitattributes`、`.gitignore`、`.github/FUNDING.yml`）。

首次使用执行：

```bash
./vim-plug.sh link
```

脚本会把该目录软链到 `~/.vim/pack/vendor/start/vim-fugitive`，Vim 启动时按原生包机制加载，**不需要联网，也不需要 `:PlugInstall`**。

版本信息记录在 `pack/plugins.tsv`，后续更新由 `scripts/sync-plugins.sh` 完成。

#### 3.2 验证清单

```vim
:echo exists(':Git')             " 期望 2
:echo exists(':Gdiffsplit')      " 期望 2
:echo !empty(FugitiveGitDir())   " 仓库文件里期望 1
:scriptnames                     " 应出现 .../vim-fugitive/plugin/fugitive.vim
:help fugitive                   " 应打开帮助
```

再在一个仓库文件里执行：

```vim
:Git status
```

能打开状态窗口就说明插件与 git 都正常。

#### 3.3 更新与帮助

```bash
scripts/sync-plugins.sh --dry-run   # 检查上游是否有更新
scripts/sync-plugins.sh             # 同步源码 + 回写清单 + 刷新 README
```

帮助标签 `doc/tags` 被 `.gitignore` 忽略，不会进入仓库；本地缺失时可以手动生成：

```vim
:helptags ~/.vim/pack/vendor/start/vim-fugitive/doc
```

### 4. Git 三棵树与对象语法

#### 4.1 工作区、索引、HEAD

理解 fugitive 的关键，是把 Git 的三个位置分清：

```text
         git add                 git commit
工作区 ─────────────▶ 索引 ─────────────────▶ HEAD
  │                     │                      │
  │ git diff            │ git diff --cached    │
  │                     │                      │
  └───────────┬─────────┴──────────────────────┘
              │
        未暂存改动 / 已暂存改动 / 已提交内容
```

对应的 fugitive 操作：

| 想比较的两端 | 命令 |
|:--|:--|
| 工作区 ↔ 索引 | `:Gdiffsplit` |
| 工作区 ↔ HEAD | `:Gdiffsplit HEAD` |
| 索引 ↔ HEAD | `:Git diff --cached` |
| 把工作区写入索引 | `:Gwrite` |
| 用索引覆盖工作区缓冲区 | `:Gread` |

#### 4.2 fugitive object 的写法

`object` 既可以是工作区文件，也可以是 Git revision，还支持受 `cmdline-special` 启发的扩展写法：

| 写法 | 含义 |
|:--|:--|
| `@` | HEAD 指向的提交 |
| `master` | `master` 分支指向的提交 |
| `master^` | `master` 的父提交 |
| `master...other` | `master` 与 `other` 的 merge base |
| `master:` | `master` 指向的树 |
| `./master` | 工作区中名为 `master` 的文件 |
| `:(top)master` | 仓库根目录下名为 `master` 的文件 |
| `Makefile` | 工作区中的 `Makefile` |
| `@^:Makefile` | HEAD 父提交中的 `Makefile` |
| `:Makefile` | 索引中的 `Makefile`（可写） |
| `@~2:%` | 祖父提交中的当前文件 |
| `:%` | 当前文件在索引中的版本 |
| `:1:%` | 冲突时当前文件的共同祖先版本 |
| `:2:#` | 冲突时目标分支中的备用文件 |
| `:3:#5` | 冲突时合并分支中第 5 个缓冲区的文件 |
| `!` | 拥有当前文件的提交 |
| `!:Makefile` | 该提交中的 `Makefile` |
| `!3^2` | 第 3 个缓冲区的文件所属提交的第二父提交 |
| `.git/config` | 仓库配置文件 |
| `:` | summary（状态）缓冲区 |
| `-` | 上一次 `:Git` 调用的输出临时文件 |
| `<cfile>` | 光标下的文件或提交 |

默认值规则：

- 命令接受可选 object 且当前是工作区文件时，默认取**索引版本**；
- 其它情况默认取**工作区版本**。

#### 4.3 对象语法与命令的对应

```vim
:Gedit @^:Makefile     " 打开父提交里的 Makefile
:Gsplit :Makefile      " 分屏打开索引版本
:Gvsplit @~2:%         " 垂直分屏打开祖父提交里的当前文件
:Gtabedit :            " 新标签页打开状态窗口
:Gedit -               " 打开上一次 :Git 的输出
:Git show HEAD:file.c  " 直接让 git 输出某个版本
```

冲突场景下，`:1:%`、`:2:%`、`:3:%` 分别对应共同祖先、ours、theirs，配合 `:Gdiffsplit!` 使用。

## 二、 `:Git` 透传命令

### 1. 入口与参数

#### 1.1 `:Git`、`:G` 与无参数形式

`:G` 是 `:Git` 的两字符缩写，二者等价。无参数时：

```vim
:Git
```

打开当前仓库的状态窗口；如果该仓库的状态窗口已经存在，则直接聚焦它，而不是重复打开。

这些命令只对仓库缓冲区可用。打开一个仓库里的文件后，`:Git`、`:Gdiffsplit` 等才存在。

#### 1.2 参数如何传给 git

`:` 后面的内容按 git 的参数规则传递，不需要额外引号：

```vim
:Git status --short
:Git log --oneline --graph --decorate -10
:Git diff --stat
:Git add -p
:Git commit --amend
```

带空格的路径要用引号或转义：

```vim
:Git add "docs/新 文档.md"
```

交互式命令（`commit`、`rebase -i`、`add -p`）会打开临时缓冲区或终端交互界面，完成并关闭后继续。

#### 1.3 路径过滤

只操作某个文件或目录时，用 `--` 分隔路径：

```vim
:Git diff -- src/main.c
:Git diff --cached -- docs/
:Git log --oneline -- vimrc
:Git difftool -y -- src/main.c
```

路径相对仓库根目录。当前目录不在仓库根时，可以用 `./` 开头的路径明确指向当前目录。

### 2. 输出与交互模式

#### 2.1 普通输出

短输出直接进入临时缓冲区；分页类命令（`log`、`diff` 等）会写入临时文件后 `:split`，避免污染当前缓冲区。

缓冲区是只读的，用 `:q` / `:close` 关闭，或用常规窗口命令处理。

#### 2.2 `:Git!` 与预览窗口

```vim
:Git! log --oneline -20
```

在后台执行，并把输出流式送到 preview 窗口；Vim 不会被阻塞。适合耗时命令或想边看边做别的事。

在交互式 `:Git` 执行期间按 `Ctrl+D`，可以切换到这种后台预览模式。

`:Git!` 的输出也会成为 `-` 对象，之后可以：

```vim
:Gedit -
```

重新打开上一次的输出。

#### 2.3 `--paginate` 临时文件

```vim
:Git --paginate log -p
:Git -p diff
:Git ++curwin --paginate log
```

`--paginate`/`-p` 会把输出捕获到临时文件，再打开一个分屏。默认用 `:split`，第一个参数加 `++curwin` 则在当前窗口 `:edit` 该临时文件。

带范围时可以把输出插入当前缓冲区：

```vim
:'<,'>Git! -p log --oneline
```

这会把 git 输出插入到选中行之后。

#### 2.4 交互式命令

`:Git commit`、`:Git rebase -i`、`:Git add -p` 会打开临时文件或交互界面。提交信息缓冲区里：

- 写入并关闭窗口：完成提交；
- 不写入直接关闭：通常放弃本次提交；
- 关闭窗口后，原来的 `:Git` 命令继续执行完毕。

### 3. 常用子命令

#### 3.1 查看类

| 命令 | 作用 |
|:--|:--|
| `:Git status` | 完整状态 |
| `:Git status -sb` | 简短状态 |
| `:Git diff` | 工作区 vs 索引 |
| `:Git diff --cached` | 索引 vs HEAD |
| `:Git diff HEAD` | 工作区 vs HEAD |
| `:Git diff --stat` | 只看统计 |
| `:Git show HEAD:file.c` | 查看某版本文件 |
| `:Git log --oneline --graph --decorate` | 图形化历史 |
| `:Git blame file.c` | 逐行归属 |

#### 3.2 提交与历史

```vim
:Git add -p
:Git commit
:Git commit --amend
:Git commit -v
:Git revert HEAD
:Git reset --soft HEAD~1
```

`:Git add -p` 的交互在 pty 中进行，`y/n/s/e` 等按键与 git 原生一致。

#### 3.3 分支与合并

```vim
:Git branch -vv
:Git switch -c feature/login
:Git checkout main
:Git merge feature/login
:Git rebase -i HEAD~3
:Git stash push -m "wip"
```

#### 3.4 远端

```vim
:Git remote -v
:Git fetch --all --prune
:Git pull --rebase
:Git push
:Git push -u origin HEAD
```

需要输入密码或 SSH passphrase 时，Unix 下 pty 会把提示显示出来，可以直接在 Vim 里输入。

### 4. 与 Vim 命令组合

#### 4.1 `:Git blame` 的窗口

`:Git blame` 会打开一个**scroll-bound 的垂直分屏**，左侧是 blame 信息，右侧是文件。带范围或显式文件名时改用水平分屏，且不做 scrollbind。

#### 4.2 `:Git difftool` 的两种模式

```vim
:Git difftool            " 把每个改动 hunk 放进 quickfix
:Git difftool -y         " 每个改动文件新开一个 tab，并执行 :Gdiffsplit!
```

第一种适合快速浏览 hunk 列表，第二种适合逐个文件左右对照。

#### 4.3 `:Git mergetool`

`:Git mergetool` 与 `:Git difftool` 类似，但目标是合并冲突：把冲突 hunk 放进 quickfix，再配合 `:Gdiffsplit!` 做三方对照。

## 三、 状态窗口

### 1. 打开与布局

#### 1.1 打开方式

```vim
:Git
```

无参数即打开 summary。它类似 `git status`，但每个条目都可以用映射直接操作。

关闭：

```text
gq   关闭状态窗口
```

#### 1.2 分区示意

```text
fugitive summary
├── Untracked (1)
│   └── examples/new_file.c
├── Unstaged (2)
│   ├── vimrc
│   └── README.md
├── Staged (1)
│   └── docs/LV006-vim-fugitive使用指南.md
└── Unpushed (1)
    └── feat(plugins): 内置 vim-fugitive ...
```

常见分区包括 Untracked、Unstaged、Staged、Unpushed、Unpulled、Rebasing。分区顺序和内容由仓库状态决定，上图只是示意。

#### 1.3 刷新与关闭

执行 `s`、`u`、`cc` 等操作后状态窗口会自动刷新。需要重新扫描时，重新执行 `:Git` 即可；已经在同一仓库打开时会聚焦而不是新建。

窗口内：

```text
gq   关闭状态窗口
g?   查看状态窗口的完整映射
```

### 2. 暂存与撤销

#### 2.1 `s`、`u`、`-`

```text
s    暂存（git add）光标下的文件或 hunk
u    取消暂存（git reset）光标下的文件或 hunk
-    切换：已暂存则取消，未暂存则暂存
```

可视模式下选中多行/多个文件后按同样的键，可以批量处理。

#### 2.2 `U` 与 `X`

```text
U    取消暂存所有文件
X    丢弃光标下的改动（checkout 或 clean）
2X   合并冲突时取 ours（checkout --ours）
3X   合并冲突时取 theirs（checkout --theirs）
```

`X` 会真正丢掉工作区内容，执行前想清楚；命令会 echo 一条如何撤销的提示，之后可以用 `:messages` 再看。

#### 2.3 可视模式批量操作

在状态窗口用 `V`/`v` 选中多个条目后：

```text
s    批量暂存
u    批量取消暂存
-    批量切换
X    批量丢弃
```

### 3. 查看差异

#### 3.1 `=` 内联 diff

```text
=    切换光标下文件的内联 diff
>    展开内联 diff
<    收起内联 diff
```

内联 diff 不打开新窗口，适合快速扫一眼；复杂改动仍建议用 `dv`。

#### 3.2 `dd`、`dv`、`ds`

```text
dd   对光标下文件执行 :Gdiffsplit（自动方向）
dv   对光标下文件执行 :Gvdiffsplit（左右）
ds   对光标下文件执行 :Ghdiffsplit（上下）
dh   同 ds
dq   关闭其它 diff 窗口，并 :diffoff!
```

#### 3.3 `dp` 的历史包袱

状态窗口里的 `dp` 是旧版"对文件执行 `git diff`"的映射，已标记为 deprecated，建议改用 `dv` 或内联 diff。

### 4. 提交

#### 4.1 `cc` 与 `cvc`

```text
cc    创建提交
cvc   创建提交并带 -v（提交信息里附 diff）
```

会打开提交信息缓冲区；写入并关闭完成提交，不写入直接关闭通常放弃。

```text
:Git（summary）
  │ cc
  ▼
commit message 缓冲区
  ├─ feat: add vim-fugitive guide
  ├─ ...
  └─ # Please enter the commit message for your changes.
  │
  │ :wq
  ▼
git commit ──▶ 新提交（Unpushed 分区）
```

#### 4.2 `ca`、`ce`、`cw`

```text
ca    amend 上一次提交，并编辑信息
cva   amend 并带 -v
ce    amend 上一次提交，不编辑信息
cw    reword 上一次提交
```

#### 4.3 `cf`、`cs`、`cn`

```text
cf    为光标下提交创建 fixup! 提交
cF    创建 fixup! 并立即 rebase
cs    为光标下提交创建 squash! 提交
cS    创建 squash! 并立即 rebase
cn    创建 squash! 并编辑提交信息
cW    为光标下提交创建 amend! 提交
```

其余相关映射：

```text
c<Space>    命令行预填 ":Git commit "
crc         撤销（revert）光标下的提交
crn         revert 到索引和工作区，但不创建提交
cr<Space>   命令行预填 ":Git revert "
cm<Space>   命令行预填 ":Git merge "
```

### 5. 导航与文件操作

#### 5.1 分区跳转

```text
gu    跳到 Untracked 或 Unstaged 分区的第 [count] 个文件
gU    跳到 Unstaged 分区
gs    跳到 Staged 分区
gp    跳到 Unpushed 分区
gP    跳到 Unpulled 分区
gr    跳到 Rebasing 分区
```

#### 5.2 打开对象

```text
<CR>    打开光标下的文件或对象
o       新分屏打开
gO      新垂直分屏打开
O       新标签页打开
p       预览窗口打开（状态窗口中需要 1p）
~       打开当前文件的第 [count] 个祖先
P       打开当前文件的第 [count] 个父提交
C       打开包含当前文件的提交
```

#### 5.3 忽略与补丁

```text
I    对光标下文件或选中范围进入补丁模式
     未暂存走 add -p，已暂存走 reset -p，未跟踪先 intent-to-add
P    与 I 类似，但不限制 patch-only，也会处理 Unpushed 分区
gI   打开 .git/info/exclude 并加入当前文件
gi   打开 .git/info/exclude（计数打开 .gitignore）
```

`gI` 适合临时忽略文件；想改团队共享的 `.gitignore` 用计数形式 `1gI`。

#### 5.4 其它映射

```text
( / )        上一个 / 下一个文件、hunk 或 revision
[c / ]c      上一个 / 下一个 hunk（自动展开内联 diff）
[/ / ]/      上一个 / 下一个文件（自动收起内联 diff）
[m / ]m      同上
i            下一个文件或 hunk（展开内联 diff）
[[ / ]]      上一个 / 下一个 section
[] / ][      上一个 / 下一个 section 结尾
* / #        在 + 行与 - 行之间跳转
.            以光标下文件预填命令行
g?           帮助
```

## 四、 Diff 与冲突

### 1. 三种 diff 命令

#### 1.1 `:Gdiffsplit`

```vim
:Gdiffsplit            " 工作区 vs 索引
:Gdiffsplit HEAD       " 工作区 vs HEAD
:Gdiffsplit HEAD~1     " 工作区 vs 上一个提交
:Gdiffsplit other.c    " 与指定文件比较
```

无参数时，工作区版本放在右边或下边，取决于当前窗口宽度；索引/HEAD 版本放在左边或上边。

在 diff 窗口里用 `do` 和 `dp` 完成取用与推送。

#### 1.2 `:Gvdiffsplit`

```vim
:Gvdiffsplit
:Gvdiffsplit HEAD
```

与 `:Gdiffsplit` 相同，但**强制左右分屏**。窗口宽度不够时也会坚持垂直布局。

#### 1.3 `:Ghdiffsplit`

```vim
:Ghdiffsplit
:Ghdiffsplit HEAD
```

强制上下分屏：它会从 `'diffopt'` 中去掉 `vertical`。如果同时加了 `:vertical` 前缀，仍然会垂直。

### 2. diff 窗口操作

#### 2.1 跳转 hunk

```text
]c    下一个差异
[c    上一个差异
:diffupdate    重新计算 diff
```

fugitive 在这些 buffer 里覆盖了 Vim 内置的 `]c`/`[c`，会顺带展开内联 diff。

#### 2.2 `do` 与 `dp`

diff 模式下两个窗口的内容是联动的：

```text
┌─ index / HEAD ────────────┐   ┌─ work tree ───────────────┐
│ - set mouse=a             │   │ + set mouse=a             │
│ - set showcmd             │   │ + set showcmd             │
│                           │   │ + set number              │
└───────────────────────────┘   └───────────────────────────┘

当前在 work tree：dp ──▶ 暂存到 index；do ◀── 从 index 取回
当前在 index：    dp ──▶ 推回 work tree；do ◀── 从 work tree 取回
```

- 当前窗口是**工作区**时：`dp` 把当前 hunk 推到索引（暂存），`do` 从索引取回内容（撤销改动）；
- 当前窗口是**索引/HEAD**时：方向相反，`dp` 推到工作区，`do` 从工作区取回。

如果两个方向都有改动，先确认当前光标在哪个窗口，再按键。

#### 2.3 `:Gwrite` 与 `:Gread`

```vim
:Gwrite     " 写入当前文件并暂存
:Gread      " 用索引版本覆盖当前缓冲区（不写盘）
```

在 diff 窗口里，它们比 `do`/`dp` 更"整文件"：`Gwrite` 处理整个文件，`Gread` 丢弃整个缓冲区的改动。

#### 2.4 关闭与刷新

```text
:diffoff       关闭当前窗口的 diff 模式
dq             在状态窗口里关闭其它 diff 窗口并 diffoff!
:Git           重新打开状态窗口
```

diff 状态异常时，先 `:diffupdate`，仍不对就关闭窗口重新 `:Gdiffsplit`。

### 3. 三方冲突

#### 3.1 `:Gdiffsplit!`

```vim
:Gdiffsplit!
```

对当前文件的所有直接祖先做 diff；合并冲突时是**三方 diff**：共同祖先、ours、theirs。与 `:Gdiffsplit` 不同的是，它保留当前窗口焦点，不强制跳转。

```text
        base（:1:%）
             │
   ours ─────┼───── theirs
 （:2:%）    │     （:3:%）
             ▼
   <<<<<<< HEAD
   ours 版本
   =======
   theirs 版本
   >>>>>>> feature

   :Gdiffsplit! ──▶ 三方窗口
        │
        ├─ d2o：取 ours 的 hunk
        └─ d3o：取 theirs 的 hunk
             │
             ▼
       解决后的工作区
```

#### 3.2 `d2o` 与 `d3o`

```text
d2o    取 ours（第二方）的 hunk
d3o    取 theirs（第三方）的 hunk
```

只在三方 diff 中提供。取完某个 hunk 后，冲突标记会相应减少。

#### 3.3 `2X` 与 `3X`

状态窗口里：

```text
2X    对冲突文件执行 checkout --ours
3X    对冲突文件执行 checkout --theirs
```

这两个是整文件级别的选择，适合明确要"整份用我方/对方"的场景。

解决完冲突后按常规 `:Gwrite` 暂存，再提交。

### 4. 批量 diff

#### 4.1 `:Git difftool` 的 quickfix 模式

```vim
:Git difftool
```

执行 `git diff`，把每个改动 hunk 放进 quickfix，并跳到第一个改动（用 `:Git! difftool` 则不跳）。适合先浏览 hunk 列表：

```text
:copen     打开 quickfix
]q / [q    下一个 / 上一个条目
```

#### 4.2 `:Git difftool -y` 的 tab 模式

```vim
:Git difftool -y
:Git difftool -y HEAD
:Git difftool -y --cached
```

对每个改动文件新开一个 tab，并执行 `:Gdiffsplit!`。三个变体分别对应：

- 无参数：工作区 vs 索引；
- `HEAD`：工作区 vs HEAD；
- `--cached`：索引 vs HEAD。

切换 tab 用 `gt`/`gT`，关闭用 `:tabclose`。

```text
:Git difftool -y HEAD
  │
  ├─ tab 1  vimrc          [HEAD | 工作区]
  ├─ tab 2  README.md      [HEAD | 工作区]
  └─ tab 3  docs/guide.md  [HEAD | 工作区]

gt / gT 切换，:tabclose 关闭
```

#### 4.3 只看某个文件

```vim
:Gvdiffsplit HEAD                 " 当前文件
:Git difftool -y HEAD -- path     " 指定文件
:Git diff -- path                 " 文本形式
```

路径相对仓库根目录；未跟踪文件先 `:Git add -N path`。

## 五、 历史、Blame 与检索

### 1. 提交历史

#### 1.1 `:Gclog`

```vim
:Gclog
:Gclog --oneline -20
:Gclog --author=sumu
```

把 `git log` 的结果装进 quickfix 列表，并跳到第一个提交（加 `!` 不跳）。每个条目是提交摘要，按 `<CR>` 打开提交对象。

```text
:Gclog
  │
  ├─ quickfix：提交列表
  │     └─ <CR> ──▶ commit 对象（patch + 文件树）
  │                       ├─ o / gO / O   打开文件
  │                       ├─ dd / dv      与父提交 diff
  │                       └─ coo          检出该提交
  │
  └─ :0Gclog / 范围 Gclog ──▶ 只包含当前文件的历史
```

#### 1.2 `:0Gclog` 与范围

```vim
:0Gclog          " 当前文件的全部历史
:'<,'>Gclog      " 当前文件选中行的历史（git log -L）
```

带范围时使用 `git log -L`，光标定位到每个提交的第一个 diff hunk；`:0Gclog` 表示整个文件。

#### 1.3 `:Gllog`

```vim
:Gllog
```

与 `:Gclog` 相同，但写入 location list 而不是 quickfix。适合一个窗口看文件历史、另一个窗口保留全局 quickfix。

#### 1.4 大仓库的替代方案

`:Gclog` 依赖 quickfix，提交很多时性能较差。可以直接看输出：

```vim
:Git log --oneline --graph --decorate -50
```

需要跳转时再对具体文件用 `:0Gclog`。

### 2. Blame

#### 2.1 打开方式

```vim
:Git blame
:Git blame -L 20,60 file.c
:Git blame file.c
```

无参数时 blame 当前文件，打开 scroll-bound 垂直分屏；带范围或显式文件名时改用水平分屏，不做 scrollbind。

```text
blame 信息                          文件内容
3b753cf sumu 2026-03-07 12:30  │ int main(void) {
0694be2 sumu 2026-03-08 09:10  │     return 0;
```

`<CR>` 跳到引入该行的 patch，`-` 在该提交处重新 blame。

#### 2.2 blame 窗口按键

```text
g?    帮助
A     调整到作者列末尾
C     调整到提交列末尾
D     调整到日期列末尾
gq    关闭 blame，回到工作区版本
<CR>  关闭 blame，跳到引入该行的 patch
o     在水平分屏打开 patch/blob
O     在新标签页打开
p     在 preview 窗口打开
-     在该提交处重新 blame
P     在父提交处重新 blame（实验性）
~     在第一个祖先处重新 blame
```

`<CR>` 是最常用的：直接看到"这行是哪次提交、改了什么"。需要继续追溯时，在 patch 里对相应的 `-` 行再按 `<CR>`。

#### 2.3 范围 blame

```vim
:'<,'>Git blame
```

只 blame 选中行，减少大文件的开销。

### 3. 浏览历史版本

#### 3.1 `:Gedit` 与对象

```vim
:Gedit @^:file.c       " 父提交中的 file.c
:Gedit :file.c         " 索引中的 file.c
:Gedit @~2:%           " 祖父提交中的当前文件
:Gedit !:file.c        " 最后修改当前文件的提交中的 file.c
```

`:Gedit` 打开的是普通缓冲区，改完不会自动写回；需要写回时用 `:Gwrite` 或显式保存。

#### 3.2 分屏打开

```vim
:Gsplit @^:file.c      " 水平分屏
:Gvsplit @^:file.c     " 垂直分屏
:Gtabedit @^:file.c    " 新标签页
:Gpedit @^:file.c      " preview 窗口
:Gdrop @^:file.c       " 若已打开则跳转，否则打开
```

#### 3.3 `:Git show`

```vim
:Git show HEAD:file.c
:Git show --stat HEAD
:Git show 3b753cf
```

`:Git show` 输出的是 git 原始文本，不是 fugitive 的 object 缓冲区；需要编辑或 diff 时用 `:Gedit`/`:Gdiffsplit`。

### 4. 搜索

#### 4.1 `:Ggrep`

```vim
:Ggrep TODO
:Ggrep -i "fugitive" -- "*.vim"
:Ggrep --quiet TODO
```

`:Ggrep` 用 `git grep` 作为 `'grepprg'`，结果进入 quickfix。`--quiet` 只打开 quickfix，不显示命令输出。

```text
:Ggrep TODO
  │
  ▼
quickfix
├─ vimrc:12: TODO ...
├─ docs/LV006-vim-fugitive使用指南.md:88: TODO ...
└─ src/main.c:44: TODO ...

:cnext / :cprev 跳转，:copen 打开列表
```

#### 4.2 `:Glgrep`

```vim
:Glgrep TODO
```

与 `:Ggrep` 相同，结果进入 location list。

#### 4.3 quickfix 列表操作

```text
:copen     打开 quickfix
:cclose    关闭
:cnext     下一个
:cprev     上一个
:colder    上一个 quickfix 列表
```

`:Ggrep`、`:Gclog`、`:Git difftool` 都会复用 quickfix，注意它们可能互相覆盖；需要保留时用 location list 版本或 `:colder`。

## 六、 写操作、分支与远端

### 1. 文件写入与索引

#### 1.1 `:Gwrite`

```vim
:Gwrite
```

把当前缓冲区写入工作区文件，并暂存到索引，等价于"保存 + git add"。

```text
工作区 vimrc ──:Gwrite──▶ 索引 :0:vimrc
工作区 vimrc ◀──:Gread─── 索引 :0:vimrc
```

`:Gwrite` 同时改工作区和索引，`:Gread` 只把索引内容读回缓冲区。

也可以指定路径或索引 stage：

```vim
:Gwrite :0:foo.txt
:Gwrite :0:%
```

在索引缓冲区里执行 `:Gwrite`，行为更接近 `git checkout`。

#### 1.2 `:Gread`

```vim
:Gread
```

清空当前缓冲区，并读入默认对象。无参数时：工作区文件读入索引版本，行为类似 `git checkout`；索引文件读入工作区版本，行为类似 `git add`。两者都只改缓冲区，不写盘。

带范围：

```vim
:'<,'>Gread @^:file.c
```

在选中行之后读入对象内容。

#### 1.3 `:Gwq`

```vim
:Gwq
:Gwq!
```

`:Gwrite` 成功后退出窗口；加 `!` 则连同强制退出。

### 2. 重命名与删除

#### 2.1 `:GMove`

```vim
:GMove new/path.c
:GMove! new/path.c
```

包装 `git mv`，并同步重命名缓冲区；`!` 传递 `-f`。

#### 2.2 `:GRename`

```vim
:GRename new_name.c
```

与 `:GMove` 类似，但目标路径相对于当前文件所在目录，适合只改文件名。

#### 2.3 `:GDelete` 与 `:GRemove`

```vim
:GDelete
:GDelete!
```

包装 `git rm` 并删除缓冲区；在索引文件里执行时自动加 `--cached`，`!` 加 `-f` 并强制丢弃缓冲区。

```vim
:GRemove
:GUnlink
```

与 `:GDelete` 类似，但保留（已经变空的）缓冲区。

### 3. 分支、提交、合并

#### 3.1 分支与 checkout

状态窗口或提交缓冲区里：

```text
coo           checkout 光标下的提交
cb<Space>     命令行预填 ":Git branch "
co<Space>     命令行预填 ":Git checkout "
cb? / co?     帮助
```

直接用命令也很清晰：

```vim
:Git switch -c feature/login
:Git switch main
:Git branch -d old-branch
```

#### 3.2 `:Git commit`

```vim
:Git commit
:Git commit -v
:Git commit --amend
```

提交信息在分屏中编辑；写入并关闭完成提交。想取消时，不写入直接关闭，或清空内容后关闭（git 会因空信息中止）。

#### 3.3 merge 与 rebase

```vim
:Git merge feature/login
:Git rebase -i HEAD~3
:Git mergetool
```

状态窗口里的快捷映射：

```text
cm<Space>   预填 ":Git merge "
ri          交互式 rebase
rf          autosquash rebase
ru          针对 @{upstream} 的交互式 rebase
rp          针对 @{push} 的交互式 rebase
rr / rs / ra / re     continue / skip / abort / edit todo
rw / rm / rd          reword / edit / drop 光标下提交
```

### 4. 远端与浏览器

#### 4.1 push / fetch / pull

```vim
:Git push
:Git push -u origin HEAD
:Git fetch --all --prune
:Git pull --rebase
```

需要认证时，Unix pty 会把提示显示在 Vim 里；长操作可以改用 `:Git!`，但交互式认证在预览模式下不一定可用。

#### 4.2 `:GBrowse`

```vim
:GBrowse
:GBrowse @^:file.c
:'<,'>GBrowse
:GBrowse!
```

行为：

- 打开当前文件、blob、tree、commit 或 tag 的托管页面；
- 带范围时在 URL 后加行号锚点，并强制使用 commit 而不是分支名；
- `:GBrowse {url}` 直接打开任意 URL；
- `:GBrowse [...]@{remote}` 指定用于推断仓库地址的 remote；
- `:GBrowse!` 把 URL 放到剪贴板而不是打开浏览器。

GitHub 支持需要额外安装 `vim-rhubarb`；没有 provider 插件时，只能打开已知的 URL 或提示不支持。

【**注意**】

本机 Vim 是 `-clipboard`，`:GBrowse!` 的剪贴板写入可能不可用；用 `:GBrowse` 直接打开浏览器更稳妥。

#### 4.3 `:Git difftool` 与 `:Git mergetool`

这两个命令已在 diff/冲突章节展开：

```vim
:Git difftool          " hunk 进 quickfix
:Git difftool -y       " 每个文件一个 tab
:Git mergetool         " 冲突 hunk 进 quickfix
```

### 5. 扩展点

#### 5.1 状态栏

```vim
set statusline=%<%f\ %h%m%r%{FugitiveStatusline()}%=%-14.(%l,%c%V%)\ %P
```

`FugitiveStatusline()` 返回当前分支和当前文件的提交信息。使用 vim-airline 时，分支信息通常由 airline 的 branch 扩展提供，不必重复添加。

#### 5.2 User 自动命令

fugitive 提供一组 `User` 事件：

| 事件 | 触发时机 |
|:--|:--|
| `FugitiveIndex` | 打开 summary 缓冲区后 |
| `FugitiveBlob` | 打开已提交的 blob 后 |
| `FugitiveStageBlob` | 打开索引 blob 后 |
| `FugitiveCommit` | 打开 commit 对象后 |
| `FugitiveTree` | 打开 tree 对象后 |
| `FugitiveTag` | 打开 tag 对象后 |
| `FugitiveObject` | 打开以上任意对象后 |
| `FugitivePager` | 打开 `:Git --paginate`/`:Git blame` 的临时文件后 |
| `FugitiveEditor` | `:Git` 命令打开提交信息等文件后 |
| `FugitiveChanged` | 任何可能改变仓库的操作后 |

例如在状态窗口打开时设置局部选项：

```vim
autocmd User FugitiveIndex setlocal number
```

#### 5.3 禁用全局映射

```vim
let g:fugitive_no_maps = 1
```

会禁用 `<C-R><C-G>`、`y<C-G>` 等全局映射，适合和已有键位冲突时使用。

## 七、 排障与速查

### 1. 常见问题

#### 1.1 命令不可用

现象：`:Git` 没有打开状态窗口，或提示当前不在 Git 仓库中。

原因通常是：

（1）当前缓冲区不属于任何 Git 仓库——先打开仓库里的一个文件，用 `:echo FugitiveGitDir()` 确认返回值非空；

（2）Vim 处于 `'compatible'` 模式——fugitive 要求 `nocompatible`，在 vimrc 中加 `set nocompatible`；

（3）插件没有加载——检查 `:scriptnames` 是否有 `fugitive/plugin/fugitive.vim`，以及 `pack/vendor/start/vim-fugitive` 软链是否存在；

（4）`git` 不在 `PATH`——先确认 `:!git --version` 可用。

#### 1.2 不在仓库中

`:Git` 在非仓库缓冲区里不可用。确认仓库位置：

```vim
:echo FugitiveGitDir()     " .git 目录
:echo FugitiveWorkTree()   " 工作树根目录
```

嵌套仓库或 worktree 场景下，`:Gcd` 可以切换到仓库根，`:Glcd` 只切换当前窗口的本地目录。

#### 1.3 提交窗口与中断

`:Git commit` 打开提交信息窗口后：

- 写入并关闭：提交；
- 不写入直接关闭：放弃；
- 窗口关不掉或提示 `index.lock`：检查是否有其它 git 进程在运行，必要时删除 `.git/index.lock`（确认没有进程占用）。

#### 1.4 性能

- `:Gclog` 在超大历史下会卡，用 `:Git log --oneline`；
- `:Git blame` 对大文件慢，用范围 `:'<,'>Git blame`；
- `:Git` 长命令阻塞 Vim，用 `:Git!` 或 `:Git --paginate`；
- `:Git difftool -y` 文件很多时会开很多 tab，先用 `-- path` 过滤。

### 2. 与其它插件协作

#### 2.1 vim-gitgutter

gitgutter 在行号旁显示 `+`/`-`/`~` 标记，适合常驻提示；fugitive 负责完整 diff、暂存和提交。二者不冲突，但都可能让 Vim 变慢，按需启用。

#### 2.2 vim-rhubarb

为 `:GBrowse` 提供 GitHub URL 推断。装法：

```vim
Plug 'tpope/vim-rhubarb'
```

没有它时，`:GBrowse` 在 GitHub 仓库上通常无法生成正确链接。

#### 2.3 vim-plug

二者职责不同：

- vim-plug 管插件安装、更新、懒加载；
- vim-fugitive 管 Git 仓库操作。

本仓库把 fugitive 放在 `pack/vendor/start`，走原生 package 加载，与 vim-plug 的 `plugged` 目录互不影响。

### 3. 速查表

#### 3.1 命令速查

| 命令 | 作用 |
|:--|:--|
| `:Git` | 打开状态窗口 |
| `:Git status` | git status |
| `:Git diff` | 工作区 vs 索引 |
| `:Gdiffsplit` | 当前文件 diff |
| `:Gvdiffsplit` | 当前文件左右 diff |
| `:Git blame` | 逐行归属 |
| `:Gclog` | 提交历史进 quickfix |
| `:Ggrep` | git grep 进 quickfix |
| `:Gwrite` | 保存并暂存 |
| `:Gread` | 用索引覆盖缓冲区 |
| `:GMove` | git mv + 重命名缓冲区 |
| `:GDelete` | git rm + 删除缓冲区 |
| `:GBrowse` | 打开托管页面 |
| `:Git difftool -y` | 每个文件一个 diff tab |

#### 3.2 状态窗口按键

| 按键 | 作用 |
|:--|:--|
| `s` / `u` / `-` | 暂存 / 取消暂存 / 切换 |
| `U` | 取消暂存全部 |
| `X` | 丢弃改动（`2X`/`3X` 取 ours/theirs） |
| `=` / `>` / `<` | 内联 diff 切换 / 展开 / 收起 |
| `dd` / `dv` / `ds` | 自动 / 左右 / 上下 diff |
| `cc` / `ca` / `cw` | 提交 / amend / reword |
| `gu` / `gs` / `gp` | 跳到 Untracked / Staged / Unpushed |
| `<CR>` / `o` / `O` | 打开 / 分屏 / 新 tab |
| `g?` | 帮助 |

#### 3.3 diff 窗口按键

| 按键 | 作用 |
|:--|:--|
| `]c` / `[c` | 下一个 / 上一个 hunk |
| `do` | 从对方取到当前窗口 |
| `dp` | 把当前内容推到对方 |
| `:Gwrite` | 保存并暂存 |
| `:Gread` | 用索引覆盖缓冲区 |
| `:diffupdate` | 重新计算 diff |
| `:diffoff` | 关闭 diff 模式 |

### 4. 版本与更新

当前内置版本：

```text
commit  3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0
date    2026-03-07
ref     master
```

更新方式：

```bash
scripts/sync-plugins.sh --dry-run
scripts/sync-plugins.sh
```

同步脚本会拉取上游完整工作树、替换 `pack/vendor/start/vim-fugitive`、回写 `pack/plugins.tsv` 并刷新 README 版本表。更新后重新执行 `./vim-plug.sh link` 不必要，软链指向目录本身；但帮助标签需要重新生成时，执行 `:helptags`。

---

*本文档由 markdowncli 技能辅助生成*
