(function attachDailyRoutineSync(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.DailyRoutineSync = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';

  const SYNC_SCHEMA_VERSION = 1;
  const METADATA_KEY = 'dailyRoutine.sync.metadata.v1';
  const CONFLICTS_KEY = 'dailyRoutine.sync.conflicts.v1';
  const ACCOUNTABILITY_SCHEMA_VERSION = 2;
  const MISSING = Symbol('missing');

  function clone(value) {
    if (value === MISSING) return MISSING;
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
  }

  function isPlainObject(value) {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
  }

  function canonicalize(value) {
    if (Array.isArray(value)) return value.map(canonicalize);
    if (!isPlainObject(value)) return value;
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = canonicalize(value[key]);
      return result;
    }, {});
  }

  function fingerprint(value) {
    return JSON.stringify(canonicalize(value));
  }

  function same(left, right) {
    if (left === MISSING || right === MISSING) return left === right;
    return fingerprint(left) === fingerprint(right);
  }

  function createDeviceId() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
    return `device-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
  }

  function syncableState(input) {
    const safe = clone(input || {});
    safe.settings = isPlainObject(safe.settings) ? safe.settings : {};
    delete safe.settings.backgroundImage;
    delete safe.settings.lastBackupAt;
    const deviceHealthIds = new Set((Array.isArray(safe.items) ? safe.items : [])
      .filter(item => String(item?.healthSource || '').startsWith('apple-health-'))
      .map(item => String(item.id || ''))
      .filter(Boolean));
    Object.values(isPlainObject(safe.days) ? safe.days : {}).forEach(day => {
      if (!isPlainObject(day?.entries)) return;
      deviceHealthIds.forEach(id => delete day.entries[id]);
    });
    return safe;
  }

  function applySyncableState(current, incoming) {
    const next = clone(incoming || {});
    next.settings = isPlainObject(next.settings) ? next.settings : {};
    const localSettings = current?.settings || {};
    next.settings.backgroundImage = String(localSettings.backgroundImage || '');
    next.settings.lastBackupAt = String(localSettings.lastBackupAt || '');
    const deviceHealthIds = new Set((Array.isArray(next.items) ? next.items : [])
      .filter(item => String(item?.healthSource || '').startsWith('apple-health-'))
      .map(item => String(item.id || ''))
      .filter(Boolean));
    const localDays = isPlainObject(current?.days) ? current.days : {};
    next.days = isPlainObject(next.days) ? next.days : {};
    Object.entries(localDays).forEach(([key, localDay]) => {
      if (!isPlainObject(localDay?.entries)) return;
      const preserved = {};
      deviceHealthIds.forEach(id => {
        if (Object.prototype.hasOwnProperty.call(localDay.entries, id)) preserved[id] = clone(localDay.entries[id]);
      });
      if (!Object.keys(preserved).length) return;
      next.days[key] = isPlainObject(next.days[key]) ? next.days[key] : { entries: {} };
      next.days[key].entries = { ...(isPlainObject(next.days[key].entries) ? next.days[key].entries : {}), ...preserved };
    });
    return next;
  }

  function mergeValue(base, local, remote, path, conflicts) {
    if (same(local, remote)) return clone(local);
    if (same(local, base)) return clone(remote);
    if (same(remote, base)) return clone(local);

    const valuesAreObjects = [base, local, remote].every(value => value === MISSING || isPlainObject(value));
    if (valuesAreObjects && local !== MISSING && remote !== MISSING) {
      const output = {};
      const keys = new Set([
        ...Object.keys(base === MISSING ? {} : base),
        ...Object.keys(local),
        ...Object.keys(remote)
      ]);
      keys.forEach(key => {
        const merged = mergeValue(
          base !== MISSING && Object.prototype.hasOwnProperty.call(base, key) ? base[key] : MISSING,
          Object.prototype.hasOwnProperty.call(local, key) ? local[key] : MISSING,
          Object.prototype.hasOwnProperty.call(remote, key) ? remote[key] : MISSING,
          path ? `${path}.${key}` : key,
          conflicts
        );
        if (merged !== MISSING) output[key] = merged;
      });
      return output;
    }

    conflicts.push({
      path: path || '$',
      local: local === MISSING ? null : clone(local),
      remote: remote === MISSING ? null : clone(remote),
      resolution: 'local'
    });
    return clone(local);
  }

  function entityMap(items) {
    return new Map((Array.isArray(items) ? items : []).filter(item => item?.id).map(item => [String(item.id), item]));
  }

  function mergeEntityArray(baseItems, localItems, remoteItems, path, conflicts) {
    const base = entityMap(baseItems), local = entityMap(localItems), remote = entityMap(remoteItems);
    const ids = new Set([...base.keys(), ...local.keys(), ...remote.keys()]);
    const merged = new Map();
    ids.forEach(id => {
      const value = mergeValue(
        base.has(id) ? base.get(id) : MISSING,
        local.has(id) ? local.get(id) : MISSING,
        remote.has(id) ? remote.get(id) : MISSING,
        `${path}.${id}`,
        conflicts
      );
      if (value !== MISSING) merged.set(id, value);
    });

    const order = [];
    [localItems, remoteItems, baseItems].forEach(items => (Array.isArray(items) ? items : []).forEach(item => {
      const id = String(item?.id || '');
      if (id && merged.has(id) && !order.includes(id)) order.push(id);
    }));
    return order.map(id => merged.get(id));
  }

  function mergeRoutineStates(baseInput, localInput, remoteInput) {
    const base = syncableState(baseInput || {});
    const local = syncableState(localInput || {});
    const remote = syncableState(remoteInput || {});
    const conflicts = [];
    const result = {};
    const entityCollections = new Set(['items', 'notes', 'memories']);
    const keys = new Set([...Object.keys(base), ...Object.keys(local), ...Object.keys(remote)]);

    keys.forEach(key => {
      if (entityCollections.has(key)) {
        result[key] = mergeEntityArray(base[key], local[key], remote[key], key, conflicts);
        return;
      }
      const merged = mergeValue(
        Object.prototype.hasOwnProperty.call(base, key) ? base[key] : MISSING,
        Object.prototype.hasOwnProperty.call(local, key) ? local[key] : MISSING,
        Object.prototype.hasOwnProperty.call(remote, key) ? remote[key] : MISSING,
        key,
        conflicts
      );
      if (merged !== MISSING) result[key] = merged;
    });
    return { state: result, conflicts };
  }

  const DEFAULT_ACCOUNTABILITY_PERMISSIONS = Object.freeze({
    progressTotals: true,
    routineNames: true,
    checkins: false,
    steps: false,
    medication: false,
    routineIds: null
  });

  function normalizeAccountabilityPermissions(input) {
    const source = isPlainObject(input) ? input : {};
    const result = ['progressTotals', 'routineNames', 'checkins', 'steps', 'medication'].reduce((normalized, key) => {
      normalized[key] = source[key] === undefined ? DEFAULT_ACCOUNTABILITY_PERMISSIONS[key] : Boolean(source[key]);
      return normalized;
    }, {});
    result.routineIds = Array.isArray(source.routineIds)
      ? [...new Set(source.routineIds.map(value => String(value || '').trim()).filter(Boolean))].slice(0, 100)
      : null;
    return result;
  }

  function accountabilityDateKey(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function accountabilityDateFromKey(key) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ''));
    if (!match) return null;
    return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  }

  function accountabilityShiftDate(date, days) {
    const next = new Date(date);
    next.setDate(next.getDate() + days);
    next.setHours(0, 0, 0, 0);
    return next;
  }

  function accountabilityItemScheduled(item, date) {
    const frequency = String(item?.frequency || 'daily');
    const day = date.getDay();
    if (frequency === 'weekdays') return day >= 1 && day <= 5;
    if (frequency === 'weekends') return day === 0 || day === 6;
    if (frequency === 'custom') return (Array.isArray(item.days) ? item.days : []).map(Number).includes(day);
    return true;
  }

  function accountabilityEntryComplete(item, value) {
    if (value === undefined || value === null || value === '') return false;
    if (item?.type === 'number') return Number(value) >= Number(item.target || 1);
    if (item?.type === 'memory') return isPlainObject(value) ? Boolean(value.reflected) : Boolean(value);
    if (item?.type === 'medication') {
      if (isPlainObject(value)) return Boolean(value.taken || value.completed || value.time || value.takenAt);
      return Boolean(value);
    }
    if (item?.type === 'scale') return Number.isFinite(Number(value));
    if (item?.type === 'text' || item?.type === 'longtext') return Boolean(String(value).trim());
    return Boolean(value);
  }

  function accountabilityDayMetrics(state, date) {
    const key = accountabilityDateKey(date);
    const day = isPlainObject(state?.days?.[key]) ? state.days[key] : {};
    const entries = isPlainObject(day.entries) ? day.entries : {};
    const items = (Array.isArray(state?.items) ? state.items : []).filter(item =>
      item && item.kind !== 'checkin' && !item.optional && accountabilityItemScheduled(item, date)
    );
    const completed = items.filter(item => accountabilityEntryComplete(item, entries[item.id])).length;
    return { key, entries, items, completed, total: items.length, percent: items.length ? Math.round(completed / items.length * 100) : 0 };
  }

  function accountabilityShareableRoutines(state) {
    return (Array.isArray(state?.items) ? state.items : []).filter(item =>
      item && item.kind !== 'checkin' && item.type !== 'medication' && !['text', 'longtext'].includes(item.type)
    );
  }

  function buildAccountabilitySnapshot(stateInput, options = {}) {
    const state = isPlainObject(stateInput) ? stateInput : {};
    const permissions = normalizeAccountabilityPermissions(options.permissions);
    const generatedAt = String(options.generatedAt || new Date().toISOString());
    const todayDate = accountabilityDateFromKey(options.today) || accountabilityDateFromKey(generatedAt.slice(0, 10)) || new Date();
    const today = accountabilityDayMetrics(state, todayDate);
    const dayOfWeek = todayDate.getDay();
    const weekStart = accountabilityShiftDate(todayDate, dayOfWeek === 0 ? -6 : 1 - dayOfWeek);
    const dates = [];
    for (let cursor = weekStart; accountabilityDateKey(cursor) <= today.key; cursor = accountabilityShiftDate(cursor, 1)) dates.push(cursor);
    const metrics = dates.map(date => accountabilityDayMetrics(state, date))
      .filter(metric => metric.key === today.key || isPlainObject(state?.days?.[metric.key]));
    const historyDates = Array.from({ length: 30 }, (_, index) => accountabilityShiftDate(todayDate, index - 29));
    const trackedHistoryDates = historyDates.filter(date => accountabilityDateKey(date) === today.key || isPlainObject(state?.days?.[accountabilityDateKey(date)]));
    const historyMetrics = trackedHistoryDates.map(date => accountabilityDayMetrics(state, date));
    const completed = metrics.reduce((sum, metric) => sum + metric.completed, 0);
    const total = metrics.reduce((sum, metric) => sum + metric.total, 0);
    const truthCompletions = isPlainObject(state?.settings?.truthBeforeTasks?.completions) ? state.settings.truthBeforeTasks.completions : {};
    const snapshot = {
      schemaVersion: ACCOUNTABILITY_SCHEMA_VERSION,
      generatedAt,
      member: { displayName: String(options.displayName || '').trim().slice(0, 80) },
      permissions,
      period: { start: accountabilityDateKey(weekStart), end: today.key }
    };

    if (permissions.progressTotals) {
      snapshot.today = {
        date: today.key,
        completed: today.completed,
        total: today.total,
        percent: today.percent,
        truthBeforeTasks: Boolean(truthCompletions[today.key])
      };
      snapshot.week = {
        completed,
        total,
        percent: total ? Math.round(completed / total * 100) : 0,
        trackedDays: metrics.filter(metric => metric.total > 0).length,
        strongDays: metrics.filter(metric => metric.total > 0 && metric.percent >= 80).length
      };
      snapshot.daily = historyMetrics.map(metric => ({
        date: metric.key,
        completed: metric.completed,
        total: metric.total,
        percent: metric.percent,
        truthBeforeTasks: Boolean(truthCompletions[metric.key])
      }));
    }

    if (permissions.routineNames) {
      const allowedIds = Array.isArray(permissions.routineIds) ? new Set(permissions.routineIds) : null;
      const sharedRoutines = accountabilityShareableRoutines(state).filter(item => !allowedIds || allowedIds.has(String(item.id || '')));
      snapshot.routines = sharedRoutines
        .filter(item => accountabilityItemScheduled(item, todayDate))
        .map(item => ({
          name: String(item.name || 'Routine').slice(0, 100),
          section: ['morning', 'day', 'evening'].includes(item.section) ? item.section : 'day',
          completed: accountabilityEntryComplete(item, today.entries[item.id])
        }));
      snapshot.routineTrends = sharedRoutines.map(item => {
        const itemDays = trackedHistoryDates.filter(date => accountabilityItemScheduled(item, date)).map(date => {
          const key = accountabilityDateKey(date);
          const entries = isPlainObject(state?.days?.[key]?.entries) ? state.days[key].entries : {};
          return { date: key, completed: accountabilityEntryComplete(item, entries[item.id]) };
        });
        const completedCount = itemDays.filter(day => day.completed).length;
        return {
          name: String(item.name || 'Routine').slice(0, 100),
          section: ['morning', 'day', 'evening'].includes(item.section) ? item.section : 'day',
          completed: completedCount,
          scheduled: itemDays.length,
          percent: itemDays.length ? Math.round(completedCount / itemDays.length * 100) : 0,
          days: itemDays
        };
      });
    }

    if (permissions.checkins) {
      snapshot.checkins = (Array.isArray(state.items) ? state.items : [])
        .filter(item => item?.kind === 'checkin' && item.type === 'scale')
        .map(item => {
          const values = metrics.map(metric => Number(metric.entries[item.id])).filter(Number.isFinite);
          return values.length ? {
            name: String(item.name || 'Check-in').slice(0, 100),
            average: Math.round(values.reduce((sum, value) => sum + value, 0) / values.length * 10) / 10,
            count: values.length
          } : null;
        }).filter(Boolean);
    }

    if (permissions.steps) {
      const stepItem = (Array.isArray(state.items) ? state.items : []).find(item => String(item?.healthSource || '') === 'apple-health-steps');
      if (stepItem) {
        const count = Math.max(0, Number(today.entries[stepItem.id]) || 0);
        const goal = Math.max(1, Number(stepItem.target) || 8000);
        snapshot.steps = { count: Math.round(count), goal: Math.round(goal), percent: Math.min(100, Math.round(count / goal * 100)) };
      }
    }

    if (permissions.medication) {
      const medicationItems = (Array.isArray(state.items) ? state.items : []).filter(item => item?.type === 'medication' && accountabilityItemScheduled(item, todayDate));
      snapshot.medication = {
        completed: medicationItems.filter(item => accountabilityEntryComplete(item, today.entries[item.id])).length,
        total: medicationItems.length
      };
    }

    return snapshot;
  }

  class SyncCoordinator {
    constructor({ storage, metadataKey = METADATA_KEY, conflictsKey = CONFLICTS_KEY } = {}) {
      this.storage = storage;
      this.metadataKey = metadataKey;
      this.conflictsKey = conflictsKey;
      this.metadata = this.readMetadata();
    }

    readMetadata() {
      let stored = {};
      try { stored = JSON.parse(this.storage?.getItem(this.metadataKey) || '{}'); } catch { stored = {}; }
      return {
        schemaVersion: SYNC_SCHEMA_VERSION,
        deviceId: String(stored.deviceId || createDeviceId()),
        provider: String(stored.provider || ''),
        accountId: String(stored.accountId || ''),
        baseRevision: Math.max(0, Number(stored.baseRevision) || 0),
        baseState: stored.baseState && typeof stored.baseState === 'object' ? stored.baseState : null,
        localFingerprint: String(stored.localFingerprint || ''),
        localChangeCount: Math.max(0, Number(stored.localChangeCount) || 0),
        dirty: Boolean(stored.dirty),
        pendingSince: String(stored.pendingSince || ''),
        lastSyncedAt: String(stored.lastSyncedAt || ''),
        lastError: String(stored.lastError || '')
      };
    }

    writeMetadata() {
      this.storage?.setItem(this.metadataKey, JSON.stringify(this.metadata));
    }

    ensureLocalState(currentState) {
      const nextFingerprint = fingerprint(syncableState(currentState));
      if (!this.metadata.localFingerprint) {
        this.metadata.localFingerprint = nextFingerprint;
        this.metadata.dirty = true;
        this.metadata.localChangeCount = Math.max(1, this.metadata.localChangeCount);
        this.metadata.pendingSince ||= new Date().toISOString();
      }
      this.writeMetadata();
      return this.status();
    }

    markLocalChange(currentState) {
      const nextFingerprint = fingerprint(syncableState(currentState));
      if (nextFingerprint === this.metadata.localFingerprint) return this.status();
      this.metadata.localFingerprint = nextFingerprint;
      this.metadata.localChangeCount += 1;
      this.metadata.dirty = true;
      this.metadata.pendingSince ||= new Date().toISOString();
      this.metadata.lastError = '';
      this.writeMetadata();
      return this.status();
    }

    status() {
      return {
        schemaVersion: this.metadata.schemaVersion,
        deviceId: this.metadata.deviceId,
        connected: Boolean(this.metadata.provider && this.metadata.accountId),
        provider: this.metadata.provider,
        baseRevision: this.metadata.baseRevision,
        dirty: this.metadata.dirty,
        localChangeCount: this.metadata.localChangeCount,
        pendingSince: this.metadata.pendingSince,
        lastSyncedAt: this.metadata.lastSyncedAt,
        lastError: this.metadata.lastError
      };
    }

    reconcile(currentState, remoteEnvelope) {
      const local = syncableState(currentState);
      if (!remoteEnvelope?.document) {
        return { action: 'upload', state: local, expectedRevision: 0, conflicts: [] };
      }

      const remote = syncableState(remoteEnvelope.document);
      const remoteRevision = Math.max(0, Number(remoteEnvelope.revision) || 0);
      if (!this.metadata.baseState) {
        if (!this.metadata.dirty) return { action: 'adopt', state: remote, remoteRevision, conflicts: [] };
        const merged = mergeRoutineStates({}, local, remote);
        this.saveConflicts(merged.conflicts, local, remote, remoteRevision);
        return { action: 'upload', state: merged.state, expectedRevision: remoteRevision, conflicts: merged.conflicts };
      }

      if (remoteRevision === this.metadata.baseRevision) {
        return this.metadata.dirty
          ? { action: 'upload', state: local, expectedRevision: remoteRevision, conflicts: [] }
          : { action: 'none', state: local, remoteRevision, conflicts: [] };
      }

      if (!this.metadata.dirty) return { action: 'adopt', state: remote, remoteRevision, conflicts: [] };
      const merged = mergeRoutineStates(this.metadata.baseState, local, remote);
      this.saveConflicts(merged.conflicts, local, remote, remoteRevision);
      return { action: 'upload', state: merged.state, expectedRevision: remoteRevision, conflicts: merged.conflicts };
    }

    commitRemote(currentState, revision, provider = this.metadata.provider, accountId = this.metadata.accountId) {
      const synced = syncableState(currentState);
      this.metadata.provider = String(provider || '');
      this.metadata.accountId = String(accountId || '');
      this.metadata.baseRevision = Math.max(0, Number(revision) || 0);
      this.metadata.baseState = synced;
      this.metadata.localFingerprint = fingerprint(synced);
      this.metadata.localChangeCount = 0;
      this.metadata.dirty = false;
      this.metadata.pendingSince = '';
      this.metadata.lastSyncedAt = new Date().toISOString();
      this.metadata.lastError = '';
      this.writeMetadata();
      return this.status();
    }

    recordFailure(error) {
      this.metadata.lastError = String(error?.message || error || 'Sync could not be completed.').slice(0, 500);
      this.writeMetadata();
      return this.status();
    }

    disconnect() {
      this.metadata.provider = '';
      this.metadata.accountId = '';
      this.metadata.baseRevision = 0;
      this.metadata.baseState = null;
      this.metadata.lastSyncedAt = '';
      this.metadata.lastError = '';
      this.writeMetadata();
      return this.status();
    }

    saveConflicts(conflicts, local, remote, remoteRevision) {
      if (!conflicts.length) return;
      let history = [];
      try { history = JSON.parse(this.storage?.getItem(this.conflictsKey) || '[]'); } catch { history = []; }
      history.unshift({
        createdAt: new Date().toISOString(),
        remoteRevision,
        conflicts: clone(conflicts),
        local: syncableState(local),
        remote: syncableState(remote)
      });
      try { this.storage?.setItem(this.conflictsKey, JSON.stringify(history.slice(0, 3))); } catch { /* best effort */ }
    }
  }

  function createCoordinator(options) {
    return new SyncCoordinator(options);
  }

  return {
    SYNC_SCHEMA_VERSION,
    ACCOUNTABILITY_SCHEMA_VERSION,
    DEFAULT_ACCOUNTABILITY_PERMISSIONS,
    METADATA_KEY,
    CONFLICTS_KEY,
    syncableState,
    applySyncableState,
    mergeRoutineStates,
    normalizeAccountabilityPermissions,
    buildAccountabilitySnapshot,
    createCoordinator,
    SyncCoordinator
  };
});
