(() => {
  'use strict';

  const STORAGE_KEY = 'dailyRoutineApp.v1';
  const DEFAULT_STATE = {
    settings: {
      wakeTime: '06:00',
      bedTime: '22:30'
    },
    items: [
      { id: 'morning-prayer', name: 'Prayer', section: 'morning', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'morning-teeth', name: 'Brush teeth', section: 'morning', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'morning-meds', name: 'Take morning medicine', section: 'morning', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'morning-reading', name: 'Morning reading', section: 'morning', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'day-water', name: 'Water', section: 'day', type: 'number', frequency: 'daily', unit: 'cups' },
      { id: 'day-movement', name: 'Movement / exercise', section: 'day', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'day-focus', name: 'Focus / productivity', section: 'day', type: 'scale', frequency: 'weekdays', unit: '' },
      { id: 'evening-teeth', name: 'Brush teeth', section: 'evening', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'evening-meds', name: 'Take evening medicine', section: 'evening', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'evening-prepare', name: 'Prepare for tomorrow', section: 'evening', type: 'checkbox', frequency: 'daily', unit: '' },
      { id: 'evening-reflection', name: 'Daily reflection', section: 'evening', type: 'text', frequency: 'daily', unit: '' }
    ],
    days: {}
  };

  const sectionLabels = {
    morning: ['Morning', 'Start deliberately'],
    day: ['Throughout the day', 'Stay on track'],
    evening: ['Evening', 'Close the day well']
  };

  const typeLabels = {
    checkbox: 'Checkbox',
    scale: '0–10 rating',
    number: 'Number',
    time: 'Time',
    text: 'Comments'
  };

  let state = loadState();
  let selectedDate = startOfToday();
  let deferredInstallPrompt = null;
  let toastTimer = null;

  const $ = (id) => document.getElementById(id);
  const els = {
    pageTitle: $('pageTitle'),
    todayEyebrow: $('todayEyebrow'),
    wakeTimeDisplay: $('wakeTimeDisplay'),
    progressRing: $('progressRing'),
    progressPercent: $('progressPercent'),
    selectedDateButton: $('selectedDateButton'),
    prevDay: $('prevDay'),
    nextDay: $('nextDay'),
    routineSections: $('routineSections'),
    moodInput: $('moodInput'),
    energyInput: $('energyInput'),
    stressInput: $('stressInput'),
    moodValue: $('moodValue'),
    energyValue: $('energyValue'),
    stressValue: $('stressValue'),
    moodNotes: $('moodNotes'),
    statCompleted: $('statCompleted'),
    statStreak: $('statStreak'),
    statMood: $('statMood'),
    copySummaryButton: $('copySummaryButton'),
    historyList: $('historyList'),
    wakeTimeInput: $('wakeTimeInput'),
    bedTimeInput: $('bedTimeInput'),
    routineEditor: $('routineEditor'),
    addItemButton: $('addItemButton'),
    exportCsvButton: $('exportCsvButton'),
    exportJsonButton: $('exportJsonButton'),
    importJsonInput: $('importJsonInput'),
    resetDataButton: $('resetDataButton'),
    itemDialog: $('itemDialog'),
    itemForm: $('itemForm'),
    dialogTitle: $('dialogTitle'),
    editingItemId: $('editingItemId'),
    itemNameInput: $('itemNameInput'),
    itemSectionInput: $('itemSectionInput'),
    itemTypeInput: $('itemTypeInput'),
    itemFrequencyInput: $('itemFrequencyInput'),
    itemUnitLabel: $('itemUnitLabel'),
    itemUnitInput: $('itemUnitInput'),
    deleteItemButton: $('deleteItemButton'),
    closeDialogButton: $('closeDialogButton'),
    installButton: $('installButton'),
    toast: $('toast')
  };

  init();

  function init() {
    bindNavigation();
    bindTodayControls();
    bindSetupControls();
    bindInstall();
    renderAll();

    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => navigator.serviceWorker.register('./service-worker.js').catch(() => {}));
    }
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return structuredClone(DEFAULT_STATE);
      const parsed = JSON.parse(raw);
      return {
        settings: { ...DEFAULT_STATE.settings, ...(parsed.settings || {}) },
        items: Array.isArray(parsed.items) ? parsed.items : structuredClone(DEFAULT_STATE.items),
        days: parsed.days && typeof parsed.days === 'object' ? parsed.days : {}
      };
    } catch {
      return structuredClone(DEFAULT_STATE);
    }
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }

  function startOfToday() {
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    return d;
  }

  function dateKey(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  function fromDateKey(key) {
    const [y, m, d] = key.split('-').map(Number);
    return new Date(y, m - 1, d, 12, 0, 0, 0);
  }

  function shiftDate(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
  }

  function isSameDay(a, b) {
    return dateKey(a) === dateKey(b);
  }

  function ensureDay(key) {
    if (!state.days[key]) {
      state.days[key] = { entries: {}, mood: null, energy: null, stress: null, notes: '' };
    }
    return state.days[key];
  }

  function scheduledItemsForDate(date) {
    const day = date.getDay();
    return state.items.filter((item) => {
      if (item.frequency === 'weekdays') return day >= 1 && day <= 5;
      if (item.frequency === 'weekends') return day === 0 || day === 6;
      return true;
    });
  }

  function entryIsLogged(item, value) {
    if (item.type === 'checkbox') return value === true;
    if (item.type === 'scale') return Number.isFinite(Number(value));
    return value !== undefined && value !== null && String(value).trim() !== '';
  }

  function completionForDate(date) {
    const items = scheduledItemsForDate(date);
    if (!items.length) return { completed: 0, total: 0, percent: 0 };
    const day = state.days[dateKey(date)] || { entries: {} };
    const completed = items.filter((item) => entryIsLogged(item, day.entries?.[item.id])).length;
    return { completed, total: items.length, percent: Math.round((completed / items.length) * 100) };
  }

  function calculateStreak() {
    let streak = 0;
    let cursor = startOfToday();
    for (let i = 0; i < 3650; i += 1) {
      const c = completionForDate(cursor);
      if (c.total > 0 && c.percent >= 80) {
        streak += 1;
        cursor = shiftDate(cursor, -1);
      } else {
        break;
      }
    }
    return streak;
  }

  function bindNavigation() {
    document.querySelectorAll('.nav-button').forEach((button) => {
      button.addEventListener('click', () => switchView(button.dataset.view));
    });
  }

  function switchView(view) {
    document.querySelectorAll('.nav-button').forEach((button) => button.classList.toggle('active', button.dataset.view === view));
    document.querySelectorAll('.view').forEach((node) => node.classList.remove('active'));
    $(`${view}View`).classList.add('active');

    const titles = { today: 'Today', history: 'History', setup: 'Setup' };
    els.pageTitle.textContent = titles[view] || 'Daily Routine';
    els.todayEyebrow.textContent = view === 'today' ? 'Daily Routine' : 'Daily Routine';
    if (view === 'history') renderHistory();
    if (view === 'setup') renderSetup();
    $('appMain').focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function bindTodayControls() {
    els.prevDay.addEventListener('click', () => {
      selectedDate = shiftDate(selectedDate, -1);
      renderToday();
    });
    els.nextDay.addEventListener('click', () => {
      selectedDate = shiftDate(selectedDate, 1);
      renderToday();
    });
    els.selectedDateButton.addEventListener('click', () => {
      selectedDate = startOfToday();
      renderToday();
    });

    [
      ['mood', els.moodInput, els.moodValue],
      ['energy', els.energyInput, els.energyValue],
      ['stress', els.stressInput, els.stressValue]
    ].forEach(([field, input, output]) => {
      input.addEventListener('input', () => {
        output.textContent = input.value;
      });
      input.addEventListener('change', () => {
        const key = dateKey(selectedDate);
        const day = ensureDay(key);
        day[field] = Number(input.value);
        saveState();
        renderStats();
      });
    });

    els.moodNotes.addEventListener('input', debounce(() => {
      const day = ensureDay(dateKey(selectedDate));
      day.notes = els.moodNotes.value;
      saveState();
    }, 250));

    els.copySummaryButton.addEventListener('click', copyDailySummary);
  }

  function bindSetupControls() {
    els.wakeTimeInput.addEventListener('change', () => {
      state.settings.wakeTime = els.wakeTimeInput.value || DEFAULT_STATE.settings.wakeTime;
      saveState();
      renderToday();
    });
    els.bedTimeInput.addEventListener('change', () => {
      state.settings.bedTime = els.bedTimeInput.value || DEFAULT_STATE.settings.bedTime;
      saveState();
    });

    els.addItemButton.addEventListener('click', () => openItemDialog());
    els.closeDialogButton.addEventListener('click', () => els.itemDialog.close());
    els.itemTypeInput.addEventListener('change', toggleUnitField);
    els.itemForm.addEventListener('submit', saveRoutineItem);
    els.deleteItemButton.addEventListener('click', deleteRoutineItem);

    els.exportCsvButton.addEventListener('click', exportCsv);
    els.exportJsonButton.addEventListener('click', exportJson);
    els.importJsonInput.addEventListener('change', importJson);
    els.resetDataButton.addEventListener('click', resetData);
  }

  function bindInstall() {
    window.addEventListener('beforeinstallprompt', (event) => {
      event.preventDefault();
      deferredInstallPrompt = event;
      els.installButton.hidden = false;
    });
    els.installButton.addEventListener('click', async () => {
      if (!deferredInstallPrompt) return;
      deferredInstallPrompt.prompt();
      await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;
      els.installButton.hidden = true;
    });
  }

  function renderAll() {
    renderToday();
    renderHistory();
    renderSetup();
  }

  function renderToday() {
    const key = dateKey(selectedDate);
    const day = state.days[key] || { entries: {}, mood: null, energy: null, stress: null, notes: '' };
    const today = startOfToday();

    els.wakeTimeDisplay.textContent = formatTime(state.settings.wakeTime);
    els.selectedDateButton.textContent = isSameDay(selectedDate, today)
      ? new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'short', day: 'numeric' }).format(selectedDate)
      : new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric', year: selectedDate.getFullYear() !== today.getFullYear() ? 'numeric' : undefined }).format(selectedDate);

    els.nextDay.disabled = dateKey(selectedDate) >= dateKey(today);
    els.nextDay.style.opacity = els.nextDay.disabled ? '.35' : '1';

    renderRoutineSections(day);
    setScaleField('mood', day.mood, els.moodInput, els.moodValue);
    setScaleField('energy', day.energy, els.energyInput, els.energyValue);
    setScaleField('stress', day.stress, els.stressInput, els.stressValue);
    els.moodNotes.value = day.notes || '';
    renderStats();
  }

  function renderRoutineSections(day) {
    els.routineSections.innerHTML = '';
    const scheduled = scheduledItemsForDate(selectedDate);

    ['morning', 'day', 'evening'].forEach((section) => {
      const items = scheduled.filter((item) => item.section === section);
      const logged = items.filter((item) => entryIsLogged(item, day.entries?.[item.id])).length;
      const [title, subtitle] = sectionLabels[section];
      const wrapper = document.createElement('section');
      wrapper.className = 'routine-section';
      wrapper.innerHTML = `
        <div class="card">
          <div class="section-heading">
            <div><p class="eyebrow">${escapeHtml(subtitle)}</p><h2>${escapeHtml(title)}</h2></div>
            <span class="section-progress">${logged}/${items.length}</span>
          </div>
          <div class="task-list" data-section="${section}"></div>
        </div>`;
      const list = wrapper.querySelector('.task-list');
      if (!items.length) {
        list.innerHTML = '<div class="empty-state">No items scheduled here.</div>';
      } else {
        items.forEach((item) => list.appendChild(buildTaskRow(item, day.entries?.[item.id])));
      }
      els.routineSections.appendChild(wrapper);
    });
  }

  function buildTaskRow(item, value) {
    const row = document.createElement('div');
    row.className = `task-row${item.type === 'checkbox' && value === true ? ' done' : ''}`;

    if (item.type === 'checkbox') {
      row.innerHTML = `
        <label class="task-main">
          <input class="check-control" type="checkbox" ${value === true ? 'checked' : ''} />
          <span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${frequencyLabel(item.frequency)}</span></span>
        </label>`;
      row.querySelector('input').addEventListener('change', (event) => saveEntry(item, event.target.checked));
      return row;
    }

    row.innerHTML = `
      <div class="task-main">
        <span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${typeLabels[item.type]}${item.unit ? ` · ${escapeHtml(item.unit)}` : ''}</span></span>
      </div>
      <div class="task-extra"></div>`;
    const extra = row.querySelector('.task-extra');

    if (item.type === 'scale') {
      const current = Number.isFinite(Number(value)) ? Number(value) : 5;
      extra.innerHTML = `<div class="scale-control"><input type="range" min="0" max="10" step="1" value="${current}" /><output>${value === undefined ? '—' : current}</output></div>`;
      const input = extra.querySelector('input');
      const output = extra.querySelector('output');
      input.addEventListener('input', () => { output.textContent = input.value; });
      input.addEventListener('change', () => saveEntry(item, Number(input.value)));
    } else if (item.type === 'text') {
      extra.innerHTML = `<textarea class="task-input" rows="2" placeholder="Add a comment…">${escapeHtml(value || '')}</textarea>`;
      extra.querySelector('textarea').addEventListener('input', debounce((event) => saveEntry(item, event.target.value, false), 250));
    } else if (item.type === 'number') {
      extra.innerHTML = `<div class="scale-control"><span></span><input class="task-input inline-number" type="number" step="any" inputmode="decimal" value="${escapeHtml(value ?? '')}" placeholder="0" /></div>`;
      extra.querySelector('input').addEventListener('change', (event) => saveEntry(item, event.target.value));
    } else if (item.type === 'time') {
      extra.innerHTML = `<input class="task-input" type="time" value="${escapeHtml(value || '')}" />`;
      extra.querySelector('input').addEventListener('change', (event) => saveEntry(item, event.target.value));
    }

    return row;
  }

  function saveEntry(item, value, rerender = true) {
    const day = ensureDay(dateKey(selectedDate));
    day.entries[item.id] = value;
    saveState();
    if (rerender) renderToday();
    else renderStats();
  }

  function setScaleField(field, value, input, output) {
    const hasValue = Number.isFinite(Number(value));
    input.value = hasValue ? Number(value) : 5;
    output.textContent = hasValue ? Number(value) : '—';
    input.setAttribute('aria-label', `${field} ${hasValue ? value : 'not logged'}`);
  }

  function renderStats() {
    const completion = completionForDate(selectedDate);
    const day = state.days[dateKey(selectedDate)] || {};
    els.progressPercent.textContent = `${completion.percent}%`;
    els.progressRing.style.setProperty('--p', completion.percent);
    els.progressRing.setAttribute('aria-label', `${completion.percent} percent complete`);
    els.statCompleted.textContent = `${completion.completed}/${completion.total}`;
    els.statStreak.textContent = calculateStreak();
    els.statMood.textContent = Number.isFinite(Number(day.mood)) ? `${day.mood}/10` : '—';
  }

  function renderHistory() {
    els.historyList.innerHTML = '';
    const today = startOfToday();
    for (let i = 0; i < 30; i += 1) {
      const date = shiftDate(today, -i);
      const key = dateKey(date);
      const day = state.days[key] || {};
      const c = completionForDate(date);
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'history-row';
      const weekday = new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(date);
      const month = new Intl.DateTimeFormat(undefined, { month: 'short' }).format(date);
      row.innerHTML = `
        <span class="history-date"><strong>${date.getDate()}</strong><span>${month}</span></span>
        <span class="history-copy"><strong>${weekday}${i === 0 ? ' · Today' : ''}</strong><span>${c.completed} of ${c.total} logged</span><span class="history-bar"><span style="width:${c.percent}%"></span></span></span>
        <span class="history-mood">Mood<br><b>${Number.isFinite(Number(day.mood)) ? day.mood : '—'}</b></span>`;
      row.addEventListener('click', () => {
        selectedDate = date;
        switchView('today');
        renderToday();
      });
      els.historyList.appendChild(row);
    }
  }

  function renderSetup() {
    els.wakeTimeInput.value = state.settings.wakeTime;
    els.bedTimeInput.value = state.settings.bedTime;
    els.routineEditor.innerHTML = '';

    ['morning', 'day', 'evening'].forEach((section) => {
      state.items.filter((item) => item.section === section).forEach((item) => {
        const row = document.createElement('div');
        row.className = 'editor-row';
        row.innerHTML = `<div><strong>${escapeHtml(item.name)}</strong><span>${sectionLabels[section][0]} · ${typeLabels[item.type]} · ${frequencyLabel(item.frequency)}</span></div><button class="edit-button" type="button">Edit</button>`;
        row.querySelector('button').addEventListener('click', () => openItemDialog(item));
        els.routineEditor.appendChild(row);
      });
    });
  }

  function openItemDialog(item = null) {
    els.editingItemId.value = item?.id || '';
    els.dialogTitle.textContent = item ? 'Edit item' : 'Add item';
    els.itemNameInput.value = item?.name || '';
    els.itemSectionInput.value = item?.section || 'morning';
    els.itemTypeInput.value = item?.type || 'checkbox';
    els.itemFrequencyInput.value = item?.frequency || 'daily';
    els.itemUnitInput.value = item?.unit || '';
    els.deleteItemButton.hidden = !item;
    toggleUnitField();
    els.itemDialog.showModal();
    setTimeout(() => els.itemNameInput.focus(), 50);
  }

  function toggleUnitField() {
    els.itemUnitLabel.hidden = els.itemTypeInput.value !== 'number';
  }

  function saveRoutineItem(event) {
    event.preventDefault();
    const name = els.itemNameInput.value.trim();
    if (!name) return;

    const payload = {
      name,
      section: els.itemSectionInput.value,
      type: els.itemTypeInput.value,
      frequency: els.itemFrequencyInput.value,
      unit: els.itemTypeInput.value === 'number' ? els.itemUnitInput.value.trim() : ''
    };
    const editingId = els.editingItemId.value;
    if (editingId) {
      const idx = state.items.findIndex((item) => item.id === editingId);
      if (idx >= 0) state.items[idx] = { ...state.items[idx], ...payload };
    } else {
      state.items.push({ id: `item-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, ...payload });
    }
    saveState();
    els.itemDialog.close();
    renderAll();
    showToast(editingId ? 'Routine item updated' : 'Routine item added');
  }

  function deleteRoutineItem() {
    const id = els.editingItemId.value;
    if (!id) return;
    const item = state.items.find((entry) => entry.id === id);
    if (!item || !confirm(`Delete “${item.name}”? Existing historical values for it will remain in backups but will no longer display.`)) return;
    state.items = state.items.filter((entry) => entry.id !== id);
    saveState();
    els.itemDialog.close();
    renderAll();
    showToast('Routine item deleted');
  }

  async function copyDailySummary() {
    const day = state.days[dateKey(selectedDate)] || {};
    const c = completionForDate(selectedDate);
    const summary = [
      `Daily Routine — ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(selectedDate)}`,
      `Progress: ${c.completed}/${c.total} (${c.percent}%)`,
      `Mood: ${Number.isFinite(Number(day.mood)) ? `${day.mood}/10` : 'not logged'}`,
      `Energy: ${Number.isFinite(Number(day.energy)) ? `${day.energy}/10` : 'not logged'}`,
      `Stress: ${Number.isFinite(Number(day.stress)) ? `${day.stress}/10` : 'not logged'}`,
      day.notes ? `Notes: ${day.notes}` : ''
    ].filter(Boolean).join('\n');
    try {
      await navigator.clipboard.writeText(summary);
      showToast('Daily summary copied');
    } catch {
      showToast('Could not copy summary');
    }
  }

  function exportCsv() {
    const rows = [['Date', 'Completion %', 'Mood', 'Energy', 'Stress', 'Daily Notes', 'Section', 'Routine Item', 'Input Type', 'Value']];
    Object.keys(state.days).sort().forEach((key) => {
      const date = fromDateKey(key);
      const day = state.days[key];
      const c = completionForDate(date);
      const scheduled = scheduledItemsForDate(date);
      if (!scheduled.length) {
        rows.push([key, c.percent, day.mood ?? '', day.energy ?? '', day.stress ?? '', day.notes || '', '', '', '', '']);
        return;
      }
      scheduled.forEach((item) => {
        const raw = day.entries?.[item.id];
        const value = item.type === 'checkbox' ? (raw === true ? 'Completed' : 'Not completed') : (raw ?? '');
        rows.push([key, c.percent, day.mood ?? '', day.energy ?? '', day.stress ?? '', day.notes || '', sectionLabels[item.section][0], item.name, typeLabels[item.type], value]);
      });
    });
    const csv = rows.map((row) => row.map(csvCell).join(',')).join('\r\n');
    downloadBlob(csv, `daily-routine-progress-${dateKey(startOfToday())}.csv`, 'text/csv;charset=utf-8');
    showToast('CSV exported');
  }

  function exportJson() {
    const payload = { version: 1, exportedAt: new Date().toISOString(), state };
    downloadBlob(JSON.stringify(payload, null, 2), `daily-routine-backup-${dateKey(startOfToday())}.json`, 'application/json');
    showToast('Backup downloaded');
  }

  async function importJson(event) {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (!file) return;
    try {
      const payload = JSON.parse(await file.text());
      const incoming = payload.state || payload;
      if (!incoming || !Array.isArray(incoming.items) || typeof incoming.days !== 'object') throw new Error('Invalid backup');
      if (!confirm('Restore this backup? It will replace the current app data on this device.')) return;
      state = {
        settings: { ...DEFAULT_STATE.settings, ...(incoming.settings || {}) },
        items: incoming.items,
        days: incoming.days
      };
      saveState();
      renderAll();
      showToast('Backup restored');
    } catch {
      alert('That file does not look like a valid Daily Routine backup.');
    }
  }

  function resetData() {
    if (!confirm('Reset all routines, history, and settings on this device? This cannot be undone unless you exported a backup.')) return;
    state = structuredClone(DEFAULT_STATE);
    saveState();
    selectedDate = startOfToday();
    renderAll();
    showToast('App reset');
  }

  function formatTime(value) {
    if (!value) return '—';
    const [hours, minutes] = value.split(':').map(Number);
    const d = new Date();
    d.setHours(hours, minutes, 0, 0);
    return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(d);
  }

  function frequencyLabel(value) {
    return value === 'weekdays' ? 'Weekdays' : value === 'weekends' ? 'Weekends' : 'Every day';
  }

  function csvCell(value) {
    const str = String(value ?? '');
    return /[",\n\r]/.test(str) ? `"${str.replaceAll('"', '""')}"` : str;
  }

  function downloadBlob(content, filename, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
  }

  function debounce(fn, delay) {
    let timer;
    return (...args) => {
      clearTimeout(timer);
      timer = setTimeout(() => fn(...args), delay);
    };
  }

  function showToast(message) {
    clearTimeout(toastTimer);
    els.toast.textContent = message;
    els.toast.classList.add('show');
    toastTimer = setTimeout(() => els.toast.classList.remove('show'), 1800);
  }
})();
