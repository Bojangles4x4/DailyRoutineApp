const assert = require('node:assert/strict');
const {
  syncableState,
  applySyncableState,
  mergeRoutineStates,
  buildAccountabilitySnapshot,
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

test('keeps automatic Apple Health entries out of cloud documents', () => {
  const state = sampleState();
  state.items.push({ id: 'steps', name: 'Daily steps', type: 'number', healthSource: 'apple-health-steps' });
  state.days['2026-08-25'].entries.steps = 8421;
  const safe = syncableState(state);
  assert.equal(safe.items.find(item => item.id === 'steps').healthSource, 'apple-health-steps');
  assert.equal(safe.days['2026-08-25'].entries.steps, undefined);
  assert.equal(safe.days['2026-08-25'].entries.prayer, true);
});

test('preserves local Apple Health entries when applying a cloud document', () => {
  const current = sampleState();
  current.items.push({ id: 'steps', name: 'Daily steps', type: 'number', target: 8000, healthSource: 'apple-health-steps' });
  current.days['2026-08-25'].entries.steps = 8421;
  const remote = syncableState(current);
  remote.settings.theme = 'dusk';
  const applied = applySyncableState(current, remote);
  assert.equal(applied.days['2026-08-25'].entries.steps, 8421);
  assert.equal(applied.settings.theme, 'dusk');
});

test('builds a privacy-filtered accountability snapshot without private text', () => {
  const state = sampleState();
  state.settings.truthBeforeTasks = { completions: { '2026-08-25': true } };
  state.items.push(
    { id: 'meds', name: 'Private medication name', type: 'medication', section: 'morning', frequency: 'daily' },
    { id: 'mood', name: 'Morning mood', kind: 'checkin', type: 'scale', section: 'morning', frequency: 'daily' }
  );
  state.days['2026-08-25'].entries.meds = { taken: true, time: '08:15', note: 'private dose note' };
  state.days['2026-08-25'].entries.mood = 7;
  state.notes = [{ id: 'secret', type: 'prayer', text: 'private prayer text' }];
  state.memories = [{ id: 'memory', text: 'private memory text' }];
  const snapshot = buildAccountabilitySnapshot(state, {
    today: '2026-08-25',
    generatedAt: '2026-08-25T14:00:00.000Z',
    displayName: 'Taylor',
    permissions: { progressTotals: true, routineNames: true, checkins: true, steps: false, medication: true, routineIds: ['prayer'] }
  });
  const serialized = JSON.stringify(snapshot);
  assert.equal(snapshot.member.displayName, 'Taylor');
  assert.equal(snapshot.today.truthBeforeTasks, true);
  assert.deepEqual(snapshot.medication, { completed: 1, total: 1 });
  assert.equal(snapshot.checkins[0].average, 7);
  assert.equal(snapshot.schemaVersion, 2);
  assert.equal(snapshot.daily.length, 1);
  assert.equal(snapshot.routineTrends.length, 1);
  assert.equal(snapshot.routineTrends[0].name, 'Prayer');
  assert.equal(serialized.includes('Private medication name'), false);
  assert.equal(serialized.includes('08:15'), false);
  assert.equal(serialized.includes('private prayer text'), false);
  assert.equal(serialized.includes('private memory text'), false);
  assert.equal(serialized.includes('private dose note'), false);
});

test('shares trends only for routines individually approved by the owner', () => {
  const state = sampleState();
  state.items.push(
    { id: 'reading', name: 'Bible reading', kind: 'routine', type: 'checkbox', section: 'morning', frequency: 'daily' },
    { id: 'reflection', name: 'Private reflection prompt', kind: 'routine', type: 'longtext', section: 'evening', frequency: 'daily' }
  );
  state.days['2026-08-25'].entries.reading = true;
  state.days['2026-08-25'].entries.reflection = 'private response';
  const snapshot = buildAccountabilitySnapshot(state, {
    today: '2026-08-25',
    permissions: { progressTotals: true, routineNames: true, routineIds: ['reading', 'reflection'] }
  });
  const serialized = JSON.stringify(snapshot);
  assert.deepEqual(snapshot.routines.map(item => item.name), ['Bible reading']);
  assert.deepEqual(snapshot.routineTrends.map(item => item.name), ['Bible reading']);
  assert.equal(serialized.includes('Private reflection prompt'), false);
  assert.equal(serialized.includes('private response'), false);
});

test('omits every optional accountability category when permission is off', () => {
  const snapshot = buildAccountabilitySnapshot(sampleState(), {
    today: '2026-08-25',
    permissions: { progressTotals: false, routineNames: false, checkins: false, steps: false, medication: false }
  });
  assert.equal(snapshot.today, undefined);
  assert.equal(snapshot.week, undefined);
  assert.equal(snapshot.routines, undefined);
  assert.equal(snapshot.checkins, undefined);
  assert.equal(snapshot.steps, undefined);
  assert.equal(snapshot.medication, undefined);
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
