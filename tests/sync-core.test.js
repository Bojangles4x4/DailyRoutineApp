const assert = require('node:assert/strict');
const {
  syncableState,
  applySyncableState,
  mergeRoutineStates,
  createCoordinator
} = require('../sync-core.js');

let passed = 0;
function test(name, body) {
  try {
    body();
    passed += 1;
  } catch (error) {
    error.message = `${name}: ${error.message}`;
    throw error;
  }
}

function copy(value) { return JSON.parse(JSON.stringify(value)); }

class MemoryStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
}

function sampleState() {
  return {
    settings: { theme: 'calm', backgroundImage: 'data:image/jpeg;base64,private', lastBackupAt: 'local-only' },
    items: [{ id: 'prayer', name: 'Prayer', order: 0 }],
    days: { '2026-08-25': { entries: { prayer: true }, skippedItems: {}, mode: 'normal' } },
    memories: [],
    notes: [],
    weeklyReviews: {}
  };
}

test('removes device-only fields from cloud documents', () => {
  const safe = syncableState(sampleState());
  assert.equal(safe.settings.backgroundImage, undefined);
  assert.equal(safe.settings.lastBackupAt, undefined);
  assert.equal(safe.days['2026-08-25'].entries.prayer, true);
});

test('preserves device-only fields when applying remote state', () => {
  const current = sampleState();
  const remote = syncableState(current);
  remote.settings.theme = 'dusk';
  const applied = applySyncableState(current, remote);
  assert.equal(applied.settings.theme, 'dusk');
  assert.equal(applied.settings.backgroundImage, current.settings.backgroundImage);
  assert.equal(applied.settings.lastBackupAt, current.settings.lastBackupAt);
});

test('merges changes made to different days without conflicts', () => {
  const base = sampleState();
  const local = copy(base);
  const remote = copy(base);
  local.days['2026-08-26'] = { entries: { prayer: true }, skippedItems: {}, mode: 'normal' };
  remote.days['2026-08-25'].entries.water = 4;
  const merged = mergeRoutineStates(base, local, remote);
  assert.equal(merged.state.days['2026-08-26'].entries.prayer, true);
  assert.equal(merged.state.days['2026-08-25'].entries.water, 4);
  assert.equal(merged.conflicts.length, 0);
});

test('merges separate note edits by id', () => {
  const base = sampleState();
  base.notes = [{ id: 'a', text: 'A' }, { id: 'b', text: 'B' }];
  const local = copy(base);
  const remote = copy(base);
  local.notes[0].text = 'A local';
  remote.notes[1].text = 'B remote';
  const merged = mergeRoutineStates(base, local, remote);
  assert.deepEqual(merged.state.notes.map(note => note.text), ['A local', 'B remote']);
  assert.equal(merged.conflicts.length, 0);
});

test('keeps the local value and records a recoverable conflict for simultaneous edits', () => {
  const base = sampleState();
  const local = copy(base);
  const remote = copy(base);
  local.settings.theme = 'sunrise';
  remote.settings.theme = 'midnight';
  const merged = mergeRoutineStates(base, local, remote);
  assert.equal(merged.state.settings.theme, 'sunrise');
  assert.equal(merged.conflicts[0].path, 'settings.theme');
});

test('tracks local changes and clears them only after a committed remote revision', () => {
  const storage = new MemoryStorage();
  const coordinator = createCoordinator({ storage });
  const state = sampleState();
  coordinator.ensureLocalState(state);
  assert.equal(coordinator.status().dirty, true);
  coordinator.commitRemote(state, 1, 'supabase', 'user-1');
  assert.equal(coordinator.status().dirty, false);
  state.days['2026-08-25'].entries.water = 2;
  coordinator.markLocalChange(state);
  assert.equal(coordinator.status().dirty, true);
  assert.equal(coordinator.status().localChangeCount, 1);
});

test('requests a three-way merge when remote and local revisions both changed', () => {
  const storage = new MemoryStorage();
  const coordinator = createCoordinator({ storage });
  const base = sampleState();
  coordinator.ensureLocalState(base);
  coordinator.commitRemote(base, 2, 'supabase', 'user-1');
  const local = copy(base);
  local.days['2026-08-26'] = { entries: { prayer: true }, skippedItems: {}, mode: 'normal' };
  coordinator.markLocalChange(local);
  const remote = copy(base);
  remote.days['2026-08-25'].entries.water = 5;
  const decision = coordinator.reconcile(local, { revision: 3, document: remote });
  assert.equal(decision.action, 'upload');
  assert.equal(decision.expectedRevision, 3);
  assert.equal(decision.state.days['2026-08-26'].entries.prayer, true);
  assert.equal(decision.state.days['2026-08-25'].entries.water, 5);
});

console.log(`Private sync foundation: ${passed} tests passed.`);
