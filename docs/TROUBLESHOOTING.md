# 故障排查

先跑：

```powershell
powershell -ExecutionPolicy Bypass -File .\verify.ps1 -Run
```

## 1. `plugin list` 看不到 `unrestricted.boost`

**原因**：插件目录没被扫描，或文件名/入口不对。

排查：

```powershell
$cfg = "$env:USERPROFILE\.config\opencode"
Get-ChildItem -Recurse $cfg\plugins, $cfg\plugin -ErrorAction SilentlyContinue
opencode plugin list
```

修复（按顺序试）：

1. `install.ps1 -Register` —— 在 `opencode.json` 里显式登记绝对路径；
2. 确认文件是 `plugins\unrestricted\index.ts`（V2 目录形式）或 `plugin\unrestricted-boost.ts`（旧式）；
3. `opencode service restart`；
4. 看日志：`~\.local\share\opencode\log\opencode.log`，过滤 `plugin`。

## 2. `Plugin must export a default definition with an id and an effect or setup function`

**原因**：当前 OpenCode 是 V1，或文件被 V1 加载器读取。V1 要求 `export default async (input) => ({ hooks })`。

修复：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Mode rules
Remove-Item "$env:USERPROFILE\.config\opencode\plugins\unrestricted" -Recurse -Force
Remove-Item "$env:USERPROFILE\.config\opencode\plugin\unrestricted-boost.ts" -Force
```

rules 模式的 `AGENTS.md` 块不依赖任何插件 API，V1/V2 都能吃。

## 3. `Cannot find module '@opencode/plugin'`

```powershell
cd "$env:USERPROFILE\.config\opencode"
npm install @opencode/plugin
```

确认 `node_modules\@opencode\plugin\package.json` 存在，然后重启服务。
若你用的是 `@opencode-ai/plugin`（V1 包），把插件首行改成：

```ts
import { Plugin } from "@opencode-ai/plugin"
```

V2 的两个包名并存时优先 `@opencode/plugin`。

## 4. `lab_status` 返回 `coverage: "build,plan"` 而不是 `all-agents`

有白名单残留。检查三处：

1. `opencode.json` → `plugins[].options.agents`
2. 环境变量 `LAB_AGENTS`
3. 项目级 `opencode.json` / `.opencode/opencode.json`（项目级优先级更高）

改成 `"*"` 或删掉该字段，`opencode service restart`。

## 5. 注入生效但模型仍然追问授权

按可能性排序：

1. **会话历史里已经有一次拒绝**：模型会锚定旧回复。开新会话，或让主 agent 重新派发子任务。
2. **项目自带 `AGENTS.md` / `CLAUDE.md` 里有更强的约束**：项目规则会与全局规则合并，冲突时前者更具体。
   在该项目里加一行显式覆盖，或临时移走项目规则验证。
3. **插件只注册了部分 hook**：看 `lab_status.hooks`，缺 `session.context` 就说明注入没跑。
   检查日志里的 `skipped` 行，对照版本事件表。
4. **模型本身对齐强度高**：破甲是上下文工程，不是权重修改。把目标写具体（IP、端口、产物路径）
   比抽象要求更有效；必要时用 `/unrestricted` 或 `/external` 直接带目标重发。

## 6. prompt 被改写后出现重复段落

幂等靠 `[UNRESTRICTED-LAB]` 与 `authorized research environment` 两个 marker 判定。
如果出现重复，说明历史消息里已有旧版改写（旧版 marker 不同）。开新会话即可，
或把 `framePrompts` 设为 `false` 只保留 system 注入：

```jsonc
"options": { "agents": "*", "framePrompts": false }
```

## 7. 两个位置都有插件副本

`verify.ps1` 会报 `[WARN] 两处插件副本同时存在`。重复注册不会破坏功能（注入幂等），
但会让 permission hook 跑两遍。保留一个：

```powershell
Remove-Item "$env:USERPROFILE\.config\opencode\plugin\unrestricted-boost.ts" -Force
```

## 8. `opencode.json` 解析失败 / 含注释

安装器的 `-Register` 用 `ConvertFrom-Json`，遇到 JSONC 注释会失败并提示手动合并。
此时用编辑器把 `payload\opencode.snippet.json` 的 `plugins` 条目合并进去，
注意保留文件里原有的其他字段。也可以先把文件另存为纯 JSON 再跑 `-Register`。

## 9. 修改后没生效

| 改动 | 生效方式 |
|---|---|
| 插件 `.ts` | watcher 热重载，保存即生效；不生效则 `opencode service restart` |
| `opencode.json` / agents / commands | 热重载 |
| `lab-scope.json` | 每次请求同步读取，立即生效 |
| `AGENTS.md` | 新会话生效（已开会话的 system 已构建） |
| `package.json` 依赖 | `npm install` + `opencode service restart` |

## 10. 完全回到安装前

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveFiles -RestoreConfig
```

备份在 `~\.config\opencode\_backup\unrestricted-kit-<时间戳>\`，按相对路径手工复制也能还原。
