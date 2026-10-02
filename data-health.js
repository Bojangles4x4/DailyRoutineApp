(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.DailyRoutineDataHealth = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  function object(value) {
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  }

  function validDateKey(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) return false;
    const [year, month, day] = String(value).split('-').map(Number);
    const date = new Date(year, month - 1, day, 12);
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day;
  }

  function shiftDateKey(key, days) {
    if (!validDateKey(key)) return '';
    const [year, month, day] = key.split('-').map(Number);
    const date = new Date(year, month - 1, day + days, 12);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  function summarizeState(input) {
    const state = object(input);
    const days = object(state.days);
    const dateKeys = Object.keys(days).filter(validDateKey).sort();
    const itemIds = new Set((Array.isArray(state.items) ? state.items : []).map(item => String(item?.id || '')).filter(Boolean));
    let entryCount = 0;
    let orphanEntryCount = 0;
    let targetDayCount = 0;
    dateKeys.forEach(key => {
      const day = object(days[key]);
      const entries = object(day.entries);
      entryCount += Object.keys(entries).length;
      orphanEntryCount += Object.keys(entries).filter(id => !itemIds.has(String(id))).length;
      if (Object.keys(object(day.targets)).length) targetDayCount += 1;
    });
    return {
      itemCount: Array.isArray(state.items) ? state.items.length : 0,
      dayCount: dateKeys.length,
      entryCount,
      noteCount: Array.isArray(state.notes) ? state.notes.length : 0,
      memoryCount: Array.isArray(state.memories) ? state.memories.length : 0,
      reviewCount: Object.keys(object(state.weeklyReviews)).length,
      orphanEntryCount,
      targetDayCount,
      firstDate: dateKeys[0] || '',
      lastDate: dateKeys[dateKeys.length - 1] || ''
    };
  }

  function auditHistory(input, todayKey) {
    const state = object(input);
    const days = object(state.days);
    const items = Array.isArray(state.items) ? state.items : [];
    const itemIds = new Set(items.map(item => String(item?.id || '')).filter(Boolean));
    const numericTargetIds = new Set(items
      .filter(item => item?.type === 'number' && Number.isFinite(Number(item.target)) && Number(item.target) > 0)
      .map(item => String(item.id)));
    const invalidDateKeys = Object.keys(days).filter(key => !validDateKey(key));
    const validKeys = Object.keys(days).filter(validDateKey).sort();
    const firstUseDate = validDateKey(state?.settings?.firstUseDate) ? state.settings.firstUseDate : validKeys[0] || '';
    const endDate = validDateKey(todayKey) ? todayKey : validKeys[validKeys.length - 1] || '';
    const unsavedDates = [];
    if (firstUseDate && endDate && firstUseDate <= endDate) {
      let cursor = firstUseDate;
      let guard = 0;
      while (cursor <= endDate && guard < 3660) {
        if (!Object.prototype.hasOwnProperty.call(days, cursor)) unsavedDates.push(cursor);
        cursor = shiftDateKey(cursor, 1);
        guard += 1;
      }
    }
    const orphanEntries = [];
    const numericDaysWithoutTargets = [];
    const targetDrift = [];
    const invalidEntries = [];
    const malformedDays = [];
    validKeys.forEach(key => {
      const rawDay = days[key];
      if (!rawDay || typeof rawDay !== 'object' || Array.isArray(rawDay)) {
        malformedDays.push(key);
        return;
      }
      const entries = object(rawDay.entries);
      Object.keys(entries).forEach(id => {
        if (!itemIds.has(String(id))) orphanEntries.push({ date: key, itemId: String(id) });
        const item = items.find(candidate => String(candidate?.id || '') === String(id));
        if (item && !entryValueIsValid(item, entries[id])) invalidEntries.push({ date: key, itemId: String(id), type: String(item.type || '') });
      });
      const targetIds = object(rawDay.targets);
      const missing = Object.keys(entries).filter(id => numericTargetIds.has(String(id)) && !Object.prototype.hasOwnProperty.call(targetIds, id));
      if (missing.length) numericDaysWithoutTargets.push({ date: key, itemIds: missing });
      Object.keys(targetIds).forEach(id => {
        const item = items.find(candidate => String(candidate?.id || '') === String(id));
        if (!item || item.type !== 'number' || !Number.isFinite(Number(targetIds[id])) || !Number.isFinite(Number(item.target))) return;
        if (Number(targetIds[id]) !== Number(item.target)) targetDrift.push({ date: key, itemId: String(id), savedTarget: Number(targetIds[id]), currentTarget: Number(item.target) });
      });
    });
    return {
      summary: summarizeState(state),
      firstUseDate,
      endDate,
      invalidDateKeys,
      malformedDays,
      unsavedDates,
      orphanEntries,
      numericDaysWithoutTargets,
      targetDrift,
      invalidEntries,
      issueCount: invalidDateKeys.length + malformedDays.length + orphanEntries.length + numericDaysWithoutTargets.length + invalidEntries.length,
      status: invalidDateKeys.length || malformedDays.length || invalidEntries.length ? 'attention' : orphanEntries.length || numericDaysWithoutTargets.length ? 'review' : 'healthy'
    };
  }

  function entryValueIsValid(item, value) {
    const type = String(item?.type || '');
    if (type === 'checkbox') return typeof value === 'boolean';
    if (type === 'linked') return typeof value === 'boolean' || (value && typeof value === 'object' && typeof value.completed === 'boolean');
    if (type === 'medication') return value === true || (value && typeof value === 'object' && typeof value.taken === 'boolean');
    if (type === 'memory') return Boolean(value && typeof value === 'object' && typeof value.reflected === 'boolean');
    if (type === 'number') return Number.isFinite(Number(value));
    if (type === 'scale') {
      if (!Number.isFinite(Number(value))) return false;
      const min = Number.isFinite(Number(item?.scale?.min)) ? Number(item.scale.min) : 0;
      const max = Number.isFinite(Number(item?.scale?.max)) ? Number(item.scale.max) : 10;
      return Number(value) >= min && Number(value) <= max;
    }
    if (type === 'time') return /^([01]\d|2[0-3]):[0-5]\d$/.test(String(value || ''));
    if (type === 'text' || type === 'longtext') return typeof value === 'string';
    return value !== undefined;
  }

  function changedCategories(localInput, nextInput) {
    const local = object(localInput);
    const next = object(nextInput);
    const categories = [
      ['settings', object(local.settings), object(next.settings)],
      ['routines', Array.isArray(local.items) ? local.items : [], Array.isArray(next.items) ? next.items : []],
      ['daily history', object(local.days), object(next.days)],
      ['notes', Array.isArray(local.notes) ? local.notes : [], Array.isArray(next.notes) ? next.notes : []],
      ['memories', Array.isArray(local.memories) ? local.memories : [], Array.isArray(next.memories) ? next.memories : []],
      ['weekly reviews', object(local.weeklyReviews), object(next.weeklyReviews)]
    ];
    return categories.filter(([, before, after]) => JSON.stringify(before) !== JSON.stringify(after)).map(([name]) => name);
  }

  function buildSyncPreview(localInput, remoteEnvelope, decisionInput) {
    const local = object(localInput);
    const remote = object(remoteEnvelope?.document);
    const decision = object(decisionInput);
    const next = object(decision.state || local);
    const action = ['upload', 'adopt', 'none'].includes(decision.action) ? decision.action : 'none';
    return {
      action,
      title: action === 'adopt' ? 'Download cloud changes' : action === 'upload' ? (remoteEnvelope?.document ? 'Merge and upload changes' : 'Create the first cloud copy') : 'Everything is already synchronized',
      local: summarizeState(local),
      cloud: remoteEnvelope?.document ? summarizeState(remote) : null,
      result: summarizeState(next),
      changedCategories: changedCategories(local, next),
      uploadCategories: changedCategories(remote, next),
      downloadCategories: changedCategories(local, next),
      conflictCount: Array.isArray(decision.conflicts) ? decision.conflicts.length : 0,
      remoteRevision: Math.max(0, Number(remoteEnvelope?.revision ?? decision.remoteRevision) || 0)
    };
  }

  return { validDateKey, shiftDateKey, summarizeState, auditHistory, changedCategories, buildSyncPreview };
});
