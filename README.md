# my-vim

个人 Vim 配置仓库。内置 NERDTree 与 vim-plug，克隆后无需联网即可使用。

## 快速开始

```bash
git clone https://cnb.cool/sumu.k/my-vim.git ~/my-vim
cd ~/my-vim

./vim-plug.sh link            # 接入内置插件，离线可用
./vim-plug.sh --with-config   # 安装 vim-plug 并写入 ~/.vimrc
```

之后直接 `vim` 打开，左侧自动出现目录树。内置插件走 Vim 8 原生 `pack` 机制，不需要 `:PlugInstall`。

## 命令速查

| 命令 | 说明 |
|---|---|
| `./vim-plug.sh link` | 把内置插件软链到 `~/.vim/pack` |
| `./vim-plug.sh --with-config` | 安装 vim-plug，并把 `vimrc` 追加到 `~/.vimrc` |
| `./vim-plug.sh plugins` | 联网安装 `vimrc` 中声明的插件 |
| `./vim-plug.sh status` | 查看已装插件与版本 |
| `./vim-plug.sh uninstall` | 卸载 vim-plug、配置块与内置插件软链 |

## 内置组件版本

<!-- BEGIN AUTOGEN:components -->
| 组件 | 上游仓库 | 跟踪 | 提交 | 日期 |
|---|---|---|---|---|
| lightline | [lightline.vim](https://github.com/itchyny/lightline.vim) | master | [`255f61d`](https://github.com/itchyny/lightline.vim/commit/255f61db1a4cc36ee11eb479261d6bc471ed0819) | 2026-10-06 |
| nerdtree | [nerdtree](https://github.com/preservim/nerdtree) | master | [`690d061`](https://github.com/preservim/nerdtree/commit/690d061b591525890f1471c6675bcb5bdc8cdff9) | 2025-09-26 |
| vim-plug | [vim-plug](https://github.com/junegunn/vim-plug) | master | [`4c4e56b`](https://github.com/junegunn/vim-plug/commit/4c4e56b5f7384369927a075804b6a17de7644edd) | 2026-11-07 |
<!-- END AUTOGEN:components -->

本表格由 `pack/plugins.tsv` 生成，请勿手动编辑。执行 `scripts/update-readme.sh` 刷新，`--check` 用于校验是否过期。

## 目录结构

```
my-vim/
├── vimrc                         基础配置：插件声明、NERDTree、netrw 兜底
├── vim-plug.sh                   安装与卸载脚本
├── pack/
│   ├── plugins.tsv               内置组件清单（上游地址、分支、提交）
│   └── vendor/start/nerdtree/    NERDTree 源码，与上游逐文件一致
├── vendor/plug.vim               vim-plug 本体
├── scripts/
│   ├── sync-plugins.sh           同步上游、回写清单并提交
│   └── update-readme.sh          刷新本文件的版本表
└── .cnb/workflows/cnb-crontab.yml  每日自动同步的定时任务
```

## 更新内置组件

```bash
scripts/sync-plugins.sh --dry-run   # 只检查上游是否有新提交，不改动工作区
scripts/sync-plugins.sh             # 同步源码 + 回写 plugins.tsv + 刷新 README + 提交推送
scripts/sync-plugins.sh --no-push   # 同步并提交，但不推送
```

CNB 流水线见 `.cnb/workflows/cnb-crontab.yml`，每天 03:30（Asia/Shanghai）自动执行一次，没有更新时不产生提交。

只想刷新版本表、不检查上游时，单独执行 `scripts/update-readme.sh`。

## 依赖

- Vim 8.0+ 或 Neovim
- `curl` 或 `wget`（仅联网安装时需要）
- `git`（仅 `plugins` 子命令需要）
