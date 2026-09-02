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
    window.DailyRoutineNative = { postMessage() {} };
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

  const setupTimeLayout = await page.locator('.daily-time-fields').evaluate(node => {
    const card = node.closest('.card').getBoundingClientRect();
    const inputs = [...node.querySelectorAll('input')].map(input => input.getBoundingClientRect());
    return { cardLeft: card.left, cardRight: card.right, inputs: inputs.map(rect => ({ left: rect.left, right: rect.right, height: rect.height })) };
  });
  setupTimeLayout.inputs.forEach(rect => {
    assert.ok(rect.left >= setupTimeLayout.cardLeft);
    assert.ok(rect.right <= setupTimeLayout.cardRight);
    assert.equal(Math.round(rect.height), 44);
  });
  if (process.env.DAILY_ROUTINE_SCREENSHOT_DIR) {
    await page.screenshot({ path: `${process.env.DAILY_ROUTINE_SCREENSHOT_DIR}/daily-routine-build6-setup.png` });
  }

  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    delete state.settings.truthBeforeTasks.completions[key];
    delete state.settings.truthBeforeTasks.sessions[key];
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });
  for (let index = 0; index < 5; index += 1) await page.locator('#truthContinueButton').click();
  assert.equal(await page.locator('#truthHeroTitle').textContent(), 'Convictions Before Circumstances');
  assert.match(await page.locator('#truthStepBody').textContent(), /Choose faithfulness over urgency/);
  assert.match(await page.locator('#truthStepBody').textContent(), /Proverbs 16:9/);
  assert.equal(await page.locator('#truthEnterDayButton').isDisabled(), true);
  if (process.env.DAILY_ROUTINE_SCREENSHOT_DIR) {
    await page.screenshot({ path: `${process.env.DAILY_ROUTINE_SCREENSHOT_DIR}/daily-routine-build6-convictions.png` });
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
  const sleepDays = await page.evaluate(({ wakeKey, priorKey }) => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    return { wake: state.days[wakeKey], prior: state.days[priorKey] };
  }, { wakeKey: localDateKey(sleepEnd), priorKey: localDateKey(sleepStart) });
  assert.equal(sleepDays.wake.actualWakeTime, '06:45');
  assert.equal(sleepDays.wake.actualBedTime, '22:55');
  assert.equal(sleepDays.prior?.actualBedTime, undefined);
  assert.doesNotMatch(await page.locator('.actual-time-card .micro-copy').textContent(), /medication/i);

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
