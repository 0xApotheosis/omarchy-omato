const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')
const root = path.join(__dirname, '..')
const source = fs.readFileSync(path.join(root, 'Service.qml'), 'utf8')
function library(name) {
  const context = vm.createContext({})
  vm.runInContext(fs.readFileSync(path.join(root, name), 'utf8').replace('.pragma library', ''), context)
  return context
}
const Model = library('TimerModel.js'), Stats = library('Stats.js')
const yesterday = new Date(2026, 9, 27, 18).getTime()
const today = new Date(2026, 9, 28, 9).getTime()
function service(patch = {}) {
  const st = { phase: 'idle', paused: false, upNext: 'long', cycleCount: 4,
    cycleDay: Stats.dayKey(new Date(yesterday)), label: 'Keep my label',
    startedAt: yesterday, endsAt: yesterday + 1500000, plannedSec: 1500,
    pausedRemaining: 600, dndOwned: false, ...patch }
  const records = [], effects = []
  const context = vm.createContext({ st, Model, Stats, Date, now: today,
    config: Model.DEFAULTS, host: 'test', history: { append: r => records.push(r) },
    cancelBreath() {}, runEffects: (...args) => effects.push(args),
    get running() { return st.phase !== 'idle' }, get phase() { return st.phase },
    get paused() { return st.paused }, get cycleCount() { return st.cycleCount },
  })
  for (const name of ['complete', 'resetForNewDay', 'loadState']) {
    const match = source.match(new RegExp('  function ' + name + '\\([^]*?^  }', 'm'))
    assert.ok(match, name)
    vm.runInContext(match[0], context)
  }
  return { context, st, records, effects, reset: () => context.resetForNewDay(today) }
}
for (const upNext of ['short', 'long', 'focus']) {
  const s = service({ upNext })
  assert.equal(s.reset(), true)
  assert.equal(s.st.upNext, 'focus')
  assert.equal(s.st.cycleCount, 0)
  assert.equal(s.st.label, 'Keep my label')
  assert.equal(s.records.length, 0)
  assert.equal(s.reset(), false)
}
{
  const s = service({ cycleDay: Stats.dayKey(new Date(today)) })
  assert.equal(s.reset(), false)
  assert.equal(s.st.upNext, 'long')
  assert.equal(s.st.cycleCount, 4)
}
for (const phase of ['focus', 'short', 'long']) {
  const s = service({ phase, dndOwned: phase === 'focus' })
  s.reset()
  assert.equal(s.st.phase, 'idle')
  assert.equal(s.st.upNext, 'focus')
  assert.equal(s.records.length, 1)
  assert.equal(s.records[0].outcome, 'completed')
  assert.equal(s.records[0].actualSec, phase === 'focus' ? 1500 : 5100)
  assert.equal(s.st.dndOwned, false)
  assert.equal(s.effects[0][1], null) // No stale notification.
}
{
  const s = service({ phase: 'focus', paused: true, dndOwned: true })
  s.reset()
  assert.equal(s.records[0].outcome, 'abandoned')
  assert.equal(s.records[0].actualSec, 900)
  assert.equal(s.st.upNext, 'focus')
}
{
  const s = service({ phase: 'focus', endsAt: today + 60000 })
  assert.equal(s.reset(), false) // A live countdown may cross midnight.
  s.context.complete('completed', today + 60000)
  s.reset()
  assert.equal(s.st.upNext, 'focus')
  assert.equal(s.st.cycleCount, 0)
}
{
  const s = service()
  s.context.stateFile = { text: () => JSON.stringify({ startedAt: yesterday }) }
  s.context.stateKeys = ['startedAt', 'cycleDay']
  s.st.cycleDay = ''
  s.context.loadState()
  assert.equal(s.st.cycleDay, Stats.dayKey(new Date(yesterday)))
  assert.equal(s.reset(), true)
}
assert.match(source, /function start\(\) \{\s*resetForNewDay/)
assert.match(source, /function resume\(\) \{\s*resetForNewDay/)
assert.match(source, /onTriggered: root.onTick\(\)/)
console.log('Daily rollover checks passed (idle, same day, expired, paused, active, legacy state).')
