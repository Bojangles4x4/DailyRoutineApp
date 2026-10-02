const assert = require('node:assert/strict');
const { summarizeState, auditHistory, buildSyncPreview, shiftDateKey } = require('../data-health.js');

let passed = 0;
function test(name, fn) {
  fn();
  passed += 1;
  console.log(`✓ ${name}`);
}

function sampleState() {
  return {
    settings: { firstUseDate: '2026-09-01' },
    items: [
      { id: 'prayer', type: 'checkbox' },
      { id: 'water', type: 'number', target: 6 }
    ],
    days: {
      '2026-09-01': { entries: { prayer: true, water: 4 }, targets: { water: 6 } },
      '2026-09-03': { entries: { prayer: false, water: 6 }, targets: { water: 6 } }
    },
    notes: [{ id: 'note-1' }],
    memories: [],
    weeklyReviews: {}
  };
}

test('summarizes local routine data without exposing contents', () => {
  assert.deepEqual(summarizeState(sampleState()), {
    itemCount: 2, dayCount: 2, entryCount: 4, noteCount: 1, memoryCount: 0, reviewCount: 0,
    orphanEntryCount: 0, targetDayCount: 2, firstDate: '2026-09-01', lastDate: '2026-09-03'
  });
});

test('audits unsaved dates separately from structural issues', () => {
  const audit = auditHistory(sampleState(), '2026-09-03');
  assert.deepEqual(audit.unsavedDates, ['2026-09-02']);
  assert.equal(audit.issueCount, 0);
  assert.equal(audit.status, 'healthy');
});

test('flags orphan entries and numeric history missing frozen targets', () => {
  const state = sampleState();
  state.days['2026-09-03'] = { entries: { water: 6, deletedItem: true } };
  const audit = auditHistory(state, '2026-09-03');
  assert.equal(audit.orphanEntries.length, 1);
  assert.equal(audit.numericDaysWithoutTargets.length, 1);
  assert.equal(audit.status, 'review');
});

test('separates expected historical target changes from invalid saved values', () => {
  const state = sampleState();
  state.items[1].target = 8;
  state.days['2026-09-03'].entries.water = 'not-a-number';
  const audit = auditHistory(state, '2026-09-03');
  assert.equal(audit.targetDrift.length, 2);
  assert.equal(audit.invalidEntries.length, 1);
  assert.equal(audit.status, 'attention');
});

test('previews merge direction, counts, changed categories, and conflicts', () => {
  const local = sampleState();
  const merged = sampleState();
  merged.days['2026-09-04'] = { entries: { prayer: true } };
  const preview = buildSyncPreview(local, { revision: 7, document: sampleState() }, { action: 'upload', state: merged, conflicts: [{ path: 'days' }] });
  assert.equal(preview.title, 'Merge and upload changes');
  assert.equal(preview.result.dayCount, 3);
  assert.deepEqual(preview.changedCategories, ['daily history']);
  assert.deepEqual(preview.downloadCategories, ['daily history']);
  assert.equal(preview.conflictCount, 1);
  assert.equal(preview.remoteRevision, 7);
});

test('lists categories that a first sync will upload to the cloud', () => {
  const local = sampleState();
  const preview = buildSyncPreview(local, null, { action: 'upload', state: local, conflicts: [] });
  assert.deepEqual(preview.downloadCategories, []);
  assert.deepEqual(preview.uploadCategories, ['settings', 'routines', 'daily history', 'notes']);
});

test('shifts date keys across month and daylight-saving boundaries', () => {
  assert.equal(shiftDateKey('2026-03-08', 1), '2026-03-09');
  assert.equal(shiftDateKey('2026-10-31', 1), '2026-11-01');
});

console.log(`Data confidence foundation: ${passed} tests passed.`);
