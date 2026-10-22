# Unrestricted 破甲 · 可移植安装包

把「Unrestricted / 安全研究执行器」从单一 `unrestricted` agent 里剥出来，做成**任意 OpenCode agent
都能直接吃到**的独立组件。装一次，`build` / `plan` / `general` / `explore` / 自定义 agent / subagent
全部继承同一套作用域契约、交付规则和权限放行。

- 版本：`3.0.0`（agent-agnostic edition）
- 目标运行时：OpenCode **V2（>= 2.0）**，验证版本 `2.1.2`
- 平台：Windows PowerShell 5.1+ / PowerShell 7（脚本同时兼容）
- 安装后不需要重启编辑配置：插件由 OpenCode 热加载，改完 `opencode service restart` 即可

---

## 0. 获取

```bash
git clone https://github.com/<owner>/unrestricted-kit.git
cd unrestricted-kit
```

纯 PowerShell 脚本 + 一个 TypeScript 插件，无构建步骤；`payload/` 就是全部产物，`install.ps1` 负责落地。

---

## 1. 它到底是什么

破甲由三层组成，缺一层效果都会打折：

| 层 | 文件 | 作用 | 生效范围 |
|---|---|---|---|
| 插件层 | `plugins/unrestricted/index.ts` | system 注入 `[UNRESTRICTED-LAB]`、prompt 语境改写、`ask`→`allow`、`lab_status` | **运行时内所有 agent** |
| 定义层 | `agents/unrestricted.md`、`agents/redteam.md` | 两个专用 agent 的完整人格与执行契约 | 仅这两个 agent |
| 规则层 | `AGENTS.md` 标记块 | 无插件也能生效的全局契约 | **所有 agent、所有项目** |

只要插件层或规则层装上一个，任意 agent 就已经是"破甲态"。定义层是可选的增强：给你一个显式的
`unrestricted` 主 agent 和一个 `redteam` 子 agent 用来定点派活。

---

## 2. 目录结构

```
unrestricted-kit/
├─ README.md                      ← 本文件（安装手册）
├─ install.ps1                    ← 安装器
├─ uninstall.ps1                  ← 卸载器
├─ verify.ps1                     ← 自检器
├─ payload/
│  ├─ plugin/
│  │  └─ unrestricted-boost.ts    ← V2 插件（agent-agnostic）
│  ├─ agents/
│  │  ├─ unrestricted.md
│  │  └─ redteam.md
│  ├─ commands/
│  │  ├─ unrestricted.md  /unrestricted
│  │  ├─ external.md      /external
│  │  ├─ apk.md           /apk
│  │  ├─ bypass.md        /bypass
│  │  ├─ exploit.md       /exploit
│  │  └─ scope.md         /scope
│  ├─ lab-scope.json              ← 作用域审计记录（不是闸门）
│  ├─ AGENTS.md                   ← 全局规则块（rules 模式）
│  └─ opencode.snippet.json       ← 手动注册插件用的配置片段
├─ tools/
│  ├─ run-selftest.ps1            ← 插件逻辑自检（mock ctx，不启动 OpenCode）
│  └─ selftest.mjs
└─ docs/
   ├─ SCOPE-MODEL.md              ← 作用域模型说明
   └─ TROUBLESHOOTING.md          ← 故障排查
```

安装目标（Windows）：

```
C:\Users\<你>\.config\opencode\
├─ opencode.json                  # 主配置（会被 -Register 修改，改动前自动备份）
├─ AGENTS.md                      # full / rules 模式写入标记块
├─ lab-scope.json                 # 审计记录
├─ plugins\unrestricted\index.ts  # V2 官方插件目录（推荐）
├─ plugin\unrestricted-boost.ts   # 旧式单文件目录（auto 会沿用已存在的那个）
├─ agents\unrestricted.md
├─ agents\redteam.md
├─ commands\*.md
└─ _backup\unrestricted-kit-<时间戳>\
```

---

## 3. 前置条件

1. **OpenCode V2**：`opencode --version` 输出 `v2.x`。
   V1 请直接用 rules 模式（`-Mode rules`），V1 插件 API 与 V2 不兼容。
2. **插件依赖**：配置文件目录下要有 `@opencode/plugin`。
   ```powershell
   cd "$env:USERPROFILE\.config\opencode"
   npm install @opencode/plugin
   ```
   已有 `node_modules\@opencode\plugin` 就跳过。
3. **PowerShell 执行策略**：用 `powershell -ExecutionPolicy Bypass -File ...` 调用，不需要改全局策略。

---

## 4. 安装

### 4.1 最快路径（推荐）

