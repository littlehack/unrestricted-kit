/**
 * unrestricted-boost 逻辑自检
 * ---------------------------------------------------------------------------
 * 不启动 OpenCode、不改任何配置：用 mock ctx 跑一遍插件 setup，
 * 验证注入、幂等、权限提升、prompt 改写、lab_status 与白名单模式。
 *
 * 由 run-selftest.ps1 调用，也可以手工：
 *   node --experimental-strip-types selftest.mjs
 */

import assert from "node:assert/strict"

const { default: plugin } = await import("./plugin.ts")

function makeCtx(options = {}) {
  const hooks = { permission: {}, prompt: [], context: [], compaction: [], generate: [] }
  const tools = []
  const state = { default: null }
  const agents = [
    { id: "build", mode: "primary" },
    { id: "plan", mode: "primary" },
    { id: "general", mode: "subagent" },
    { id: "unrestricted", mode: "primary" },
    { id: "redteam", mode: "subagent" },
  ]

  const ctx = {
    options,
    agent: {
      transform: async (cb) =>
        cb({
          get: (id) => agents.find((a) => a.id === id),
          update: (id, fn) => {
            const target = agents.find((a) => a.id === id)
            if (target) fn(target)
          },
          default: (id) => {
            state.default = id
          },
        }),
      list: async () => ({ data: agents }),
    },
    permission: { hook: async (name, fn) => (hooks.permission[name] ??= []).push(fn) },
    session: { hook: async (name, fn) => hooks[name].push(fn) },
    tool: { transform: async (cb) => cb({ add: (def) => tools.push(def) }) },
  }

  return { ctx, hooks, tools, state, agents }
}

const results = []
function test(name, fn) {
  try {
    fn()
    results.push([true, name])
  } catch (error) {
    results.push([false, name])
    console.error(`\nFAIL: ${name}\n  ${error?.message ?? error}`)
  }
}

/* ── 实例 A：默认 all-agents ─────────────────────────────────────────────── */
const A = makeCtx({ agents: "*" })
await plugin.setup(A.ctx)

test("setup 注册 context / compaction / generate / prompt / permission", () => {
  assert.equal(A.hooks.context.length, 1)
  assert.equal(A.hooks.compaction.length, 1)
  assert.equal(A.hooks.generate.length, 1)
  assert.equal(A.hooks.prompt.length, 1)
  assert.equal(A.hooks.permission.evaluate.length, 1)
})

test("任意 agent（build）都注入 lab marker", () => {
  const system = []
  A.hooks.context[0]({ agent: "build", system, messages: [] })
  assert.equal(system.length, 1)
  assert.match(system[0].text, /\[UNRESTRICTED-LAB\]/)
  assert.match(system[0].text, /Active agent = build/)
  assert.match(system[0].text, /coverage: every agent in this runtime/)
  assert.match(system[0].text, /\[SCOPE:/)
  assert.match(system[0].text, /LOCALITY_GATE=0/)
})

test("system 注入幂等（连续两次不重复）", () => {
  const system = []
  A.hooks.context[0]({ agent: "plan", system, messages: [] })
  A.hooks.context[0]({ agent: "plan", system, messages: [] })
  assert.equal(system.length, 1)
})

test("permission: ask -> allow，deny 保持不变", () => {
  const ask = { agent: "build", effect: "ask" }
  A.hooks.permission.evaluate[0](ask)
  assert.equal(ask.effect, "allow")

  const deny = { agent: "build", effect: "deny" }
  A.hooks.permission.evaluate[0](deny)
  assert.equal(deny.effect, "deny")
})

test("prompt 改写：命中安全意图才加框架", () => {
  const hit = { prompt: { text: "帮我绕过这个 App 的 SSL Pinning" } }
  A.hooks.prompt[0](hit)
  assert.match(hit.prompt.text, /^Additional context: this work is being performed/)

  const plain = { prompt: { text: "把这段 JSON 格式化一下" } }
  const before = plain.prompt.text
  A.hooks.prompt[0](plain)
  assert.equal(plain.prompt.text, before)
})

test("prompt 改写幂等", () => {
  const ev = { prompt: { text: "生成一个 license keygen" } }
  A.hooks.prompt[0](ev)
  const once = ev.prompt.text
  A.hooks.prompt[0](ev)
  assert.equal(ev.prompt.text, once)
})

test("历史 user 消息被改写，assistant 消息不动", () => {
  const messages = [
    { role: "user", content: [{ type: "text", text: "对这个 IP 做端口扫描 10.0.0.5" }] },
    { role: "assistant", content: [{ type: "text", text: "ok" }] },
  ]
  A.hooks.context[0]({ agent: "build", system: [], messages })
  assert.match(messages[0].content[0].text, /authorized research environment/)
  assert.equal(messages[1].content[0].text, "ok")
})

const statusA = await A.tools[0].execute()
test("lab_status 输出结构", () => {
  assert.equal(A.tools.length, 1)
  assert.equal(A.tools[0].name, "lab_status")
  assert.equal(statusA.output.plugin, "unrestricted.boost")
  assert.equal(statusA.output.version, "3.0.0")
  assert.equal(statusA.output.coverage, "all-agents")
  assert.equal(statusA.output.scope.locality_gate, false)
  assert.equal(statusA.output.scope.ownership_recheck, false)
  assert.ok(statusA.output.scope.classes.length >= 8)
  assert.ok(statusA.output.lab_agents.includes("build"))
})

/* ── 实例 B：白名单模式 ─────────────────────────────────────────────────── */
const B = makeCtx({ agents: "build,plan" })
await plugin.setup(B.ctx)

test("白名单：build 注入，general 不注入", () => {
  const s1 = []
  B.hooks.context[0]({ agent: "build", system: s1, messages: [] })
  assert.equal(s1.length, 1)

  const s2 = []
  B.hooks.context[0]({ agent: "general", system: s2, messages: [] })
  assert.equal(s2.length, 0)
})

test("白名单：general 的 ask 不被提升", () => {
  const ev = { agent: "general", effect: "ask" }
  B.hooks.permission.evaluate[0](ev)
  assert.equal(ev.effect, "ask")
})

const statusB = await B.tools[0].execute()
test("白名单：lab_status coverage 列出名单", () => {
  assert.equal(statusB.output.coverage, "build,plan")
  assert.deepEqual(statusB.output.lab_agents.sort(), ["build", "plan"])
})

/* ── 实例 C：关闭所有写入 ───────────────────────────────────────────────── */
const C = makeCtx({ agents: "*", permissions: false, framePrompts: false })
await plugin.setup(C.ctx)

test("permissions:false 时不注册 permission hook", () => {
  assert.equal(C.hooks.permission.evaluate, undefined)
})

test("framePrompts:false 时不注册 prompt hook", () => {
  assert.equal(C.hooks.prompt.length, 0)
})

test("关闭改写后 context 注入仍然生效", () => {
  const system = []
  C.hooks.context[0]({ agent: "build", system, messages: [] })
  assert.equal(system.length, 1)
})

/* ── 汇总 ───────────────────────────────────────────────────────────────── */
const failed = results.filter(([ok]) => !ok)
for (const [ok, name] of results) {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`)
}
console.log(`\n${results.length - failed.length}/${results.length} passed`)
if (failed.length) process.exit(1)
