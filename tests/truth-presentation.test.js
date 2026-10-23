const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser' });
  const baseURL = process.env.DAILY_ROUTINE_TEST_URL || 'http://127.0.0.1:9878/';
  async function fixture({ count = 3, currentStep = 0, convictions = true } = {}) {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
    await page.addInitScript(({ count, currentStep, convictions }) => {
      const now = Date.now();
      const date = new Date();
      const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
      window.__nativeMessages = [];
      window.DailyRoutineNative = { postMessage: message => window.__nativeMessages.push(message) };
      if (localStorage.getItem('truth-presentation-fixture-seeded')) return;
      localStorage.setItem('truth-presentation-fixture-seeded', 'true');
      localStorage.setItem('dailyRoutineApp.v1', JSON.stringify({
        settings: { truthBeforeTasks: {
          personalPlea: 'Begin quietly.', openingPrayer: 'Father, help me remember.', coreTruths: ['Grace is not earned.'],
          themes: [{ id: 'test-theme', name: 'Remember grace', body: 'God’s grace is the ground beneath every faithful step.',
            scriptures: Array.from({ length: count }, (_, index) => ({ reference: `Passage ${index + 1}`, text: `Saved verse ${index + 1}.` })) }],
          convictions: { intro: 'Remember.', items: convictions ? [{ id: 'first', text: 'Keep trusting.' }, { id: 'second', text: 'Do the next thing in faith.' }] : [] },
          sessions: { [key]: { startedAt: now - 600000, convictionsStartedAt: now - 300000, currentStep,
            visited: Array.from({ length: currentStep + 1 }, (_, index) => index) } }, completions: {}
        } }, items: [], days: {}, memories: [], notes: [], weeklyReviews: {}
      }));
    }, { count, currentStep, convictions });
    await page.goto(baseURL, { waitUntil: 'networkidle' });
    return page;
  }
  for (const count of [1, 2, 3]) {
    const page = await fixture({ count });
    const before = await page.evaluate(() => Object.values(window.DailyRoutineApp.getState().settings.truthBeforeTasks.sessions)[0].startedAt);
    await page.locator('#truthContinueButton').click();
    await page.locator('#truthContinueButton').click();
    assert.equal(await page.locator('#truthStepBody .truth-theme-scripture').count(), count);
    assert.match(await page.locator('#truthStepBody .truth-lead').textContent(), /ground beneath/);
    for (let index = 1; index <= count; index++) {
      assert.equal(await page.locator('#truthStepBody cite').nth(index - 1).textContent(), `Passage ${index}`);
      assert.equal(await page.locator('#truthStepBody blockquote p').nth(index - 1).textContent(), `Saved verse ${index}.`);
    }
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    if (count === 3 && process.env.DAILY_ROUTINE_BUILD46_SCREENSHOTS) {
      fs.mkdirSync(process.env.DAILY_ROUTINE_BUILD46_SCREENSHOTS, { recursive: true });
      await page.screenshot({ path: `${process.env.DAILY_ROUTINE_BUILD46_SCREENSHOTS}/truth-theme-and-verses.png`, fullPage: true });
    }
    await page.locator('#truthContinueButton').click();
    assert.equal(await page.locator('#truthStepBody blockquote').count(), 0);
    await page.locator('#truthContinueButton').click();
    assert.match(await page.locator('#truthStepBody').textContent(), /Keep trusting/);
    let session = await page.evaluate(() => Object.values(window.DailyRoutineApp.getState().settings.truthBeforeTasks.sessions)[0]);
    assert.equal(session.currentStep, 5);
    assert.equal(session.startedAt, before);
    await page.reload({ waitUntil: 'networkidle' });
    assert.match(await page.locator('#truthStepBody').textContent(), /Keep trusting/);
    await page.locator('#truthPreviousButton').click();
    assert.match(await page.locator('#truthStepBody').textContent(), /Grace is not earned/);
    await page.locator('#truthPreviousButton').click();
    assert.equal(await page.locator('#truthStepBody blockquote').count(), count);
    assert.equal(await page.evaluate(() => Object.values(window.DailyRoutineApp.getState().settings.truthBeforeTasks.sessions)[0].convictionsStartedAt), session.convictionsStartedAt);
    await page.close();
  }
  const legacyScripture = await fixture({ currentStep: 4 });
  assert.equal(await legacyScripture.locator('#truthStepBody blockquote').count(), 3);
  assert.equal(await legacyScripture.evaluate(() => Object.values(window.DailyRoutineApp.getState().settings.truthBeforeTasks.sessions)[0].currentStep), 2);
  await legacyScripture.close();
  const legacyConviction = await fixture({ currentStep: 6 });
  assert.match(await legacyConviction.locator('#truthStepBody').textContent(), /Do the next thing in faith/);
  assert.equal(await legacyConviction.evaluate(() => Object.values(window.DailyRoutineApp.getState().settings.truthBeforeTasks.sessions)[0].currentStep), 6);
  await legacyConviction.close();
  const noConvictions = await fixture({ convictions: false });
  for (let index = 0; index < 3; index++) await noConvictions.locator('#truthContinueButton').click();
  assert.equal(await noConvictions.locator('#truthContinueButton').isHidden(), true);
  assert.equal(await noConvictions.locator('#truthEnterDayButton').isEnabled(), true);
  await noConvictions.locator('#truthEnterDayButton').click();
  assert.equal(await noConvictions.evaluate(() => document.body.classList.contains('truth-locked')), false);
  assert.equal(await noConvictions.evaluate(() => window.__nativeMessages.some(message => message.action === 'app.appearance.update' && message.value.theme === 'calm')), true);
  await browser.close();
  console.log('Truth presentation: verse visibility, legacy sessions, navigation, timers, and completion passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