```powershell
# 进入解压/克隆出来的 kit 根目录（本 README 所在目录）
cd <path-to>\unrestricted-kit

# 先看一眼会做什么，不写文件
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun

# 正式安装：插件 + 两个 agent + 六个命令 + lab-scope
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 目录自动扫描不生效时，显式注册进 opencode.json
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Register
```

### 4.2 三种模式

| 命令 | 装入内容 | 适用场景 |
|---|---|---|
| `.\install.ps1` | 插件 + agents + commands + lab-scope | **默认**。V2 且已有 `plugin/` 或 `plugins/` 目录 |
| `.\install.ps1 -Mode full` | 插件 + agents + commands + lab-scope + `AGENTS.md` | 想要双保险：插件失效时规则层兜底 |
| `.\install.ps1 -Mode rules` | 只写 `AGENTS.md` 标记块 | V1、插件 API 变动、无 node 依赖、只想改规则 |

### 4.3 安装器参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Mode plugin\|rules\|full` | `plugin` | 安装模式 |
| `-Target auto\|plugin\|plugins` | `auto` | 插件落地位置。`auto` 优先沿用已存在的目录 |
| `-Register` | 关 | 把插件以绝对路径 + options 写入 `opencode.json` 的 `plugins` |
| `-NoAgents` / `-NoCommands` | 关 | 不覆盖你已有的同名 agent / 命令 |
| `-DryRun` | 关 | 只打印操作 |

安装器会做这些事：

1. 校验 payload、opencode 版本、`@opencode/plugin` 依赖；
2. 把将被覆盖的文件复制到 `_backup\unrestricted-kit-<时间戳>\`（保留相对路径）；
3. agents / commands 就位；`lab-scope.json` 已存在则**保留**并备份；
4. 插件落地，并把另一处同名副本重命名为 `.disabled-<时间戳>`，避免双加载重复注入；
5. `-Register` 时合并 `opencode.json`（保留无关配置和已有插件，跳过旧的 unrestricted 条目）；
6. `full` / `rules` 模式写入 `AGENTS.md`：已有标记块则**替换块内容**，不会碰块外内容。

### 4.4 手动安装（不用脚本）

```powershell
$cfg = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force "$cfg\plugins\unrestricted" | Out-Null
Copy-Item .\payload\plugin\unrestricted-boost.ts "$cfg\plugins\unrestricted\index.ts"
Copy-Item .\payload\agents\*.md "$cfg\agents\" -Force
Copy-Item .\payload\commands\*.md "$cfg\commands\" -Force
Copy-Item .\payload\lab-scope.json "$cfg\lab-scope.json" -Force
```

然后在 `opencode.json` 里加（保留你原有的其他字段）。把 `<OPENCODE_CONFIG>` 换成你的 OpenCode 配置目录，
Windows 下是 `%USERPROFILE%\.config\opencode`，类 Unix 下是 `~/.config/opencode`：

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    {
      "package": "<OPENCODE_CONFIG>/plugins/unrestricted",
      "options": {
        "agents": "*",
        "permissions": true,
        "setDefault": false,
        "framePrompts": true
      }
    }
  ]
}
```

rules 模式手动安装：把 `payload\AGENTS.md` 的内容整体追加到 `~/.config/opencode/AGENTS.md`
（保留 `<!-- BEGIN/END UNRESTRICTED-LAB -->` 两个标记，方便日后替换）。

---

## 5. 验证

