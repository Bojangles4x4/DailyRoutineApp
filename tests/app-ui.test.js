const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');

const baseURL = process.env.DAILY_ROUTINE_TEST_URL || 'http://127.0.0.1:9878/';

function localDateKey(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

(async () => {
  const bravePath = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.DAILY_ROUTINE_BROWSER || (fs.existsSync(bravePath) ? bravePath : undefined)
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    window.__dailyRoutineNativeMessages = [];
    window.DailyRoutineNative = { postMessage(message) { window.__dailyRoutineNativeMessages.push(message); } };
  });

  await page.goto(baseURL, { waitUntil: 'networkidle' });
  assert.equal(await page.locator('#truthHeroTitle').textContent(), 'Truth Before Tasks');
  assert.equal(await page.locator('#truthEnterDayButton').isDisabled(), true);

  const today = localDateKey();
  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    state.settings.truthBeforeTasks.completions[key] = new Date().toISOString();
    delete state.settings.truthBeforeTasks.sessions[key];
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });

  await page.locator('[data-view="setup"]').click();
  assert.equal((await page.locator('#pageTitle').textContent()).trim(), 'Daily Routine');
  assert.equal(await page.locator('#pageContext').count(), 0);
  assert.equal(await page.locator('#setupOverview').isVisible(), true);
  await page.locator('[data-setup-target="health"]').click();
  assert.ok(await page.locator('#appleWatchQuickActionInput option').count() > 1);
  await page.locator('#appleWatchQuickActionInput').selectOption('routine:morning-meds');
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('dailyRoutineApp.v1')).settings.watchQuickAction), 'routine:morning-meds');
  const watchContext = await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'watch.context.update')?.value);
  assert.ok(watchContext.items.some(item => item.id === 'morning-meds' && item.action === 'takeMedication'));
  assert.equal(watchContext.customAction.itemId, 'morning-meds');

  await page.evaluate(key => {
    const state = window.DailyRoutineApp.getState();
    state.days[key] ||= { entries: {}, skippedItems: {} };
    state.days[key].entries['morning-prayer'] = true;
    window.DailyRoutineApp.saveState();
  }, today);
  await page.locator('[data-view="today"]').click();
  await page.locator('[data-view="setup"]').click();
  await page.locator('[data-setup-target="health"]').click();
  assert.match(await page.locator('#earnedAccessMorningStatus').textContent(), /1 of 3 complete · 5 min added today/);

  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 4820, sleepHours: 0, workoutCount: 0, sourceNames: ['Garmin Connect', 'Apple Watch'] } } }));
  });
  assert.match(await page.locator('#healthSourceDetail').textContent(), /Garmin Connect/);
  await page.locator('#earnedAccessLabelInput').fill('Reddit');
  await page.locator('#earnedAccessStepsInput').fill('1000');
  await page.locator('#earnedAccessMinutesInput').fill('20');
  await page.locator('#earnedAccessModeInput').selectOption('fixed');
  await page.locator('#startEarnedAccessButton').click();
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), 'Reddit step goal');
  assert.match(await page.locator('.earned-access-disclosure').textContent(), /Screen Time blocking/);
  await page.locator('#openEarnedAccessControlsButton').click();
  assert.equal(await page.evaluate(() => window.__dailyRoutineNativeMessages.at(-1).action), 'earned.access.controls.open');
  assert.match(await page.locator('#earnedAccessDetail').textContent(), /0 \/ 1,000/);
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1')).active.baselineSteps), 4820);

  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 5320, sleepHours: 0, workoutCount: 0 } } }));
  });
  assert.match(await page.locator('#earnedAccessDetail').textContent(), /500 \/ 1,000/);
  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 5820, sleepHours: 0, workoutCount: 0 } } }));
  });
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '25 of 60 minutes ready');
  assert.equal(await page.locator('#useEarnedAccessButton').isDisabled(), false);
  await page.locator('#useEarnedAccessButton').click();
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), '15 minutes available');
  assert.equal((await page.locator('#earnedAccessBadge').textContent()).trim(), 'Reward earned');
  const nativeAllowance = await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'earned.access.allow'));
  assert.equal(nativeAllowance?.value?.minutes, 15);
  assert.match(nativeAllowance?.value?.redemptionId, /^allowance-/);
  const earnedAccessData = await page.evaluate(key => {
    const device = JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1'));
    const syncedState = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    return { rounds: device.roundsByDate[key], active: device.active, bank: device.bankByDate[key], earned: device.earnedByDate[key], syncedSettings: syncedState.settings };
  }, today);
  assert.equal(earnedAccessData.rounds, 1);
  assert.equal(earnedAccessData.active, null);
  assert.equal(earnedAccessData.bank, 10);
  assert.equal(earnedAccessData.earned, 25);
  assert.equal(Object.hasOwn(earnedAccessData.syncedSettings, 'earnedAccess'), false);

  const earnedAccessLayout = await page.locator('#earnedAccessCard').evaluate(node => {
    const rect = node.getBoundingClientRect();
    return { left: rect.left, right: rect.right, viewport: innerWidth };
  });
  assert.ok(earnedAccessLayout.left >= 0);
  assert.ok(earnedAccessLayout.right <= earnedAccessLayout.viewport);
  await page.locator('#setupBackButton').click();
  await page.locator('[data-setup-target="faith"]').click();
  await page.locator('#openTruthRemindersButton').click();
  assert.equal(await page.evaluate(() => window.__dailyRoutineNativeMessages.at(-1).action), 'truth.reminders.open');
  assert.match(await page.locator('#truthCoreInput').inputValue(), /Not for righteousness\. Because of righteousness\./);
  assert.match(await page.locator('#truthCoreInput').inputValue(), /Faithfulness, not infallibility/);
  assert.match(await page.locator('#truthCoreInput').inputValue(), /I do not need to agonize over every choice/);
  await page.locator('#createTruthThemeButton').click();
  assert.equal(await page.locator('#truthThemeForm').isVisible(), true);
  assert.equal(await page.locator('#truthWhoGodInput').count(), 0);
  assert.equal(await page.locator('#truthChristInput').count(), 0);
  await page.locator('#truthThemeNameInput').fill('An open-ended theme');
  await page.locator('#truthThemeBodyInput').fill('A body that can hold any theme Taylor chooses.');
  await page.locator('#truthScripturesInput').fill('Psalm 46:10 | Be still, and know that I am God.');
  await page.locator('#truthThemeSubmitButton').click();
  assert.match(await page.locator('#truthThemeList').textContent(), /An open-ended theme/);

  assert.equal(await page.locator('.conviction-editor-item').count(), 16);
  assert.match(await page.locator('#convictionIntroInput').inputValue(), /unchanging Word of God/);
  while (await page.locator('.conviction-editor-item').count() > 2) {
    await page.locator('.conviction-editor-item').last().evaluate(node => node.remove());
  }
  await page.locator('.conviction-editor-item').nth(0).locator('.conviction-text-input').fill('Choose faithfulness over urgency.');
  await page.locator('.conviction-editor-item').nth(0).locator('.conviction-scripture-input').fill('Proverbs 16:9 | The heart of man plans his way, but the Lord establishes his steps.');
  await page.locator('.conviction-editor-item').nth(1).locator('summary').click();
  await page.locator('.conviction-editor-item').nth(1).locator('.conviction-text-input').fill('Respond thoughtfully instead of reacting quickly.');
  await page.locator('#saveConvictionsButton').click();
  assert.equal((await page.locator('#convictionStatus').textContent()).trim(), '2 active');

  await page.locator('#setupBackButton').click();
  await page.locator('[data-setup-target="routine"]').click();
  const setupTimeLayout = await page.locator('.daily-anchor-list').evaluate(node => {
    const card = node.closest('.card').getBoundingClientRect();
    const inputs = [...node.querySelectorAll('input')].map(input => input.getBoundingClientRect());
    return { cardLeft: card.left, cardRight: card.right, inputs: inputs.map(rect => ({ left: rect.left, right: rect.right, height: rect.height })) };
  });
  setupTimeLayout.inputs.forEach(rect => {
    assert.ok(rect.left >= setupTimeLayout.cardLeft);
    assert.ok(rect.right <= setupTimeLayout.cardRight);
    assert.equal(Math.round(rect.height), 38);
  });
  if (process.env.DAILY_ROUTINE_SCREENSHOT_DIR) {
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({ path: `${process.env.DAILY_ROUTINE_SCREENSHOT_DIR}/daily-routine-build13-setup.png` });
  }

  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    delete state.settings.truthBeforeTasks.completions[key];
    delete state.settings.truthBeforeTasks.sessions[key];
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });
  assert.equal(await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action.startsWith('morning.foundation'))?.action), 'morning.foundation.lock');
  for (let index = 0; index < 5; index += 1) await page.locator('#truthContinueButton').click();
  assert.equal(await page.locator('#truthHeroTitle').textContent(), 'Convictions Before Circumstances');
  assert.equal((await page.locator('#pageTitle').textContent()).trim(), 'Daily Routine');
  assert.equal(await page.locator('#pageContext').count(), 0);
  assert.match(await page.locator('#truthStepBody').textContent(), /Choose faithfulness over urgency/);
  assert.match(await page.locator('#truthStepBody').textContent(), /Proverbs 16:9/);
  assert.equal(await page.locator('#truthEnterDayButton').isDisabled(), true);
  if (process.env.DAILY_ROUTINE_SCREENSHOT_DIR) {
    await page.screenshot({ path: `${process.env.DAILY_ROUTINE_SCREENSHOT_DIR}/daily-routine-build13-convictions.png` });
  }

  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    state.settings.truthBeforeTasks.completions[key] = new Date().toISOString();
    delete state.settings.truthBeforeTasks.sessions[key];
    state.days[key] ||= { entries: {}, skippedItems: {}, mode: 'normal' };
    state.days[key].entries['morning-meds'] = { taken: true, time: '07:30', timestamp: new Date().toISOString(), dose: '', note: '' };
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });
  assert.equal(await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action.startsWith('morning.foundation'))?.action), 'morning.foundation.complete');

  await page.locator('[data-view="setup"]').click();
  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    state.days[key].entries['morning-prayer'] = true;
    state.days[key].entries['morning-teeth'] = true;
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
    localStorage.removeItem('dailyRoutine.earnedAccess.device.v1');
  }, today);
  await page.reload({ waitUntil: 'networkidle' });
  await page.locator('[data-view="setup"]').click();
  await page.locator('[data-setup-target="health"]').click();
  assert.equal((await page.locator('#earnedAccessMorningStatus').textContent()).trim(), '3 of 3 complete · 15 min added today');
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '15 of 60 minutes ready');
  await page.reload({ waitUntil: 'networkidle' });
  await page.locator('[data-view="setup"]').click();
  await page.locator('[data-setup-target="health"]').click();
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '15 of 60 minutes ready');
  assert.equal(await page.locator('#useEarnedAccessButton').isDisabled(), false);
  await page.locator('#useEarnedAccessButton').click();
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), '15 minutes available');
  await page.locator('[data-view="today"]').click();

  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'watch.event', value: { id: 'watch-toggle-1', action: 'toggleRoutine', itemId: 'day-movement' } } }));
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'watch.event', value: { id: 'watch-note-1', action: 'captureNote', text: 'Pray for wisdom', noteType: 'prayer' } } }));
  });
  const watchUpdates = await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    return { movement: state.days[key].entries['day-movement'], note: state.notes.at(-1) };
  }, today);
  assert.equal(watchUpdates.movement, true);
  assert.equal(watchUpdates.note.text, 'Pray for wisdom');
  assert.equal(watchUpdates.note.type, 'prayer');
  assert.equal(watchUpdates.note.source, 'Apple Watch');

  const medicationLayout = await page.locator('.medication-detail-grid').first().evaluate(node => {
    const bounds = node.closest('.task-row').getBoundingClientRect();
    const inputs = [...node.querySelectorAll('input')].map(input => input.getBoundingClientRect());
    return { left: bounds.left, right: bounds.right, inputs: inputs.map(rect => ({ left: rect.left, right: rect.right, height: rect.height })) };
  });
  assert.equal(medicationLayout.inputs.length, 2);
  assert.ok(medicationLayout.inputs[0].right <= medicationLayout.inputs[1].left);
  medicationLayout.inputs.forEach(rect => {
    assert.ok(rect.left >= medicationLayout.left);
    assert.ok(rect.right <= medicationLayout.right);
    assert.equal(Math.round(rect.height), 44);
  });

  const sleepEnd = new Date();
  sleepEnd.setHours(6, 45, 0, 0);
  const sleepStart = new Date(sleepEnd);
  sleepStart.setDate(sleepStart.getDate() - 1);
  sleepStart.setHours(22, 55, 0, 0);
  await page.evaluate(({ start, end }) => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 0, sleepHours: 7.8, workoutCount: 0, sleepStart: start, sleepEnd: end } } }));
  }, { start: sleepStart.toISOString(), end: sleepEnd.toISOString() });
  await page.locator('#applyHealthSleepButton').click();
  assert.equal(await page.locator('#healthSleepDialog').isVisible(), true);
  assert.equal(await page.locator('#healthBedDateInput').inputValue(), localDateKey(sleepStart));
  assert.equal(await page.locator('#healthWakeDateInput').inputValue(), localDateKey(sleepEnd));
  assert.equal(await page.locator('#actualWakeInput').inputValue(), '');
  await page.locator('#healthSleepForm button[type="submit"]').click();
  const sleepDays = await page.evaluate(({ wakeKey, priorKey }) => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    return { wake: state.days[wakeKey], prior: state.days[priorKey] };
  }, { wakeKey: localDateKey(sleepEnd), priorKey: localDateKey(sleepStart) });
  assert.equal(sleepDays.wake.actualWakeTime, '06:45');
  assert.equal(sleepDays.wake.actualBedTime, undefined);
  assert.equal(sleepDays.prior?.actualBedTime, '22:55');
  assert.doesNotMatch(await page.locator('.actual-time-card .micro-copy').textContent(), /medication/i);

  // A second review preserves existing times unless the person explicitly chooses replacement.
  await page.locator('#applyHealthSleepButton').click();
  assert.equal(await page.locator('#confirmHealthBedInput').isChecked(), false);
  assert.equal(await page.locator('#confirmHealthWakeInput').isChecked(), false);
  await page.locator('#healthSleepForm button[type="submit"]').click();
  assert.match(await page.locator('#healthSleepReviewStatus').textContent(), /Select at least one/);
  await page.locator('#closeHealthSleepButton').click();

  // Actual sleep fields remain separate from Now at phone widths, including 12-hour text.
  for (const width of [320, 390, 440]) {
    await page.setViewportSize({ width, height: 844 });
    const timeRows = await page.locator('.actual-time-field').evaluateAll(rows => rows.map(row => {
      const input = row.querySelector('input').getBoundingClientRect();
      const button = row.querySelector('button').getBoundingClientRect();
      return { right: input.right, buttonLeft: button.left, buttonRight: button.right, viewport: innerWidth };
    }));
    timeRows.forEach(row => { assert.ok(row.right + 8 <= row.buttonLeft); assert.ok(row.buttonRight <= row.viewport); });
  }
  await page.setViewportSize({ width: 390, height: 844 });

  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  const navPosition = await page.locator('.bottom-nav').evaluate(node => {
    const rect = node.getBoundingClientRect();
    return { position: getComputedStyle(node).position, bottom: rect.bottom, viewport: innerHeight };
  });
  assert.equal(navPosition.position, 'fixed');
  assert.ok(Math.abs(navPosition.bottom - navPosition.viewport) < 2);

  assert.deepEqual(errors, []);
  await browser.close();
  console.log('App UI regression tests passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
