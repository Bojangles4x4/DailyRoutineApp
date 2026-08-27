(function attachDailyRoutineCloud(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.DailyRoutineCloud = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';

  const SESSION_KEY = 'dailyRoutine.sync.session.v1';

  class CloudRequestError extends Error {
    constructor(message, status = 0, code = '') {
      super(message);
      this.name = 'CloudRequestError';
      this.status = status;
      this.code = code;
    }
  }

  class CloudConflictError extends CloudRequestError {
    constructor(message = 'The cloud copy changed before this device could save.') {
      super(message, 409, 'revision_conflict');
      this.name = 'CloudConflictError';
    }
  }

  class SupabaseRoutineClient {
    constructor({ url, publishableKey, storage, fetchImpl, sessionKey = SESSION_KEY } = {}) {
      this.url = String(url || '').replace(/\/$/, '');
      this.publishableKey = String(publishableKey || '');
      this.storage = storage;
      this.fetchImpl = fetchImpl || globalThis.fetch?.bind(globalThis);
      this.sessionKey = sessionKey;
      if (!this.url || !this.publishableKey || !this.fetchImpl) {
        throw new Error('Private sync cloud configuration is incomplete.');
      }
    }

    readSession() {
      try {
        const session = JSON.parse(this.storage?.getItem(this.sessionKey) || 'null');
        return session?.access_token && session?.refresh_token ? session : null;
      } catch {
        return null;
      }
    }

    writeSession(session) {
      if (!session) {
        this.storage?.removeItem(this.sessionKey);
        return null;
      }
      const expiresAt = Number(session.expires_at) || Math.floor(Date.now() / 1000) + Number(session.expires_in || 3600);
      const stored = { ...session, expires_at: expiresAt };
      this.storage?.setItem(this.sessionKey, JSON.stringify(stored));
      return stored;
    }

    async request(path, { method = 'GET', token = '', body, headers = {} } = {}) {
      const response = await this.fetchImpl(`${this.url}${path}`, {
        method,
        headers: {
          apikey: this.publishableKey,
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
          ...headers
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) })
      });
      const text = await response.text();
      let payload = null;
      try { payload = text ? JSON.parse(text) : null; } catch { payload = text || null; }
      if (!response.ok) {
        const message = payload?.msg || payload?.message || payload?.error_description || payload?.error || `Cloud request failed (${response.status}).`;
        throw new CloudRequestError(String(message), response.status, String(payload?.code || payload?.error_code || ''));
      }
      return payload;
    }

    async requestEmailLink(email, createUser = false, redirectTo = '') {
      const suffix = redirectTo ? `?redirect_to=${encodeURIComponent(redirectTo)}` : '';
      await this.request(`/auth/v1/otp${suffix}`, {
        method: 'POST',
        body: { email: String(email || '').trim().toLowerCase(), create_user: Boolean(createUser) }
      });
    }

    async requestEmailCode(email, createUser = false, redirectTo = '') {
      return this.requestEmailLink(email, createUser, redirectTo);
    }

    async signInWithPassword(email, password) {
      const session = await this.request('/auth/v1/token?grant_type=password', {
        method: 'POST',
        body: {
          email: String(email || '').trim().toLowerCase(),
          password: String(password || '')
        }
      });
      return this.writeSession(session);
    }

    async verifyEmailCode(email, token) {
      const session = await this.request('/auth/v1/verify', {
        method: 'POST',
        body: {
          type: 'email',
          email: String(email || '').trim().toLowerCase(),
          token: String(token || '').replace(/\s/g, '')
        }
      });
      return this.writeSession(session);
    }

    async consumeAuthRedirect(locationInput = globalThis.location, historyInput = globalThis.history) {
      const rawHash = String(locationInput?.hash || '').replace(/^#/, '');
      if (!rawHash) return null;
      const params = new URLSearchParams(rawHash);
      const errorDescription = params.get('error_description');
      if (errorDescription) {
        this.clearAuthFragment(locationInput, historyInput);
        throw new CloudRequestError(errorDescription, 401, params.get('error_code') || 'auth_redirect_error');
      }
      const accessToken = params.get('access_token');
      const refreshToken = params.get('refresh_token');
      if (!accessToken || !refreshToken) return null;
      const user = await this.request('/auth/v1/user', { token: accessToken });
      const session = this.writeSession({
        access_token: accessToken,
        refresh_token: refreshToken,
        token_type: params.get('token_type') || 'bearer',
        expires_in: Number(params.get('expires_in')) || 3600,
        expires_at: Number(params.get('expires_at')) || 0,
        user
      });
      this.clearAuthFragment(locationInput, historyInput);
      return session;
    }

    clearAuthFragment(locationInput, historyInput) {
      if (!historyInput?.replaceState || !locationInput) return;
      historyInput.replaceState(null, '', `${locationInput.pathname || ''}${locationInput.search || ''}`);
    }

    async session() {
      let session = this.readSession();
      if (!session) return null;
      if (Number(session.expires_at) > Math.floor(Date.now() / 1000) + 60) return session;
      try {
        session = await this.request('/auth/v1/token?grant_type=refresh_token', {
          method: 'POST',
          body: { refresh_token: session.refresh_token }
        });
        return this.writeSession(session);
      } catch (error) {
        if (error.status === 400 || error.status === 401) this.writeSession(null);
        throw error;
      }
    }

    async signOut() {
      const session = this.readSession();
      try {
        if (session?.access_token) await this.request('/auth/v1/logout', { method: 'POST', token: session.access_token });
      } finally {
        this.writeSession(null);
      }
    }

    async fetchRoutine(sessionInput) {
      const session = sessionInput || await this.session();
      if (!session?.access_token || !session?.user?.id) throw new CloudRequestError('Sign in before syncing.', 401, 'not_signed_in');
      const rows = await this.request('/rest/v1/routine_documents?select=owner_id,schema_version,revision,document,updated_at,updated_by&limit=1', {
        token: session.access_token
      });
      return Array.isArray(rows) && rows.length ? rows[0] : null;
    }

    async deleteRoutine(sessionInput) {
      const session = sessionInput || await this.session();
      if (!session?.access_token || !session?.user?.id) throw new CloudRequestError('Sign in before deleting the cloud copy.', 401, 'not_signed_in');
      await this.request(`/rest/v1/routine_documents?owner_id=eq.${encodeURIComponent(session.user.id)}`, {
        method: 'DELETE',
        token: session.access_token,
        headers: { Prefer: 'return=minimal' }
      });
    }

    async pushRoutine({ session: sessionInput, document, expectedRevision, deviceId, schemaVersion = 1 }) {
      const session = sessionInput || await this.session();
      if (!session?.access_token || !session?.user?.id) throw new CloudRequestError('Sign in before syncing.', 401, 'not_signed_in');
      const ownerId = session.user.id;
      const body = {
        owner_id: ownerId,
        schema_version: schemaVersion,
        document,
        updated_by: String(deviceId || '').slice(0, 100)
      };
      try {
        if (Number(expectedRevision) <= 0) {
          const rows = await this.request('/rest/v1/routine_documents', {
            method: 'POST',
            token: session.access_token,
            body,
            headers: { Prefer: 'return=representation' }
          });
          if (!Array.isArray(rows) || !rows[0]) throw new CloudConflictError();
          return rows[0];
        }

        const rows = await this.request(`/rest/v1/routine_documents?owner_id=eq.${encodeURIComponent(ownerId)}&revision=eq.${Number(expectedRevision)}`, {
          method: 'PATCH',
          token: session.access_token,
          body: { schema_version: schemaVersion, document, updated_by: body.updated_by },
          headers: { Prefer: 'return=representation' }
        });
        if (!Array.isArray(rows) || !rows[0]) throw new CloudConflictError();
        return rows[0];
      } catch (error) {
        if (error instanceof CloudConflictError || error.status === 409) throw new CloudConflictError();
        throw error;
      }
    }
  }

  function createClient(options) {
    return new SupabaseRoutineClient(options);
  }

  return { SESSION_KEY, CloudRequestError, CloudConflictError, SupabaseRoutineClient, createClient };
});
