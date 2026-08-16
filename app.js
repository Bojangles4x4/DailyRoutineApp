(() => {
  'use strict';

  const STORAGE_KEY = 'dailyRoutineApp.v1';
  const SNAPSHOT_KEY = 'dailyRoutineApp.snapshots.v1';
  const APP_VERSION = '1.8';
  const BIBLE_INTEGRATION_KEY = 'dailyRoutine.integration.bibleReading.v1';
  const INTEGRATION_CHANNEL = 'dailyRoutine.integrations.v1';
  const DEFAULT_BIBLE_APP_URL = 'https://bojangles4x4.github.io/Bible-Reading-Plan/';
  const DEFAULT_SCALE = { min: 0, max: 10, step: 1, lowLabel: 'Low', highLabel: 'Great' };
  const DEFAULT_STATE = {
    settings: { wakeTime: '06:00', bedTime: '22:30', theme: 'calm', backgroundImage: '', badgeEnabled: true, streakThreshold: 80, streakMode: 'forgiving', streakWeekdaysOnly: false, bibleAppUrl: DEFAULT_BIBLE_APP_URL, resurfacingFrequency: 'occasional', lastBackupAt: '' },
    items: [
      { id: 'morning-prayer', name: 'Prayer', kind: 'routine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-teeth', name: 'Brush teeth', kind: 'routine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-meds', name: 'Take morning medicine', kind: 'routine', section: 'morning', type: 'medication', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-reading', name: '10-Chapter Bible Reading', kind: 'routine', section: 'morning', type: 'linked', frequency: 'daily', days: [], optional: false, linkedTemplate: 'bible', linkedCompletion: 'sync', linkedUrl: DEFAULT_BIBLE_APP_URL, linkedButtonLabel: 'Continue reading', linkedInternalTarget: '', timeWindowStart: '', timeWindowEnd: '', unit: '', target: null },
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
    memories: [],
    notes: [],
    weeklyReviews: {}
  };

  const sectionLabels = {
    morning: ['Morning', 'Start deliberately'],
    day: ['Throughout the day', 'Stay on track'],
    evening: ['Evening', 'Close the day well']
  };
  const typeLabels = { checkbox: 'Checkbox', linked: 'Linked app / action', medication: 'Medication + time', memory: 'Memory reflection', scale: 'Rating scale', number: 'Number', time: 'Time', text: 'Short comment', longtext: 'Journal entry' };
  const noteTypeLabels = { entrust: 'Entrust to the Lord', review: 'Review later', action: 'Action item', prayer: 'Prayer', 'god-moment': 'God Moment', general: 'General note', routine: 'Routine note', memory: 'Memory Bank' };
  const THOUGHT_INBOX_KEYS = ['dailyRoutine.thoughtInbox.v1', 'dailyRoutineApp.thoughtInbox.v1', 'dailyRoutineApp.thoughts.v1', 'thoughtInbox'];

  let state = loadState();
  let selectedDate = startOfToday();
  let deferredInstallPrompt = null;
  let toastTimer = null;
  let analyticsRange = 7;
  let undoAction = null;
  let pendingLinkedAction = null;
  let integrationChannel = null;
  let reflectionReviewExpanded = false;
  const collapsedSections = new Set();

  const $ = id => document.getElementById(id);
  const els = {
    pageTitle: $('pageTitle'), todayEyebrow: $('todayEyebrow'), heroGreeting: $('heroGreeting'), heroDate: $('heroDate'), heroStatus: $('heroStatus'),
    wakeTimeDisplay: $('wakeTimeDisplay'), bedTimeDisplay: $('bedTimeDisplay'), progressRing: $('progressRing'), progressPercent: $('progressPercent'),
    selectedDateButton: $('selectedDateButton'), datePickerInput: $('datePickerInput'), prevDay: $('prevDay'), nextDay: $('nextDay'), routineSections: $('routineSections'), dayModeInput: $('dayModeInput'), undoButton: $('undoButton'), weekFocusBanner: $('weekFocusBanner'), onThisDayMemory: $('onThisDayMemory'),
    statCompleted: $('statCompleted'), statOptional: $('statOptional'), statStreak: $('statStreak'), statMood: $('statMood'), copySummaryButton: $('copySummaryButton'),
    historyList: $('historyList'), rangeSelector: $('rangeSelector'), progressOverall: $('progressOverall'), progress80Days: $('progress80Days'), progressTrackedDays: $('progressTrackedDays'),
    progressRangeNote: $('progressRangeNote'), weekSummary: $('weekSummary'), weekOverall: $('weekOverall'), sectionBreakdown: $('sectionBreakdown'), strongHabits: $('strongHabits'), weakHabits: $('weakHabits'), trendList: $('trendList'), patternInsights: $('patternInsights'),
    wakeTimeInput: $('wakeTimeInput'), bedTimeInput: $('bedTimeInput'), streakThresholdInput: $('streakThresholdInput'), streakModeInput: $('streakModeInput'), streakWeekdaysOnlyInput: $('streakWeekdaysOnlyInput'), themeInput: $('themeInput'), backgroundImageInput: $('backgroundImageInput'), clearBackgroundButton: $('clearBackgroundButton'),
    routineEditor: $('routineEditor'), checkinEditor: $('checkinEditor'), addItemButton: $('addItemButton'), addCheckinButton: $('addCheckinButton'),
    exportCsvButton: $('exportCsvButton'), exportJsonButton: $('exportJsonButton'), importJsonInput: $('importJsonInput'), resetDataButton: $('resetDataButton'),
    itemDialog: $('itemDialog'), itemForm: $('itemForm'), builderEyebrow: $('builderEyebrow'), dialogTitle: $('dialogTitle'), editingItemId: $('editingItemId'), editingItemKind: $('editingItemKind'),
    itemNameInput: $('itemNameInput'), itemSectionInput: $('itemSectionInput'), itemTypeInput: $('itemTypeInput'), itemFrequencyInput: $('itemFrequencyInput'), customDaysField: $('customDaysField'),
    numberGoalFields: $('numberGoalFields'), itemTargetInput: $('itemTargetInput'), itemUnitInput: $('itemUnitInput'), scaleFields: $('scaleFields'), scaleMinInput: $('scaleMinInput'), scaleMaxInput: $('scaleMaxInput'), scaleStepInput: $('scaleStepInput'), scaleLowLabelInput: $('scaleLowLabelInput'), scaleHighLabelInput: $('scaleHighLabelInput'),
    promptField: $('promptField'), itemPlaceholderInput: $('itemPlaceholderInput'), optionalField: $('optionalField'), itemOptionalInput: $('itemOptionalInput'),
    medicationFields: $('medicationFields'), medicationDoseInput: $('medicationDoseInput'), memoryFields: $('memoryFields'), memoryCategoryInput: $('memoryCategoryInput'), pauseUntilInput: $('pauseUntilInput'),
    actualWakeInput: $('actualWakeInput'), actualBedInput: $('actualBedInput'), wakeNowButton: $('wakeNowButton'), bedNowButton: $('bedNowButton'), badgeEnabledInput: $('badgeEnabledInput'),
    quickNoteButton: $('quickNoteButton'), quickMemoryButton: $('quickMemoryButton'), memoryTodayPreview: $('memoryTodayPreview'), addMemoryButton: $('addMemoryButton'), memoryCount: $('memoryCount'), memoryArchive: $('memoryArchive'), exportMemoriesButton: $('exportMemoriesButton'), memorySearchInput: $('memorySearchInput'), memoryFilterInput: $('memoryFilterInput'), memoryFavoritesOnlyInput: $('memoryFavoritesOnlyInput'),
    godMomentReminder: $('godMomentReminder'), godMomentReminderText: $('godMomentReminderText'), godMomentReminderDate: $('godMomentReminderDate'), openGodMomentsButton: $('openGodMomentsButton'), backupReminder: $('backupReminder'), backupReminderText: $('backupReminderText'), openBackupButton: $('openBackupButton'),
    addNoteButton: $('addNoteButton'), notesOpenCount: $('notesOpenCount'), godMomentCount: $('godMomentCount'), notesDueCount: $('notesDueCount'), notesSearchInput: $('notesSearchInput'), notesTypeFilter: $('notesTypeFilter'), notesStatusFilter: $('notesStatusFilter'), notesResultsTitle: $('notesResultsTitle'), notesResultCount: $('notesResultCount'), notesList: $('notesList'), importGodMomentsInput: $('importGodMomentsInput'),
    reflectionReviewCard: $('reflectionReviewCard'), toggleReflectionReviewButton: $('toggleReflectionReviewButton'), reflectionReviewStatus: $('reflectionReviewStatus'), reflectionReviewPanel: $('reflectionReviewPanel'), reflectionReviewLists: $('reflectionReviewLists'), reviewDueCount: $('reviewDueCount'), reviewActionCount: $('reviewActionCount'), reviewPrayerCount: $('reviewPrayerCount'), reviewMomentCount: $('reviewMomentCount'), weeklyReflectionInput: $('weeklyReflectionInput'), finishReflectionReviewButton: $('finishReflectionReviewButton'),
    noteDialog: $('noteDialog'), noteForm: $('noteForm'), noteDialogTitle: $('noteDialogTitle'), closeNoteDialogButton: $('closeNoteDialogButton'), editingNoteId: $('editingNoteId'), noteTextInput: $('noteTextInput'), noteTypeInput: $('noteTypeInput'), noteScriptureField: $('noteScriptureField'), noteScriptureInput: $('noteScriptureInput'), notePrayerStatusField: $('notePrayerStatusField'), notePrayerStatusInput: $('notePrayerStatusInput'), noteReviewAtInput: $('noteReviewAtInput'), noteSnoozedUntilInput: $('noteSnoozedUntilInput'), noteSourceInput: $('noteSourceInput'), notePinnedInput: $('notePinnedInput'), noteResurfaceField: $('noteResurfaceField'), noteResurfaceInput: $('noteResurfaceInput'), deleteNoteButton: $('deleteNoteButton'),
    medicationInsights: $('medicationInsights'), weeklyReviewLabel: $('weeklyReviewLabel'), weeklyReviewSummary: $('weeklyReviewSummary'), weeklyFocusInput: $('weeklyFocusInput'), saveWeeklyFocusButton: $('saveWeeklyFocusButton'), memoryDialog: $('memoryDialog'), memoryForm: $('memoryForm'), closeMemoryDialogButton: $('closeMemoryDialogButton'), memoryTextInput: $('memoryTextInput'), memoryCategoryCaptureInput: $('memoryCategoryCaptureInput'), memoryDateTimeInput: $('memoryDateTimeInput'),
    createSnapshotButton: $('createSnapshotButton'), restoreSnapshotButton: $('restoreSnapshotButton'), snapshotStatus: $('snapshotStatus'), backupDownloadStatus: $('backupDownloadStatus'), appVersion: $('appVersion'), resurfacingFrequencyInput: $('resurfacingFrequencyInput'),
    connectionsCard: $('connectionsCard'), syncConnectionsButton: $('syncConnectionsButton'), bibleConnectionStatus: $('bibleConnectionStatus'), openBibleConnectionButton: $('openBibleConnectionButton'), bibleAppUrlInput: $('bibleAppUrlInput'), saveBibleConnectionButton: $('saveBibleConnectionButton'), testBibleConnectionButton: $('testBibleConnectionButton'), connectionTemplates: $('connectionTemplates'),
    linkedActionFields: $('linkedActionFields'), linkedTemplateInput: $('linkedTemplateInput'), linkedCompletionInput: $('linkedCompletionInput'), linkedUrlField: $('linkedUrlField'), linkedUrlInput: $('linkedUrlInput'), linkedInternalField: $('linkedInternalField'), linkedInternalTargetInput: $('linkedInternalTargetInput'), linkedButtonLabelInput: $('linkedButtonLabelInput'), timeWindowFields: $('timeWindowFields'), timeWindowStartInput: $('timeWindowStartInput'), timeWindowEndInput: $('timeWindowEndInput'),
    medicationProgressCard: $('medicationProgressCard'), weeklyReviewCard: $('weeklyReviewCard'), memoryBankCard: $('memoryBankCard'), dataBackupCard: $('dataBackupCard'),
    deleteItemButton: $('deleteItemButton'), closeDialogButton: $('closeDialogButton'), installButton: $('installButton'), toast: $('toast')
  };

  init();

  function init() {
    ensureFirstUseDate();
    consumeIntegrationReturn();
    syncLinkedIntegrations(false);
    bindNavigation();
    bindTodayControls();
    bindNotesControls();
    bindProgressControls();
    bindSetupControls();
    bindInstall();
    bindIntegrationEvents();
    applyPersonalization();
    renderAll();
    consumeQuickCapture();
    maybeAutoSnapshot();
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
      medicationDose: item.medicationDose || '',
      pausedFrom: item.pausedFrom || '',
      pausedUntil: item.pausedUntil || '',
      linkedTemplate: item.linkedTemplate || 'website',
      linkedCompletion: item.linkedCompletion || 'manual',
      linkedUrl: item.linkedUrl || '',
      linkedButtonLabel: item.linkedButtonLabel || '',
      linkedInternalTarget: item.linkedInternalTarget || 'memory',
      timeWindowStart: item.timeWindowStart || '',
      timeWindowEnd: item.timeWindowEnd || '',
      scale: type === 'scale' ? normalizeScale(item.scale) : undefined
    };
  }

  function normalizeNote(note, index = 0) {
    const allowedTypes = ['entrust', 'review', 'action', 'prayer', 'god-moment', 'general'];
    const typeAliases = { later: 'review', 'review-later': 'review', task: 'action', 'action-item': 'action', godmoment: 'god-moment', thought: 'general' };
    const requestedType = typeAliases[String(note?.type || '').toLowerCase()] || String(note?.type || '').toLowerCase();
    const createdAt = validDateValue(note?.createdAt || note?.date || note?.timestamp) || new Date().toISOString();
    const type = allowedTypes.includes(requestedType) ? requestedType : 'general';
    const requestedPrayerStatus = String(note?.prayerStatus || '').toLowerCase();
    const prayerStatus = type === 'prayer' && ['active', 'answered', 'archived'].includes(requestedPrayerStatus) ? requestedPrayerStatus : type === 'prayer' ? (note?.completedAt ? 'archived' : 'active') : '';
    const completedAt = validDateValue(note?.completedAt || (note?.completed ? note?.updatedAt || createdAt : '') || (['answered', 'archived'].includes(prayerStatus) ? note?.answeredAt || note?.updatedAt || createdAt : ''));
    return {
      id: String(note?.id || `note-${Date.now()}-${index}-${Math.random().toString(36).slice(2, 7)}`),
      text: String(note?.text || note?.content || note?.body || note?.title || '').trim(),
      type,
      scripture: String(note?.scripture || note?.truth || '').trim(),
      reviewAt: validDateValue(note?.reviewAt || note?.reviewDate || note?.remindAt),
      snoozedUntil: validDateValue(note?.snoozedUntil || note?.snoozeUntil),
      source: String(note?.source || 'Daily Routine'),
      createdAt,
      updatedAt: validDateValue(note?.updatedAt) || createdAt,
      completedAt,
      prayerStatus,
      answeredAt: validDateValue(note?.answeredAt || (prayerStatus === 'answered' ? completedAt : '')),
      pinned: Boolean(note?.pinned ?? note?.favorite),
      resurface: note?.resurface === undefined ? requestedType === 'god-moment' : Boolean(note.resurface),
      migrationKey: String(note?.migrationKey || '')
    };
  }

  function noteIsClosed(note) {
    return Boolean(note.completedAt) || (note.type === 'prayer' && ['answered', 'archived'].includes(note.prayerStatus));
  }

  function noteIsSnoozed(note, now = Date.now()) {
    return !noteIsClosed(note) && Boolean(note.snoozedUntil && new Date(note.snoozedUntil).getTime() > now);
  }

  function noteIsDue(note, now = Date.now()) {
    if (noteIsClosed(note) || noteIsSnoozed(note, now)) return false;
    const reviewTime = note.reviewAt ? new Date(note.reviewAt).getTime() : NaN;
    const snoozeTime = note.snoozedUntil ? new Date(note.snoozedUntil).getTime() : NaN;
    return (!Number.isNaN(reviewTime) && reviewTime <= now) || (!Number.isNaN(snoozeTime) && snoozeTime <= now);
  }

  function validDateValue(value) {
    if (!value) return '';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? '' : date.toISOString();
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
        memories: Array.isArray(parsed.memories) ? parsed.memories.map(memory => ({ ...memory, favorite: Boolean(memory.favorite), archived: Boolean(memory.archived) })) : [],
        notes: Array.isArray(parsed.notes) ? parsed.notes.map(normalizeNote).filter(note => note.text) : [],
        weeklyReviews: parsed.weeklyReviews && typeof parsed.weeklyReviews === 'object' ? parsed.weeklyReviews : {}
      };
    } catch {
      return structuredClone(DEFAULT_STATE);
    }
  }

  function saveState() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    maybeAutoSnapshot();
  }

  function snapshotPayload() {
    const safe = structuredClone(state);
    if (safe.settings) safe.settings.backgroundImage = '';
    return safe;
  }

  function readSnapshots() {
    try { const parsed = JSON.parse(localStorage.getItem(SNAPSHOT_KEY) || '[]'); return Array.isArray(parsed) ? parsed : []; }
    catch { return []; }
  }

  function writeSnapshots(snapshots) {
    try { localStorage.setItem(SNAPSHOT_KEY, JSON.stringify(snapshots.slice(0, 5))); } catch { /* local storage may be full */ }
  }

  function createLocalSnapshot(label = 'Manual snapshot', quiet = false) {
    const snapshots = readSnapshots();
    snapshots.unshift({ createdAt: new Date().toISOString(), label, state: snapshotPayload() });
    writeSnapshots(snapshots);
    renderSnapshotStatus();
    if (!quiet) showToast('Local snapshot created');
  }

  function maybeAutoSnapshot() {
    const today = dateKey(startOfToday());
    const snapshots = readSnapshots();
    if (!snapshots.some(snapshot => String(snapshot.createdAt || '').slice(0, 10) === today)) createLocalSnapshot('Automatic daily snapshot', true);
  }

  function renderSnapshotStatus() {
    if (!els.snapshotStatus) return;
    const latest = readSnapshots()[0];
    els.snapshotStatus.textContent = latest ? `Latest local snapshot: ${new Date(latest.createdAt).toLocaleString()} · ${latest.label}` : 'No local snapshots yet.';
  }

  function renderBackupDownloadStatus() {
    if (!els.backupDownloadStatus) return;
    const last = state.settings.lastBackupAt ? new Date(state.settings.lastBackupAt) : null;
    els.backupDownloadStatus.textContent = last && !Number.isNaN(last.getTime())
      ? `Last downloaded backup: ${last.toLocaleString()}`
      : 'No downloaded backup recorded yet. Local snapshots do not replace a downloaded backup.';
  }

  function restoreLatestSnapshot() {
    const latest = readSnapshots()[0];
    if (!latest?.state) { showToast('No local snapshot available'); return; }
    if (!confirm(`Restore the snapshot from ${new Date(latest.createdAt).toLocaleString()}? Current local data will be replaced.`)) return;
    state = {
      settings: { ...DEFAULT_STATE.settings, ...(latest.state.settings || {}), backgroundImage: state.settings.backgroundImage || '' },
      items: Array.isArray(latest.state.items) ? latest.state.items.map(normalizeItem) : [],
      days: latest.state.days || {},
      memories: Array.isArray(latest.state.memories) ? latest.state.memories : [],
      notes: Array.isArray(latest.state.notes) ? latest.state.notes.map(normalizeNote).filter(note => note.text) : [],
      weeklyReviews: latest.state.weeklyReviews || {}
    };
    ensureFirstUseDate(); localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); applyPersonalization(); renderAll(); showToast('Snapshot restored');
  }
  function startOfToday() { const d = new Date(); d.setHours(12, 0, 0, 0); return d; }
  function dateKey(date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`; }
  function fromDateKey(key) { const [y, m, d] = key.split('-').map(Number); return new Date(y, m - 1, d, 12, 0, 0, 0); }
  function shiftDate(date, days) { const d = new Date(date); d.setDate(d.getDate() + days); return d; }
  function isSameDay(a, b) { return dateKey(a) === dateKey(b); }
  function ensureDay(key) { if (!state.days[key]) state.days[key] = { entries: {}, skippedItems: {}, mode: 'normal' }; if (!state.days[key].entries) state.days[key].entries = {}; if (!state.days[key].skippedItems) state.days[key].skippedItems = {}; if (!state.days[key].mode) state.days[key].mode = 'normal'; return state.days[key]; }

  function ensureFirstUseDate() {
    let changed = false;
    if (!state.settings.firstUseDate) {
      const historical = Object.keys(state.days || {}).filter(key => /^\d{4}-\d{2}-\d{2}$/.test(key)).sort();
      state.settings.firstUseDate = historical[0] || dateKey(startOfToday());
      changed = true;
    }
    if (!Array.isArray(state.memories)) { state.memories = []; changed = true; }
    state.memories = state.memories.map(memory => ({ ...memory, favorite: Boolean(memory.favorite), archived: Boolean(memory.archived) }));
    if (!Array.isArray(state.notes)) { state.notes = []; changed = true; }
    state.notes = state.notes.map(normalizeNote).filter(note => note.text);
    if (!state.weeklyReviews || typeof state.weeklyReviews !== 'object') { state.weeklyReviews = {}; changed = true; }
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
    if (!state.settings.bibleAppUrl) { state.settings.bibleAppUrl = DEFAULT_BIBLE_APP_URL; changed = true; }
    if (!state.settings.v16Seeded) {
      const reading = state.items.find(item => item.id === 'morning-reading') || state.items.find(item => /bible reading/i.test(item.name));
      if (reading && reading.type === 'checkbox') {
        Object.assign(reading, {
          name: '10-Chapter Bible Reading', type: 'linked', kind: 'routine', linkedTemplate: 'bible', linkedCompletion: 'sync',
          linkedUrl: state.settings.bibleAppUrl || DEFAULT_BIBLE_APP_URL, linkedButtonLabel: 'Continue reading', linkedInternalTarget: '',
          timeWindowStart: reading.timeWindowStart || '', timeWindowEnd: reading.timeWindowEnd || ''
        });
      }
      state.settings.v16Seeded = true;
      changed = true;
    }
    if (!state.settings.notesV2Migrated) {
      const migrated = migrateThoughtInbox();
      state.settings.notesV2Migrated = true;
      changed = true;
      if (migrated) state.settings.notesV2MigratedCount = migrated;
    }
    if (changed) saveState();
  }

  function migrateThoughtInbox() {
    let migrated = 0;
    const existingKeys = new Set(state.notes.map(note => note.migrationKey).filter(Boolean));
    THOUGHT_INBOX_KEYS.forEach(storageKey => {
      let parsed;
      try { parsed = JSON.parse(localStorage.getItem(storageKey) || 'null'); } catch { parsed = null; }
      const candidates = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.notes) ? parsed.notes : Array.isArray(parsed?.thoughts) ? parsed.thoughts : Array.isArray(parsed?.entries) ? parsed.entries : [];
      candidates.forEach((candidate, index) => {
        if (typeof candidate === 'string') candidate = { text: candidate };
        const migrationKey = `${storageKey}:${candidate?.id || index}`;
        if (existingKeys.has(migrationKey)) return;
        const note = normalizeNote({
          ...candidate,
          type: candidate?.type || candidate?.category || (candidate?.entrusted ? 'entrust' : candidate?.actionable ? 'action' : 'review'),
          source: candidate?.source || 'Imported Thought Inbox',
          migrationKey
        }, index);
        if (!note.text) return;
        state.notes.push(note);
        existingKeys.add(migrationKey);
        migrated += 1;
      });
    });
    return migrated;
  }

  function scheduledItemsForDate(date) {
    const dow = date.getDay();
    return state.items.filter(item => {
      if (item.createdDate && dateKey(date) < item.createdDate) return false;
      const key = dateKey(date);
      if (item.pausedFrom && item.pausedUntil && key >= item.pausedFrom && key <= item.pausedUntil) return false;
      if (item.frequency === 'weekdays') return dow >= 1 && dow <= 5;
      if (item.frequency === 'weekends') return dow === 0 || dow === 6;
      if (item.frequency === 'custom') return (item.days || []).includes(dow);
      return true;
    });
  }

  function scoredItemsForDate(date) {
    const day = state.days[dateKey(date)] || {};
    const skipped = day.skippedItems || {};
    return scheduledItemsForDate(date).filter(item => !skipped[item.id]);
  }

  function dayIsExcused(date) {
    const mode = state.days[dateKey(date)]?.mode || 'normal';
    return mode !== 'normal';
  }

  function entryIsLogged(item, value) {
    if (item.type === 'checkbox') return value === true;
    if (item.type === 'linked') return value === true || Boolean(value && typeof value === 'object' && value.completed);
    if (item.type === 'medication') return value === true || Boolean(value && typeof value === 'object' && value.taken);
    if (item.type === 'memory') return Boolean(value && typeof value === 'object' && value.reflected);
    if (item.type === 'scale') return Number.isFinite(Number(value));
    return value !== undefined && value !== null && String(value).trim() !== '';
  }

  function hasTarget(item) { return item.type === 'number' && item.target !== null && item.target !== '' && item.target !== undefined && Number.isFinite(Number(item.target)); }

  function entryMeetsTarget(item, value) {
    if (!entryIsLogged(item, value)) return false;
    if (hasTarget(item)) return Number(value) >= Number(item.target);
    return true;
  }

  function completionForDate(date) {
    const items = scoredItemsForDate(date);
    const required = items.filter(item => !item.optional);
    const optional = items.filter(item => item.optional);
    const day = state.days[dateKey(date)] || { entries: {} };
    const completed = required.filter(item => entryMeetsTarget(item, day.entries?.[item.id])).length;
    const optionalLogged = optional.filter(item => entryIsLogged(item, day.entries?.[item.id])).length;
    return { completed, total: required.length, optionalLogged, optionalTotal: optional.length, percent: required.length ? Math.round(completed / required.length * 100) : 100, excused: dayIsExcused(date) };
  }

  function calculateStreak() {
    let streak = 0;
    let cursor = startOfToday();
    const threshold = Math.min(100, Math.max(1, Number(state.settings.streakThreshold) || 80));
    const forgiving = state.settings.streakMode !== 'strict';
    const weekdaysOnly = Boolean(state.settings.streakWeekdaysOnly);
    for (let i = 0; i < 3650; i += 1) {
      if (weekdaysOnly && [0, 6].includes(cursor.getDay())) { cursor = shiftDate(cursor, -1); continue; }
      const c = completionForDate(cursor);
      if (c.excused) {
        if (forgiving) { cursor = shiftDate(cursor, -1); continue; }
        break;
      }
      if (c.total > 0 && c.percent >= threshold) { streak += 1; cursor = shiftDate(cursor, -1); }
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
    els.pageTitle.textContent = ({ today: 'Today', notes: 'Notes', history: 'Progress', setup: 'Setup' })[view] || 'Daily Routine';
    if (view === 'notes') renderNotes();
    if (view === 'history') renderHistory();
    if (view === 'setup') renderSetup();
    $('appMain').focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function bindTodayControls() {
    els.prevDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate, -1); renderToday(); });
    els.nextDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate, 1); renderToday(); });
    els.selectedDateButton.addEventListener('click', () => { selectedDate = startOfToday(); renderToday(); });
    els.datePickerInput.addEventListener('change', () => { if (!els.datePickerInput.value) return; const picked = fromDateKey(els.datePickerInput.value); if (dateKey(picked) <= dateKey(startOfToday())) { selectedDate = picked; renderToday(); } });
    els.dayModeInput.addEventListener('change', () => setDayMode(els.dayModeInput.value));
    els.undoButton.addEventListener('click', performUndo);
    els.copySummaryButton.addEventListener('click', copyDailySummary);
    els.actualWakeInput.addEventListener('change', () => saveActualTime('actualWakeTime', els.actualWakeInput.value));
    els.actualBedInput.addEventListener('change', () => saveActualTime('actualBedTime', els.actualBedInput.value));
    els.wakeNowButton.addEventListener('click', () => { const value = currentTimeValue(); els.actualWakeInput.value = value; saveActualTime('actualWakeTime', value); });
    els.bedNowButton.addEventListener('click', () => { const value = currentTimeValue(); els.actualBedInput.value = value; saveActualTime('actualBedTime', value); });
    els.quickMemoryButton.addEventListener('click', () => openMemoryDialog('blessing'));
    els.quickNoteButton.addEventListener('click', () => { switchView('notes'); openNoteDialog(); });
    els.openGodMomentsButton.addEventListener('click', () => { switchView('notes'); els.notesTypeFilter.value = 'god-moment'; renderNotes(); });
    els.openBackupButton.addEventListener('click', () => { switchView('setup'); els.dataBackupCard?.scrollIntoView({ behavior: 'smooth', block: 'start' }); });
  }

  function bindNotesControls() {
    els.addNoteButton.addEventListener('click', () => openNoteDialog());
    els.closeNoteDialogButton.addEventListener('click', () => els.noteDialog.close());
    els.noteTypeInput.addEventListener('change', toggleNoteFields);
    els.noteForm.addEventListener('submit', saveNote);
    els.deleteNoteButton.addEventListener('click', deleteNote);
    els.notesSearchInput.addEventListener('input', renderNotes);
    els.notesTypeFilter.addEventListener('change', renderNotes);
    els.notesStatusFilter.addEventListener('change', renderNotes);
    els.importGodMomentsInput.addEventListener('change', importGodMoments);
    els.toggleReflectionReviewButton.addEventListener('click', () => { reflectionReviewExpanded = !reflectionReviewExpanded; renderReflectionReview(); });
    els.finishReflectionReviewButton.addEventListener('click', finishReflectionReview);
  }

  function bindProgressControls() {
    els.saveWeeklyFocusButton.addEventListener('click', saveWeeklyFocus);
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
    els.streakThresholdInput.addEventListener('change', () => { state.settings.streakThreshold = Math.min(100, Math.max(1, Number(els.streakThresholdInput.value) || 80)); saveState(); renderAll(); });
    els.streakModeInput.addEventListener('change', () => { state.settings.streakMode = els.streakModeInput.value; saveState(); renderAll(); });
    els.streakWeekdaysOnlyInput.addEventListener('change', () => { state.settings.streakWeekdaysOnly = els.streakWeekdaysOnlyInput.checked; saveState(); renderAll(); });
    els.themeInput.addEventListener('change', () => { state.settings.theme = els.themeInput.value; saveState(); applyPersonalization(); });
    els.resurfacingFrequencyInput.addEventListener('change', () => { state.settings.resurfacingFrequency = els.resurfacingFrequencyInput.value; saveState(); renderToday(); showToast('Resurfacing preference saved'); });
    els.backgroundImageInput.addEventListener('change', handleBackgroundImage);
    els.clearBackgroundButton.addEventListener('click', () => { state.settings.backgroundImage = ''; saveState(); applyPersonalization(); showToast('Background photo removed'); });
    els.addItemButton.addEventListener('click', () => openItemDialog(null, 'routine'));
    els.addCheckinButton.addEventListener('click', () => openItemDialog(null, 'checkin'));
    els.closeDialogButton.addEventListener('click', () => els.itemDialog.close());
    els.itemTypeInput.addEventListener('change', toggleBuilderFields);
    els.itemFrequencyInput.addEventListener('change', toggleBuilderFields);
    els.linkedTemplateInput.addEventListener('change', () => { applyLinkedTemplate(els.linkedTemplateInput.value, false); toggleBuilderFields(); });
    els.itemForm.addEventListener('submit', saveRoutineItem);
    els.deleteItemButton.addEventListener('click', deleteRoutineItem);
    els.addMemoryButton.addEventListener('click', () => openMemoryDialog('blessing'));
    els.closeMemoryDialogButton.addEventListener('click', () => els.memoryDialog.close());
    els.memoryForm.addEventListener('submit', saveMemory);
    els.exportMemoriesButton.addEventListener('click', exportMemoriesCsv);
    els.memorySearchInput.addEventListener('input', renderMemoryArchive);
    els.memoryFilterInput.addEventListener('change', renderMemoryArchive);
    els.memoryFavoritesOnlyInput.addEventListener('change', renderMemoryArchive);
    els.exportCsvButton.addEventListener('click', exportCsv);
    els.exportJsonButton.addEventListener('click', exportJson);
    els.importJsonInput.addEventListener('change', importJson);
    els.createSnapshotButton.addEventListener('click', () => createLocalSnapshot('Manual snapshot'));
    els.restoreSnapshotButton.addEventListener('click', restoreLatestSnapshot);
    els.syncConnectionsButton.addEventListener('click', () => { syncLinkedIntegrations(true); renderAll(); });
    els.saveBibleConnectionButton.addEventListener('click', saveBibleConnection);
    els.testBibleConnectionButton.addEventListener('click', () => openBibleApp(startOfToday()));
    els.openBibleConnectionButton.addEventListener('click', () => openBibleApp(startOfToday()));
    els.connectionTemplates.querySelectorAll('[data-template]').forEach(button => button.addEventListener('click', () => openItemDialog(null, 'routine', button.dataset.template)));
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

  function allNoteRecords() {
    const records = state.notes.map(note => ({ ...note, kind: 'standalone', title: noteTypeLabels[note.type] || 'Note', readOnly: false }));
    Object.entries(state.days || {}).forEach(([key, day]) => {
      Object.entries(day.entries || {}).forEach(([itemId, value]) => {
        const item = state.items.find(candidate => candidate.id === itemId);
        if (!item || !['text', 'longtext'].includes(item.type) || value === undefined || value === null || !String(value).trim()) return;
        const createdAt = new Date(`${key}T12:00:00`).toISOString();
        records.push({ id: `routine:${key}:${itemId}`, kind: 'routine', type: 'routine', title: item.name, text: String(value).trim(), scripture: '', reviewAt: '', source: `Daily Routine · ${sectionLabels[item.section]?.[0] || 'Routine'}`, createdAt, updatedAt: createdAt, completedAt: '', readOnly: true });
      });
    });
    state.memories.forEach(memory => {
      records.push({ id: `memory:${memory.id}`, kind: 'memory', type: 'memory', title: memoryCategoryLabel(memory.category), text: memory.text, scripture: '', reviewAt: '', source: 'Memory Bank', createdAt: validDateValue(memory.createdAt) || new Date().toISOString(), updatedAt: validDateValue(memory.createdAt) || new Date().toISOString(), completedAt: memory.archived ? validDateValue(memory.createdAt) : '', readOnly: true, favorite: Boolean(memory.favorite), archived: Boolean(memory.archived) });
    });
    return records;
  }

  function renderNotes() {
    if (!els.notesList) return;
    const now = Date.now();
    const search = els.notesSearchInput.value.trim().toLowerCase();
    const typeFilter = els.notesTypeFilter.value;
    const statusFilter = els.notesStatusFilter.value;
    const standaloneOpen = state.notes.filter(note => !noteIsClosed(note)).length;
    const godMoments = state.notes.filter(note => note.type === 'god-moment').length;
    const due = state.notes.filter(note => noteIsDue(note, now)).length;
    els.notesOpenCount.textContent = String(standaloneOpen);
    els.godMomentCount.textContent = String(godMoments);
    els.notesDueCount.textContent = String(due);

    let records = allNoteRecords().filter(note => {
      if (typeFilter !== 'all' && note.type !== typeFilter) return false;
      const isCompleted = noteIsClosed(note);
      const isDue = noteIsDue(note, now);
      const isSnoozed = noteIsSnoozed(note, now);
      if (statusFilter === 'open' && isCompleted) return false;
      if (statusFilter === 'completed' && !isCompleted) return false;
      if (statusFilter === 'due' && !isDue) return false;
      if (statusFilter === 'snoozed' && !isSnoozed) return false;
      if (statusFilter === 'pinned' && !note.pinned) return false;
      if (statusFilter === 'answered' && !(note.type === 'prayer' && note.prayerStatus === 'answered')) return false;
      if (!search) return true;
      return [note.title, note.text, note.scripture, note.source, noteTypeLabels[note.type]].some(value => String(value || '').toLowerCase().includes(search));
    });
    records.sort((a, b) => {
      const aDue = noteIsDue(a, now) ? 1 : 0;
      const bDue = noteIsDue(b, now) ? 1 : 0;
      return Number(Boolean(b.pinned)) - Number(Boolean(a.pinned)) || bDue - aDue || new Date(b.createdAt) - new Date(a.createdAt);
    });
    els.notesResultsTitle.textContent = typeFilter === 'all' ? 'All notes' : noteTypeLabels[typeFilter] || 'Notes';
    els.notesResultCount.textContent = `${records.length} shown`;
    if (!records.length) {
      els.notesList.innerHTML = '<div class="empty-state notes-empty">No notes match these filters. Capture a thought or clear a filter to begin.</div>';
      renderReflectionReview();
      return;
    }
    els.notesList.innerHTML = records.map(note => noteCardHtml(note, now)).join('');
    els.notesList.querySelectorAll('[data-edit-note]').forEach(button => button.addEventListener('click', () => {
      const note = state.notes.find(candidate => candidate.id === button.dataset.editNote);
      if (note) openNoteDialog(note);
    }));
    els.notesList.querySelectorAll('[data-toggle-note]').forEach(button => button.addEventListener('click', () => toggleNoteCompletion(button.dataset.toggleNote)));
    els.notesList.querySelectorAll('[data-pin-note]').forEach(button => button.addEventListener('click', () => toggleNotePinned(button.dataset.pinNote)));
    els.notesList.querySelectorAll('[data-prayer-status]').forEach(button => button.addEventListener('click', () => setPrayerStatus(button.dataset.prayerStatus, button.dataset.status)));
    els.notesList.querySelectorAll('[data-god-moment-from-prayer]').forEach(button => button.addEventListener('click', () => createGodMomentFromPrayer(button.dataset.godMomentFromPrayer)));
    renderReflectionReview();
  }

  function noteCardHtml(note, now) {
    const completed = noteIsClosed(note);
    const due = noteIsDue(note, now);
    const snoozed = noteIsSnoozed(note, now);
    const actionable = note.kind === 'standalone' && ['action', 'review'].includes(note.type);
    const classes = ['note-card', `note-${note.type}`, completed ? 'completed' : '', due ? 'due' : '', note.pinned ? 'pinned' : ''].filter(Boolean).join(' ');
    const scripture = note.scripture ? `<blockquote class="note-scripture"><span>Remember first</span>${escapeHtml(note.scripture)}</blockquote>` : '';
    const review = note.reviewAt ? `<span class="note-review${due ? ' due' : ''}">${due ? 'Ready to review' : 'Review'} · ${escapeHtml(formatNoteDate(note.reviewAt))}</span>` : '';
    const snooze = snoozed ? `<span class="note-snoozed">Snoozed until ${escapeHtml(formatNoteDate(note.snoozedUntil))}</span>` : '';
    const prayerLabel = note.type === 'prayer' ? `<span class="note-prayer-status ${escapeHtml(note.prayerStatus || 'active')}">${note.prayerStatus === 'answered' ? 'Answered' : note.prayerStatus === 'archived' ? 'Archived' : 'Still praying'}</span>` : '';
    const status = completed && note.type !== 'prayer' ? `<span class="note-completed">Completed ${escapeHtml(formatNoteDate(note.completedAt))}</span>` : '';
    let prayerActions = '';
    if (note.type === 'prayer') {
      prayerActions = note.prayerStatus === 'active'
        ? `<button class="primary-button" type="button" data-prayer-status="${escapeHtml(note.id)}" data-status="answered">Answered</button><button class="small-button" type="button" data-prayer-status="${escapeHtml(note.id)}" data-status="archived">Archive</button>`
        : `<button class="secondary-button" type="button" data-prayer-status="${escapeHtml(note.id)}" data-status="active">Pray again</button>${note.prayerStatus === 'answered' ? `<button class="small-button" type="button" data-god-moment-from-prayer="${escapeHtml(note.id)}">Save as God Moment</button>` : ''}`;
    }
    const actions = note.kind === 'standalone' ? `<div class="note-actions">${actionable ? `<button class="${completed ? 'secondary-button' : 'primary-button'}" type="button" data-toggle-note="${escapeHtml(note.id)}">${completed ? 'Reopen' : 'Complete'}</button>` : ''}${prayerActions}<button class="small-button pin-note-button" type="button" data-pin-note="${escapeHtml(note.id)}">${note.pinned ? 'Unpin' : 'Pin'}</button><button class="small-button" type="button" data-edit-note="${escapeHtml(note.id)}">Edit / move</button></div>` : '<span class="read-only-note">Shown from its original source</span>';
    return `<article class="${classes}"><div class="note-card-head"><span class="note-type-badge">${escapeHtml(noteTypeLabels[note.type] || note.title)}</span>${note.pinned || note.favorite ? '<span class="note-favorite" aria-label="Pinned">★</span>' : ''}</div>${note.title && !['standalone'].includes(note.kind) ? `<h3>${escapeHtml(note.title)}</h3>` : ''}${scripture}<p>${escapeHtml(note.text)}</p><div class="note-meta"><span>${escapeHtml(formatNoteDate(note.createdAt))}</span><span>${escapeHtml(note.source || 'Daily Routine')}</span>${review}${snooze}${prayerLabel}${status}</div>${actions}</article>`;
  }

  function formatNoteDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', year: date.getFullYear() === new Date().getFullYear() ? undefined : 'numeric', hour: 'numeric', minute: '2-digit' }).format(date);
  }

  function openNoteDialog(note = null, prefill = {}) {
    const source = normalizeNoteSource(prefill.source || note?.source || 'Daily Routine');
    els.editingNoteId.value = note?.id || '';
    els.noteDialogTitle.textContent = note ? 'Edit note' : 'Add a note';
    els.noteTextInput.value = prefill.text || note?.text || '';
    els.noteTypeInput.value = normalizeNoteType(prefill.type || note?.type || 'entrust');
    els.noteScriptureInput.value = note?.scripture || '';
    els.notePrayerStatusInput.value = note?.prayerStatus || 'active';
    els.noteReviewAtInput.value = note?.reviewAt ? localDateTimeValue(new Date(note.reviewAt)) : '';
    els.noteSnoozedUntilInput.value = note?.snoozedUntil ? localDateTimeValue(new Date(note.snoozedUntil)) : '';
    els.noteSourceInput.value = [...els.noteSourceInput.options].some(option => option.value === source) ? source : 'Daily Routine';
    els.notePinnedInput.checked = Boolean(note?.pinned);
    els.noteResurfaceInput.checked = note?.resurface === undefined ? true : Boolean(note.resurface);
    els.deleteNoteButton.hidden = !note;
    toggleNoteFields();
    els.noteDialog.showModal();
    setTimeout(() => els.noteTextInput.focus(), 0);
  }

  function normalizeNoteType(value) {
    const aliases = { later: 'review', 'review-later': 'review', task: 'action', 'action-item': 'action', godmoment: 'god-moment', 'god-moments': 'god-moment', thought: 'general' };
    const type = aliases[String(value || '').toLowerCase()] || String(value || '').toLowerCase();
    return ['entrust', 'review', 'action', 'prayer', 'god-moment', 'general'].includes(type) ? type : 'general';
  }

  function normalizeNoteSource(value) {
    const aliases = { watch: 'Apple Watch', applewatch: 'Apple Watch', pushcut: 'Pushcut', shortcut: 'Shortcut', 'apple-notes': 'Apple Notes', notes: 'Apple Notes', app: 'Daily Routine' };
    const raw = String(value || '').trim();
    return aliases[raw.toLowerCase()] || raw || 'Daily Routine';
  }

  function toggleNoteFields() {
    const type = els.noteTypeInput.value;
    els.noteScriptureField.hidden = type !== 'prayer';
    els.notePrayerStatusField.hidden = type !== 'prayer';
    els.noteResurfaceField.hidden = type !== 'god-moment';
  }

  function saveNote(event) {
    event.preventDefault();
    const text = els.noteTextInput.value.trim();
    if (!text) return;
    const now = new Date().toISOString();
    const existing = state.notes.find(note => note.id === els.editingNoteId.value);
    const next = normalizeNote({
      ...(existing || {}),
      id: existing?.id || `note-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      text,
      type: els.noteTypeInput.value,
      scripture: els.noteScriptureInput.value.trim(),
      reviewAt: els.noteReviewAtInput.value ? new Date(els.noteReviewAtInput.value).toISOString() : '',
      snoozedUntil: els.noteSnoozedUntilInput.value ? new Date(els.noteSnoozedUntilInput.value).toISOString() : '',
      source: els.noteSourceInput.value,
      createdAt: existing?.createdAt || now,
      updatedAt: now,
      completedAt: els.noteTypeInput.value === 'prayer' && ['answered', 'archived'].includes(els.notePrayerStatusInput.value) ? (existing?.completedAt || now) : els.noteTypeInput.value === 'prayer' ? '' : existing?.completedAt || '',
      prayerStatus: els.noteTypeInput.value === 'prayer' ? els.notePrayerStatusInput.value : '',
      answeredAt: els.noteTypeInput.value === 'prayer' && els.notePrayerStatusInput.value === 'answered' ? (existing?.answeredAt || now) : '',
      pinned: els.notePinnedInput.checked,
      resurface: els.noteTypeInput.value === 'god-moment' && els.noteResurfaceInput.checked,
      migrationKey: existing?.migrationKey || ''
    });
    if (existing) Object.assign(existing, next); else state.notes.push(next);
    saveState();
    els.noteDialog.close();
    renderAll();
    showToast(existing ? 'Note updated' : next.type === 'entrust' ? 'Captured. You do not need to resolve this now.' : 'Note saved');
  }

  function deleteNote() {
    const id = els.editingNoteId.value;
    const note = state.notes.find(candidate => candidate.id === id);
    if (!note || !confirm('Delete this standalone note? This cannot be undone.')) return;
    state.notes = state.notes.filter(candidate => candidate.id !== id);
    saveState(); els.noteDialog.close(); renderAll(); showToast('Note deleted');
  }

  function toggleNoteCompletion(id) {
    const note = state.notes.find(candidate => candidate.id === id);
    if (!note || !['action', 'review'].includes(note.type)) return;
    note.completedAt = note.completedAt ? '' : new Date().toISOString();
    note.updatedAt = new Date().toISOString();
    saveState(); renderNotes(); showToast(note.completedAt ? 'Note completed' : 'Note reopened');
  }

  function toggleNotePinned(id) {
    const note = state.notes.find(candidate => candidate.id === id);
    if (!note) return;
    note.pinned = !note.pinned;
    note.updatedAt = new Date().toISOString();
    saveState(); renderNotes(); showToast(note.pinned ? 'Note pinned' : 'Note unpinned');
  }

  function setPrayerStatus(id, status) {
    const note = state.notes.find(candidate => candidate.id === id && candidate.type === 'prayer');
    if (!note || !['active', 'answered', 'archived'].includes(status)) return;
    const now = new Date().toISOString();
    note.prayerStatus = status;
    note.answeredAt = status === 'answered' ? now : '';
    note.completedAt = status === 'active' ? '' : now;
    note.updatedAt = now;
    saveState(); renderNotes();
    showToast(status === 'answered' ? 'Prayer marked answered' : status === 'archived' ? 'Prayer archived' : 'Prayer reopened');
  }

  function createGodMomentFromPrayer(id) {
    const prayer = state.notes.find(candidate => candidate.id === id && candidate.type === 'prayer');
    if (!prayer) return;
    const duplicate = state.notes.some(note => note.type === 'god-moment' && note.text === prayer.text && note.source === 'Answered prayer');
    if (duplicate) { showToast('This answered prayer is already a God Moment'); return; }
    const now = new Date().toISOString();
    state.notes.push(normalizeNote({ text: prayer.text, type: 'god-moment', scripture: prayer.scripture, source: 'Answered prayer', createdAt: prayer.answeredAt || now, updatedAt: now, resurface: true, pinned: prayer.pinned }));
    saveState(); renderNotes(); showToast('Answered prayer saved as a God Moment');
  }

  function renderReflectionReview() {
    if (!els.reflectionReviewCard) return;
    const now = Date.now();
    const weekStart = startOfCurrentWeek();
    const due = state.notes.filter(note => noteIsDue(note, now));
    const actions = state.notes.filter(note => note.type === 'action' && !noteIsClosed(note) && !noteIsSnoozed(note, now));
    const prayers = state.notes.filter(note => note.type === 'prayer' && note.prayerStatus === 'active' && !noteIsSnoozed(note, now));
    const moments = state.notes.filter(note => note.type === 'god-moment' && new Date(note.createdAt).getTime() >= weekStart.getTime());
    els.reviewDueCount.textContent = String(due.length);
    els.reviewActionCount.textContent = String(actions.length);
    els.reviewPrayerCount.textContent = String(prayers.length);
    els.reviewMomentCount.textContent = String(moments.length);
    els.reflectionReviewPanel.hidden = !reflectionReviewExpanded;
    els.toggleReflectionReviewButton.textContent = reflectionReviewExpanded ? 'Close review' : 'Begin review';
    els.toggleReflectionReviewButton.setAttribute('aria-expanded', String(reflectionReviewExpanded));
    const review = state.weeklyReviews?.[currentWeekKey()] || {};
    els.reflectionReviewStatus.textContent = review.reviewedAt
      ? `Last completed ${formatNoteDate(review.reviewedAt)}. You can return anytime this week.`
      : 'Return to what needs prayer, action, or remembrance without carrying everything at once.';
    if (!reflectionReviewExpanded) return;
    els.weeklyReflectionInput.value = review.reflection || '';
    els.reflectionReviewLists.innerHTML = [
      reviewGroupHtml('Ready to review', due, 'due'),
      reviewGroupHtml('Open action items', actions, 'action'),
      reviewGroupHtml('Still praying', prayers, 'prayer'),
      reviewGroupHtml('God Moments this week', moments, 'god-moment')
    ].join('');
    els.reflectionReviewLists.querySelectorAll('[data-review-note]').forEach(button => button.addEventListener('click', () => {
      const note = state.notes.find(candidate => candidate.id === button.dataset.reviewNote);
      if (note) openNoteDialog(note);
    }));
    els.reflectionReviewLists.querySelectorAll('[data-review-filter]').forEach(button => button.addEventListener('click', () => {
      const filter = button.dataset.reviewFilter;
      els.notesSearchInput.value = '';
      if (filter === 'due') { els.notesTypeFilter.value = 'all'; els.notesStatusFilter.value = 'due'; }
      else { els.notesTypeFilter.value = filter; els.notesStatusFilter.value = 'all'; }
      renderNotes();
      els.notesList.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }));
  }

  function reviewGroupHtml(title, notes, filter) {
    const rows = [...notes].sort((a, b) => Number(Boolean(b.pinned)) - Number(Boolean(a.pinned)) || new Date(b.updatedAt) - new Date(a.updatedAt)).slice(0, 4);
    const content = rows.length
      ? rows.map(note => `<button class="reflection-note-row" type="button" data-review-note="${escapeHtml(note.id)}"><span>${note.pinned ? '★ ' : ''}${escapeHtml(note.text.length > 110 ? `${note.text.slice(0, 107)}…` : note.text)}</span><small>${escapeHtml(noteTypeLabels[note.type] || 'Note')} · ${escapeHtml(formatNoteDate(note.createdAt))}</small></button>`).join('')
      : '<p class="reflection-empty">Nothing waiting here.</p>';
    return `<section class="reflection-review-group"><div><h3>${escapeHtml(title)}</h3>${notes.length ? `<button type="button" data-review-filter="${escapeHtml(filter)}">View all ${notes.length}</button>` : ''}</div>${content}</section>`;
  }

  function finishReflectionReview() {
    const key = currentWeekKey();
    state.weeklyReviews[key] = { ...(state.weeklyReviews[key] || {}), reflection: els.weeklyReflectionInput.value.trim(), reviewedAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    saveState();
    reflectionReviewExpanded = false;
    renderReflectionReview();
    showToast('Weekly review complete');
  }

  async function importGodMoments(event) {
    const files = [...(event.target.files || [])]; event.target.value = '';
    if (!files.length) return;
    let imported = 0, skipped = 0;
    for (const file of files) {
      try {
        const text = cleanImportedMarkdown(await file.text(), file.name);
        if (!text || state.notes.some(note => note.type === 'god-moment' && note.text === text)) { skipped += 1; continue; }
        state.notes.push(normalizeNote({ text, type: 'god-moment', source: 'Apple Notes', createdAt: new Date(file.lastModified || Date.now()).toISOString(), resurface: true }));
        imported += 1;
      } catch { skipped += 1; }
    }
    if (imported) saveState();
    renderAll();
    showToast(`${imported} God Moment${imported === 1 ? '' : 's'} imported${skipped ? ` · ${skipped} skipped` : ''}`);
  }

  function cleanImportedMarkdown(content, filename) {
    let text = String(content || '')
      .replace(/^---\s*\n[\s\S]*?\n---\s*(?:\n|$)/, '')
      .replace(/^#{1,6}\s+/gm, '')
      .replace(/\[([^\]]+)]\([^)]+\)/g, '$1')
      .trim();
    const fallbackTitle = String(filename || '').replace(/\.(md|markdown|txt)$/i, '').trim();
    if (!text && fallbackTitle) text = fallbackTitle;
    return text;
  }

  function consumeQuickCapture() {
    const params = new URLSearchParams(location.search);
    const capture = params.get('capture');
    if (!capture || !['1', 'true', 'note', 'thought'].includes(capture.toLowerCase())) return;
    switchView('notes');
    openNoteDialog(null, { text: params.get('text') || '', type: params.get('type') || 'general', source: params.get('source') || 'Daily Routine' });
    const clean = new URL(location.href);
    ['capture', 'text', 'type', 'source'].forEach(key => clean.searchParams.delete(key));
    history.replaceState({}, '', clean.pathname + clean.search + clean.hash);
  }

  function renderGodMomentReminder() {
    if (!els.godMomentReminder) return;
    const eligible = state.notes.filter(note => note.type === 'god-moment' && note.resurface !== false && !note.completedAt);
    const frequency = state.settings.resurfacingFrequency || 'occasional';
    const allowedDays = frequency === 'weekly' ? [0] : frequency === 'never' ? [] : [1, 3, 6];
    const showToday = isSameDay(selectedDate, startOfToday()) && allowedDays.includes(new Date().getDay());
    if (!eligible.length || !showToday) { els.godMomentReminder.hidden = true; return; }
    const index = Math.abs(hashString(`${dateKey(startOfToday())}:${eligible.length}`)) % eligible.length;
    const note = eligible[index];
    els.godMomentReminderText.textContent = note.text;
    els.godMomentReminderDate.textContent = formatNoteDate(note.createdAt);
    els.godMomentReminder.hidden = false;
  }

  function renderBackupReminder() {
    if (!els.backupReminder) return;
    const today = startOfToday();
    const lastBackup = state.settings.lastBackupAt ? new Date(state.settings.lastBackupAt) : null;
    const firstUse = state.settings.firstUseDate ? fromDateKey(state.settings.firstUseDate) : today;
    const daysSinceBackup = lastBackup && !Number.isNaN(lastBackup.getTime()) ? Math.floor((today - lastBackup) / 86400000) : null;
    const daysUsingApp = Math.max(0, Math.floor((today - firstUse) / 86400000));
    const due = daysSinceBackup !== null ? daysSinceBackup >= 30 : daysUsingApp >= 30;
    els.backupReminder.hidden = !due || !isSameDay(selectedDate, today);
    els.backupReminderText.textContent = daysSinceBackup === null ? 'Your routine and notes live only on this device. Download a backup to protect them.' : `Your last downloaded backup was ${daysSinceBackup} days ago.`;
  }

  function hashString(value) {
    let hash = 0;
    for (let i = 0; i < value.length; i += 1) hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
    return hash;
  }

  function renderAll() { renderToday(); renderNotes(); renderHistory(); renderSetup(); }

  function renderToday() {
    const day = state.days[dateKey(selectedDate)] || { entries: {} };
    const today = startOfToday();
    els.heroGreeting.textContent = greetingForHour(new Date().getHours());
    els.heroDate.textContent = new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' }).format(selectedDate);
    els.wakeTimeDisplay.textContent = formatTime(state.settings.wakeTime);
    els.bedTimeDisplay.textContent = formatTime(state.settings.bedTime);
    els.actualWakeInput.value = day.actualWakeTime || '';
    els.actualBedInput.value = day.actualBedTime || '';
    els.dayModeInput.value = day.mode || 'normal';
    els.datePickerInput.value = dateKey(selectedDate);
    renderWeekFocusBanner();
    renderOnThisDay();
    renderGodMomentReminder();
    renderBackupReminder();
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
      const scored = items.filter(item => !day.skippedItems?.[item.id]);
      const required = scored.filter(item => !item.optional);
      const logged = required.filter(item => entryMeetsTarget(item, day.entries?.[item.id])).length;
      const routineItems = items.filter(item => item.kind !== 'checkin');
      const checkinItems = items.filter(item => item.kind === 'checkin');
      const [title, subtitle] = sectionLabels[section];
      const wrapper = document.createElement('section');
      const isCollapsed = collapsedSections.has(section);
      const checkboxItems = routineItems.filter(item => item.type === 'checkbox' && !day.skippedItems?.[item.id] && !entryIsLogged(item, day.entries?.[item.id]));
      wrapper.className = `routine-section${isCollapsed ? ' collapsed' : ''}`;
      wrapper.innerHTML = `<div class="card"><div class="section-heading"><div><p class="eyebrow">${escapeHtml(subtitle)}</p><h2>${escapeHtml(title)}</h2></div><div class="section-tools"><span class="section-progress">${logged}/${required.length}</span>${checkboxItems.length ? '<button class="tiny-action check-all" type="button">Check all</button>' : ''}<button class="tiny-action collapse-section" type="button">${isCollapsed ? 'Show' : 'Hide'}</button></div></div><div class="section-body"><div class="task-list routine-task-list"></div><div class="checkin-slot"></div></div></div>`;
      const routineList = wrapper.querySelector('.routine-task-list');
      const checkinSlot = wrapper.querySelector('.checkin-slot');
      if (!routineItems.length) routineList.innerHTML = '<div class="empty-state compact-empty">No routine items scheduled.</div>';
      else routineItems.forEach(item => {
        const row = day.skippedItems?.[item.id] ? buildSkippedRow(item) : buildTaskRow(item, day.entries?.[item.id]);
        if (!day.skippedItems?.[item.id]) decorateRoutineRow(row, item);
        routineList.appendChild(row);
      });
      if (checkinItems.length) {
        const panel = document.createElement('div');
        panel.className = 'checkin-panel';
        panel.innerHTML = `<div class="checkin-heading"><span>${escapeHtml(title)} check-in</span><small>${checkinItems.filter(item => entryIsLogged(item, day.entries?.[item.id])).length}/${checkinItems.length} logged</small></div><div class="checkin-list"></div>`;
        const list = panel.querySelector('.checkin-list');
        checkinItems.forEach(item => list.appendChild(day.skippedItems?.[item.id] ? buildSkippedRow(item) : buildCheckinRow(item, day.entries?.[item.id])));
        checkinSlot.appendChild(panel);
      }
      wrapper.querySelector('.collapse-section').addEventListener('click', () => { collapsedSections.has(section) ? collapsedSections.delete(section) : collapsedSections.add(section); renderToday(); });
      wrapper.querySelector('.check-all')?.addEventListener('click', () => completeSectionCheckboxes(section));
      els.routineSections.appendChild(wrapper);
    });
  }

  function decorateRoutineRow(row, item) {
    const utility = document.createElement('div');
    utility.className = 'task-utility';
    utility.innerHTML = `<button class="skip-item" type="button">Skip this day</button>`;
    utility.querySelector('button').addEventListener('click', () => skipItemToday(item));
    row.appendChild(utility);
  }

  function buildSkippedRow(item) {
    const row = document.createElement('div');
    row.className = 'task-row skipped';
    row.innerHTML = `<div class="task-main"><span class="skip-mark">↷</span><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">Skipped for this day · does not lower completion</span></span><button class="small-button unskip-item" type="button">Undo skip</button></div>`;
    row.querySelector('.unskip-item').addEventListener('click', () => unskipItemToday(item));
    return row;
  }

  function skipItemToday(item) {
    const key = dateKey(selectedDate), day = ensureDay(key), previous = Boolean(day.skippedItems[item.id]);
    day.skippedItems[item.id] = true;
    pushUndo(`Skip ${item.name}`, () => { const target = ensureDay(key); if (previous) target.skippedItems[item.id] = true; else delete target.skippedItems[item.id]; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); renderToday(); renderHistory(); showToast(`${item.name} skipped today`);
  }

  function unskipItemToday(item) {
    const key = dateKey(selectedDate), day = ensureDay(key);
    delete day.skippedItems[item.id]; saveState(); renderToday(); renderHistory(); showToast('Skip removed');
  }

  function completeSectionCheckboxes(section) {
    const key = dateKey(selectedDate), day = ensureDay(key), changed = [];
    scheduledItemsForDate(selectedDate).filter(item => item.section === section && item.type === 'checkbox' && !day.skippedItems?.[item.id]).forEach(item => {
      if (day.entries[item.id] !== true) { changed.push([item.id, day.entries[item.id]]); day.entries[item.id] = true; }
    });
    if (!changed.length) return;
    pushUndo('Check all', () => { const target = ensureDay(key); changed.forEach(([id, value]) => value === undefined ? delete target.entries[id] : target.entries[id] = value); localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); renderToday(); renderHistory(); showToast('Checkboxes completed');
  }

  function metaForItem(item) {
    const bits = [item.optional ? 'Optional' : 'Required', frequencyLabel(item)];
    if (hasTarget(item)) bits.push(`Target ${item.target}${item.unit ? ` ${item.unit}` : ''}`);
    const timing = timeWindowStatus(item, selectedDate);
    if (timing.label) bits.push(timing.label);
    return bits.join(' · ');
  }

  function buildTaskRow(item, value) {
    const row = document.createElement('div');
    row.className = `task-row${entryMeetsTarget(item, value) ? ' done' : ''}`;
    if (item.type === 'linked') return buildLinkedRow(row, item, value);
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
      container.innerHTML = `<div class="number-entry"><input class="task-input inline-number" type="number" step="any" inputmode="decimal" value="${escapeHtml(value ?? '')}" placeholder="0"/><span>${escapeHtml(item.unit || '')}</span>${hasTarget(item) ? `<small>/ ${escapeHtml(item.target)} ${escapeHtml(item.unit || '')}</small>` : ''}</div>`;
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
    const key = dateKey(selectedDate), day = ensureDay(key);
    const hadPrevious = Object.prototype.hasOwnProperty.call(day.entries, item.id);
    const previous = structuredClone(day.entries[item.id]);
    day.entries[item.id] = value;
    if (rerender) pushUndo(`Update ${item.name}`, () => { const target = ensureDay(key); if (hadPrevious) target.entries[item.id] = previous; else delete target.entries[item.id]; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
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
    els.heroStatus.textContent = c.excused ? `${dayModeLabel(day.mode)} · this day is excused from routine analytics.` : c.percent === 100 ? 'Day complete. Nicely done.' : c.percent >= Number(state.settings.streakThreshold || 80) ? 'Strong day. Keep closing it out.' : c.percent >= 40 ? 'Good progress. Keep moving.' : 'Start deliberately.';
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
    renderWeeklyReview();
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
      if (!c.total || c.excused) return;
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
      const c = unavailable ? null : completionForDate(date), percent = c?.percent ?? 0, excused = Boolean(c?.excused);
      return `<button type="button" class="week-day${isSameDay(date, today) ? ' today' : ''}${unavailable ? ' unavailable' : ''}${excused ? ' excused' : ''}" data-date="${dateKey(date)}" ${unavailable ? 'disabled' : ''}><span class="week-label">${escapeHtml(new Intl.DateTimeFormat(undefined, { weekday: 'narrow' }).format(date))}</span><div class="week-track"><span style="height:${unavailable || excused ? 0 : percent}%"></span></div><strong>${unavailable ? '—' : excused ? 'Skip' : `${percent}%`}</strong><small>${date.getDate()}</small></button>`;
    }).join('');
    els.weekSummary.querySelectorAll('.week-day:not(:disabled)').forEach(button => button.addEventListener('click', () => { selectedDate = fromDateKey(button.dataset.date); switchView('today'); renderToday(); }));
  }

  function renderSectionBreakdown() {
    const dates = activeRangeDates();
    els.sectionBreakdown.innerHTML = ['morning', 'day', 'evening'].map(section => {
      let completed = 0, total = 0;
      dates.forEach(date => {
        if (dayIsExcused(date)) return;
        const day = state.days[dateKey(date)] || { entries: {} };
        scoredItemsForDate(date).filter(item => item.section === section && !item.optional).forEach(item => { total += 1; if (entryMeetsTarget(item, day.entries?.[item.id])) completed += 1; });
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
        if (dayIsExcused(date) || !scoredItemsForDate(date).some(candidate => candidate.id === item.id)) return;
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
      row.innerHTML = `<span class="history-date"><strong>${date.getDate()}</strong><span>${new Intl.DateTimeFormat(undefined, { month: 'short' }).format(date)}</span></span><span class="history-copy"><strong>${new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(date)}${i === 0 ? ' · Today' : ''}</strong><span>${c.excused ? `${dayModeLabel(day.mode)} · excused` : `${c.completed} of ${c.total} required`}</span><span class="history-bar"><span style="width:${c.excused ? 0 : c.percent}%"></span></span></span><span class="history-mood">Mood<br><b>${getLatestMood(day) ?? '—'}</b></span>`;
      row.addEventListener('click', () => { selectedDate = date; switchView('today'); renderToday(); });
      els.historyList.appendChild(row);
    }
  }

  function formatShortDate(date) { return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date); }

  function renderSetup() {
    els.wakeTimeInput.value = state.settings.wakeTime;
    els.bedTimeInput.value = state.settings.bedTime;
    els.badgeEnabledInput.checked = state.settings.badgeEnabled !== false;
    els.streakThresholdInput.value = Number(state.settings.streakThreshold) || 80;
    els.streakModeInput.value = state.settings.streakMode || 'forgiving';
    els.streakWeekdaysOnlyInput.checked = Boolean(state.settings.streakWeekdaysOnly);
    els.themeInput.value = state.settings.theme || 'calm';
    els.resurfacingFrequencyInput.value = ['occasional', 'weekly', 'never'].includes(state.settings.resurfacingFrequency) ? state.settings.resurfacingFrequency : 'occasional';
    els.appVersion.textContent = `v${APP_VERSION}`;
    els.bibleAppUrlInput.value = state.settings.bibleAppUrl || DEFAULT_BIBLE_APP_URL;
    renderConnections();
    renderSnapshotStatus();
    renderBackupDownloadStatus();
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
        const pauseText = item.pausedFrom && item.pausedUntil && dateKey(startOfToday()) <= item.pausedUntil ? ` · Paused through ${formatShortDate(fromDateKey(item.pausedUntil))}` : '';
        row.innerHTML = `<div class="editor-copy"><strong>${escapeHtml(item.name)}</strong><span>${sectionLabels[section][0]} · ${escapeHtml(detail)}${item.optional ? ' · Optional' : ''}${escapeHtml(pauseText)}</span></div><div class="editor-actions"><button class="move-button" type="button" aria-label="Move up" ${index === 0 ? 'disabled' : ''}>↑</button><button class="move-button" type="button" aria-label="Move down" ${index === sectionItems.length - 1 ? 'disabled' : ''}>↓</button><button class="edit-button duplicate-button" type="button">Copy</button><button class="edit-button" type="button">Edit</button></div>`;
        const buttons = row.querySelectorAll('button');
        buttons[0].addEventListener('click', () => moveItem(item, -1));
        buttons[1].addEventListener('click', () => moveItem(item, 1));
        buttons[2].addEventListener('click', () => duplicateItem(item));
        buttons[3].addEventListener('click', () => openItemDialog(item, kind));
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

  function duplicateItem(item) {
    const copy = structuredClone(item);
    copy.id = `item-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    copy.name = `${item.name} copy`;
    copy.createdDate = dateKey(startOfToday());
    copy.pausedFrom = ''; copy.pausedUntil = '';
    const same = state.items.filter(candidate => candidate.kind === item.kind && candidate.section === item.section);
    copy.order = same.reduce((max, candidate) => Math.max(max, Number(candidate.order) || 0), -1) + 1;
    state.items.push(copy); saveState(); renderAll(); showToast('Routine item duplicated');
  }

  function openItemDialog(item = null, kind = 'routine', template = '') {
    const resolvedKind = item?.kind || kind;
    const preset = template ? linkedTemplateDefaults(template) : null;
    els.editingItemId.value = item?.id || '';
    els.editingItemKind.value = resolvedKind;
    els.builderEyebrow.textContent = resolvedKind === 'checkin' ? 'Check-in builder' : 'Routine builder';
    els.dialogTitle.textContent = item ? `Edit ${resolvedKind === 'checkin' ? 'check-in' : 'item'}` : `Add ${resolvedKind === 'checkin' ? 'check-in' : 'item'}`;
    els.itemNameInput.value = item?.name || preset?.name || '';
    els.itemNameInput.placeholder = resolvedKind === 'checkin' ? 'Example: How was your sleep?' : 'Example: Prayer';
    els.itemSectionInput.value = item?.section || preset?.section || 'morning';
    ['medication', 'memory', 'linked'].forEach(value => {
      const option = els.itemTypeInput.querySelector(`option[value="${value}"]`);
      option.hidden = option.disabled = resolvedKind === 'checkin';
    });
    const defaultType = resolvedKind === 'checkin' ? 'scale' : 'checkbox';
    els.itemTypeInput.value = item?.type || (preset ? 'linked' : defaultType);
    if (!els.itemTypeInput.value) els.itemTypeInput.value = defaultType;
    els.itemFrequencyInput.value = item?.frequency || 'daily';
    els.itemTargetInput.value = item?.target ?? '';
    els.itemUnitInput.value = item?.unit || '';
    els.itemPlaceholderInput.value = item?.placeholder || '';
    els.memoryCategoryInput.value = item?.memoryCategory || 'any';
    els.medicationDoseInput.value = item?.medicationDose || '';
    els.pauseUntilInput.value = item?.pausedUntil || '';
    els.itemOptionalInput.checked = item ? Boolean(item.optional) : resolvedKind === 'checkin';
    const linked = item || preset || {};
    els.linkedTemplateInput.value = linked.linkedTemplate || 'website';
    els.linkedCompletionInput.value = linked.linkedCompletion || 'manual';
    els.linkedUrlInput.value = linked.linkedUrl || '';
    els.linkedInternalTargetInput.value = linked.linkedInternalTarget || 'memory';
    els.linkedButtonLabelInput.value = linked.linkedButtonLabel || '';
    els.timeWindowStartInput.value = linked.timeWindowStart || '';
    els.timeWindowEndInput.value = linked.timeWindowEnd || '';
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
    const isCheckin = els.editingItemKind.value === 'checkin';
    els.numberGoalFields.hidden = type !== 'number';
    els.scaleFields.hidden = type !== 'scale';
    els.medicationFields.hidden = type !== 'medication';
    els.linkedActionFields.hidden = type !== 'linked';
    els.memoryFields.hidden = type !== 'memory';
    els.promptField.hidden = !['text', 'longtext'].includes(type);
    els.customDaysField.hidden = els.itemFrequencyInput.value !== 'custom';
    els.timeWindowFields.hidden = isCheckin;
    const internal = type === 'linked' && els.linkedTemplateInput.value === 'internal';
    els.linkedInternalField.hidden = !internal;
    els.linkedUrlField.hidden = type !== 'linked' || internal;
    if (type === 'linked' && els.linkedTemplateInput.value === 'bible') els.linkedCompletionInput.value = 'sync';
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
      target: type === 'number' && els.itemTargetInput.value !== '' && Number(els.itemTargetInput.value) > 0 ? Number(els.itemTargetInput.value) : null,
      placeholder: ['text', 'longtext'].includes(type) ? els.itemPlaceholderInput.value.trim() : '',
      memoryCategory: type === 'memory' ? els.memoryCategoryInput.value : 'any',
      medicationDose: type === 'medication' ? els.medicationDoseInput.value.trim() : '',
      linkedTemplate: type === 'linked' ? els.linkedTemplateInput.value : 'website',
      linkedCompletion: type === 'linked' ? els.linkedCompletionInput.value : 'manual',
      linkedUrl: type === 'linked' ? els.linkedUrlInput.value.trim() : '',
      linkedButtonLabel: type === 'linked' ? els.linkedButtonLabelInput.value.trim() : '',
      linkedInternalTarget: type === 'linked' ? els.linkedInternalTargetInput.value : 'memory',
      timeWindowStart: kind === 'routine' ? els.timeWindowStartInput.value : '',
      timeWindowEnd: kind === 'routine' ? els.timeWindowEndInput.value : '',
      pausedUntil: els.pauseUntilInput.value || '',
      pausedFrom: els.pauseUntilInput.value ? (state.items.find(candidate => candidate.id === els.editingItemId.value)?.pausedFrom || dateKey(startOfToday())) : '',
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
    createLocalSnapshot('Before deleting routine item', true);
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
    if (item.type === 'linked') {
      if (value === true) return 'Completed manually';
      if (value?.completed) return `${value.completed}/${value.total || value.completed} complete${value.completedAt ? ` · ${new Date(value.completedAt).toLocaleString()}` : ''}`;
      if (value && typeof value === 'object' && Number.isFinite(Number(value.completed))) return `${value.completed}/${value.total || 10}`;
      return 'Not completed';
    }
    if (item.type === 'medication') {
      if (value === true) return 'Taken (time not logged)';
      return value?.taken ? `Taken${value.time ? ` at ${formatTime(value.time)}` : ''}${value.dose ? ` · ${value.dose}` : ''}${value.note ? ` · ${value.note}` : ''}` : 'Not taken';
    }
    if (item.type === 'memory') {
      const memory = state.memories.find(candidate => candidate.id === value?.memoryId);
      return value?.reflected ? `Reflected${memory ? ` — ${memory.text}` : ''}` : 'Not reflected';
    }
    if (item.type === 'scale') { const scale = normalizeScale(item.scale); return `${value} (${formatNumber(scale.min)}–${formatNumber(scale.max)})`; }
    return `${value}${item.unit ? ` ${item.unit}` : ''}`;
  }

  function exportCsv() {
    const rows = [['Date', 'Day Mode', 'Actual Wake', 'Actual Bed', 'Completion %', 'Required Completed', 'Required Total', 'Optional Logged', 'Section', 'Kind', 'Item', 'Input Type', 'Optional', 'Target', 'Unit', 'Scale Min', 'Scale Max', 'Value']];
    Object.keys(state.days).sort().forEach(key => {
      const date = fromDateKey(key), day = state.days[key], c = completionForDate(date), scheduled = scheduledItemsForDate(date);
      if (!scheduled.length) rows.push([key, day.mode || 'normal', day.actualWakeTime || '', day.actualBedTime || '', c.percent, c.completed, c.total, c.optionalLogged, '', '', '', '', '', '', '', '', '', '']);
      else scheduled.forEach(item => {
        const scale = item.type === 'scale' ? normalizeScale(item.scale) : {};
        rows.push([key, day.mode || 'normal', day.actualWakeTime || '', day.actualBedTime || '', c.percent, c.completed, c.total, c.optionalLogged, sectionLabels[item.section][0], item.kind, item.name, typeLabels[item.type], item.optional ? 'Yes' : 'No', item.target ?? '', item.unit || '', scale.min ?? '', scale.max ?? '', formatEntry(item, day.entries?.[item.id] ?? '')]);
      });
    });
    downloadBlob(rows.map(row => row.map(csvCell).join(',')).join('\r\n'), `daily-routine-progress-${dateKey(startOfToday())}.csv`, 'text/csv;charset=utf-8');
    showToast('CSV exported');
  }

  function exportJson() {
    const exportedAt = new Date().toISOString();
    state.settings.lastBackupAt = exportedAt;
    saveState();
    downloadBlob(JSON.stringify({ version: 1.8, exportedAt, state }, null, 2), `daily-routine-backup-${dateKey(startOfToday())}.json`, 'application/json');
    renderSetup(); renderToday(); showToast('Backup downloaded');
  }

  async function importJson(event) {
    const file = event.target.files?.[0]; event.target.value = ''; if (!file) return;
    try {
      const payload = JSON.parse(await file.text()), incoming = payload.state || payload;
      if (!incoming || !Array.isArray(incoming.items) || typeof incoming.days !== 'object') throw new Error('Invalid backup');
      if (!confirm('Restore this backup? It will replace current app data on this device.')) return;
      createLocalSnapshot('Before backup restore', true);
      state = { settings: { ...DEFAULT_STATE.settings, ...(incoming.settings || {}) }, items: incoming.items.map(normalizeItem), days: incoming.days, memories: Array.isArray(incoming.memories) ? incoming.memories : [], notes: Array.isArray(incoming.notes) ? incoming.notes.map(normalizeNote).filter(note => note.text) : [], weeklyReviews: incoming.weeklyReviews && typeof incoming.weeklyReviews === 'object' ? incoming.weeklyReviews : {} };
      ensureFirstUseDate(); saveState(); applyPersonalization(); renderAll(); showToast('Backup restored');
    } catch { alert('That file does not look like a valid Daily Routine backup.'); }
  }

  function resetData() {
    if (!confirm('Reset all routines, notes, history, and settings on this device?')) return;
    createLocalSnapshot('Before app reset', true);
    state = structuredClone(DEFAULT_STATE); state.settings.firstUseDate = dateKey(startOfToday()); ensureFirstUseDate(); saveState(); selectedDate = startOfToday(); undoAction = null; applyPersonalization(); renderAll(); showToast('App reset');
  }

  function saveActualTime(field, value) {
    const key = dateKey(selectedDate), day = ensureDay(key), previous = day[field];
    if (value) day[field] = value; else delete day[field];
    pushUndo('Update actual time', () => { const target = ensureDay(key); if (previous) target[field] = previous; else delete target[field]; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); renderHistory(); showToast(value ? 'Actual time saved' : 'Actual time cleared');
  }

  function currentTimeValue() {
    const now = new Date();
    return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  }

  function medicationTime(value) {
    return value && typeof value === 'object' && value.taken ? (value.time || '') : '';
  }

  function buildMedicationRow(row, item, value) {
    const taken = entryIsLogged(item, value), time = medicationTime(value), dose = value?.dose ?? item.medicationDose ?? '', note = value?.note ?? '';
    row.classList.toggle('done', taken);
    row.innerHTML = `<div class="task-main medication-main"><span class="medication-icon" aria-hidden="true">Rx</span><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}${taken ? ` · ${time ? `Taken ${formatTime(time)}` : 'Taken · time not logged'}${dose ? ` · ${escapeHtml(dose)}` : ''}` : ''}</span></span></div><div class="medication-actions"></div>`;
    const actions = row.querySelector('.medication-actions');
    if (!taken) {
      actions.innerHTML = `<button class="primary-button medication-now" type="button">Taken now</button><button class="small-button medication-manual" type="button">Add time</button>`;
      actions.querySelector('.medication-now').addEventListener('click', () => logMedicationNow(item));
      actions.querySelector('.medication-manual').addEventListener('click', () => saveMedicationTime(item, currentTimeValue(), true));
    } else {
      actions.innerHTML = `<div class="medication-detail-grid"><label class="med-time-edit"><span>Taken at</span><input class="task-input med-time-input" type="time" value="${escapeHtml(time)}" /></label><label class="med-time-edit"><span>Dose</span><input class="task-input med-dose-input" type="text" maxlength="40" value="${escapeHtml(dose)}" placeholder="optional" /></label></div><label class="med-note-edit"><span>Note</span><input class="task-input med-note-input" type="text" maxlength="160" value="${escapeHtml(note)}" placeholder="Optional note…" /></label><div class="medication-finished"><span class="already-logged">✓ Already logged</span><button class="small-button medication-clear" type="button">Clear</button></div>`;
      actions.querySelector('.med-time-input').addEventListener('change', event => saveMedicationTime(item, event.target.value, true));
      actions.querySelector('.med-dose-input').addEventListener('change', event => saveMedicationDetail(item, 'dose', event.target.value));
      actions.querySelector('.med-note-input').addEventListener('change', event => saveMedicationDetail(item, 'note', event.target.value));
      actions.querySelector('.medication-clear').addEventListener('click', () => clearMedication(item));
    }
    return row;
  }

  function logMedicationNow(item) { saveMedicationTime(item, currentTimeValue(), true); }

  function saveMedicationTime(item, time, rerender = true) {
    const key = dateKey(selectedDate), day = ensureDay(key), previous = structuredClone(day.entries[item.id]);
    const selected = fromDateKey(key), existing = day.entries[item.id] && typeof day.entries[item.id] === 'object' ? day.entries[item.id] : {};
    if (time) {
      const [hours, minutes] = time.split(':').map(Number); selected.setHours(hours, minutes, 0, 0);
      day.entries[item.id] = { ...existing, taken: true, time, timestamp: selected.toISOString(), dose: existing.dose ?? item.medicationDose ?? '', note: existing.note ?? '' };
    } else day.entries[item.id] = { ...existing, taken: true, time: '', timestamp: null, dose: existing.dose ?? item.medicationDose ?? '', note: existing.note ?? '' };
    pushUndo(`Log ${item.name}`, () => { const target = ensureDay(key); if (previous === undefined) delete target.entries[item.id]; else target.entries[item.id] = previous; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); if (rerender) renderToday(); else renderStats(); showToast(time ? `Medication logged at ${formatTime(time)}` : 'Medication logged');
  }

  function saveMedicationDetail(item, field, value) {
    const day = ensureDay(dateKey(selectedDate)), entry = day.entries[item.id]; if (!entry || typeof entry !== 'object') return;
    entry[field] = value.trim(); saveState(); renderHistory(); showToast('Medication detail saved');
  }

  function clearMedication(item) {
    const key = dateKey(selectedDate), day = ensureDay(key), previous = structuredClone(day.entries[item.id]);
    delete day.entries[item.id];
    pushUndo(`Clear ${item.name}`, () => { ensureDay(key).entries[item.id] = previous; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); renderToday(); showToast('Medication log cleared');
  }

  function eligibleMemories(item) {
    const category = item.memoryCategory || 'any';
    return state.memories.filter(memory => !memory.archived && (category === 'any' || memory.category === category));
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
    state.memories.push({ id: `memory-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, text, category: els.memoryCategoryCaptureInput.value, createdAt, favorite: false, archived: false });
    saveState(); els.memoryDialog.close(); renderAll(); showToast('Memory saved');
  }

  function renderMemoryPreview() {
    const memories = state.memories.filter(memory => !memory.archived).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    if (!memories.length) {
      els.memoryTodayPreview.innerHTML = '<span class="muted">Capture small blessings, moments, prayers, or thoughts so the app can bring them back later.</span>';
      return;
    }
    const latest = memories[0];
    els.memoryTodayPreview.innerHTML = `<div><strong>${state.memories.length} saved</strong><span>Latest · ${escapeHtml(memoryCategoryLabel(latest.category))} · ${escapeHtml(formatMemoryDate(latest.createdAt))}</span></div><p>${escapeHtml(latest.text)}</p>`;
  }

  function renderMemoryArchive() {
    const activeCount = state.memories.filter(memory => !memory.archived).length;
    els.memoryCount.textContent = activeCount;
    const query = (els.memorySearchInput?.value || '').trim().toLowerCase();
    const filter = els.memoryFilterInput?.value || 'all';
    const favoritesOnly = Boolean(els.memoryFavoritesOnlyInput?.checked);
    let memories = [...state.memories];
    memories = memories.filter(memory => {
      if (filter === 'archived') { if (!memory.archived) return false; }
      else { if (memory.archived) return false; if (filter !== 'all' && memory.category !== filter) return false; }
      if (favoritesOnly && !memory.favorite) return false;
      if (query && !`${memory.text} ${memoryCategoryLabel(memory.category)}`.toLowerCase().includes(query)) return false;
      return true;
    }).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 100);
    if (!memories.length) { els.memoryArchive.innerHTML = '<div class="analytics-empty">No memories match these filters.</div>'; return; }
    els.memoryArchive.innerHTML = '';
    memories.forEach(memory => {
      const row = document.createElement('div'); row.className = `memory-archive-row${memory.archived ? ' archived' : ''}`;
      row.innerHTML = `<div><span class="memory-category">${escapeHtml(memoryCategoryLabel(memory.category))}</span><p>${escapeHtml(memory.text)}</p><small>${escapeHtml(formatMemoryDate(memory.createdAt))}</small></div><div class="memory-row-actions"><button class="memory-star" type="button" aria-label="${memory.favorite ? 'Remove favorite' : 'Favorite'}">${memory.favorite ? '★' : '☆'}</button><button class="edit-button memory-archive-toggle" type="button">${memory.archived ? 'Restore' : 'Archive'}</button><button class="edit-button memory-delete" type="button">Delete</button></div>`;
      row.querySelector('.memory-star').addEventListener('click', () => toggleMemoryFavorite(memory.id));
      row.querySelector('.memory-archive-toggle').addEventListener('click', () => toggleMemoryArchive(memory.id));
      row.querySelector('.memory-delete').addEventListener('click', () => deleteMemory(memory.id));
      els.memoryArchive.appendChild(row);
    });
  }

  function toggleMemoryFavorite(id) { const memory = state.memories.find(item => item.id === id); if (!memory) return; memory.favorite = !memory.favorite; saveState(); renderMemoryArchive(); }
  function toggleMemoryArchive(id) { const memory = state.memories.find(item => item.id === id); if (!memory) return; memory.archived = !memory.archived; saveState(); renderAll(); showToast(memory.archived ? 'Memory archived' : 'Memory restored'); }

  function deleteMemory(id) {
    const memory = state.memories.find(candidate => candidate.id === id);
    if (!memory || !confirm('Delete this saved memory?')) return;
    state.memories = state.memories.filter(candidate => candidate.id !== id);
    Object.values(state.days).forEach(day => Object.entries(day.entries || {}).forEach(([itemId, entry]) => { if (entry?.memoryId === id) delete day.entries[itemId]; }));
    saveState(); renderAll(); showToast('Memory deleted');
  }

  function exportMemoriesCsv() {
    const rows = [['Date & Time', 'Category', 'Favorite', 'Archived', 'Memory']];
    [...state.memories].sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt)).forEach(memory => rows.push([new Date(memory.createdAt).toLocaleString(), memoryCategoryLabel(memory.category), memory.favorite ? 'Yes' : 'No', memory.archived ? 'Yes' : 'No', memory.text]));
    downloadBlob(rows.map(row => row.map(csvCell).join(',')).join('\r\n'), `daily-routine-memories-${dateKey(startOfToday())}.csv`, 'text/csv;charset=utf-8');
    showToast('Memories exported');
  }

  function memoryCategoryLabel(category) { return ({ blessing:'Blessing', gratitude:'Gratitude', prayer:'Prayer', thought:'Thought', quote:'Quote', memory:'Memory' })[category] || 'Memory'; }
  function formatMemoryDate(value) { const date = new Date(value); return Number.isNaN(date.getTime()) ? '' : new Intl.DateTimeFormat(undefined, { month:'short', day:'numeric', year:'numeric', hour:'numeric', minute:'2-digit' }).format(date); }
  function toDateTimeLocal(date) { const offset = date.getTimezoneOffset(); const local = new Date(date.getTime() - offset * 60000); return local.toISOString().slice(0, 16); }

  function readBibleIntegration() {
    try {
      const parsed = JSON.parse(localStorage.getItem(BIBLE_INTEGRATION_KEY) || 'null');
      return parsed && typeof parsed === 'object' ? parsed : null;
    } catch { return null; }
  }

  function consumeIntegrationReturn() {
    const params = new URLSearchParams(location.search);
    if (params.get('integration') !== 'bible') return;
    const date = params.get('date');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '')) return;
    const completed = Math.max(0, Math.min(10, Number(params.get('completed')) || 0));
    const total = Math.max(1, Number(params.get('total')) || 10);
    const completedAt = params.get('completedAt') || '';
    const nextReference = params.get('next') || '';
    const day = ensureDay(date);
    state.items.filter(item => item.type === 'linked' && item.linkedTemplate === 'bible').forEach(item => {
      day.entries[item.id] = { completed: completed >= total, progress: completed, completedCount: completed, total, completedAt, nextReference, source: 'return-link', updatedAt: new Date().toISOString() };
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    const clean = new URL(location.href); ['integration','date','completed','total','completedAt','next'].forEach(key => clean.searchParams.delete(key));
    history.replaceState({}, '', clean.pathname + clean.search + clean.hash);
  }

  function syncLinkedIntegrations(showMessage = false) {
    const integration = readBibleIntegration();
    let updates = 0;
    state.items.filter(item => item.type === 'linked' && item.linkedTemplate === 'bible' && item.linkedCompletion === 'sync').forEach(item => {
      const records = integration?.days || {};
      Object.entries(records).forEach(([key, record]) => {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || !record) return;
        if (key > dateKey(startOfToday()) || (item.createdDate && key < item.createdDate)) return;
        const day = ensureDay(key);
        const nextValue = {
          completed: Number(record.completed) >= Number(record.total || 10),
          progress: Number(record.completed) || 0,
          completedCount: Number(record.completed) || 0,
          total: Number(record.total) || 10,
          completedAt: record.completedAt || '',
          nextReference: record.nextReference || '',
          nextCategory: record.nextCategory || null,
          dayNumber: record.dayNumber || null,
          source: 'bible-integration',
          updatedAt: record.updatedAt || integration.updatedAt || ''
        };
        if (JSON.stringify(day.entries[item.id]) !== JSON.stringify(nextValue)) { day.entries[item.id] = nextValue; updates += 1; }
      });
    });
    if (updates) localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    if (showMessage) showToast(integration ? (updates ? 'Connected app progress updated' : 'Connections are up to date') : 'Open the Bible app once to start syncing');
    renderConnections();
    return updates;
  }

  function bindIntegrationEvents() {
    window.addEventListener('focus', () => { syncLinkedIntegrations(false); maybeConfirmPendingAction(); renderAll(); });
    window.addEventListener('pageshow', () => { syncLinkedIntegrations(false); renderAll(); });
    window.addEventListener('storage', event => { if (event.key === BIBLE_INTEGRATION_KEY) { syncLinkedIntegrations(false); renderAll(); } });
    try {
      integrationChannel = new BroadcastChannel(INTEGRATION_CHANNEL);
      integrationChannel.addEventListener('message', event => { if (event.data?.type === 'bible-progress') { syncLinkedIntegrations(false); renderAll(); } });
    } catch { integrationChannel = null; }
  }

  function renderConnections() {
    if (!els.bibleConnectionStatus) return;
    const integration = readBibleIntegration();
    const updated = integration?.updatedAt ? new Date(integration.updatedAt) : null;
    els.bibleConnectionStatus.textContent = updated && !Number.isNaN(updated.getTime())
      ? `Connected · synced ${formatRelativeTime(updated)}`
      : 'Not synced yet · open the Bible app once';
  }

  function saveBibleConnection() {
    const raw = els.bibleAppUrlInput.value.trim() || DEFAULT_BIBLE_APP_URL;
    try {
      const url = new URL(raw, location.href);
      if (!['http:', 'https:'].includes(url.protocol)) throw new Error('Invalid protocol');
      state.settings.bibleAppUrl = url.href;
      state.items.filter(item => item.type === 'linked' && item.linkedTemplate === 'bible').forEach(item => { item.linkedUrl = url.href; });
      saveState(); renderAll(); showToast('Bible connection saved');
    } catch { showToast('Enter a valid Bible app address'); }
  }

  function linkedTemplateDefaults(template) {
    const bibleUrl = state.settings.bibleAppUrl || DEFAULT_BIBLE_APP_URL;
    const presets = {
      bible: { name: '10-Chapter Bible Reading', section: 'morning', linkedTemplate: 'bible', linkedCompletion: 'sync', linkedUrl: bibleUrl, linkedButtonLabel: 'Continue reading' },
      website: { name: 'Open website', section: 'day', linkedTemplate: 'website', linkedCompletion: 'manual', linkedUrl: 'https://', linkedButtonLabel: 'Open' },
      shortcut: { name: 'Run Shortcut', section: 'day', linkedTemplate: 'shortcut', linkedCompletion: 'confirm', linkedUrl: 'shortcuts://run-shortcut?name=', linkedButtonLabel: 'Run shortcut' },
      phone: { name: 'Make a call', section: 'day', linkedTemplate: 'phone', linkedCompletion: 'confirm', linkedUrl: 'tel:', linkedButtonLabel: 'Call' },
      text: { name: 'Send a message', section: 'day', linkedTemplate: 'text', linkedCompletion: 'confirm', linkedUrl: 'sms:', linkedButtonLabel: 'Text' },
      email: { name: 'Send an email', section: 'day', linkedTemplate: 'email', linkedCompletion: 'confirm', linkedUrl: 'mailto:', linkedButtonLabel: 'Email' },
      maps: { name: 'Open in Maps', section: 'day', linkedTemplate: 'maps', linkedCompletion: 'manual', linkedUrl: 'https://maps.apple.com/?q=', linkedButtonLabel: 'Open Maps' },
      internal: { name: 'Review a blessing', section: 'day', linkedTemplate: 'internal', linkedCompletion: 'manual', linkedUrl: '', linkedInternalTarget: 'memory', linkedButtonLabel: 'Open' }
    };
    return presets[template] || presets.website;
  }

  function applyLinkedTemplate(template, overwrite = true) {
    const preset = linkedTemplateDefaults(template);
    if (overwrite || !els.itemNameInput.value.trim()) els.itemNameInput.value = preset.name;
    if (overwrite || !els.linkedUrlInput.value.trim()) els.linkedUrlInput.value = preset.linkedUrl || '';
    els.linkedCompletionInput.value = preset.linkedCompletion;
    els.linkedButtonLabelInput.value = preset.linkedButtonLabel;
    els.linkedInternalTargetInput.value = preset.linkedInternalTarget || 'memory';
  }

  function linkedProgress(value) {
    if (value === true) return { completed: true, current: 1, total: 1, label: 'Completed' };
    const current = Number(value?.completedCount ?? value?.progress ?? 0) || 0;
    const total = Number(value?.total) || 10;
    return { completed: Boolean(value?.completed || current >= total), current, total, label: `${current}/${total}` };
  }

  function buildLinkedRow(row, item, value) {
    const progress = linkedProgress(value);
    const timing = timeWindowStatus(item, selectedDate);
    const templateIcon = ({ bible: '📖', website: '↗', shortcut: '⚡', phone: '☎', text: '💬', email: '✉', maps: '⌖', internal: '◎' })[item.linkedTemplate] || '↗';
    const next = value?.nextReference ? `Next: ${value.nextReference}` : '';
    row.classList.toggle('done', progress.completed);
    row.innerHTML = `<div class="linked-main"><span class="linked-icon" aria-hidden="true">${templateIcon}</span><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaForItem(item))}${next ? ` · ${escapeHtml(next)}` : ''}</span></span>${timing.status ? `<span class="due-pill ${timing.status}">${escapeHtml(timing.shortLabel)}</span>` : ''}</div><div class="linked-progress"><div class="linked-progress-copy"><strong>${escapeHtml(progress.label)}</strong><span>${progress.completed ? 'Complete' : item.linkedTemplate === 'bible' ? 'Reading progress' : 'Action status'}</span></div><div class="linked-progress-track"><span style="width:${Math.min(100, Math.round(progress.current / Math.max(1, progress.total) * 100))}%"></span></div></div><div class="linked-actions"><button class="primary-button open-linked-button" type="button">${escapeHtml(item.linkedButtonLabel || (item.linkedTemplate === 'bible' ? 'Continue reading' : 'Open'))}</button><button class="secondary-button manual-linked-button" type="button">${progress.completed ? 'Mark incomplete' : 'Mark complete'}</button>${item.linkedTemplate === 'bible' ? '<button class="small-button sync-linked-button" type="button">Sync</button>' : ''}</div>`;
    row.querySelector('.open-linked-button').addEventListener('click', () => openLinkedAction(item));
    row.querySelector('.manual-linked-button').addEventListener('click', () => saveEntry(item, progress.completed ? { completed: false, progress: 0, total: progress.total, source: 'manual' } : { completed: true, progress: progress.total, completedCount: progress.total, total: progress.total, completedAt: new Date().toISOString(), source: 'manual' }));
    row.querySelector('.sync-linked-button')?.addEventListener('click', () => { syncLinkedIntegrations(true); renderAll(); });
    return row;
  }

  function openBibleApp(date = selectedDate) {
    const base = state.settings.bibleAppUrl || DEFAULT_BIBLE_APP_URL;
    try {
      const url = new URL(base, location.href);
      url.searchParams.set('source', 'daily-routine');
      url.searchParams.set('date', dateKey(date));
      url.searchParams.set('continue', '1');
      url.searchParams.set('return', new URL('./', location.href).href);
      location.assign(url.href);
    } catch { showToast('The Bible app address is not valid'); }
  }

  function openLinkedAction(item) {
    if (item.linkedTemplate === 'bible') { openBibleApp(selectedDate); return; }
    if (item.linkedTemplate === 'internal') { openInternalAction(item.linkedInternalTarget); return; }
    const url = normalizeActionUrl(item);
    if (!url) { showToast('Add a valid action link in Setup'); return; }
    if (item.linkedCompletion === 'confirm') pendingLinkedAction = { itemId: item.id, date: dateKey(selectedDate), openedAt: Date.now() };
    location.assign(url);
  }

  function normalizeActionUrl(item) {
    const raw = String(item.linkedUrl || '').trim();
    if (!raw) return '';
    if (/^javascript:/i.test(raw)) return '';
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return raw;
    if (item.linkedTemplate === 'phone') return `tel:${raw}`;
    if (item.linkedTemplate === 'text') return `sms:${raw}`;
    if (item.linkedTemplate === 'email') return `mailto:${raw}`;
    if (item.linkedTemplate === 'shortcut') return `shortcuts://run-shortcut?name=${encodeURIComponent(raw)}`;
    if (item.linkedTemplate === 'maps') return `https://maps.apple.com/?q=${encodeURIComponent(raw)}`;
    try { return new URL(raw, location.href).href; } catch { return ''; }
  }

  function maybeConfirmPendingAction() {
    if (!pendingLinkedAction || Date.now() - pendingLinkedAction.openedAt < 750) return;
    const pending = pendingLinkedAction; pendingLinkedAction = null;
    const item = state.items.find(candidate => candidate.id === pending.itemId);
    if (!item || !confirm(`Did you finish “${item.name}”?`)) return;
    const day = ensureDay(pending.date);
    day.entries[item.id] = { completed: true, progress: 1, completedCount: 1, total: 1, completedAt: new Date().toISOString(), source: 'confirmed-return' };
    saveState(); renderAll(); showToast('Linked action completed');
  }

  function openInternalAction(target) {
    if (target === 'notes') { switchView('notes'); openNoteDialog(); return; }
    if (target === 'memory') { switchView('today'); openMemoryDialog('blessing'); return; }
    if (target === 'weekly') { switchView('history'); els.weeklyReviewCard?.scrollIntoView({ behavior: 'smooth', block: 'start' }); return; }
    if (target === 'medication') { switchView('history'); els.medicationProgressCard?.scrollIntoView({ behavior: 'smooth', block: 'start' }); return; }
    if (target === 'backup') { switchView('setup'); els.dataBackupCard?.scrollIntoView({ behavior: 'smooth', block: 'start' }); return; }
    switchView('today');
  }

  function timeWindowStatus(item, date) {
    const start = item.timeWindowStart || '', end = item.timeWindowEnd || '';
    if (!start && !end) return { status: '', label: '', shortLabel: '' };
    const windowText = `${start ? formatTime(start) : 'Any time'}${end ? `–${formatTime(end)}` : ''}`;
    if (!isSameDay(date, startOfToday())) return { status: '', label: `Window ${windowText}`, shortLabel: '' };
    const now = new Date().getHours() * 60 + new Date().getMinutes();
    const startMin = start ? timeToMinutes(start) : null, endMin = end ? timeToMinutes(end) : null;
    let status = 'due', label = 'Due now', shortLabel = 'Due';
    if (startMin !== null && endMin !== null && endMin < startMin) {
      const inWindow = now >= startMin || now <= endMin;
      if (inWindow) { status = 'due'; label = 'Due now'; shortLabel = 'Due'; }
      else if (now < startMin) { status = 'upcoming'; label = `Upcoming ${formatTime(start)}`; shortLabel = 'Upcoming'; }
      else { status = 'late'; label = `Late · ended ${formatTime(end)}`; shortLabel = 'Late'; }
    } else if (startMin !== null && now < startMin) { status = 'upcoming'; label = `Upcoming ${formatTime(start)}`; shortLabel = 'Upcoming'; }
    else if (endMin !== null && now > endMin) { status = 'late'; label = `Late · ended ${formatTime(end)}`; shortLabel = 'Late'; }
    return { status, label, shortLabel, windowText };
  }

  function formatRelativeTime(date) {
    const seconds = Math.max(0, Math.round((Date.now() - date.getTime()) / 1000));
    if (seconds < 60) return 'just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return date.toLocaleDateString();
  }

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
      const recent = medicationRecentHistory(metric.item, dates);
      return `<div class="med-insight"><div class="med-insight-head"><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.loggedTimes.length} timed dose${metric.loggedTimes.length === 1 ? '' : 's'} · ${metric.pairs.length} paired with next wake</span></div><div class="med-stat-grid"><div><b>${formatMinutesClock(avgTaken)}</b><span>Avg taken</span></div><div><b>${formatMinutesClock(avgWake)}</b><span>Avg next wake</span></div><div><b>${avgInterval === null ? '—' : formatDurationMinutes(avgInterval)}</b><span>Avg taken → wake</span></div></div>${comparison}<div class="med-history">${recent}</div></div>`;
    }).join('');
  }

  function medicationRecentHistory(item, dates) {
    const rows = [...dates].reverse().map(date => {
      const entry = state.days[dateKey(date)]?.entries?.[item.id];
      if (!entryIsLogged(item, entry)) return '';
      const time = medicationTime(entry);
      return `<div class="med-history-row"><span>${escapeHtml(formatShortDate(date))}</span><b>${time ? escapeHtml(formatTime(time)) : 'time —'}</b><em>${escapeHtml(entry?.dose || item.medicationDose || '')}</em>${entry?.note ? `<small>${escapeHtml(entry.note)}</small>` : ''}</div>`;
    }).filter(Boolean).slice(0, 7);
    return rows.length ? `<div class="med-history-title">Recent logs</div>${rows.join('')}` : '';
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

  function dayModeLabel(mode) { return ({ normal: 'Normal day', sick: 'Sick day', travel: 'Travel day', vacation: 'Vacation', rest: 'Planned rest' })[mode] || 'Normal day'; }

  function setDayMode(mode) {
    const key = dateKey(selectedDate), day = ensureDay(key), previous = day.mode || 'normal';
    day.mode = mode;
    pushUndo('Change day mode', () => { ensureDay(key).mode = previous; localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); renderToday(); renderHistory(); });
    saveState(); renderToday(); renderHistory(); showToast(mode === 'normal' ? 'Normal scoring restored' : `${dayModeLabel(mode)} set as excused`);
  }

  function pushUndo(label, action) { undoAction = { label, action }; if (els.undoButton) { els.undoButton.disabled = false; els.undoButton.textContent = `Undo`; els.undoButton.title = label; } }
  function performUndo() { if (!undoAction) return; const action = undoAction.action; undoAction = null; action(); if (els.undoButton) { els.undoButton.disabled = true; els.undoButton.textContent = 'Undo'; } showToast('Last action undone'); }

  function currentWeekKey() { return dateKey(startOfCurrentWeek()); }
  function nextWeekKey() { return dateKey(shiftDate(startOfCurrentWeek(), 7)); }
  function renderWeekFocusBanner() {
    const focus = state.weeklyReviews?.[currentWeekKey()]?.focus || '';
    els.weekFocusBanner.hidden = !focus;
    els.weekFocusBanner.textContent = focus ? `This week: ${focus}` : '';
  }

  function saveWeeklyFocus() {
    const key = nextWeekKey();
    state.weeklyReviews[key] = { ...(state.weeklyReviews[key] || {}), focus: els.weeklyFocusInput.value.trim(), updatedAt: new Date().toISOString() };
    saveState(); renderWeekFocusBanner(); showToast('Weekly focus saved');
  }

  function renderWeeklyReview() {
    const weekStart = startOfCurrentWeek(), today = startOfToday();
    const dates = Array.from({ length: 7 }, (_, i) => shiftDate(weekStart, i)).filter(date => dateKey(date) <= dateKey(today));
    const scoredDates = dates.filter(date => !dayIsExcused(date));
    const completion = aggregateCompletion(scoredDates);
    const sectionStats = ['morning', 'day', 'evening'].map(section => {
      let done = 0, total = 0;
      scoredDates.forEach(date => { const day = state.days[dateKey(date)] || { entries:{} }; scoredItemsForDate(date).filter(item => item.section === section && !item.optional).forEach(item => { total += 1; if (entryMeetsTarget(item, day.entries?.[item.id])) done += 1; }); });
      return { section, percent: total ? Math.round(done / total * 100) : null };
    }).filter(row => row.percent !== null);
    const bestSection = sectionStats.sort((a,b) => b.percent - a.percent)[0];
    const habits = habitMetrics(scoredDates).sort((a,b) => b.percent - a.percent);
    const bestHabit = habits[0], missedHabit = [...habits].sort((a,b) => a.percent - b.percent)[0];
    const sleepItem = state.items.find(item => item.type === 'scale' && /sleep/i.test(item.name));
    const sleepValues = sleepItem ? scaleSeries(sleepItem, dates) : [];
    const memories = state.memories.filter(memory => { const d = new Date(memory.createdAt); return !Number.isNaN(d.getTime()) && dateKey(d) >= dateKey(weekStart) && dateKey(d) <= dateKey(today); });
    const openActions = state.notes.filter(note => note.type === 'action' && !noteIsClosed(note)).length;
    const activePrayers = state.notes.filter(note => note.type === 'prayer' && note.prayerStatus === 'active').length;
    const godMoments = state.notes.filter(note => note.type === 'god-moment' && new Date(note.createdAt).getTime() >= weekStart.getTime()).length;
    els.weeklyReviewLabel.textContent = `${formatShortDate(weekStart)} – ${formatShortDate(shiftDate(weekStart, 6))}`;
    const cards = [
      ['Routine', completion.percent === null ? '—' : `${completion.percent}%`],
      ['Best section', bestSection ? `${sectionLabels[bestSection.section][0]} ${bestSection.percent}%` : '—'],
      ['Most consistent', bestHabit ? `${bestHabit.item.name} ${bestHabit.percent}%` : '—'],
      ['Most missed', missedHabit ? `${missedHabit.item.name} ${missedHabit.percent}%` : '—'],
      ['Avg sleep', sleepValues.length ? average(sleepValues).toFixed(1) : '—'],
      ['Memories', String(memories.length)],
      ['Open actions', String(openActions)],
      ['Active prayers', String(activePrayers)],
      ['God Moments', String(godMoments)]
    ];
    els.weeklyReviewSummary.innerHTML = cards.map(([label,value]) => `<div><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join('');
    els.weeklyFocusInput.value = state.weeklyReviews?.[nextWeekKey()]?.focus || '';
  }

  function renderOnThisDay() {
    const target = selectedDate;
    const matches = state.memories.filter(memory => {
      if (memory.archived) return false;
      const d = new Date(memory.createdAt);
      return !Number.isNaN(d.getTime()) && d.getFullYear() < target.getFullYear() && d.getMonth() === target.getMonth() && d.getDate() === target.getDate();
    }).sort((a,b) => Number(Boolean(b.favorite)) - Number(Boolean(a.favorite)) || new Date(b.createdAt) - new Date(a.createdAt));
    els.onThisDayMemory.hidden = !matches.length;
    els.onThisDayMemory.innerHTML = matches.length ? `<span>On this day</span><p>${escapeHtml(matches[0].text)}</p><small>${escapeHtml(formatMemoryDate(matches[0].createdAt))}</small>` : '';
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
