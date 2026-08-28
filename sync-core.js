(function attachDailyRoutineSync(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.DailyRoutineSync = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';

  const SYNC_SCHEMA_VERSION = 1;
  const METADATA_KEY = 'dailyRoutine.sync.metadata.v1';
  const CONFLICTS_KEY = 'dailyRoutine.sync.conflicts.v1';
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
    METADATA_KEY,
    CONFLICTS_KEY,
    syncableState,
    applySyncableState,
    mergeRoutineStates,
    createCoordinator,
    SyncCoordinator
  };
});
