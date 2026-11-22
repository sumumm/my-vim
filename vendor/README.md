<!-- more -->

`vendor/` 存放第三方的安装期资源：脚本会读取或拷贝这里的文件，但 Vim 启动时不会把它们加入 `runtimepath`。

## 一、 目录定位

### 1. 目录职责

这里的文件只服务于安装与同步流程，不参与编辑器运行时的插件加载。需要被 Vim 加载的插件放在 `pack/vendor/start/`，两者职责互不重叠。

### 2. 文件清单

| 文件 | 上游 | 用途 |
| --- | --- | --- |
| `plug.vim` | [junegunn/vim-plug](https://github.com/junegunn/vim-plug) | vim-plug 本体，上游以单文件发布，由安装脚本拷贝到编辑器的 autoload 目录 |

## 二、 plug.vim 的存放原因

### 1. 官方安装位置

vim-plug 的官方安装方式就是把 `plug.vim` 放进编辑器的 `autoload` 目录：

- Vim：`~/.vim/autoload/plug.vim`
- Neovim：`${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/autoload/plug.vim`

它是安装期资产，不是运行期插件，因此没有放进 `pack/vendor/start/`。

### 2. 与 pack 目录的分工

| 位置 | 形态 | 使用者 | 接入方式 |
| --- | --- | --- | --- |
| `pack/vendor/start/<插件>/` | 插件目录 | Vim 启动时 | `./vim-plug.sh link` 软链到 `~/.vim/pack/vendor/start/`，由原生 pack 加入 `runtimepath` |
| `vendor/plug.vim` | 单文件 | 安装脚本 | `./vim-plug.sh install` 拷贝到 `~/.vim/autoload/` |

### 3. 放进 pack 的后果

如果把 `plug.vim` 放进 `pack/vendor/start/vim-plug/autoload/`，Vim 会把它当作普通插件目录自动加入 `runtimepath`。这样 `vimrc` 里 `globpath(&runtimepath, 'autoload/plug.vim')` 的判断、`status` 输出的“是否已安装”、`uninstall` 的删除动作都会失去意义。

## 三、 使用与更新

### 1. 安装期处理流程

执行 `./vim-plug.sh`（默认动作 install）时会走 `fetch_plug`，流程如下：

（1）默认优先使用本目录这份副本（变量 `PLUG_LOCAL`），无网络也能完成安装。

（2）使用前经 `verify_plug` 校验：体积大于 `30000` 字节，且含 `function! plug#begin` 与 `plug#end`，避免误用 HTML 错误页。

（3）目标位置已有文件时，先备份为 `plug.vim.bak.<时间戳>` 再覆盖。

（4）`--online` 跳过本地副本强制下载，`--mirror` 优先走国内加速镜像。

`uninstall` 只删除 home 里的副本，不动本目录；`link` 与 `status` 也不读写它，`status` 展示的是 home 里那份是否已安装。

### 2. 更新方式

上游地址、分支与提交记录在 `../pack/plugins.tsv`，根目录 README 的版本表由该清单生成：

```bash
scripts/sync-plugins.sh --dry-run   # 只检查上游是否有新提交
scripts/sync-plugins.sh             # 按清单同步并刷新版本表
```

同步脚本对文件型 target 只覆盖同名文件（`sync_file`），不会改动本目录其他内容。

也可以手动更新：从上游下载 `plug.vim` 覆盖本文件，再执行 `./vim-plug.sh install` 刷新 home 里的副本。

### 3. 维护约定

不要手工修改 `plug.vim`，保持与上游逐字节一致，diff 与自动同步才有意义。

---

*本文档由 markdowncli 技能辅助生成*
