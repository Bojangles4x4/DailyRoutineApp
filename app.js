(() => {
  'use strict';

  const STORAGE_KEY = 'dailyRoutineApp.v1';
  const DEFAULT_SCALE = { min: 0, max: 10, step: 1, lowLabel: 'Low', highLabel: 'Great' };
  const DEFAULT_STATE = {
    settings: { wakeTime: '06:00', bedTime: '22:30', theme: 'calm', backgroundImage: '', badgeEnabled: true },
    items: [
      { id: 'morning-prayer', name: 'Prayer', kind: 'routine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-teeth', name: 'Brush teeth', kind: 'routine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-meds', name: 'Take morning medicine', kind: 'routine', section: 'morning', type: 'medication', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-reading', name: 'Bible reading', kind: 'routine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-sleep', name: 'Sleep quality', kind: 'checkin', section: 'morning', type: 'scale', frequency: 'daily', days: [], optional: true, scale: { min: 0, max: 10, step: 1, lowLabel: 'Poor', highLabel: 'Excellent' } },
      { id: 'morning-mood', name: 'Morning mood', kind: 'checkin', section: 'morning', type: 'scale', frequency: 'daily', days: [], optional: true, scale: { min: 0, max: 10, step: 1, lowLabel: 'Low', highLabel: 'Great' } },
      { id: 'day-water', name: 'Water', kind: 'routine', section: 'day', type: 'number', frequency: 'daily', days: [], optional: false, unit: 'cups', target: 8 },
      { id: 'day-movement', name: 'Movement / exercise', kind: 'routine', section: 'day', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'day-remember', name: 'Remember a blessing', kind: 'routine', section: 'day', type: 'memory', frequency: 'daily', days: [], optional: true, memoryCategory: 'blessing', unit: '', target: null },
      { id: 'day-focus', name: 'Focus / productivity', kind: 'checkin', section: 'day', type: 'scale', frequency: 'weekdays', days: [], optional: true, scale: { min: 0, max: 10, step: 1, lowLabel: 'Scattered', highLabel: 'Locked in' } },
      { id: 'day-stress', name: 'Stress', kind: 'checkin', section: 'day', type: 'scale', frequency: 'daily', days: [], optional: true, scale: { min: 0, max: 10, step: 1, lowLabel: 'Calm', highLabel: 'High' } },
      { id: 'evening-teeth', name: 'Brush teeth', kind: 'routine', section: 'evening', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-meds', name: 'Take evening medicine', kind: 'routine', section: 'evening', type: 'medication', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-prepare', name: 'Prepare for tomorrow', kind: 'routine', section: 'evening', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-overall', name: 'Overall day', kind: 'checkin', section: 'evening', type: 'scale', frequency: 'daily', days: [], optional: true, scale: { min: 0, max: 10, step: 1, lowLabel: 'Rough', highLabel: 'Excellent' } },
      { id: 'evening-reflection', name: 'What went well today?', kind: 'checkin', section: 'evening', type: 'longtext', frequency: 'daily', days: [], optional: true, placeholder: 'What are you thankful for or glad happened?' },
      { id: 'evening-tomorrow', name: 'What needs attention tomorrow?', kind: 'checkin', section: 'evening', type: 'text', frequency: 'daily', days: [], optional: true, placeholder: 'One thing to carry forward…' }
    ],
    days: {},
    memories: []
  };

  const sectionLabels = {
    morning: ['Morning', 'Start deliberately'],
    day: ['Throughout the day', 'Stay on track'],
    evening: ['Evening', 'Close the day well']
  };
  const typeLabels = { checkbox: 'Checkbox', medication: 'Medication + time', memory: 'Memory reflection', scale: 'Rating scale', number: 'Number', time: 'Time', text: 'Short comment', longtext: 'Journal entry' };

  let state = loadState();
  let selectedDate = startOfToday();
  let deferredInstallPrompt = null;
  let toastTimer = null;
  let analyticsRange = 7;

  const $ = id => document.getElementById(id);
  const els = {
    pageTitle: $('pageTitle'), todayEyebrow: $('todayEyebrow'), heroGreeting: $('heroGreeting'), heroDate: $('heroDate'), heroStatus: $('heroStatus'),
    wakeTimeDisplay: $('wakeTimeDisplay'), bedTimeDisplay: $('bedTimeDisplay'), progressRing: $('progressRing'), progressPercent: $('progressPercent'),
    selectedDateButton: $('selectedDateButton'), prevDay: $('prevDay'), nextDay: $('nextDay'), routineSections: $('routineSections'),
    statCompleted: $('statCompleted'), statOptional: $('statOptional'), statStreak: $('statStreak'), statMood: $('statMood'), copySummaryButton: $('copySummaryButton'),
    historyList: $('historyList'), rangeSelector: $('rangeSelector'), progressOverall: $('progressOverall'), progress80Days: $('progress80Days'), progressTrackedDays: $('progressTrackedDays'),
    progressRangeNote: $('progressRangeNote'), weekSummary: $('weekSummary'), weekOverall: $('weekOverall'), sectionBreakdown: $('sectionBreakdown'), strongHabits: $('strongHabits'), weakHabits: $('weakHabits'), trendList: $('trendList'), patternInsights: $('patternInsights'),
    wakeTimeInput: $('wakeTimeInput'), bedTimeInput: $('bedTimeInput'), themeInput: $('themeInput'), backgroundImageInput: $('backgroundImageInput'), clearBackgroundButton: $('clearBackgroundButton'),
    routineEditor: $('routineEditor'), checkinEditor: $('checkinEditor'), addItemButton: $('addItemButton'), addCheckinButton: $('addCheckinButton'),
    exportCsvButton: $('exportCsvButton'), exportJsonButton: $('exportJsonButton'), importJsonInput: $('importJsonInput'), resetDataButton: $('resetDataButton'),
    itemDialog: $('itemDialog'), itemForm: $('itemForm'), builderEyebrow: $('builderEyebrow'), dialogTitle: $('dialogTitle'), editingItemId: $('editingItemId'), editingItemKind: $('editingItemKind'),
    itemNameInput: $('itemNameInput'), itemSectionInput: $('itemSectionInput'), itemTypeInput: $('itemTypeInput'), itemFrequencyInput: $('itemFrequencyInput'), customDaysField: $('customDaysField'),
    numberGoalFields: $('numberGoalFields'), itemTargetInput: $('itemTargetInput'), itemUnitInput: $('itemUnitInput'), scaleFields: $('scaleFields'), scaleMinInput: $('scaleMinInput'), scaleMaxInput: $('scaleMaxInput'), scaleStepInput: $('scaleStepInput'), scaleLowLabelInput: $('scaleLowLabelInput'), scaleHighLabelInput: $('scaleHighLabelInput'),
    promptField: $('promptField'), itemPlaceholderInput: $('itemPlaceholderInput'), optionalField: $('optionalField'), itemOptionalInput: $('itemOptionalInput'),
    medicationFields: $('medicationFields'), memoryFields: $('memoryFields'), memoryCategoryInput: $('memoryCategoryInput'),
    actualWakeInput: $('actualWakeInput'), actualBedInput: $('actualBedInput'), wakeNowButton: $('wakeNowButton'), bedNowButton: $('bedNowButton'), badgeEnabledInput: $('badgeEnabledInput'),
    quickMemoryButton: $('quickMemoryButton'), memoryTodayPreview: $('memoryTodayPreview'), addMemoryButton: $('addMemoryButton'), memoryCount: $('memoryCount'), memoryArchive: $('memoryArchive'), exportMemoriesButton: $('exportMemoriesButton'),
    medicationInsights: $('medicationInsights'), memoryDialog: $('memoryDialog'), memoryForm: $('memoryForm'), closeMemoryDialogButton: $('closeMemoryDialogButton'), memoryTextInput: $('memoryTextInput'), memoryCategoryCaptureInput: $('memoryCategoryCaptureInput'), memoryDateTimeInput: $('memoryDateTimeInput'),
    deleteItemButton: $('deleteItemButton'), closeDialogButton: $('closeDialogButton'), installButton: $('installButton'), toast: $('toast')
  };

  init();

  function init() {
    ensureFirstUseDate();
    bindNavigation();
    bindTodayControls();
    bindProgressControls();
    bindSetupControls();
    bindInstall();
    applyPersonalization();
    renderAll();
    if ('serviceWorker' in navigator) window.addEventListener('load', () => navigator.serviceWorker.register('./service-worker.js').catch(() => {}));
  }

  function normalizeScale(scale) {
    const min = Number.isFinite(Number(scale?.min)) ? Number(scale.min) : DEFAULT_SCALE.min;
    const maxCandidate = Number.isFinite(Number(scale?.max)) ? Number(scale.max) : DEFAULT_SCALE.max;
    const max = maxCandidate > min ? maxCandidate : min + 10;
    const step = Number.isFinite(Number(scale?.step)) && Number(scale.step) > 0 ? Number(scale.step) : DEFAULT_SCALE.step;
    return {
      min,
      max,
      step,
      lowLabel: String(scale?.lowLabel ?? DEFAULT_SCALE.lowLabel),
      highLabel: String(scale?.highLabel ?? DEFAULT_SCALE.highLabel)
    };
  }

  function normalizeItem(item, index) {
    let type = item.type;
    if (['morning-meds', 'evening-meds'].includes(item.id) && type === 'checkbox') type = 'medication';
    const kind = item.kind || (['scale', 'text', 'longtext'].includes(type) ? 'checkin' : 'routine');
    return {
      ...item,
      type,
      kind,
      days: Array.isArray(item.days) ? item.days.map(Number) : [],
      optional: kind === 'checkin' && item.optional === undefined ? true : Boolean(item.optional),
      target: item.target === '' || item.target === undefined ? null : item.target,
      order: Number.isFinite(Number(item.order)) ? Number(item.order) : index,
      placeholder: item.placeholder || '',
      memoryCategory: item.memoryCategory || 'any',
      scale: type === 'scale' ? normalizeScale(item.scale) : undefined
    };
  }

  function loadState() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return structuredClone(DEFAULT_STATE);
      const parsed = JSON.parse(raw);
      return {
        settings: { ...DEFAULT_STATE.settings, ...(parsed.settings || {}) },
        items: Array.isArray(parsed.items) ? parsed.items.map(normalizeItem) : structuredClone(DEFAULT_STATE.items),
        days: parsed.days && typeof parsed.days === 'object' ? parsed.days : {},
        memories: Array.isArray(parsed.memories) ? parsed.memories : []
      };
    } catch {
      return structuredClone(DEFAULT_STATE);
    }
  }

  function saveState() { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); }
  function startOfToday() { const d = new Date(); d.setHours(12, 0, 0, 0); return d; }
  function dateKey(date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`; }
  function fromDateKey(key) { const [y, m, d] = key.split('-').map(Number); return new Date(y, m - 1, d, 12, 0, 0, 0); }
  function shiftDate(date, days) { const d = new Date(date); d.setDate(d.getDate() + days); return d; }
  function isSameDay(a, b) { return dateKey(a) === dateKey(b); }
  function ensureDay(key) { if (!state.days[key]) state.days[key] = { entries: {} }; if (!state.days[key].entries) state.days[key].entries = {}; return state.days[key]; }

  function ensureFirstUseDate() {
    let changed = false;
    if (!state.settings.firstUseDate) {
      const historical = Object.keys(state.days || {}).filter(key => /^\d{4}-\d{2}-\d{2}$/.test(key)).sort();
      state.settings.firstUseDate = historical[0] || dateKey(startOfToday());
      changed = true;
    }
    if (!Array.isArray(state.memories)) { state.memories = []; changed = true; }
    state.items.forEach((item, index) => {
      const normalized = normalizeItem(item, index);
      Object.assign(item, normalized);
      if (!item.createdDate) { item.createdDate = state.settings.firstUseDate; changed = true; }
    });
    if (!state.settings.v14Seeded) {
      if (!state.items.some(item => item.type === 'memory')) {
        const maxOrder = state.items.filter(item => item.section === 'day' && item.kind === 'routine').reduce((max, item) => Math.max(max, Number(item.order) || 0), -1);
        state.items.push({ id: 'day-remember', name: 'Remember a blessing', kind: 'routine', section: 'day', type: 'memory', frequency: 'daily', days: [], optional: true, memoryCategory: 'blessing', order: maxOrder + 1, createdDate: dateKey(startOfToday()) });
      }
      state.settings.v14Seeded = true;
      changed = true;
    }
    if (changed) saveState();
  }

  function scheduledItemsForDate(date) {
    const dow = date.getDay();
    return state.items.filter(item => {
      if (item.createdDate && dateKey(date) < item.createdDate) return false;
      if (item.frequency === 'weekdays') return dow >= 1 && dow <= 5;
      if (item.frequency === 'weekends') return dow === 0 || dow === 6;
      if (item.frequency === 'custom') return (item.days || []).includes(dow);
      return true;
    });
  }

  function entryIsLogged(item, value) {
    if (item.type === 'checkbox') return value === true;
    if (item.type === 'medication') return value === true || Boolean(value && typeof value === 'object' && value.taken);
    if (item.type === 'memory') return Boolean(value && typeof value === 'object' && value.reflected);
    if (item.type === 'scale') return Number.isFinite(Number(value));
    return value !== undefined && value !== null && String(value).trim() !== '';
  }

  function entryMeetsTarget(item, value) {
    if (!entryIsLogged(item, value)) return false;
    if (item.type === 'number' && Number.isFinite(Number(item.target))) return Number(value) >= Number(item.target);
    return true;
  }

  function completionForDate(date) {
    const items = scheduledItemsForDate(date);
    const required = items.filter(item => !item.optional);
    const optional = items.filter(item => item.optional);
    const day = state.days[dateKey(date)] || { entries: {} };
    const completed = required.filter(item => entryMeetsTarget(item, day.entries?.[item.id])).length;
    const optionalLogged = optional.filter(item => entryIsLogged(item, day.entries?.[item.id])).length;
    return { completed, total: required.length, optionalLogged, optionalTotal: optional.length, percent: required.length ? Math.round(completed / required.length * 100) : 100 };
  }

  function calculateStreak() {
    let streak = 0;
    let cursor = startOfToday();
    for (let i = 0; i < 3650; i += 1) {
      const c = completionForDate(cursor);
      if (c.total > 0 && c.percent >= 80) { streak += 1; cursor = shiftDate(cursor, -1); }
      else break;
    }
    return streak;
  }

  function bindNavigation() {
    document.querySelectorAll('.nav-button').forEach(button => button.addEventListener('click', () => switchView(button.dataset.view)));
  }

  function switchView(view) {
    document.querySelectorAll('.nav-button').forEach(button => button.classList.toggle('active', button.dataset.view === view));
    document.querySelectorAll('.view').forEach(node => node.classList.remove('active'));
    $(`${view}View`).classList.add('active');
    els.pageTitle.textContent = ({ today: 'Today', history: 'Progress', setup: 'Setup' })[view] || 'Daily Routine';
    if (view === 'history') renderHistory();
    if (view === 'setup') renderSetup();
    $('appMain').focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function bindTodayControls() {
    els.prevDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate, -1); renderToday(); });
    els.nextDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate, 1); renderToday(); });
    els.selectedDateButton.addEventListener('click', () => { selectedDate = startOfToday(); renderToday(); });
    els.copySummaryButton.addEventListener('click', copyDailySummary);
    els.actualWakeInput.addEventListener('change', () => saveActualTime('actualWakeTime', els.actualWakeInput.value));
    els.actualBedInput.addEventListener('change', () => saveActualTime('actualBedTime', els.actualBedInput.value));
    els.wakeNowButton.addEventListener('click', () => { const value = currentTimeValue(); els.actualWakeInput.value = value; saveActualTime('actualWakeTime', value); });
    els.bedNowButton.addEventListener('click', () => { const value = currentTimeValue(); els.actualBedInput.value = value; saveActualTime('actualBedTime', value); });
    els.quickMemoryButton.addEventListener('click', () => openMemoryDialog('blessing'));
  }

  function bindProgressControls() {
    els.rangeSelector.querySelectorAll('.range-button').forEach(button => button.addEventListener('click', () => {
      analyticsRange = Number(button.dataset.range) || 7;
      els.rangeSelector.querySelectorAll('.range-button').forEach(candidate => candidate.classList.toggle('active', candidate === button));
      renderHistory();
    }));
  }

  function bindSetupControls() {
    els.wakeTimeInput.addEventListener('change', () => { state.settings.wakeTime = els.wakeTimeInput.value || '06:00'; saveState(); renderToday(); });
    els.bedTimeInput.addEventListener('change', () => { state.settings.bedTime = els.bedTimeInput.value || '22:30'; saveState(); renderToday(); });
    els.badgeEnabledInput.addEventListener('change', () => { state.settings.badgeEnabled = els.badgeEnabledInput.checked; saveState(); updateAppBadge(); });
    els.themeInput.addEventListener('change', () => { state.settings.theme = els.themeInput.value; saveState(); applyPersonalization(); });
    els.backgroundImageInput.addEventListener('change', handleBackgroundImage);
    els.clearBackgroundButton.addEventListener('click', () => { state.settings.backgroundImage = ''; saveState(); applyPersonalization(); showToast('Background photo removed'); });
    els.addItemButton.addEventListener('click', () => openItemDialog(null, 'routine'));
    els.addCheckinButton.addEventListener('click', () => openItemDialog(null, 'checkin'));
    els.closeDialogButton.addEventListener('click', () => els.itemDialog.close());
    els.itemTypeInput.addEventListener('change', toggleBuilderFields);
    els.itemFrequencyInput.addEventListener('change', toggleBuilderFields);
    els.itemForm.addEventListener('submit', saveRoutineItem);
    els.deleteItemButton.addEventListener('click', deleteRoutineItem);
    els.addMemoryButton.addEventListener('click', () => openMemoryDialog('blessing'));
    els.closeMemoryDialogButton.addEventListener('click', () => els.memoryDialog.close());
    els.memoryForm.addEventListener('submit', saveMemory);
    els.exportMemoriesButton.addEventListener('click', exportMemoriesCsv);
    els.exportCsvButton.addEventListener('click', exportCsv);
    els.exportJsonButton.addEventListener('click', exportJson);
    els.importJsonInput.addEventListener('change', importJson);
    els.resetDataButton.addEventListener('click', resetData);
  }

  function bindInstall() {
    window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); deferredInstallPrompt = event; els.installButton.hidden = false; });
    els.installButton.addEventListener('click', async () => {
      if (!deferredInstallPrompt) return;
      deferredInstallPrompt.prompt();
      await deferredInstallPrompt.userChoice;
      deferredInstallPrompt = null;
      els.installButton.hidden = true;
    });
  }

  function renderAll() { renderToday(); renderHistory(); renderSetup(); }

  function renderToday() {
    const day = state.days[dateKey(selectedDate)] || { entries: {} };
    const today = startOfToday();
    els.heroGreeting.textContent = greetingForHour(new Date().getHours());
    els.heroDate.textContent = new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' }).format(selectedDate);
    els.wakeTimeDisplay.textContent = formatTime(state.settings.wakeTime);
    els.bedTimeDisplay.textContent = formatTime(state.settings.bedTime);
    els.actualWakeInput.value = day.actualWakeTime || '';
    els.actualBedInput.value = day.actualBedTime || '';
    els.selectedDateButton.textContent = isSameDay(selectedDate, today) ? 'Today' : new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric' }).format(selectedDate);
    els.nextDay.disabled = dateKey(selectedDate) >= dateKey(today);
    els.nextDay.style.opacity = els.nextDay.disabled ? '.35' : '1';
    renderMemoryPreview();
    renderRoutineSections(day);
    renderStats();
  }

  function renderRoutineSections(day) {
    els.routineSections.innerHTML = '';
    const scheduled = scheduledItemsForDate(selectedDate);
    ['morning', 'day', 'evening'].forEach(section => {
      const items = scheduled.filter(item => item.section === section).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
      const required = items.filter(item => !item.optional);
      const logged = required.filter(item => entryMeetsTarget(item, day.entries?.[item.id])).length;
      const routineItems = items.filter(item => item.kind !== 'checkin');
      const checkinItems = items.filter(item => item.kind === 'checkin');
      const [title, subtitle] = sectionLabels[section];
      const wrapper = document.createElement('section');
      wrapper.className = 'routine-section';
      wrapper.innerHTML = `<div class="card"><div class="section-heading"><div><p class="eyebrow">${escapeHtml(subtitle)}</p><h2>${escapeHtml(title)}</h2></div><span class="section-progress">${logged}/${required.length}</span></div><div class="task-list routine-task-list"></div><div class="checkin-slot"></div></div>`;
      const routineList = wrapper.querySelector('.routine-task-list');
      const checkinSlot = wrapper.querySelector('.checkin-slot');
      if (!routineItems.length) routineList.innerHTML = '<div class="empty-state compact-empty">No routine items scheduled.</div>';
      else routineItems.forEach(item => routineList.appendChild(buildTaskRow(item, day.entries?.[item.id])));
      if (checkinItems.length) {
        const panel = document.createElement('div');
        panel.className = 'checkin-panel';
        panel.innerHTML = `<div class="checkin-heading"><span>${escapeHtml(title)} check-in</span><small>${checkinItems.filter(item => entryIsLogged(item, day.entries?.[item.id])).length}/${checkinItems.length} logged</small></div><div class="checkin-list"></div>`;
        const list = panel.querySelector('.checkin-list');
        checkinItems.forEach(item => list.appendChild(buildCheckinRow(item, day.entries?.[item.id])));
        checkinSlot.appendChild(panel);
      }
      els.routineSections.appendChild(wrapper);
    });
  }

  function metaForItem(item) {
    const bits = [item.optional ? 'Optional' : 'Required', frequencyLabel(item)];
    if (item.type === 'number' && Number.isFinite(Number(item.target))) bits.push(`Target ${item.target}${item.unit ? ` ${item.unit}` : ''}`);
    return bits.join(' · ');
  }

  function buildTaskRow(item, value) {
    const row = document.createElement('div');
    row.className = `task-row${entryMeetsTarget(item, value) ? ' done' : ''}`;
    if (item.type === 'medication') return buildMedicationRow(row, item, value);
    if (item.type === 'memory') return buildMemoryRow(row, item, value);
    if (item.type === 'checkbox') {
      row.innerHTML = `<label class="task-main"><input class="check-control" type="checkbox" ${value === true ? 'checked' : ''}/><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}</span></span></label>`;
      row.querySelector('input').addEventListener('change', event => saveEntry(item, event.target.checked));
      return row;
    }
    row.innerHTML = `<div class="task-main"><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}</span></span></div><div class="task-extra"></div>`;
    buildEntryControl(row.querySelector('.task-extra'), item, value, false);
    return row;
  }

  function buildCheckinRow(item, value) {
    const row = document.createElement('div');
    row.className = `checkin-row${entryIsLogged(item, value) ? ' logged' : ''}`;
    row.innerHTML = `<div class="checkin-question"><strong>${escapeHtml(item.name)}</strong>${item.optional ? '' : '<span class="required-badge">Required</span>'}</div><div class="checkin-control"></div>`;
    buildEntryControl(row.querySelector('.checkin-control'), item, value, true);
    return row;
  }

  function buildEntryControl(container, item, value, compact) {
    if (item.type === 'scale') {
      buildScaleControl(container, item, value, compact);
    } else if (item.type === 'text' || item.type === 'longtext') {
      const rows = item.type === 'longtext' ? 4 : 2;
      const placeholder = item.placeholder || (item.type === 'longtext' ? 'Write a reflection…' : 'Add a comment…');
      container.innerHTML = `<textarea class="task-input" rows="${rows}" placeholder="${escapeHtml(placeholder)}">${escapeHtml(value || '')}</textarea>`;
      container.querySelector('textarea').addEventListener('input', debounce(event => saveEntry(item, event.target.value, false), 250));
    } else if (item.type === 'number') {
      container.innerHTML = `<div class="number-entry"><input class="task-input inline-number" type="number" step="any" inputmode="decimal" value="${escapeHtml(value ?? '')}" placeholder="0"/><span>${escapeHtml(item.unit || '')}</span>${Number.isFinite(Number(item.target)) ? `<small>/ ${escapeHtml(item.target)} ${escapeHtml(item.unit || '')}</small>` : ''}</div>`;
      container.querySelector('input').addEventListener('change', event => saveEntry(item, event.target.value));
    } else if (item.type === 'time') {
      container.innerHTML = `<input class="task-input" type="time" value="${escapeHtml(value || '')}"/>`;
      container.querySelector('input').addEventListener('change', event => saveEntry(item, event.target.value));
    } else if (item.type === 'checkbox') {
      container.innerHTML = `<label class="inline-check"><input class="check-control" type="checkbox" ${value === true ? 'checked' : ''}/><span>${value === true ? 'Done' : 'Mark complete'}</span></label>`;
      container.querySelector('input').addEventListener('change', event => saveEntry(item, event.target.checked));
    }
  }

  function buildScaleControl(container, item, value, compact) {
    const scale = normalizeScale(item.scale);
    const hasValue = Number.isFinite(Number(value));
    const midpoint = scale.min + (scale.max - scale.min) / 2;
    const current = hasValue ? clampScale(Number(value), scale) : snapScale(midpoint, scale);
    container.innerHTML = `<div class="rating-control${compact ? ' compact' : ''}">
      <div class="rating-top"><span>${escapeHtml(scale.lowLabel)}</span><div class="rating-edit"><button type="button" class="rating-step" data-step="-1" aria-label="Decrease rating">−</button><input class="rating-number" type="number" min="${scale.min}" max="${scale.max}" step="${scale.step}" value="${hasValue ? current : ''}" placeholder="—" inputmode="decimal" aria-label="${escapeHtml(item.name)} rating"/><button type="button" class="rating-step" data-step="1" aria-label="Increase rating">+</button></div><span>${escapeHtml(scale.highLabel)}</span></div>
      <input class="rating-range" type="range" min="${scale.min}" max="${scale.max}" step="${scale.step}" value="${current}" aria-label="${escapeHtml(item.name)} slider"/>
      <div class="rating-scale-ends"><span>${formatNumber(scale.min)}</span><span>${formatNumber(scale.max)}</span></div>
    </div>`;
    const range = container.querySelector('.rating-range');
    const number = container.querySelector('.rating-number');
    const commit = raw => {
      const next = clampScale(Number(raw), scale);
      range.value = next;
      number.value = next;
      saveEntry(item, next, false);
      container.closest('.checkin-row')?.classList.add('logged');
    };
    range.addEventListener('input', () => { number.value = range.value; saveEntry(item, Number(range.value), false); container.closest('.checkin-row')?.classList.add('logged'); });
    number.addEventListener('change', () => {
      if (number.value === '') { const day = ensureDay(dateKey(selectedDate)); delete day.entries[item.id]; saveState(); renderStats(); return; }
      commit(number.value);
    });
    container.querySelectorAll('.rating-step').forEach(button => button.addEventListener('click', () => {
      const base = number.value === '' ? current : Number(number.value);
      commit(base + Number(button.dataset.step) * scale.step);
    }));
  }

  function clampScale(value, scale) {
    if (!Number.isFinite(value)) value = scale.min;
    return Math.min(scale.max, Math.max(scale.min, snapScale(value, scale)));
  }

  function snapScale(value, scale) {
    const snapped = Math.round((value - scale.min) / scale.step) * scale.step + scale.min;
    return Number(snapped.toFixed(6));
  }

  function saveEntry(item, value, rerender = true) {
    const day = ensureDay(dateKey(selectedDate));
    day.entries[item.id] = value;
    saveState();
    if (rerender) renderToday();
    else renderStats();
  }

  function renderStats() {
    const c = completionForDate(selectedDate);
    const day = state.days[dateKey(selectedDate)] || {};
    els.progressPercent.textContent = `${c.percent}%`;
    els.progressRing.style.setProperty('--p', c.percent);
    els.progressRing.setAttribute('aria-label', `${c.percent} percent complete`);
    els.statCompleted.textContent = `${c.completed}/${c.total}`;
    els.statOptional.textContent = `${c.optionalLogged}/${c.optionalTotal}`;
    els.statStreak.textContent = calculateStreak();
    const latestMood = getLatestMood(day); els.statMood.textContent = latestMood === null ? '—' : formatNumber(latestMood);
    els.heroStatus.textContent = c.percent === 100 ? 'Day complete. Nicely done.' : c.percent >= 80 ? 'Strong day. Keep closing it out.' : c.percent >= 40 ? 'Good progress. Keep moving.' : 'Start deliberately.';
    updateAppBadge();
  }

  function getLatestMood(day) {
    const moodItems = state.items.filter(item => item.type === 'scale' && /mood|overall day/i.test(item.name)).sort((a, b) => (({ evening: 3, day: 2, morning: 1 }[b.section] ?? 0) - ({ evening: 3, day: 2, morning: 1 }[a.section] ?? 0)));
    for (const item of moodItems) {
      const value = day.entries?.[item.id];
      if (Number.isFinite(Number(value))) return Number(value);
    }
    if (Number.isFinite(Number(day.mood))) return Number(day.mood);
    return null;
  }

  function renderHistory() {
    renderProgressOverview();
    renderWeekSummary();
    renderSectionBreakdown();
    renderHabitPerformance();
    renderTrendList();
    renderMedicationTiming();
    renderPatternInsights();
    renderRecentHistory();
  }

  function activeRangeDates(days = analyticsRange, endDate = startOfToday()) {
    const firstUse = fromDateKey(state.settings.firstUseDate || dateKey(endDate));
    const start = shiftDate(endDate, -(days - 1));
    const effectiveStart = dateKey(start) < dateKey(firstUse) ? firstUse : start;
    const dates = [];
    for (let cursor = new Date(effectiveStart); dateKey(cursor) <= dateKey(endDate); cursor = shiftDate(cursor, 1)) dates.push(cursor);
    return dates;
  }

  function previousRangeDates(days = analyticsRange) { return activeRangeDates(days, shiftDate(startOfToday(), -days)); }

  function aggregateCompletion(dates) {
    let completed = 0, total = 0, days80 = 0, scoredDays = 0;
    dates.forEach(date => {
      const c = completionForDate(date);
      if (!c.total) return;
      completed += c.completed; total += c.total; scoredDays += 1;
      if (c.percent >= 80) days80 += 1;
    });
    return { completed, total, days80, scoredDays, percent: total ? Math.round(completed / total * 100) : null };
  }

  function renderProgressOverview() {
    const dates = activeRangeDates();
    const aggregate = aggregateCompletion(dates);
    els.progressOverall.textContent = aggregate.percent === null ? '—' : `${aggregate.percent}%`;
    els.progress80Days.textContent = `${aggregate.days80}/${aggregate.scoredDays || 0}`;
    els.progressTrackedDays.textContent = dates.length;
    const first = dates[0], last = dates[dates.length - 1];
    els.progressRangeNote.textContent = first && last ? `${formatShortDate(first)} – ${formatShortDate(last)} · Required items drive completion scores.` : 'Log a day to start building your progress history.';
  }

  function startOfCurrentWeek() {
    const today = startOfToday(), dow = today.getDay();
    return shiftDate(today, dow === 0 ? -6 : 1 - dow);
  }

  function renderWeekSummary() {
    const today = startOfToday(), weekStart = startOfCurrentWeek(), firstUse = fromDateKey(state.settings.firstUseDate || dateKey(today));
    const days = Array.from({ length: 7 }, (_, index) => shiftDate(weekStart, index));
    const eligible = days.filter(date => dateKey(date) <= dateKey(today) && dateKey(date) >= dateKey(firstUse));
    const aggregate = aggregateCompletion(eligible);
    els.weekOverall.textContent = aggregate.percent === null ? '—' : `${aggregate.percent}% week`;
    els.weekSummary.innerHTML = days.map(date => {
      const future = dateKey(date) > dateKey(today), beforeUse = dateKey(date) < dateKey(firstUse), unavailable = future || beforeUse;
      const c = unavailable ? null : completionForDate(date), percent = c?.percent ?? 0;
      return `<button type="button" class="week-day${isSameDay(date, today) ? ' today' : ''}${unavailable ? ' unavailable' : ''}" data-date="${dateKey(date)}" ${unavailable ? 'disabled' : ''}><span class="week-label">${escapeHtml(new Intl.DateTimeFormat(undefined, { weekday: 'narrow' }).format(date))}</span><div class="week-track"><span style="height:${unavailable ? 0 : percent}%"></span></div><strong>${unavailable ? '—' : `${percent}%`}</strong><small>${date.getDate()}</small></button>`;
    }).join('');
    els.weekSummary.querySelectorAll('.week-day:not(:disabled)').forEach(button => button.addEventListener('click', () => { selectedDate = fromDateKey(button.dataset.date); switchView('today'); renderToday(); }));
  }

  function renderSectionBreakdown() {
    const dates = activeRangeDates();
    els.sectionBreakdown.innerHTML = ['morning', 'day', 'evening'].map(section => {
      let completed = 0, total = 0;
      dates.forEach(date => {
        const day = state.days[dateKey(date)] || { entries: {} };
        scheduledItemsForDate(date).filter(item => item.section === section && !item.optional).forEach(item => { total += 1; if (entryMeetsTarget(item, day.entries?.[item.id])) completed += 1; });
      });
      const percent = total ? Math.round(completed / total * 100) : null;
      return progressRowMarkup(sectionLabels[section][0], percent, total ? `${completed}/${total} completed` : 'No required items');
    }).join('');
  }

  function progressRowMarkup(label, percent, detail = '') {
    return `<div class="breakdown-row"><div class="breakdown-copy"><strong>${escapeHtml(label)}</strong><span>${escapeHtml(detail)}</span></div><div class="breakdown-score">${percent === null ? '—' : `${percent}%`}</div><div class="breakdown-bar"><span style="width:${percent ?? 0}%"></span></div></div>`;
  }

  function habitMetrics(dates) {
    return state.items.filter(item => item.kind !== 'checkin' && ['checkbox', 'number', 'time'].includes(item.type)).map(item => {
      let opportunities = 0, successes = 0;
      dates.forEach(date => {
        if (!scheduledItemsForDate(date).some(candidate => candidate.id === item.id)) return;
        opportunities += 1;
        const day = state.days[dateKey(date)] || { entries: {} };
        if (entryMeetsTarget(item, day.entries?.[item.id])) successes += 1;
      });
      return { item, opportunities, successes, percent: opportunities ? Math.round(successes / opportunities * 100) : null };
    }).filter(metric => metric.opportunities > 0);
  }

  function renderHabitPerformance() {
    const metrics = habitMetrics(activeRangeDates());
    if (!metrics.length) {
      const empty = '<div class="analytics-empty">Add checkbox, number, or time habits to see consistency here.</div>';
      els.strongHabits.innerHTML = empty; els.weakHabits.innerHTML = empty; return;
    }
    const strongest = [...metrics].sort((a, b) => b.percent - a.percent || b.successes - a.successes).slice(0, 3);
    const weakest = [...metrics].sort((a, b) => a.percent - b.percent || a.successes - b.successes).slice(0, 3);
    els.strongHabits.innerHTML = strongest.map(habitMetricMarkup).join('');
    els.weakHabits.innerHTML = weakest.map(habitMetricMarkup).join('');
  }

  function habitMetricMarkup(metric) { return `<div class="habit-row"><div><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.successes}/${metric.opportunities} days</span></div><b>${metric.percent}%</b></div>`; }

  function scaleValueForDay(item, day) {
    const entry = day.entries?.[item.id];
    if (Number.isFinite(Number(entry))) return Number(entry);
    const name = item.name.toLowerCase();
    if (name.includes('mood') && Number.isFinite(Number(day.mood))) return Number(day.mood);
    if (name.includes('energy') && Number.isFinite(Number(day.energy))) return Number(day.energy);
    if (name.includes('stress') && Number.isFinite(Number(day.stress))) return Number(day.stress);
    return null;
  }

  function scaleSeries(item, dates) {
    return dates.map(date => scheduledItemsForDate(date).some(candidate => candidate.id === item.id) ? scaleValueForDay(item, state.days[dateKey(date)] || { entries: {} }) : null).filter(value => value !== null);
  }

  function average(values) { return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null; }

  function renderTrendList() {
    const currentDates = activeRangeDates(), priorDates = previousRangeDates();
    const metrics = state.items.filter(item => item.type === 'scale').map(item => {
      const current = scaleSeries(item, currentDates), prior = scaleSeries(item, priorDates);
      return { item, current, prior, currentAvg: average(current), priorAvg: average(prior) };
    }).filter(metric => metric.current.length > 0);
    if (!metrics.length) { els.trendList.innerHTML = '<div class="analytics-empty">Your rating check-ins will appear here after you log them.</div>'; return; }
    els.trendList.innerHTML = metrics.map(metric => {
      const delta = metric.priorAvg === null ? null : metric.currentAvg - metric.priorAvg;
      const direction = delta === null ? '' : delta > .15 ? '↑' : delta < -.15 ? '↓' : '→';
      const deltaText = delta === null ? `No prior ${analyticsRange}-day comparison` : `${direction} ${Math.abs(delta).toFixed(1)} vs prior ${analyticsRange}D`;
      const scale = normalizeScale(metric.item.scale);
      return `<div class="trend-row"><div class="trend-copy"><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.current.length} logged · ${escapeHtml(deltaText)}</span></div><div class="trend-chart">${sparkline(metric.current, scale)}</div><div class="trend-average"><strong>${metric.currentAvg.toFixed(1)}</strong><span>${formatNumber(scale.min)}–${formatNumber(scale.max)}</span></div></div>`;
    }).join('');
  }

  function sparkline(values, scale) {
    if (!values.length) return '';
    const width = 104, height = 34, pad = 3, range = Math.max(.0001, scale.max - scale.min);
    const yFor = value => height - pad - ((value - scale.min) / range) * (height - pad * 2);
    if (values.length === 1) return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="One value: ${values[0]}"><circle cx="${width / 2}" cy="${yFor(values[0]).toFixed(1)}" r="3"></circle></svg>`;
    const points = values.map((value, index) => `${(pad + index / (values.length - 1) * (width - pad * 2)).toFixed(1)},${yFor(value).toFixed(1)}`).join(' ');
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Rating trend"><polyline points="${points}" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"></polyline></svg>`;
  }

  function renderPatternInsights() {
    const dates = activeRangeDates();
    const habits = state.items.filter(item => item.kind !== 'checkin' && ['checkbox', 'number', 'time'].includes(item.type));
    const scales = state.items.filter(item => item.kind === 'checkin' && item.type === 'scale');
    const candidates = [];
    scales.forEach(scaleItem => {
      habits.forEach(habit => {
        const withHabit = [], withoutHabit = [];
        dates.forEach(date => {
          const scheduled = scheduledItemsForDate(date);
          if (!scheduled.some(item => item.id === scaleItem.id) || !scheduled.some(item => item.id === habit.id)) return;
          const day = state.days[dateKey(date)] || { entries: {} };
          const rating = scaleValueForDay(scaleItem, day);
          if (rating === null) return;
          if (entryMeetsTarget(habit, day.entries?.[habit.id])) withHabit.push(rating); else withoutHabit.push(rating);
        });
        if (withHabit.length < 2 || withoutHabit.length < 2) return;
        const withAvg = average(withHabit), withoutAvg = average(withoutHabit), delta = withAvg - withoutAvg;
        if (Math.abs(delta) < .5) return;
        candidates.push({ habit, scaleItem, withAvg, withoutAvg, delta, count: withHabit.length + withoutHabit.length });
      });
    });
    candidates.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta) || b.count - a.count);
    if (!candidates.length) {
      els.patternInsights.innerHTML = '<div class="analytics-empty">Keep logging routines and check-ins. Once there are enough matched days, simple personal patterns will appear here.</div>';
      return;
    }
    els.patternInsights.innerHTML = candidates.slice(0, 4).map(insight => `<div class="insight-row"><div class="insight-icon">↔</div><p>On days you completed <strong>${escapeHtml(insight.habit.name)}</strong>, <strong>${escapeHtml(insight.scaleItem.name)}</strong> averaged <b>${insight.withAvg.toFixed(1)}</b> versus <b>${insight.withoutAvg.toFixed(1)}</b> on other logged days. <span>${insight.count} matched days</span></p></div>`).join('');
  }

  function renderRecentHistory() {
    els.historyList.innerHTML = '';
    const today = startOfToday(), firstUse = fromDateKey(state.settings.firstUseDate || dateKey(today));
    const maxDays = Math.min(30, Math.max(1, Math.floor((today - firstUse) / 86400000) + 1));
    for (let i = 0; i < maxDays; i += 1) {
      const date = shiftDate(today, -i); if (dateKey(date) < dateKey(firstUse)) break;
      const day = state.days[dateKey(date)] || {}, c = completionForDate(date), row = document.createElement('button');
      row.type = 'button'; row.className = 'history-row';
      row.innerHTML = `<span class="history-date"><strong>${date.getDate()}</strong><span>${new Intl.DateTimeFormat(undefined, { month: 'short' }).format(date)}</span></span><span class="history-copy"><strong>${new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(date)}${i === 0 ? ' · Today' : ''}</strong><span>${c.completed} of ${c.total} required</span><span class="history-bar"><span style="width:${c.percent}%"></span></span></span><span class="history-mood">Mood<br><b>${getLatestMood(day) ?? '—'}</b></span>`;
      row.addEventListener('click', () => { selectedDate = date; switchView('today'); renderToday(); });
      els.historyList.appendChild(row);
    }
  }

  function formatShortDate(date) { return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date); }

  function renderSetup() {
    els.wakeTimeInput.value = state.settings.wakeTime;
    els.bedTimeInput.value = state.settings.bedTime;
    els.badgeEnabledInput.checked = state.settings.badgeEnabled !== false;
    els.themeInput.value = state.settings.theme || 'calm';
    els.routineEditor.innerHTML = '';
    els.checkinEditor.innerHTML = '';
    renderEditorGroup('routine', els.routineEditor);
    renderEditorGroup('checkin', els.checkinEditor);
    renderMemoryArchive();
  }

  function renderEditorGroup(kind, target) {
    let count = 0;
    ['morning', 'day', 'evening'].forEach(section => {
      const sectionItems = state.items.filter(item => item.kind === kind && item.section === section).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
      sectionItems.forEach((item, index) => {
        count += 1;
        const row = document.createElement('div'); row.className = 'editor-row';
        const detail = item.type === 'scale' ? `${scaleLabel(item)} · ${frequencyLabel(item)}` : `${typeLabels[item.type] || item.type} · ${frequencyLabel(item)}`;
        row.innerHTML = `<div class="editor-copy"><strong>${escapeHtml(item.name)}</strong><span>${sectionLabels[section][0]} · ${escapeHtml(detail)}${item.optional ? ' · Optional' : ''}</span></div><div class="editor-actions"><button class="move-button" type="button" aria-label="Move up" ${index === 0 ? 'disabled' : ''}>↑</button><button class="move-button" type="button" aria-label="Move down" ${index === sectionItems.length - 1 ? 'disabled' : ''}>↓</button><button class="edit-button" type="button">Edit</button></div>`;
        const buttons = row.querySelectorAll('button');
        buttons[0].addEventListener('click', () => moveItem(item, -1));
        buttons[1].addEventListener('click', () => moveItem(item, 1));
        buttons[2].addEventListener('click', () => openItemDialog(item, kind));
        target.appendChild(row);
      });
    });
    if (!count) target.innerHTML = `<div class="analytics-empty">No ${kind === 'checkin' ? 'check-ins' : 'routine items'} yet.</div>`;
  }

  function moveItem(item, direction) {
    const sectionItems = state.items.filter(candidate => candidate.kind === item.kind && candidate.section === item.section).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
    const index = sectionItems.findIndex(candidate => candidate.id === item.id), swap = sectionItems[index + direction];
    if (!swap) return;
    const a = state.items.find(candidate => candidate.id === item.id), b = state.items.find(candidate => candidate.id === swap.id);
    const ao = a.order ?? index, bo = b.order ?? index + direction; a.order = bo; b.order = ao;
    saveState(); renderAll();
  }

  function openItemDialog(item = null, kind = 'routine') {
    const resolvedKind = item?.kind || kind;
    els.editingItemId.value = item?.id || '';
    els.editingItemKind.value = resolvedKind;
    els.builderEyebrow.textContent = resolvedKind === 'checkin' ? 'Check-in builder' : 'Routine builder';
    els.dialogTitle.textContent = item ? `Edit ${resolvedKind === 'checkin' ? 'check-in' : 'item'}` : `Add ${resolvedKind === 'checkin' ? 'check-in' : 'item'}`;
    els.itemNameInput.value = item?.name || '';
    els.itemNameInput.placeholder = resolvedKind === 'checkin' ? 'Example: How was your sleep?' : 'Example: Prayer';
    els.itemSectionInput.value = item?.section || 'morning';
    const medicationOption = els.itemTypeInput.querySelector('option[value="medication"]');
    const memoryOption = els.itemTypeInput.querySelector('option[value="memory"]');
    medicationOption.hidden = medicationOption.disabled = resolvedKind === 'checkin';
    memoryOption.hidden = memoryOption.disabled = resolvedKind === 'checkin';
    const defaultType = resolvedKind === 'checkin' ? 'scale' : 'checkbox';
    els.itemTypeInput.value = item?.type || defaultType;
    if (!els.itemTypeInput.value) els.itemTypeInput.value = defaultType;
    els.itemFrequencyInput.value = item?.frequency || 'daily';
    els.itemTargetInput.value = item?.target ?? '';
    els.itemUnitInput.value = item?.unit || '';
    els.itemPlaceholderInput.value = item?.placeholder || '';
    els.memoryCategoryInput.value = item?.memoryCategory || 'any';
    els.itemOptionalInput.checked = item ? Boolean(item.optional) : resolvedKind === 'checkin';
    const scale = normalizeScale(item?.scale);
    els.scaleMinInput.value = scale.min; els.scaleMaxInput.value = scale.max; els.scaleStepInput.value = scale.step; els.scaleLowLabelInput.value = scale.lowLabel; els.scaleHighLabelInput.value = scale.highLabel;
    els.deleteItemButton.hidden = !item;
    els.customDaysField.querySelectorAll('input').forEach(cb => cb.checked = (item?.days || []).includes(Number(cb.value)));
    toggleBuilderFields();
    els.itemDialog.showModal();
    setTimeout(() => els.itemNameInput.focus(), 50);
  }

  function toggleBuilderFields() {
    const type = els.itemTypeInput.value;
    els.numberGoalFields.hidden = type !== 'number';
    els.scaleFields.hidden = type !== 'scale';
    els.medicationFields.hidden = type !== 'medication';
    els.memoryFields.hidden = type !== 'memory';
    els.promptField.hidden = !['text', 'longtext'].includes(type);
    els.customDaysField.hidden = els.itemFrequencyInput.value !== 'custom';
  }

  function saveRoutineItem(event) {
    event.preventDefault();
    const name = els.itemNameInput.value.trim();
    if (!name) return;
    const days = [...els.customDaysField.querySelectorAll('input:checked')].map(cb => Number(cb.value));
    if (els.itemFrequencyInput.value === 'custom' && !days.length) { showToast('Choose at least one day'); return; }
    const kind = els.editingItemKind.value || 'routine';
    const type = els.itemTypeInput.value;
    let scale;
    if (type === 'scale') {
      scale = normalizeScale({ min: els.scaleMinInput.value, max: els.scaleMaxInput.value, step: els.scaleStepInput.value, lowLabel: els.scaleLowLabelInput.value.trim() || 'Low', highLabel: els.scaleHighLabelInput.value.trim() || 'High' });
      if (scale.max <= scale.min) { showToast('Scale maximum must be above minimum'); return; }
    }
    const payload = {
      name, kind, section: els.itemSectionInput.value, type, frequency: els.itemFrequencyInput.value, days, optional: els.itemOptionalInput.checked,
      unit: type === 'number' ? els.itemUnitInput.value.trim() : '',
      target: type === 'number' && els.itemTargetInput.value !== '' ? Number(els.itemTargetInput.value) : null,
      placeholder: ['text', 'longtext'].includes(type) ? els.itemPlaceholderInput.value.trim() : '',
      memoryCategory: type === 'memory' ? els.memoryCategoryInput.value : 'any',
      scale: type === 'scale' ? scale : undefined
    };
    const id = els.editingItemId.value;
    if (id) {
      const index = state.items.findIndex(item => item.id === id);
      if (index >= 0) state.items[index] = { ...state.items[index], ...payload };
    } else {
      const same = state.items.filter(item => item.kind === kind && item.section === payload.section);
      const maxOrder = same.reduce((max, item) => Math.max(max, Number(item.order) || 0), -1);
      state.items.push({ id: `item-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, order: maxOrder + 1, createdDate: dateKey(startOfToday()), ...payload });
    }
    saveState(); els.itemDialog.close(); renderAll(); showToast(id ? `${kind === 'checkin' ? 'Check-in' : 'Routine item'} updated` : `${kind === 'checkin' ? 'Check-in' : 'Routine item'} added`);
  }

  function deleteRoutineItem() {
    const id = els.editingItemId.value;
    if (!id) return;
    const item = state.items.find(candidate => candidate.id === id);
    if (!item || !confirm(`Delete “${item.name}”?`)) return;
    state.items = state.items.filter(candidate => candidate.id !== id);
    saveState(); els.itemDialog.close(); renderAll(); showToast(item.kind === 'checkin' ? 'Check-in deleted' : 'Routine item deleted');
  }

  async function handleBackgroundImage(event) {
    const file = event.target.files?.[0]; event.target.value = ''; if (!file) return;
    if (file.size > 12 * 1024 * 1024) { alert('Please choose an image under 12 MB.'); return; }
    try { state.settings.backgroundImage = await compressImage(file); saveState(); applyPersonalization(); showToast('Background updated'); }
    catch { alert('Could not use that image. Try a JPG or PNG.'); }
  }

  function compressImage(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader(); reader.onerror = reject; reader.onload = () => {
        const img = new Image(); img.onerror = reject; img.onload = () => {
          const max = 1400, scale = Math.min(1, max / Math.max(img.width, img.height)), canvas = document.createElement('canvas');
          canvas.width = Math.round(img.width * scale); canvas.height = Math.round(img.height * scale);
          canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
          resolve(canvas.toDataURL('image/jpeg', .72));
        }; img.src = reader.result;
      }; reader.readAsDataURL(file);
    });
  }

  function applyPersonalization() {
    document.body.dataset.theme = state.settings.theme || 'calm';
    document.body.style.setProperty('--custom-bg', state.settings.backgroundImage ? `url("${state.settings.backgroundImage}")` : 'none');
    document.body.classList.toggle('has-custom-bg', Boolean(state.settings.backgroundImage));
  }

  async function copyDailySummary() {
    const day = state.days[dateKey(selectedDate)] || {}, c = completionForDate(selectedDate);
    const lines = [`Daily Routine — ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: 'numeric' }).format(selectedDate)}`, `Required: ${c.completed}/${c.total} (${c.percent}%)`, `Optional logged: ${c.optionalLogged}/${c.optionalTotal}`];
    scheduledItemsForDate(selectedDate).forEach(item => { const value = day.entries?.[item.id]; if (entryIsLogged(item, value)) lines.push(`${item.name}: ${formatEntry(item, value)}`); });
    try { await navigator.clipboard.writeText(lines.join('\n')); showToast('Daily summary copied'); } catch { showToast('Could not copy summary'); }
  }

  function formatEntry(item, value) {
    if (item.type === 'checkbox') return value ? 'Completed' : 'Not completed';
    if (item.type === 'medication') {
      if (value === true) return 'Taken (time not logged)';
      return value?.taken ? `Taken${value.time ? ` at ${formatTime(value.time)}` : ''}` : 'Not taken';
    }
    if (item.type === 'memory') {
      const memory = state.memories.find(candidate => candidate.id === value?.memoryId);
      return value?.reflected ? `Reflected${memory ? ` — ${memory.text}` : ''}` : 'Not reflected';
    }
    if (item.type === 'scale') { const scale = normalizeScale(item.scale); return `${value} (${formatNumber(scale.min)}–${formatNumber(scale.max)})`; }
    return `${value}${item.unit ? ` ${item.unit}` : ''}`;
  }

  function exportCsv() {
    const rows = [['Date', 'Actual Wake', 'Actual Bed', 'Completion %', 'Required Completed', 'Required Total', 'Optional Logged', 'Section', 'Kind', 'Item', 'Input Type', 'Optional', 'Target', 'Unit', 'Scale Min', 'Scale Max', 'Value']];
    Object.keys(state.days).sort().forEach(key => {
      const date = fromDateKey(key), day = state.days[key], c = completionForDate(date), scheduled = scheduledItemsForDate(date);
      if (!scheduled.length) rows.push([key, day.actualWakeTime || '', day.actualBedTime || '', c.percent, c.completed, c.total, c.optionalLogged, '', '', '', '', '', '', '', '', '', '']);
      else scheduled.forEach(item => {
        const scale = item.type === 'scale' ? normalizeScale(item.scale) : {};
        rows.push([key, day.actualWakeTime || '', day.actualBedTime || '', c.percent, c.completed, c.total, c.optionalLogged, sectionLabels[item.section][0], item.kind, item.name, typeLabels[item.type], item.optional ? 'Yes' : 'No', item.target ?? '', item.unit || '', scale.min ?? '', scale.max ?? '', formatEntry(item, day.entries?.[item.id] ?? '')]);
      });
    });
    downloadBlob(rows.map(row => row.map(csvCell).join(',')).join('\r\n'), `daily-routine-progress-${dateKey(startOfToday())}.csv`, 'text/csv;charset=utf-8');
    showToast('CSV exported');
  }

  function exportJson() { downloadBlob(JSON.stringify({ version: 1.4, exportedAt: new Date().toISOString(), state }, null, 2), `daily-routine-backup-${dateKey(startOfToday())}.json`, 'application/json'); showToast('Backup downloaded'); }

  async function importJson(event) {
    const file = event.target.files?.[0]; event.target.value = ''; if (!file) return;
    try {
      const payload = JSON.parse(await file.text()), incoming = payload.state || payload;
      if (!incoming || !Array.isArray(incoming.items) || typeof incoming.days !== 'object') throw new Error('Invalid backup');
      if (!confirm('Restore this backup? It will replace current app data on this device.')) return;
      state = { settings: { ...DEFAULT_STATE.settings, ...(incoming.settings || {}) }, items: incoming.items.map(normalizeItem), days: incoming.days, memories: Array.isArray(incoming.memories) ? incoming.memories : [] };
      ensureFirstUseDate(); saveState(); applyPersonalization(); renderAll(); showToast('Backup restored');
    } catch { alert('That file does not look like a valid Daily Routine backup.'); }
  }

  function resetData() {
    if (!confirm('Reset all routines, history, and settings on this device?')) return;
    state = structuredClone(DEFAULT_STATE); state.settings.firstUseDate = dateKey(startOfToday()); ensureFirstUseDate(); saveState(); selectedDate = startOfToday(); applyPersonalization(); renderAll(); showToast('App reset');
  }

  function saveActualTime(field, value) {
    const day = ensureDay(dateKey(selectedDate));
    if (value) day[field] = value; else delete day[field];
    saveState();
    renderHistory();
    showToast(value ? 'Actual time saved' : 'Actual time cleared');
  }

  function currentTimeValue() {
    const now = new Date();
    return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  }

  function medicationTime(value) {
    return value && typeof value === 'object' && value.taken ? (value.time || '') : '';
  }

  function buildMedicationRow(row, item, value) {
    const taken = entryIsLogged(item, value);
    const time = medicationTime(value);
    row.classList.toggle('done', taken);
    row.innerHTML = `<div class="task-main medication-main"><span class="medication-icon" aria-hidden="true">Rx</span><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}${taken ? ` · ${time ? `Taken ${formatTime(time)}` : 'Taken · time not logged'}` : ''}</span></span></div><div class="medication-actions"></div>`;
    const actions = row.querySelector('.medication-actions');
    if (!taken) {
      actions.innerHTML = `<button class="primary-button medication-now" type="button">Taken now</button><button class="small-button medication-manual" type="button">Add time</button>`;
      actions.querySelector('.medication-now').addEventListener('click', () => logMedicationNow(item));
      actions.querySelector('.medication-manual').addEventListener('click', () => saveMedicationTime(item, currentTimeValue(), true));
    } else {
      actions.innerHTML = `<label class="med-time-edit"><span>Taken at</span><input class="task-input" type="time" value="${escapeHtml(time)}" /></label><button class="small-button medication-clear" type="button">Clear</button>`;
      actions.querySelector('input').addEventListener('change', event => saveMedicationTime(item, event.target.value, true));
      actions.querySelector('.medication-clear').addEventListener('click', () => clearMedication(item));
    }
    return row;
  }

  function logMedicationNow(item) { saveMedicationTime(item, currentTimeValue(), true); }

  function saveMedicationTime(item, time, rerender = true) {
    const day = ensureDay(dateKey(selectedDate));
    const selected = fromDateKey(dateKey(selectedDate));
    if (time) {
      const [hours, minutes] = time.split(':').map(Number);
      selected.setHours(hours, minutes, 0, 0);
      day.entries[item.id] = { taken: true, time, timestamp: selected.toISOString() };
    } else {
      day.entries[item.id] = { taken: true, time: '', timestamp: null };
    }
    saveState();
    if (rerender) renderToday(); else renderStats();
    showToast(time ? `Medication logged at ${formatTime(time)}` : 'Medication logged');
  }

  function clearMedication(item) {
    const day = ensureDay(dateKey(selectedDate));
    delete day.entries[item.id];
    saveState(); renderToday(); showToast('Medication log cleared');
  }

  function eligibleMemories(item) {
    const category = item.memoryCategory || 'any';
    return state.memories.filter(memory => category === 'any' || memory.category === category);
  }

  function recentMemoryIds(item, limit = 5) {
    const ids = [];
    const today = startOfToday();
    for (let i = 0; i < 30 && ids.length < limit; i += 1) {
      const day = state.days[dateKey(shiftDate(today, -i))];
      const entry = day?.entries?.[item.id];
      if (entry?.memoryId && !ids.includes(entry.memoryId)) ids.push(entry.memoryId);
    }
    return ids;
  }

  function chooseMemory(item, excludeId = '') {
    const available = eligibleMemories(item);
    if (!available.length) return null;
    const recent = new Set(recentMemoryIds(item));
    let pool = available.filter(memory => memory.id !== excludeId && !recent.has(memory.id));
    if (!pool.length) pool = available.filter(memory => memory.id !== excludeId);
    if (!pool.length) pool = available;
    return pool[Math.floor(Math.random() * pool.length)];
  }

  function memoryEntryForToday(item, value) {
    if (value && typeof value === 'object' && value.memoryId && state.memories.some(memory => memory.id === value.memoryId)) return value;
    const memory = chooseMemory(item);
    if (!memory) return null;
    const entry = { memoryId: memory.id, reflected: false, shownAt: new Date().toISOString() };
    ensureDay(dateKey(selectedDate)).entries[item.id] = entry;
    saveState();
    return entry;
  }

  function buildMemoryRow(row, item, value) {
    const entry = memoryEntryForToday(item, value);
    row.classList.add('memory-routine-row');
    if (!entry) {
      row.innerHTML = `<div class="task-main"><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}</span></span></div><div class="memory-empty-inline"><span>No saved ${item.memoryCategory && item.memoryCategory !== 'any' ? escapeHtml(item.memoryCategory) + 's' : 'memories'} yet.</span><button class="primary-button" type="button">+ Remember something</button></div>`;
      row.querySelector('button').addEventListener('click', () => openMemoryDialog(item.memoryCategory === 'any' ? 'blessing' : item.memoryCategory));
      return row;
    }
    const memory = state.memories.find(candidate => candidate.id === entry.memoryId);
    if (!memory) return row;
    row.classList.toggle('done', Boolean(entry.reflected));
    row.innerHTML = `<div class="memory-routine-head"><div><span class="memory-category">${escapeHtml(memoryCategoryLabel(memory.category))}</span><strong>${escapeHtml(item.name)}</strong></div><span class="task-meta">${escapeHtml(metaForItem(item))}</span></div><blockquote>${escapeHtml(memory.text)}</blockquote><div class="memory-routine-meta">${escapeHtml(formatMemoryDate(memory.createdAt))}</div><div class="memory-routine-actions"><button class="small-button another-memory" type="button">Another one ↻</button><button class="${entry.reflected ? 'secondary-button' : 'primary-button'} reflect-memory" type="button">${entry.reflected ? 'Reflected ✓' : 'I reflected on this'}</button></div>`;
    row.querySelector('.another-memory').addEventListener('click', () => rotateMemory(item, entry.memoryId));
    row.querySelector('.reflect-memory').addEventListener('click', () => toggleMemoryReflected(item));
    return row;
  }

  function rotateMemory(item, currentId) {
    const memory = chooseMemory(item, currentId);
    if (!memory) { showToast('No other memories available yet'); return; }
    const day = ensureDay(dateKey(selectedDate));
    day.entries[item.id] = { memoryId: memory.id, reflected: false, shownAt: new Date().toISOString() };
    saveState(); renderToday();
  }

  function toggleMemoryReflected(item) {
    const day = ensureDay(dateKey(selectedDate));
    const entry = day.entries[item.id];
    if (!entry?.memoryId) return;
    entry.reflected = !entry.reflected;
    entry.reflectedAt = entry.reflected ? new Date().toISOString() : null;
    saveState(); renderToday();
  }

  function openMemoryDialog(category = 'blessing') {
    els.memoryTextInput.value = '';
    els.memoryCategoryCaptureInput.value = ['blessing','gratitude','prayer','thought','quote','memory'].includes(category) ? category : 'blessing';
    els.memoryDateTimeInput.value = toDateTimeLocal(new Date());
    els.memoryDialog.showModal();
    setTimeout(() => els.memoryTextInput.focus(), 50);
  }

  function saveMemory(event) {
    event.preventDefault();
    const text = els.memoryTextInput.value.trim();
    if (!text) return;
    const when = new Date(els.memoryDateTimeInput.value);
    const createdAt = Number.isNaN(when.getTime()) ? new Date().toISOString() : when.toISOString();
    state.memories.push({ id: `memory-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, text, category: els.memoryCategoryCaptureInput.value, createdAt });
    saveState(); els.memoryDialog.close(); renderAll(); showToast('Memory saved');
  }

  function renderMemoryPreview() {
    const memories = [...state.memories].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    if (!memories.length) {
      els.memoryTodayPreview.innerHTML = '<span class="muted">Capture small blessings, moments, prayers, or thoughts so the app can bring them back later.</span>';
      return;
    }
    const latest = memories[0];
    els.memoryTodayPreview.innerHTML = `<div><strong>${state.memories.length} saved</strong><span>Latest · ${escapeHtml(memoryCategoryLabel(latest.category))} · ${escapeHtml(formatMemoryDate(latest.createdAt))}</span></div><p>${escapeHtml(latest.text)}</p>`;
  }

  function renderMemoryArchive() {
    els.memoryCount.textContent = state.memories.length;
    const memories = [...state.memories].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 25);
    if (!memories.length) { els.memoryArchive.innerHTML = '<div class="analytics-empty">Nothing saved yet. Capture the first small thing you do not want to forget.</div>'; return; }
    els.memoryArchive.innerHTML = '';
    memories.forEach(memory => {
      const row = document.createElement('div'); row.className = 'memory-archive-row';
      row.innerHTML = `<div><span class="memory-category">${escapeHtml(memoryCategoryLabel(memory.category))}</span><p>${escapeHtml(memory.text)}</p><small>${escapeHtml(formatMemoryDate(memory.createdAt))}</small></div><button class="edit-button" type="button" aria-label="Delete memory">Delete</button>`;
      row.querySelector('button').addEventListener('click', () => deleteMemory(memory.id));
      els.memoryArchive.appendChild(row);
    });
  }

  function deleteMemory(id) {
    const memory = state.memories.find(candidate => candidate.id === id);
    if (!memory || !confirm('Delete this saved memory?')) return;
    state.memories = state.memories.filter(candidate => candidate.id !== id);
    Object.values(state.days).forEach(day => Object.entries(day.entries || {}).forEach(([itemId, entry]) => { if (entry?.memoryId === id) delete day.entries[itemId]; }));
    saveState(); renderAll(); showToast('Memory deleted');
  }

  function exportMemoriesCsv() {
    const rows = [['Date & Time', 'Category', 'Memory']];
    [...state.memories].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt)).forEach(memory => rows.push([new Date(memory.createdAt).toLocaleString(), memoryCategoryLabel(memory.category), memory.text]));
    downloadBlob(rows.map(row => row.map(csvCell).join(',')).join('\r\n'), `daily-routine-memories-${dateKey(startOfToday())}.csv`, 'text/csv;charset=utf-8');
    showToast('Memories exported');
  }

  function memoryCategoryLabel(category) { return ({ blessing:'Blessing', gratitude:'Gratitude', prayer:'Prayer', thought:'Thought', quote:'Quote', memory:'Memory' })[category] || 'Memory'; }
  function formatMemoryDate(value) { const date = new Date(value); return Number.isNaN(date.getTime()) ? '' : new Intl.DateTimeFormat(undefined, { month:'short', day:'numeric', year:'numeric', hour:'numeric', minute:'2-digit' }).format(date); }
  function toDateTimeLocal(date) { const offset = date.getTimezoneOffset(); const local = new Date(date.getTime() - offset * 60000); return local.toISOString().slice(0, 16); }

  async function updateAppBadge() {
    try {
      if (!('setAppBadge' in navigator) || !('clearAppBadge' in navigator)) return;
      if (state.settings.badgeEnabled === false) { await navigator.clearAppBadge(); return; }
      const c = completionForDate(startOfToday());
      const remaining = Math.max(0, c.total - c.completed);
      if (remaining > 0) await navigator.setAppBadge(remaining); else await navigator.clearAppBadge();
    } catch { /* Some browsers expose the API but do not permit badges outside an installed app. */ }
  }

  function timeToMinutes(value) {
    if (!/^\d{2}:\d{2}$/.test(value || '')) return null;
    const [hours, minutes] = value.split(':').map(Number);
    return hours * 60 + minutes;
  }

  function averageClock(values, eveningWrap = false) {
    if (!values.length) return null;
    const adjusted = values.map(value => eveningWrap && value < 360 ? value + 1440 : value);
    const avg = adjusted.reduce((sum, value) => sum + value, 0) / adjusted.length;
    return ((Math.round(avg) % 1440) + 1440) % 1440;
  }

  function formatMinutesClock(minutes) {
    if (minutes === null || minutes === undefined) return '—';
    const normalized = ((Math.round(minutes) % 1440) + 1440) % 1440;
    return formatTime(`${String(Math.floor(normalized / 60)).padStart(2, '0')}:${String(normalized % 60).padStart(2, '0')}`);
  }

  function formatDurationMinutes(minutes) {
    const rounded = Math.max(0, Math.round(minutes));
    const hours = Math.floor(rounded / 60), mins = rounded % 60;
    return `${hours}h ${String(mins).padStart(2, '0')}m`;
  }

  function renderMedicationTiming() {
    const medicationItems = state.items.filter(item => item.type === 'medication');
    if (!medicationItems.length) { els.medicationInsights.innerHTML = '<div class="analytics-empty">Change a routine item to “Medication + time” to start building timing history.</div>'; return; }
    const dates = activeRangeDates();
    const blocks = medicationItems.map(item => medicationTimingMetric(item, dates)).filter(metric => metric.loggedTimes.length);
    if (!blocks.length) { els.medicationInsights.innerHTML = '<div class="analytics-empty">Tap “Taken now” on a medication item to start building this view.</div>'; return; }
    els.medicationInsights.innerHTML = blocks.map(metric => {
      const avgTaken = averageClock(metric.loggedTimes, true);
      const avgWake = averageClock(metric.pairs.map(pair => pair.wake), false);
      const avgInterval = metric.pairs.length ? average(metric.pairs.map(pair => pair.interval)) : null;
      let comparison = '';
      if (metric.pairs.length >= 6) {
        const sorted = [...metric.pairs].sort((a,b) => a.medAdjusted - b.medAdjusted);
        const cut = Math.floor(sorted.length / 2);
        const early = sorted.slice(0, cut), late = sorted.slice(cut);
        const earlyWake = averageClock(early.map(pair => pair.wake));
        const lateWake = averageClock(late.map(pair => pair.wake));
        comparison = `<div class="med-compare"><span>Earlier half → <b>${formatMinutesClock(earlyWake)}</b> avg next wake</span><span>Later half → <b>${formatMinutesClock(lateWake)}</b> avg next wake</span></div>`;
      }
      return `<div class="med-insight"><div class="med-insight-head"><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.loggedTimes.length} timed dose${metric.loggedTimes.length === 1 ? '' : 's'} · ${metric.pairs.length} paired with next wake</span></div><div class="med-stat-grid"><div><b>${formatMinutesClock(avgTaken)}</b><span>Avg taken</span></div><div><b>${formatMinutesClock(avgWake)}</b><span>Avg next wake</span></div><div><b>${avgInterval === null ? '—' : formatDurationMinutes(avgInterval)}</b><span>Avg taken → wake</span></div></div>${comparison}</div>`;
    }).join('');
  }

  function medicationTimingMetric(item, dates) {
    const loggedTimes = [], pairs = [];
    dates.forEach(date => {
      const day = state.days[dateKey(date)] || {};
      const entry = day.entries?.[item.id];
      const med = timeToMinutes(medicationTime(entry));
      if (med === null) return;
      loggedTimes.push(med);
      const nextDay = state.days[dateKey(shiftDate(date, 1))] || {};
      const wake = timeToMinutes(nextDay.actualWakeTime);
      if (wake === null) return;
      const medAdjusted = med < 360 ? med + 1440 : med;
      let wakeAdjusted = wake;
      while (wakeAdjusted <= medAdjusted) wakeAdjusted += 1440;
      pairs.push({ med, medAdjusted, wake, interval: wakeAdjusted - medAdjusted });
    });
    return { item, loggedTimes, pairs };
  }

  function scaleLabel(item) { const scale = normalizeScale(item.scale); return `${formatNumber(scale.min)}–${formatNumber(scale.max)} scale`; }
  function greetingForHour(hour) { return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'; }
  function formatTime(value) { if (!value) return '—'; const [h, m] = value.split(':').map(Number), d = new Date(); d.setHours(h, m, 0, 0); return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(d); }
  function frequencyLabel(item) { const v = item.frequency; if (v === 'weekdays') return 'Weekdays'; if (v === 'weekends') return 'Weekends'; if (v === 'custom') { const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']; return (item.days || []).sort((a, b) => a - b).map(day => labels[day]).join(', ') || 'Specific days'; } return 'Every day'; }
  function formatNumber(value) { return Number(value).toLocaleString(undefined, { maximumFractionDigits: 2 }); }
  function csvCell(value) { const str = String(value ?? ''); return /[",\n\r]/.test(str) ? `"${str.replaceAll('"', '""')}"` : str; }
  function downloadBlob(content, filename, type) { const blob = new Blob([content], { type }), url = URL.createObjectURL(blob), a = document.createElement('a'); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000); }
  function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char])); }
  function debounce(fn, delay) { let timer; return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), delay); }; }
  function showToast(message) { clearTimeout(toastTimer); els.toast.textContent = message; els.toast.classList.add('show'); toastTimer = setTimeout(() => els.toast.classList.remove('show'), 1800); }
})();