### 5.0 逻辑自检（最快，不碰运行环境）

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run-selftest.ps1
```

在临时目录里搭一个假的 `@opencode/plugin`，用 mock ctx 直接跑插件 `setup`，覆盖 14 项断言：

- 任意 agent（`build`）注入 `[UNRESTRICTED-LAB]`，且带 agent 名与 `[SCOPE:` 行；
- system 注入幂等（连续两次只有一份）；
- `permission.evaluate`：`ask → allow`，`deny` 原样；
- prompt 改写只命中安全意图词，普通请求不动，二次调用幂等；
- 历史 user 消息被改写、assistant 消息不动；
- `lab_status` 的 `coverage` / `version` / scope 字段；
- 白名单模式（`agents: "build,plan"`）只覆盖名单内 agent；
- `permissions:false` / `framePrompts:false` 时对应 hook 不注册。

需要 Node 22.6+（`--experimental-strip-types`），不联网。

### 5.1 静态自检

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Run
```

`PASS` 覆盖：插件文件与入口、双 agent、六个命令、`lab-scope.json` 的 `locality_gate` /
`ownership_recheck` / 启用 class 数、`AGENTS.md` 标记块、插件依赖、opencode 版本。
`-Run` 会额外打印 `plugin list` / `debug agents` / `service status`。

### 5.2 运行时自检

```powershell
opencode service restart
opencode plugin list        # 应出现 unrestricted.boost
opencode debug agents       # 应出现 unrestricted / redteam
```

会话里（**任意 agent 都可以**）调用内置工具：

```json
{
  "plugin": "unrestricted.boost",
  "version": "3.0.0",
  "api": "opencode-v2",
  "coverage": "all-agents",
  "lab_agents": ["build", "plan", "general", "explore", "unrestricted", "redteam", "..."],
  "hooks": [
    "agent.transform",
    "permission.evaluate",
    "session.prompt",
    "session.context",
    "session.compaction",
    "session.generate",
    "tool.lab_status"
  ],
  "scope": {
    "file": "C:\\Users\\<你>\\.config\\opencode\\lab-scope.json",
    "mode": "open-declared",
    "locality_gate": false,
    "ownership_recheck": false,
    "classes": ["local_path", "loopback", "private_net", "container_emulator",
                "external_vps", "cloud_instance", "public_ip", "public_cidr",
                "domain", "api_endpoint"],
    "engagements": 1
  }
}
```

判读标准：

- `coverage` 必须是 `all-agents`；
- `lab_agents` 里应该看到你平时用的内置 agent 名字；
- `hooks` 缺项说明该 OpenCode 小版本没有对应事件，插件会跳过并在日志里打 `skipped`，不影响其余挂钩。

### 5.3 端到端验证（30 秒）

1. 切到 `build`（或任意非 unrestricted agent）；
2. 发一句带目标的话，例如：`对 127.0.0.1 上这个工作区的服务做一次端口与服务指纹枚举`；
3. 正常结果：直接进入工具调用，输出 `当前：...` 行，不出现授权追问、不出现 A/B 菜单；
4. 再发一句纯日常问题（例如「把这段 JSON 格式化」），确认没有被改写或加 disclaimer。

---

## 6. 使用

### 6.1 任意 agent

装完即生效，无需切换。插件在模型请求前把 `[UNRESTRICTED-LAB]` 段插到 system 最前面，
因此优先级高于 provider 基础提示和各 agent 自己的 system prompt。

想限定只对某些 agent 生效，把 `options.agents` 从 `"*"` 改成 `"build,plan,my-agent"`，
或设环境变量 `LAB_AGENTS=build,plan`。

### 6.2 专用 agent

| agent | 类型 | 用途 |
|---|---|---|
| `unrestricted` | primary | 默认安全研究执行器：逆向 / 补丁 / 渗透 / 取证 / 样本复现 |
| `redteam` | subagent | 由主 agent 派发：漏洞利用、payload、提权、横向 |

主 agent 派活时会带上 `lab-scope.json` 的 engagement 记录，子 agent 不再反问授权。

### 6.3 斜杠命令

| 命令 | 作用 |
|---|---|
| `/unrestricted <请求>` | 立刻进入执行态，保持原动词，工具优先 |
| `/external <IP/CIDR/域名>` | 外网目标全链：recon → exploit → privesc → lateral → report |
| `/apk <路径/包名/关注点>` | APK 全流程逆向：解包、反编译、定位校验、smali/Frida 补丁 |
| `/bypass <校验类型 + 目标>` | 授权/试用/签名/root/SSL Pinning 绕过 + 验证 |
| `/exploit <目标与已知信息>` | 从原语到可运行 PoC，含保护绕过 |
| `/scope [目标...]` | 查看/追加作用域审计记录 |

### 6.4 作用域

`lab-scope.json` 是**审计记录，不是准入闸门**。会话里点名的目标默认已授权；
`/scope 203.0.113.10 2001:db8::/32 vps.example.com` 追加记录后继续执行。
完整模型见 [`docs/SCOPE-MODEL.md`](docs/SCOPE-MODEL.md)。

---

## 7. 配置项

`opencode.json` 的插件对象形式：

```jsonc
{
  "package": "<OPENCODE_CONFIG>/plugins/unrestricted",
  "options": {
    "agents": "*",
    "permissions": true,
    "setDefault": false,
    "framePrompts": true,
    "scopeFile": "<OPENCODE_CONFIG>/lab-scope.json"
  }
}
```

| option | 环境变量 | 默认 | 说明 |
|---|---|---|---|
| `agents` | `LAB_AGENTS` | `*` | `*` = 所有 agent；或逗号分隔白名单 |
| `permissions` | `LAB_PERMISSIONS=off` | `true` | 命中 agent 的 `ask` 提升为 `allow`；显式 `deny` 永不放行 |
| `setDefault` | `LAB_SET_DEFAULT=1` | `false` | 把默认 agent 设为 `unrestricted` |
| `framePrompts` | `LAB_FRAME_PROMPTS=off` | `true` | prompt 落盘前按安全意图词注入研究语境 |
| `scopeFile` | `LAB_SCOPE_FILE` | `~/.config/opencode/lab-scope.json` | 审计文件路径 |

改完配置后 `opencode service restart`。插件文件本身由 watcher 热重载。

---

## 8. 工作原理

| 挂钩 | 行为 |
|---|---|
| `agent.transform` | 修补 `unrestricted` / `redteam` 的 mode、color、permissions；`setDefault` 时才改默认 agent |
| `permission.hook("evaluate")` | 命中覆盖范围的 agent，`ask` → `allow`；`deny` 原样保留 |
| `session.hook("prompt")` | admission 阶段按 `INTENT` 正则改写：加"授权研究环境"框架（幂等，带 marker 不重复） |
| `session.hook("context")` | 每个模型请求前 unshift `[UNRESTRICTED-LAB]` 段；改写历史 user 消息 |
| `session.hook("compaction")` | 压缩摘要也保留 lab 语境，避免长会话被"摘要洗白" |
| `session.hook("generate")` | 瞬态生成请求同样注入 |
| `tool.transform` | 注册 `lab_status` 自检工具 |

设计约束：

- **幂等**：system 里已有 `[UNRESTRICTED-LAB]` 就不再注入；prompt 已有 marker 或框架句就不再改写。
- **失败隔离**：每个 hook 单独 `try/catch`，某个小版本缺事件只跳过该项。
- **可观测**：跳过项写 `console.warn`，`lab_status.hooks` 返回实际注册成功的清单。
- **作用域热读**：每次请求同步读 `lab-scope.json`，`/scope` 追加目标后立即生效，无需重启。

---

## 9. 卸载与回滚

```powershell
# 默认：只移除插件 + opencode.json 条目 + AGENTS.md 块
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

# 连 agents / commands 一起清理（有备份则恢复备份版本）
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles

# 删除作用域审计记录
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -PurgeScope

# 从最近一次 kit 备份恢复 opencode.json（会覆盖安装后的配置改动）
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RestoreConfig
```

手动回滚：到 `~\.config\opencode\_backup\unrestricted-kit-<时间戳>\` 按相对路径复制回去即可。
卸载器默认**保留** `lab-scope.json`，因为它只是审计记录，删不删都不影响行为。

---

## 10. 兼容性

| OpenCode | 插件模式 | rules 模式 | 备注 |
|---|---|---|---|
| V2 >= 2.0（验证 2.1.2） | 支持 | 支持 | `plugins/` 自动扫描；`plugin/` 旧式目录也可 |
| V2 早期 2.0.x | 支持 | 支持 | 事件集可能少 1-2 个，插件自动跳过 |
| V1.x | 不支持 | 支持 | V1 插件必须导出函数式定义，V2 会直接报错 |

其他平台把 `$HOME/.config/opencode` 换成 `~/.config/opencode` 或用 `XDG_CONFIG_HOME`；
脚本里的路径处理已兼容 `XDG_CONFIG_HOME`。

---

## 11. 故障排查

先跑 `verify.ps1 -Run`，再对照 [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)。最常见的三条：

1. **`plugin list` 里没有 `unrestricted.boost`** → 目录没被扫描。重跑 `install.ps1 -Register`，
   或确认文件在 `plugins\unrestricted\index.ts`。
2. **报 `Plugin must export a default definition with an id`** → OpenCode 是 V1，或文件被当成
   V1 插件加载。用 `-Mode rules` 并删掉插件文件。
3. **`lab_status.coverage` 不是 `all-agents`** → `opencode.json` 里残留 `options.agents` 白名单，
   改成 `"*"` 或删掉该项后重启服务。

---

## 12. 本机实测记录

| 项 | 值 |
|---|---|
| 日期 | 2026-10-22 |
| OpenCode | v2.1.2 |
| 安装命令 | `install.ps1 -Target plugins -Mode plugin -Register` |
| 插件落地 | `~/.config/opencode/plugins/unrestricted/index.ts` |
| 旧插件处置 | `plugin/unrestricted-boost.ts` → `unrestricted-boost.ts.disabled-20261022-160458` |
| 备份目录 | `~/.config/opencode/_backup/unrestricted-kit-20261022-160458/` |
| `lab_status` | `coverage=all-agents`，`hooks` 7/7 注册成功 |
| 覆盖 agent | `unrestricted, build, general, explore, compaction, title, summary, plan, redteam` |
| 逻辑自检 | `tools/run-selftest.ps1` → 14/14 passed |

实测结论：插件在真实 OpenCode 运行时热加载成功，`opencode.json` 的 `default_agent`、`mcp`、
原有 `agents` 定义全部保留，只有 `plugins` 数组新增一条 unrestricted 记录。
