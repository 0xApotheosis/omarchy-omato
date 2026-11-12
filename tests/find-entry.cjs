const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const path = require('node:path')
const context = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'TimerModel.js'), 'utf8').replace('.pragma library', ''), context)
const id = 'io.github.0xapotheosis.omato'

for (const section of ['left', 'centerBegin', 'center', 'centerEnd', 'right', 'tray']) {
  const entry = { id, overtime: true, breaths: 2 }
  const bar = { layout: { center: [{ id: 'omarchy.clock' }], [section]: [entry] } }
  if (section === 'center') bar.layout.center.push(entry)
  assert.deepEqual(context.findEntry(bar, id), entry, section)
}
assert.equal(JSON.stringify(context.findEntry({ layout: { right: [{ id: 'other' }] } }, id)), JSON.stringify({ id }))
assert.equal(JSON.stringify(context.findEntry(null, id)), JSON.stringify({ id }))
console.log('find-entry ok')
