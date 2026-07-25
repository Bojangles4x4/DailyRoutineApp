(() => {
  'use strict';

  const STORAGE_KEY = 'dailyRoutineApp.v1';
  const DEFAULT_STATE = {
    settings: { wakeTime: '06:00', bedTime: '22:30', theme: 'calm', backgroundImage: '' },
    items: [
      { id: 'morning-prayer', name: 'Prayer', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-teeth', name: 'Brush teeth', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-meds', name: 'Take morning medicine', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-reading', name: 'Bible reading', section: 'morning', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'morning-sleep', name: 'Sleep quality', section: 'morning', type: 'scale', frequency: 'daily', days: [], optional: true, unit: '', target: null },
      { id: 'morning-mood', name: 'Morning mood', section: 'morning', type: 'scale', frequency: 'daily', days: [], optional: true, unit: '', target: null },
      { id: 'day-water', name: 'Water', section: 'day', type: 'number', frequency: 'daily', days: [], optional: false, unit: 'cups', target: 8 },
      { id: 'day-movement', name: 'Movement / exercise', section: 'day', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'day-focus', name: 'Focus / productivity', section: 'day', type: 'scale', frequency: 'weekdays', days: [], optional: true, unit: '', target: null },
      { id: 'day-stress', name: 'Stress', section: 'day', type: 'scale', frequency: 'daily', days: [], optional: true, unit: '', target: null },
      { id: 'evening-teeth', name: 'Brush teeth', section: 'evening', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-meds', name: 'Take evening medicine', section: 'evening', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-prepare', name: 'Prepare for tomorrow', section: 'evening', type: 'checkbox', frequency: 'daily', days: [], optional: false, unit: '', target: null },
      { id: 'evening-overall', name: 'Overall day', section: 'evening', type: 'scale', frequency: 'daily', days: [], optional: true, unit: '', target: null },
      { id: 'evening-reflection', name: 'What went well today?', section: 'evening', type: 'longtext', frequency: 'daily', days: [], optional: true, unit: '', target: null }
    ],
    days: {}
  };

  const sectionLabels = {
    morning: ['Morning', 'Start deliberately'],
    day: ['Throughout the day', 'Stay on track'],
    evening: ['Evening', 'Close the day well']
  };
  const typeLabels = { checkbox: 'Checkbox', scale: '0–10 rating', number: 'Number', time: 'Time', text: 'Short comment', longtext: 'Journal entry' };

  let state = loadState();
  let selectedDate = startOfToday();
  let deferredInstallPrompt = null;
  let toastTimer = null;
  let analyticsRange = 7;

  const $ = (id) => document.getElementById(id);
  const els = {
    pageTitle: $('pageTitle'), todayEyebrow: $('todayEyebrow'), heroGreeting: $('heroGreeting'), heroDate: $('heroDate'), heroStatus: $('heroStatus'),
    wakeTimeDisplay: $('wakeTimeDisplay'), bedTimeDisplay: $('bedTimeDisplay'), progressRing: $('progressRing'), progressPercent: $('progressPercent'),
    selectedDateButton: $('selectedDateButton'), prevDay: $('prevDay'), nextDay: $('nextDay'), routineSections: $('routineSections'),
    statCompleted: $('statCompleted'), statOptional: $('statOptional'), statStreak: $('statStreak'), statMood: $('statMood'), copySummaryButton: $('copySummaryButton'),
    historyList: $('historyList'), rangeSelector: $('rangeSelector'), progressOverall: $('progressOverall'), progress80Days: $('progress80Days'), progressTrackedDays: $('progressTrackedDays'),
    progressRangeNote: $('progressRangeNote'), weekSummary: $('weekSummary'), weekOverall: $('weekOverall'), sectionBreakdown: $('sectionBreakdown'),
    strongHabits: $('strongHabits'), weakHabits: $('weakHabits'), trendList: $('trendList'), wakeTimeInput: $('wakeTimeInput'), bedTimeInput: $('bedTimeInput'), themeInput: $('themeInput'),
    backgroundImageInput: $('backgroundImageInput'), clearBackgroundButton: $('clearBackgroundButton'), routineEditor: $('routineEditor'), addItemButton: $('addItemButton'),
    exportCsvButton: $('exportCsvButton'), exportJsonButton: $('exportJsonButton'), importJsonInput: $('importJsonInput'), resetDataButton: $('resetDataButton'),
    itemDialog: $('itemDialog'), itemForm: $('itemForm'), dialogTitle: $('dialogTitle'), editingItemId: $('editingItemId'), itemNameInput: $('itemNameInput'),
    itemSectionInput: $('itemSectionInput'), itemTypeInput: $('itemTypeInput'), itemFrequencyInput: $('itemFrequencyInput'), customDaysField: $('customDaysField'),
    numberGoalFields: $('numberGoalFields'), itemTargetInput: $('itemTargetInput'), itemUnitInput: $('itemUnitInput'), itemOptionalInput: $('itemOptionalInput'),
    deleteItemButton: $('deleteItemButton'), closeDialogButton: $('closeDialogButton'), installButton: $('installButton'), toast: $('toast')
  };

  init();

  function init() {
    ensureFirstUseDate();
    bindNavigation(); bindTodayControls(); bindProgressControls(); bindSetupControls(); bindInstall(); applyPersonalization(); renderAll();
    if ('serviceWorker' in navigator) window.addEventListener('load', () => navigator.serviceWorker.register('./service-worker.js').catch(() => {}));
  }

  function normalizeItem(item, index) {
    return {
      ...item,
      days: Array.isArray(item.days) ? item.days.map(Number) : [],
      optional: Boolean(item.optional),
      target: item.target === '' || item.target === undefined ? null : item.target,
      order: Number.isFinite(Number(item.order)) ? Number(item.order) : index
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
        days: parsed.days && typeof parsed.days === 'object' ? parsed.days : {}
      };
    } catch { return structuredClone(DEFAULT_STATE); }
  }
  function saveState() { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); }
  function startOfToday() { const d = new Date(); d.setHours(12,0,0,0); return d; }
  function dateKey(date) { return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`; }
  function fromDateKey(key) { const [y,m,d] = key.split('-').map(Number); return new Date(y,m-1,d,12,0,0,0); }
  function shiftDate(date, days) { const d = new Date(date); d.setDate(d.getDate()+days); return d; }
  function isSameDay(a,b) { return dateKey(a) === dateKey(b); }
  function ensureDay(key) { if (!state.days[key]) state.days[key] = { entries: {} }; if (!state.days[key].entries) state.days[key].entries = {}; return state.days[key]; }
  function ensureFirstUseDate() {
    let changed = false;
    if (!state.settings.firstUseDate) {
      const historical = Object.keys(state.days || {}).filter(key => /^\d{4}-\d{2}-\d{2}$/.test(key)).sort();
      state.settings.firstUseDate = historical[0] || dateKey(startOfToday());
      changed = true;
    }
    state.items.forEach(item => { if (!item.createdDate) { item.createdDate = state.settings.firstUseDate; changed = true; } });
    if (changed) saveState();
  }

  function scheduledItemsForDate(date) {
    const dow = date.getDay();
    return state.items.filter((item) => {
      if (item.createdDate && dateKey(date) < item.createdDate) return false;
      if (item.frequency === 'weekdays') return dow >= 1 && dow <= 5;
      if (item.frequency === 'weekends') return dow === 0 || dow === 6;
      if (item.frequency === 'custom') return (item.days || []).includes(dow);
      return true;
    });
  }
  function entryIsLogged(item, value) {
    if (item.type === 'checkbox') return value === true;
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
    const required = items.filter(i => !i.optional);
    const optional = items.filter(i => i.optional);
    const day = state.days[dateKey(date)] || { entries: {} };
    const completed = required.filter(i => entryMeetsTarget(i, day.entries?.[i.id])).length;
    const optionalLogged = optional.filter(i => entryIsLogged(i, day.entries?.[i.id])).length;
    return { completed, total: required.length, optionalLogged, optionalTotal: optional.length, percent: required.length ? Math.round(completed/required.length*100) : 100 };
  }
  function calculateStreak() {
    let streak = 0, cursor = startOfToday();
    for (let i=0;i<3650;i++) { const c = completionForDate(cursor); if (c.total > 0 && c.percent >= 80) { streak++; cursor = shiftDate(cursor,-1); } else break; }
    return streak;
  }

  function bindNavigation() {
    document.querySelectorAll('.nav-button').forEach(btn => btn.addEventListener('click', () => switchView(btn.dataset.view)));
  }
  function switchView(view) {
    document.querySelectorAll('.nav-button').forEach(b => b.classList.toggle('active', b.dataset.view === view));
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    $(`${view}View`).classList.add('active');
    els.pageTitle.textContent = ({today:'Today',history:'Progress',setup:'Setup'})[view] || 'Daily Routine';
    if (view === 'history') renderHistory(); if (view === 'setup') renderSetup();
    $('appMain').focus({preventScroll:true}); window.scrollTo({top:0,behavior:'smooth'});
  }
  function bindTodayControls() {
    els.prevDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate,-1); renderToday(); });
    els.nextDay.addEventListener('click', () => { selectedDate = shiftDate(selectedDate,1); renderToday(); });
    els.selectedDateButton.addEventListener('click', () => { selectedDate = startOfToday(); renderToday(); });
    els.copySummaryButton.addEventListener('click', copyDailySummary);
  }
  function bindProgressControls() {
    els.rangeSelector?.querySelectorAll('.range-button').forEach(button => button.addEventListener('click', () => {
      analyticsRange = Number(button.dataset.range) || 7;
      els.rangeSelector.querySelectorAll('.range-button').forEach(candidate => candidate.classList.toggle('active', candidate === button));
      renderHistory();
    }));
  }
  function bindSetupControls() {
    els.wakeTimeInput.addEventListener('change', () => { state.settings.wakeTime = els.wakeTimeInput.value || '06:00'; saveState(); renderToday(); });
    els.bedTimeInput.addEventListener('change', () => { state.settings.bedTime = els.bedTimeInput.value || '22:30'; saveState(); renderToday(); });
    els.themeInput.addEventListener('change', () => { state.settings.theme = els.themeInput.value; saveState(); applyPersonalization(); });
    els.backgroundImageInput.addEventListener('change', handleBackgroundImage);
    els.clearBackgroundButton.addEventListener('click', () => { state.settings.backgroundImage=''; saveState(); applyPersonalization(); showToast('Background photo removed'); });
    els.addItemButton.addEventListener('click', () => openItemDialog());
    els.closeDialogButton.addEventListener('click', () => els.itemDialog.close());
    els.itemTypeInput.addEventListener('change', toggleBuilderFields);
    els.itemFrequencyInput.addEventListener('change', toggleBuilderFields);
    els.itemForm.addEventListener('submit', saveRoutineItem);
    els.deleteItemButton.addEventListener('click', deleteRoutineItem);
    els.exportCsvButton.addEventListener('click', exportCsv); els.exportJsonButton.addEventListener('click', exportJson);
    els.importJsonInput.addEventListener('change', importJson); els.resetDataButton.addEventListener('click', resetData);
  }
  function bindInstall() {
    window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); deferredInstallPrompt=e; els.installButton.hidden=false; });
    els.installButton.addEventListener('click', async () => { if(!deferredInstallPrompt)return; deferredInstallPrompt.prompt(); await deferredInstallPrompt.userChoice; deferredInstallPrompt=null; els.installButton.hidden=true; });
  }

  function renderAll() { renderToday(); renderHistory(); renderSetup(); }
  function renderToday() {
    const day = state.days[dateKey(selectedDate)] || { entries:{} };
    const today = startOfToday(); const now = new Date();
    els.heroGreeting.textContent = greetingForHour(now.getHours());
    els.heroDate.textContent = new Intl.DateTimeFormat(undefined,{weekday:'long',month:'long',day:'numeric'}).format(selectedDate);
    els.wakeTimeDisplay.textContent = formatTime(state.settings.wakeTime); els.bedTimeDisplay.textContent = formatTime(state.settings.bedTime);
    els.selectedDateButton.textContent = isSameDay(selectedDate,today) ? 'Today' : new Intl.DateTimeFormat(undefined,{weekday:'short',month:'short',day:'numeric'}).format(selectedDate);
    els.nextDay.disabled = dateKey(selectedDate) >= dateKey(today); els.nextDay.style.opacity = els.nextDay.disabled ? '.35':'1';
    renderRoutineSections(day); renderStats();
  }
  function renderRoutineSections(day) {
    els.routineSections.innerHTML=''; const scheduled = scheduledItemsForDate(selectedDate);
    ['morning','day','evening'].forEach(section => {
      const items = scheduled.filter(i=>i.section===section).sort((a,b)=>(a.order??0)-(b.order??0));
      const required = items.filter(i=>!i.optional); const logged = required.filter(i=>entryMeetsTarget(i,day.entries?.[i.id])).length;
      const [title,subtitle] = sectionLabels[section]; const wrapper=document.createElement('section'); wrapper.className='routine-section';
      wrapper.innerHTML=`<div class="card"><div class="section-heading"><div><p class="eyebrow">${escapeHtml(subtitle)}</p><h2>${escapeHtml(title)}</h2></div><span class="section-progress">${logged}/${required.length}</span></div><div class="task-list"></div></div>`;
      const list=wrapper.querySelector('.task-list'); if(!items.length) list.innerHTML='<div class="empty-state">No items scheduled here.</div>'; else items.forEach(i=>list.appendChild(buildTaskRow(i,day.entries?.[i.id])));
      els.routineSections.appendChild(wrapper);
    });
  }
  function buildTaskRow(item,value) {
    const row=document.createElement('div'); row.className=`task-row${entryMeetsTarget(item,value)?' done':''}`;
    const metaBits=[item.optional?'Optional':'Required', frequencyLabel(item)]; if(item.type==='number'&&Number.isFinite(Number(item.target))) metaBits.push(`Target ${item.target}${item.unit?' '+item.unit:''}`);
    if(item.type==='checkbox') {
      row.innerHTML=`<label class="task-main"><input class="check-control" type="checkbox" ${value===true?'checked':''}/><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaBits.join(' · '))}</span></span></label>`;
      row.querySelector('input').addEventListener('change',e=>saveEntry(item,e.target.checked)); return row;
    }
    row.innerHTML=`<div class="task-main"><span class="task-name">${escapeHtml(item.name)}<span class="task-meta">${escapeHtml(metaBits.join(' · '))}</span></span></div><div class="task-extra"></div>`;
    const extra=row.querySelector('.task-extra');
    if(item.type==='scale') {
      const current=Number.isFinite(Number(value))?Number(value):5; extra.innerHTML=`<div class="scale-control"><input type="range" min="0" max="10" step="1" value="${current}"/><output>${value===undefined?'—':current}</output></div>`;
      const input=extra.querySelector('input'),output=extra.querySelector('output'); input.addEventListener('input',()=>output.textContent=input.value); input.addEventListener('change',()=>saveEntry(item,Number(input.value)));
    } else if(item.type==='text'||item.type==='longtext') {
      extra.innerHTML=`<textarea class="task-input" rows="${item.type==='longtext'?4:2}" placeholder="${item.type==='longtext'?'Write a reflection…':'Add a comment…'}">${escapeHtml(value||'')}</textarea>`;
      extra.querySelector('textarea').addEventListener('input',debounce(e=>saveEntry(item,e.target.value,false),250));
    } else if(item.type==='number') {
      extra.innerHTML=`<div class="number-entry"><input class="task-input inline-number" type="number" step="any" inputmode="decimal" value="${escapeHtml(value??'')}" placeholder="0"/><span>${escapeHtml(item.unit||'')}</span>${Number.isFinite(Number(item.target))?`<small>/ ${escapeHtml(item.target)} ${escapeHtml(item.unit||'')}</small>`:''}</div>`;
      extra.querySelector('input').addEventListener('change',e=>saveEntry(item,e.target.value));
    } else if(item.type==='time') { extra.innerHTML=`<input class="task-input" type="time" value="${escapeHtml(value||'')}"/>`; extra.querySelector('input').addEventListener('change',e=>saveEntry(item,e.target.value)); }
    return row;
  }
  function saveEntry(item,value,rerender=true) { const day=ensureDay(dateKey(selectedDate)); day.entries[item.id]=value; saveState(); if(rerender)renderToday(); else renderStats(); }
  function renderStats() {
    const c=completionForDate(selectedDate), day=state.days[dateKey(selectedDate)]||{};
    els.progressPercent.textContent=`${c.percent}%`; els.progressRing.style.setProperty('--p',c.percent); els.progressRing.setAttribute('aria-label',`${c.percent} percent complete`);
    els.statCompleted.textContent=`${c.completed}/${c.total}`; els.statOptional.textContent=`${c.optionalLogged}/${c.optionalTotal}`; els.statStreak.textContent=calculateStreak();
    const latestMood = getLatestMood(day); els.statMood.textContent=latestMood===null?'—':`${latestMood}/10`;
    els.heroStatus.textContent = c.percent===100 ? 'Day complete. Nicely done.' : c.percent>=80 ? 'Strong day. Keep closing it out.' : c.percent>=40 ? 'Good progress. Keep moving.' : 'Start deliberately.';
  }
  function getLatestMood(day) {
    const moodIds=['evening-overall','morning-mood']; for(const id of moodIds){ const v=day.entries?.[id]; if(Number.isFinite(Number(v))) return Number(v); }
    if(Number.isFinite(Number(day.mood))) return Number(day.mood); return null;
  }
  function renderHistory() {
    renderProgressOverview();
    renderWeekSummary();
    renderSectionBreakdown();
    renderHabitPerformance();
    renderTrendList();
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

  function previousRangeDates(days = analyticsRange) {
    const end = shiftDate(startOfToday(), -days);
    return activeRangeDates(days, end);
  }

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
    els.progressRangeNote.textContent = first && last
      ? `${formatShortDate(first)} – ${formatShortDate(last)} · Required routine items drive completion scores.`
      : 'Log a day to start building your progress history.';
  }

  function startOfCurrentWeek() {
    const today = startOfToday();
    const dow = today.getDay();
    return shiftDate(today, dow === 0 ? -6 : 1 - dow);
  }

  function renderWeekSummary() {
    const today = startOfToday(), weekStart = startOfCurrentWeek(), firstUse = fromDateKey(state.settings.firstUseDate || dateKey(today));
    const days = Array.from({length: 7}, (_, index) => shiftDate(weekStart, index));
    const eligible = days.filter(date => dateKey(date) <= dateKey(today) && dateKey(date) >= dateKey(firstUse));
    const aggregate = aggregateCompletion(eligible);
    els.weekOverall.textContent = aggregate.percent === null ? '—' : `${aggregate.percent}% week`;
    els.weekSummary.innerHTML = days.map(date => {
      const future = dateKey(date) > dateKey(today), beforeUse = dateKey(date) < dateKey(firstUse), unavailable = future || beforeUse;
      const c = unavailable ? null : completionForDate(date);
      const percent = c?.percent ?? 0;
      const label = new Intl.DateTimeFormat(undefined, { weekday: 'narrow' }).format(date);
      const value = unavailable ? '—' : `${percent}%`;
      return `<div class="week-day${isSameDay(date,today)?' today':''}${unavailable?' unavailable':''}">
        <span class="week-label">${escapeHtml(label)}</span>
        <div class="week-track"><span style="height:${unavailable ? 0 : percent}%"></span></div>
        <strong>${value}</strong>
        <small>${date.getDate()}</small>
      </div>`;
    }).join('');
  }

  function renderSectionBreakdown() {
    const dates = activeRangeDates();
    els.sectionBreakdown.innerHTML = ['morning','day','evening'].map(section => {
      let completed = 0, total = 0;
      dates.forEach(date => {
        const day = state.days[dateKey(date)] || { entries: {} };
        scheduledItemsForDate(date).filter(item => item.section === section && !item.optional).forEach(item => {
          total += 1;
          if (entryMeetsTarget(item, day.entries?.[item.id])) completed += 1;
        });
      });
      const percent = total ? Math.round(completed / total * 100) : null;
      return progressRowMarkup(sectionLabels[section][0], percent, total ? `${completed}/${total} completed` : 'No required items');
    }).join('');
  }

  function progressRowMarkup(label, percent, detail = '') {
    const width = percent ?? 0;
    return `<div class="breakdown-row">
      <div class="breakdown-copy"><strong>${escapeHtml(label)}</strong><span>${escapeHtml(detail)}</span></div>
      <div class="breakdown-score">${percent === null ? '—' : `${percent}%`}</div>
      <div class="breakdown-bar"><span style="width:${width}%"></span></div>
    </div>`;
  }

  function habitMetrics(dates) {
    return state.items
      .filter(item => ['checkbox','number','time'].includes(item.type))
      .map(item => {
        let opportunities = 0, successes = 0;
        dates.forEach(date => {
          if (!scheduledItemsForDate(date).some(scheduled => scheduled.id === item.id)) return;
          opportunities += 1;
          const day = state.days[dateKey(date)] || { entries: {} };
          if (entryMeetsTarget(item, day.entries?.[item.id])) successes += 1;
        });
        return { item, opportunities, successes, percent: opportunities ? Math.round(successes / opportunities * 100) : null };
      })
      .filter(metric => metric.opportunities > 0);
  }

  function renderHabitPerformance() {
    const metrics = habitMetrics(activeRangeDates());
    if (!metrics.length) {
      const empty = '<div class="analytics-empty">Add checkbox, number, or time habits to see consistency here.</div>';
      els.strongHabits.innerHTML = empty; els.weakHabits.innerHTML = empty; return;
    }
    const strongest = [...metrics].sort((a,b) => b.percent - a.percent || b.successes - a.successes || (a.item.order ?? 0) - (b.item.order ?? 0)).slice(0,3);
    const weakest = [...metrics].sort((a,b) => a.percent - b.percent || a.successes - b.successes || (b.item.order ?? 0) - (a.item.order ?? 0)).slice(0,3);
    els.strongHabits.innerHTML = strongest.map(habitMetricMarkup).join('');
    els.weakHabits.innerHTML = weakest.map(habitMetricMarkup).join('');
  }

  function habitMetricMarkup(metric) {
    return `<div class="habit-row"><div><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.successes}/${metric.opportunities} days</span></div><b>${metric.percent}%</b></div>`;
  }

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
    return dates.map(date => {
      const scheduled = scheduledItemsForDate(date).some(candidate => candidate.id === item.id);
      if (!scheduled) return null;
      return scaleValueForDay(item, state.days[dateKey(date)] || { entries: {} });
    }).filter(value => value !== null);
  }

  function average(values) { return values.length ? values.reduce((sum,value) => sum + value, 0) / values.length : null; }

  function renderTrendList() {
    const currentDates = activeRangeDates(), priorDates = previousRangeDates();
    const scaleItems = state.items.filter(item => item.type === 'scale');
    const metrics = scaleItems.map(item => {
      const current = scaleSeries(item, currentDates), prior = scaleSeries(item, priorDates);
      return { item, current, prior, currentAvg: average(current), priorAvg: average(prior) };
    }).filter(metric => metric.current.length > 0);
    if (!metrics.length) {
      els.trendList.innerHTML = '<div class="analytics-empty">Your 0–10 check-ins will appear here after you log them.</div>';
      return;
    }
    els.trendList.innerHTML = metrics.map(metric => {
      const delta = metric.priorAvg === null ? null : metric.currentAvg - metric.priorAvg;
      const direction = delta === null ? '' : delta > .15 ? '↑' : delta < -.15 ? '↓' : '→';
      const deltaText = delta === null ? `No prior ${analyticsRange}-day comparison` : `${direction} ${Math.abs(delta).toFixed(1)} vs prior ${analyticsRange}D`;
      return `<div class="trend-row">
        <div class="trend-copy"><strong>${escapeHtml(metric.item.name)}</strong><span>${metric.current.length} logged · ${escapeHtml(deltaText)}</span></div>
        <div class="trend-chart">${sparkline(metric.current)}</div>
        <div class="trend-average"><strong>${metric.currentAvg.toFixed(1)}</strong><span>/10 avg</span></div>
      </div>`;
    }).join('');
  }

  function sparkline(values) {
    if (!values.length) return '';
    const width = 104, height = 34, pad = 3;
    if (values.length === 1) {
      const y = height - pad - (values[0] / 10) * (height - pad * 2);
      return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="One value: ${values[0]}"><circle cx="${width/2}" cy="${y.toFixed(1)}" r="3"></circle></svg>`;
    }
    const points = values.map((value,index) => {
      const x = pad + index / (values.length - 1) * (width - pad * 2);
      const y = height - pad - value / 10 * (height - pad * 2);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(' ');
    return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Rating trend"><polyline points="${points}" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"></polyline></svg>`;
  }

  function renderRecentHistory() {
    els.historyList.innerHTML=''; const today=startOfToday(), firstUse=fromDateKey(state.settings.firstUseDate || dateKey(today));
    const maxDays = Math.min(30, Math.max(1, Math.floor((today - firstUse) / 86400000) + 1));
    for(let i=0;i<maxDays;i++){
      const date=shiftDate(today,-i); if (dateKey(date) < dateKey(firstUse)) break;
      const day=state.days[dateKey(date)]||{}, c=completionForDate(date), row=document.createElement('button'); row.type='button'; row.className='history-row';
      row.innerHTML=`<span class="history-date"><strong>${date.getDate()}</strong><span>${new Intl.DateTimeFormat(undefined,{month:'short'}).format(date)}</span></span><span class="history-copy"><strong>${new Intl.DateTimeFormat(undefined,{weekday:'short'}).format(date)}${i===0?' · Today':''}</strong><span>${c.completed} of ${c.total} required</span><span class="history-bar"><span style="width:${c.percent}%"></span></span></span><span class="history-mood">Mood<br><b>${getLatestMood(day)??'—'}</b></span>`;
      row.addEventListener('click',()=>{selectedDate=date;switchView('today');renderToday();}); els.historyList.appendChild(row);
    }
  }

  function formatShortDate(date) { return new Intl.DateTimeFormat(undefined,{month:'short',day:'numeric'}).format(date); }

  function renderSetup() {
    els.wakeTimeInput.value=state.settings.wakeTime; els.bedTimeInput.value=state.settings.bedTime; els.themeInput.value=state.settings.theme||'calm'; els.routineEditor.innerHTML='';
    ['morning','day','evening'].forEach(section=>{
      const sectionItems=state.items.filter(i=>i.section===section).sort((a,b)=>(a.order??0)-(b.order??0));
      sectionItems.forEach((item,idx)=>{
        const row=document.createElement('div'); row.className='editor-row';
        row.innerHTML=`<div class="editor-copy"><strong>${escapeHtml(item.name)}</strong><span>${sectionLabels[section][0]} · ${typeLabels[item.type]||item.type} · ${frequencyLabel(item)}${item.optional?' · Optional':''}</span></div><div class="editor-actions"><button class="move-button" type="button" aria-label="Move up" ${idx===0?'disabled':''}>↑</button><button class="move-button" type="button" aria-label="Move down" ${idx===sectionItems.length-1?'disabled':''}>↓</button><button class="edit-button" type="button">Edit</button></div>`;
        const buttons=row.querySelectorAll('button'); buttons[0].addEventListener('click',()=>moveItem(item,-1)); buttons[1].addEventListener('click',()=>moveItem(item,1)); buttons[2].addEventListener('click',()=>openItemDialog(item)); els.routineEditor.appendChild(row);
      });
    });
  }
  function moveItem(item,direction) {
    const sectionItems=state.items.filter(i=>i.section===item.section).sort((a,b)=>(a.order??0)-(b.order??0)); const idx=sectionItems.findIndex(i=>i.id===item.id), swap=sectionItems[idx+direction]; if(!swap)return;
    const a=state.items.find(i=>i.id===item.id), b=state.items.find(i=>i.id===swap.id); const ao=a.order??idx, bo=b.order??idx+direction; a.order=bo; b.order=ao; saveState(); renderAll();
  }
  function openItemDialog(item=null) {
    els.editingItemId.value=item?.id||''; els.dialogTitle.textContent=item?'Edit item':'Add item'; els.itemNameInput.value=item?.name||''; els.itemSectionInput.value=item?.section||'morning'; els.itemTypeInput.value=item?.type||'checkbox'; els.itemFrequencyInput.value=item?.frequency||'daily'; els.itemTargetInput.value=item?.target??''; els.itemUnitInput.value=item?.unit||''; els.itemOptionalInput.checked=Boolean(item?.optional); els.deleteItemButton.hidden=!item;
    els.customDaysField.querySelectorAll('input').forEach(cb=>cb.checked=(item?.days||[]).includes(Number(cb.value))); toggleBuilderFields(); els.itemDialog.showModal(); setTimeout(()=>els.itemNameInput.focus(),50);
  }
  function toggleBuilderFields() { els.numberGoalFields.hidden=els.itemTypeInput.value!=='number'; els.customDaysField.hidden=els.itemFrequencyInput.value!=='custom'; }
  function saveRoutineItem(event) {
    event.preventDefault(); const name=els.itemNameInput.value.trim(); if(!name)return; const days=[...els.customDaysField.querySelectorAll('input:checked')].map(cb=>Number(cb.value));
    if(els.itemFrequencyInput.value==='custom'&&!days.length){showToast('Choose at least one day');return;}
    const payload={name,section:els.itemSectionInput.value,type:els.itemTypeInput.value,frequency:els.itemFrequencyInput.value,days,optional:els.itemOptionalInput.checked,unit:els.itemTypeInput.value==='number'?els.itemUnitInput.value.trim():'',target:els.itemTypeInput.value==='number'&&els.itemTargetInput.value!==''?Number(els.itemTargetInput.value):null};
    const id=els.editingItemId.value; if(id){const idx=state.items.findIndex(i=>i.id===id);if(idx>=0)state.items[idx]={...state.items[idx],...payload};} else { const same=state.items.filter(i=>i.section===payload.section); const max=same.reduce((m,i)=>Math.max(m,Number(i.order)||0),-1); state.items.push({id:`item-${Date.now()}-${Math.random().toString(36).slice(2,7)}`,order:max+1,createdDate:dateKey(startOfToday()),...payload}); }
    saveState(); els.itemDialog.close(); renderAll(); showToast(id?'Routine item updated':'Routine item added');
  }
  function deleteRoutineItem() { const id=els.editingItemId.value;if(!id)return;const item=state.items.find(i=>i.id===id);if(!item||!confirm(`Delete “${item.name}”?`))return;state.items=state.items.filter(i=>i.id!==id);saveState();els.itemDialog.close();renderAll();showToast('Routine item deleted'); }

  async function handleBackgroundImage(event) {
    const file=event.target.files?.[0]; event.target.value=''; if(!file)return;
    if(file.size>12*1024*1024){alert('Please choose an image under 12 MB.');return;}
    try{state.settings.backgroundImage=await compressImage(file);saveState();applyPersonalization();showToast('Background updated');}catch{alert('Could not use that image. Try a JPG or PNG.');}
  }
  function compressImage(file) { return new Promise((resolve,reject)=>{const reader=new FileReader();reader.onerror=reject;reader.onload=()=>{const img=new Image();img.onerror=reject;img.onload=()=>{const max=1400,scale=Math.min(1,max/Math.max(img.width,img.height)),canvas=document.createElement('canvas');canvas.width=Math.round(img.width*scale);canvas.height=Math.round(img.height*scale);canvas.getContext('2d').drawImage(img,0,0,canvas.width,canvas.height);resolve(canvas.toDataURL('image/jpeg',.72));};img.src=reader.result;};reader.readAsDataURL(file);}); }
  function applyPersonalization() { document.body.dataset.theme=state.settings.theme||'calm'; document.body.style.setProperty('--custom-bg',state.settings.backgroundImage?`url("${state.settings.backgroundImage}")`:'none'); document.body.classList.toggle('has-custom-bg',Boolean(state.settings.backgroundImage)); }

  async function copyDailySummary() {
    const day=state.days[dateKey(selectedDate)]||{}, c=completionForDate(selectedDate), lines=[`Daily Routine — ${new Intl.DateTimeFormat(undefined,{month:'short',day:'numeric',year:'numeric'}).format(selectedDate)}`,`Required: ${c.completed}/${c.total} (${c.percent}%)`,`Optional logged: ${c.optionalLogged}/${c.optionalTotal}`];
    scheduledItemsForDate(selectedDate).forEach(item=>{const value=day.entries?.[item.id];if(entryIsLogged(item,value))lines.push(`${item.name}: ${formatEntry(item,value)}`);});
    try{await navigator.clipboard.writeText(lines.join('\n'));showToast('Daily summary copied');}catch{showToast('Could not copy summary');}
  }
  function formatEntry(item,value){if(item.type==='checkbox')return value?'Completed':'Not completed';if(item.type==='scale')return `${value}/10`;return `${value}${item.unit?' '+item.unit:''}`;}
  function exportCsv() {
    const rows=[['Date','Completion %','Required Completed','Required Total','Optional Logged','Section','Routine Item','Input Type','Optional','Target','Unit','Value']];
    Object.keys(state.days).sort().forEach(key=>{const date=fromDateKey(key),day=state.days[key],c=completionForDate(date),scheduled=scheduledItemsForDate(date); if(!scheduled.length)rows.push([key,c.percent,c.completed,c.total,c.optionalLogged,'','','','','','','']); else scheduled.forEach(item=>rows.push([key,c.percent,c.completed,c.total,c.optionalLogged,sectionLabels[item.section][0],item.name,typeLabels[item.type],item.optional?'Yes':'No',item.target??'',item.unit||'',formatEntry(item,day.entries?.[item.id]??'')]));});
    downloadBlob(rows.map(r=>r.map(csvCell).join(',')).join('\r\n'),`daily-routine-progress-${dateKey(startOfToday())}.csv`,'text/csv;charset=utf-8');showToast('CSV exported');
  }
  function exportJson(){downloadBlob(JSON.stringify({version:1.2,exportedAt:new Date().toISOString(),state},null,2),`daily-routine-backup-${dateKey(startOfToday())}.json`,'application/json');showToast('Backup downloaded');}
  async function importJson(event){const file=event.target.files?.[0];event.target.value='';if(!file)return;try{const payload=JSON.parse(await file.text()),incoming=payload.state||payload;if(!incoming||!Array.isArray(incoming.items)||typeof incoming.days!=='object')throw new Error();if(!confirm('Restore this backup? It will replace current app data on this device.'))return;state={settings:{...DEFAULT_STATE.settings,...(incoming.settings||{})},items:incoming.items.map(normalizeItem),days:incoming.days};ensureFirstUseDate();saveState();applyPersonalization();renderAll();showToast('Backup restored');}catch{alert('That file does not look like a valid Daily Routine backup.');}}
  function resetData(){if(!confirm('Reset all routines, history, and settings on this device?'))return;state=structuredClone(DEFAULT_STATE);state.settings.firstUseDate=dateKey(startOfToday());ensureFirstUseDate();saveState();selectedDate=startOfToday();applyPersonalization();renderAll();showToast('App reset');}

  function greetingForHour(hour){return hour<12?'Good morning':hour<17?'Good afternoon':'Good evening';}
  function formatTime(value){if(!value)return'—';const[h,m]=value.split(':').map(Number),d=new Date();d.setHours(h,m,0,0);return new Intl.DateTimeFormat(undefined,{hour:'numeric',minute:'2-digit'}).format(d);}
  function frequencyLabel(item){const v=item.frequency;if(v==='weekdays')return'Weekdays';if(v==='weekends')return'Weekends';if(v==='custom'){const labels=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];return(item.days||[]).sort((a,b)=>a-b).map(d=>labels[d]).join(', ')||'Specific days';}return'Every day';}
  function csvCell(value){const s=String(value??'');return/[",\n\r]/.test(s)?`"${s.replaceAll('"','""')}"`:s;}
  function downloadBlob(content,filename,type){const blob=new Blob([content],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  function escapeHtml(value){return String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
  function debounce(fn,delay){let timer;return(...args)=>{clearTimeout(timer);timer=setTimeout(()=>fn(...args),delay);};}
  function showToast(message){clearTimeout(toastTimer);els.toast.textContent=message;els.toast.classList.add('show');toastTimer=setTimeout(()=>els.toast.classList.remove('show'),1800);}
})();
