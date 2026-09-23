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
  assert.equal(await page.locator('#accountabilitySharingCard').count(), 1);
  assert.equal(await page.locator('#appVersion').textContent(), 'v1.25.0 · Build 27');
  assert.match(await page.locator('#openAccountabilityFromSetupButton').textContent(), /Open private accountability/);
  assert.equal(await page.locator('#accountabilitySharingSignedOut').evaluate(element => element.hidden), false);
  assert.match(await page.locator('#accountabilitySharingSignedOut').textContent(), /Connect Private Sync first/);
  assert.equal(await page.locator('#accountabilityDashboardCard').evaluate(element => element.hidden), true);
  assert.equal(await page.locator('#connectRoutineAgentButton').count(), 1);
  assert.match(await page.locator('#dataBackupCard').textContent(), /routine definitions and daily completion history/);
  assert.match(await page.locator('#routineAgentFileStatus').textContent(), /Not connected|Brave will connect|Reconnect|Connected/);

  const partnerPage = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const partnerCloudRequests = [];
  await partnerPage.addInitScript(() => {
    localStorage.setItem('dailyRoutine.sync.session.v1', JSON.stringify({
      access_token: 'partner-access',
      refresh_token: 'partner-refresh',
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      user: { id: 'partner-1', email: 'partner@example.com' }
    }));
  });
  await partnerPage.route('https://shmvxujnlbolgcjwwewe.supabase.co/**', async route => {
    const url = route.request().url();
    partnerCloudRequests.push(url);
    const relationship = {
      id: 'relationship-1', owner_id: 'owner-1', owner_display_name: 'Taylor', partner_id: 'partner-1',
      partner_email: 'partner@example.com', partner_display_name: 'Accountability Partner', status: 'active',
      permissions: { progressTotals: true, routineNames: true, checkins: false, steps: true, medication: false },
      accepted_at: new Date().toISOString(), updated_at: new Date().toISOString()
    };
    const secondRelationship = {
      ...relationship,
      id: 'relationship-2', owner_id: 'owner-2', owner_display_name: 'Jordan',
      permissions: { progressTotals: true, routineNames: true, checkins: false, steps: false, medication: false }
    };
    if (url.includes('/accountability_relationships?owner_id=')) return route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
    if (url.includes('/accountability_relationships?partner_id=')) return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([relationship, secondRelationship]) });
    if (url.includes('/accountability_snapshots?relationship_id=')) {
      const isSecond = url.includes('relationship-2');
      const daily = Array.from({ length: 7 }, (_, index) => {
        const date = new Date();
        date.setDate(date.getDate() - (6 - index));
        return { date: localDateKey(date), percent: isSecond ? 55 : 80 + (index % 3) * 5, completed: isSecond ? 4 : 7, total: 8, truthBeforeTasks: true };
      });
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([{
        relationship_id: isSecond ? 'relationship-2' : 'relationship-1', owner_id: isSecond ? 'owner-2' : 'owner-1', revision: 2, updated_at: new Date().toISOString(),
        payload: {
          schemaVersion: 2,
          member: { displayName: isSecond ? 'Jordan' : 'Taylor' },
          generatedAt: new Date().toISOString(),
          today: { percent: isSecond ? 55 : 75, completed: isSecond ? 4 : 6, total: 8, truthBeforeTasks: true },
          week: { percent: isSecond ? 60 : 82, strongDays: isSecond ? 1 : 4, trackedDays: 5 },
          daily,
          ...(isSecond ? {} : { steps: { count: 6400, goal: 8000 } }),
          routines: [{ name: 'Prayer', completed: true }, { name: 'Movement', completed: false }],
          routineTrends: [{ name: 'Prayer', completed: 6, scheduled: 7, percent: 86, days: daily.map(day => ({ date: day.date, completed: true })) }]
        }
      }]) });
    }
    return route.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ message: 'Unexpected test request' }) });
  });
  await partnerPage.goto(`${baseURL}?accountability=partner`, { waitUntil: 'networkidle' });
  await partnerPage.waitForFunction(() => document.body.classList.contains('accountability-partner-mode'));
  assert.equal(await partnerPage.locator('body').evaluate(element => element.classList.contains('truth-locked')), false);
  assert.equal((await partnerPage.locator('#pageTitle').textContent()).trim(), 'Accountability');
  assert.equal((await partnerPage.locator('#pageContext').textContent()).trim(), 'Shared progress');
  assert.equal(await partnerPage.locator('#historyView').evaluate(element => element.classList.contains('active')), true);
  assert.equal(await partnerPage.locator('#accountabilityDashboardCard').isVisible(), true);
  assert.equal(await partnerPage.locator('.accountability-roster-person').count(), 2);
  assert.match(await partnerPage.locator('#accountabilityPartnerDetail').textContent(), /Taylor/);
  assert.match(await partnerPage.locator('#accountabilityPartnerDetail').textContent(), /75%/);
  assert.match(await partnerPage.locator('#accountabilityPartnerDetail').textContent(), /Routine trends/);
  assert.equal(await partnerPage.locator('.accountability-day').count(), 7);
  assert.match(await partnerPage.locator('#accountabilityPartnerAccount').textContent(), /Signed in privately/);
  assert.doesNotMatch(await partnerPage.locator('#accountabilityPartnerAccount').textContent(), /partner@example\.com/);
  await partnerPage.locator('#accountabilityPartnerSearchInput').fill('Jordan');
  assert.equal(await partnerPage.locator('.accountability-roster-person').count(), 1);
  assert.match(await partnerPage.locator('.accountability-roster-person').textContent(), /Jordan/);
  await partnerPage.locator('#accountabilityPartnerSearchInput').fill('');
  assert.equal(await partnerPage.locator('#accountabilityPartnerSignOutButton').isVisible(), true);
  assert.equal(await partnerPage.locator('.bottom-nav').evaluate(element => getComputedStyle(element).display), 'none');
  const partnerVisibleSections = await partnerPage.evaluate(() => [...document.querySelectorAll('#historyView > section')]
    .filter(section => getComputedStyle(section).display !== 'none').map(section => section.id));
  assert.deepEqual(partnerVisibleSections, ['accountabilityDashboardCard']);
  assert.equal(partnerCloudRequests.some(url => url.includes('/routine_documents')), false);
  await partnerPage.close();

  const today = localDateKey();
  const lockedCommandResult = await page.evaluate(key => {
    const snapshot = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.snapshot.publish')?.value;
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'routine.commands.pending', value: [{
      schemaVersion: 1,
      id: 'locked-command-1',
      actionID: 'routine.checkbox.set',
      origin: 'test',
      createdAt: new Date().toISOString(),
      localDateKey: key,
      timeZoneIdentifier: Intl.DateTimeFormat().resolvedOptions().timeZone,
      targetID: 'evening-prepare',
      expectedRevision: snapshot.revision,
      requiresFoundationComplete: true,
      payload: { completed: 'true' }
    }] } }));
    return {
      snapshot,
      acknowledgement: [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value,
      prepare: JSON.parse(localStorage.getItem('dailyRoutineApp.v1')).days[key]?.entries?.['evening-prepare']
    };
  }, today);
  assert.equal(lockedCommandResult.snapshot.schemaVersion, 1);
  assert.equal(lockedCommandResult.snapshot.foundationComplete, false);
  assert.equal(lockedCommandResult.snapshot.convictionsEnabled, true);
  assert.equal(lockedCommandResult.snapshot.earnedAccessRemainingMinutes, 0);
  assert.equal(lockedCommandResult.snapshot.earnedAccessDailyLimitMinutes, 60);
  assert.equal(lockedCommandResult.acknowledgement.status, 'rejected');
  assert.match(lockedCommandResult.acknowledgement.message, /Morning Foundation/);
  assert.equal(lockedCommandResult.prepare, undefined);

  const yesterday = localDateKey(new Date(Date.now() - 86_400_000));
  await page.evaluate(({ key, startedAt }) => {
    localStorage.setItem('dailyRoutine.earnedAccess.device.v1', JSON.stringify({
      automaticSteps: true,
      automaticAccess: true,
      activeAllowance: { id: 'yesterday-allowance', minutes: 20, dateKey: key, startedAt },
      bankByDate: { [key]: 10 },
      earnedByDate: { [key]: 30 }
    }));
  }, { key: yesterday, startedAt: `${yesterday}T18:00:00.000Z` });
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForFunction(() => Boolean(window.DailyRoutineApp?.getState()?.settings?.truthBeforeTasks));
  const rolloverProtection = await page.evaluate(() => ({
    activeAllowance: JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1')).activeAllowance,
    lastDirective: [...window.__dailyRoutineNativeMessages].reverse().find(message => ['earned.access.lock', 'earned.access.allow'].includes(message.action))?.action
  }));
  assert.equal(rolloverProtection.activeAllowance, null);
  assert.equal(rolloverProtection.lastDirective, 'earned.access.lock');

  await page.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    state.settings.truthBeforeTasks.completions[key] = new Date().toISOString();
    delete state.settings.truthBeforeTasks.sessions[key];
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });

  const sharedCommandResult = await page.evaluate(key => {
    const snapshot = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.snapshot.publish')?.value;
    const command = {
      schemaVersion: 1,
      id: 'shared-checkbox-command-1',
      actionID: 'routine.checkbox.set',
      origin: 'test',
      createdAt: new Date().toISOString(),
      localDateKey: key,
      timeZoneIdentifier: Intl.DateTimeFormat().resolvedOptions().timeZone,
      targetID: 'evening-prepare',
      expectedRevision: snapshot.revision,
      requiresFoundationComplete: true,
      payload: { completed: 'true' }
    };
    const send = value => window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'routine.commands.pending', value } }));
    const wrongDayCommand = { ...command, id: 'wrong-day-command-1', localDateKey: '1999-01-01' };
    send([wrongDayCommand]);
    const wrongDayAcknowledgement = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value;
    const currentTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const wrongTimeZoneCommand = {
      ...command,
      id: 'wrong-time-zone-command-1',
      timeZoneIdentifier: currentTimeZone === 'Pacific/Honolulu' ? 'America/Chicago' : 'Pacific/Honolulu'
    };
    send([wrongTimeZoneCommand]);
    const wrongTimeZoneAcknowledgement = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value;
    send([command]);
    const firstAcknowledgement = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value;
    send([command]);
    const duplicateAcknowledgement = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value;
    const staleCommand = { ...command, id: 'stale-command-1', targetID: 'evening-teeth' };
    send([staleCommand]);
    const staleAcknowledgement = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.command.acknowledge')?.value;
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    const latestSnapshot = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.snapshot.publish')?.value;
    return {
      initialSnapshot: snapshot,
      latestSnapshot,
      wrongDayAcknowledgement,
      wrongTimeZoneAcknowledgement,
      firstAcknowledgement,
      duplicateAcknowledgement,
      staleAcknowledgement,
      prepare: state.days[key].entries['evening-prepare'],
      eveningTeeth: state.days[key].entries['evening-teeth']
    };
  }, today);
  assert.equal(sharedCommandResult.initialSnapshot.foundationComplete, true);
  assert.equal(sharedCommandResult.initialSnapshot.eligibleItems.some(item => item.id === 'morning-meds'), false);
  assert.equal(sharedCommandResult.wrongDayAcknowledgement.status, 'rejected');
  assert.match(sharedCommandResult.wrongDayAcknowledgement.message, /different local day/);
  assert.equal(sharedCommandResult.wrongTimeZoneAcknowledgement.status, 'rejected');
  assert.match(sharedCommandResult.wrongTimeZoneAcknowledgement.message, /time zone changed/);
  assert.equal(sharedCommandResult.firstAcknowledgement.status, 'applied');
  assert.equal(sharedCommandResult.duplicateAcknowledgement.status, 'applied');
  assert.equal(sharedCommandResult.prepare, true);
  assert.equal(sharedCommandResult.staleAcknowledgement.status, 'rejected');
  assert.match(sharedCommandResult.staleAcknowledgement.message, /changed before/);
  assert.equal(sharedCommandResult.eveningTeeth, undefined);
  assert.ok(sharedCommandResult.latestSnapshot.revision > sharedCommandResult.initialSnapshot.revision);

  assert.equal(await page.locator('#todayView .hero-targets').count(), 0);
  assert.equal(await page.locator('#todayView #heroStatus').count(), 0);
  assert.match(await page.locator('.foundation-copy').textContent(), /your worth is not in what you do, but in what Christ did for you/i);
  assert.equal((await page.locator('.foundation-mark').textContent()).trim(), '100%');
  const todaySectionOrder = await page.evaluate(() => {
    const morning = document.querySelector('#morningRoutineSection [data-routine-section="morning"]');
    const moments = document.querySelector('#postMorningMoments');
    const later = document.querySelector('#laterRoutineSections');
    return Boolean(morning && moments && later
      && (morning.compareDocumentPosition(moments) & Node.DOCUMENT_POSITION_FOLLOWING)
      && (moments.compareDocumentPosition(later) & Node.DOCUMENT_POSITION_FOLLOWING));
  });
  assert.equal(todaySectionOrder, true);

  const compactTodayRow = page.locator('#todayView .routine-task-list .compact-checkbox-row').first();
  assert.equal(await compactTodayRow.isVisible(), true);
  const compactRowGeometry = await compactTodayRow.evaluate(row => {
    const main = row.querySelector(':scope > .task-main').getBoundingClientRect();
    return { rowHeight: row.getBoundingClientRect().height, mainHeight: main.height };
  });
  assert.ok(compactRowGeometry.rowHeight <= 60, `Expected a compact Today row, received ${compactRowGeometry.rowHeight}px`);
  assert.ok(compactRowGeometry.mainHeight >= 48, `Expected a 48px task target, received ${compactRowGeometry.mainHeight}px`);
  assert.equal(await compactTodayRow.locator('.task-meta').count(), 0);
  assert.equal(await page.locator('#todayView .skip-item').count(), 0);
  assert.equal(await page.locator('#todayView .task-row.skipped').count(), 0);
  assert.equal(await page.locator('.day-mode-card').count(), 0);
  assert.equal(await page.locator('.date-nav #dayModeInput').count(), 1);
  assert.equal(await page.locator('.summary-card').count(), 0);
  assert.equal((await page.locator('#morningRoutineSection .check-all').textContent()).trim(), 'All');
  assert.equal(await page.locator('#morningRoutineSection .check-all').getAttribute('aria-label'), 'Complete all unchecked tasks');
  assert.equal((await page.locator('#morningRoutineSection .collapse-section').textContent()).trim(), '⌃');
  assert.equal(await page.locator('#memoryTodayPreview').count(), 0);
  assert.equal(await page.locator('#todayView .linked-more-actions').count(), 1);
  assert.equal(await page.locator('#todayView .linked-more-actions .manual-linked-button').count(), 1);
  const medicationRow = page.locator('#todayView .medication-row').first();
  assert.equal(await medicationRow.isVisible(), true);
  assert.doesNotMatch(await medicationRow.textContent(), /optional/i);
  assert.equal(await medicationRow.locator('.medication-now').count(), 1);
  assert.equal(await medicationRow.locator('.medication-manual').count(), 1);
  const waterRow = page.locator('#todayView .water-task-row').first();
  assert.equal(await waterRow.isVisible(), true);
  assert.equal(await waterRow.locator('.number-step').count(), 2);

  if (process.env.DAILY_ROUTINE_TODAY_SCREENSHOT_DIR) {
    const screenshotDir = process.env.DAILY_ROUTINE_TODAY_SCREENSHOT_DIR;
    fs.mkdirSync(screenshotDir, { recursive: true });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({ path: `${screenshotDir}/today-top.png` });
    await page.locator('#morningRoutineSection').scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollBy(0, -54));
    await page.screenshot({ path: `${screenshotDir}/today-morning.png` });
    await page.evaluate(() => {
      const reminder = document.querySelector('#godMomentReminder');
      reminder.hidden = false;
      document.querySelector('#godMomentReminderText').textContent = 'God met you with patience when you needed it most.';
      document.querySelector('#godMomentReminderDate').textContent = 'Remembered today';
    });
    await page.locator('#postMorningMoments').scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollBy(0, -54));
    await page.screenshot({ path: `${screenshotDir}/today-moments.png` });
    await page.locator('#laterRoutineSections [data-routine-section="day"]').scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollBy(0, -54));
    await page.screenshot({ path: `${screenshotDir}/today-throughout.png` });
    await page.evaluate(key => {
      const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
      state.days[key] ||= { entries: {}, skippedItems: {}, mode: 'normal' };
      state.days[key].actualWakeTime = '06:30';
      state.days[key].actualBedTime = '22:15';
      localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
    }, today);
    await page.reload({ waitUntil: 'networkidle' });
    assert.equal(await page.locator('#actualTimeDetails').isHidden(), true);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({ path: `${screenshotDir}/today-sleep-collapsed.png` });
    await page.locator('#toggleActualTimeButton').click();
    assert.equal(await page.locator('#actualTimeDetails').isVisible(), true);
    await page.evaluate(key => {
      const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
      delete state.days[key].actualWakeTime;
      delete state.days[key].actualBedTime;
      localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
    }, today);
    await page.reload({ waitUntil: 'networkidle' });
  }

  await page.locator('[data-view="setup"]').click();
  assert.equal((await page.locator('#pageTitle').textContent()).trim(), 'Daily Routine');
  assert.equal((await page.locator('#pageContext').textContent()).trim(), 'Setup');
  assert.equal(await page.locator('#setupOverview').isVisible(), true);
  await page.locator('[data-setup-target="health"]').click();
  assert.equal((await page.locator('#setupCategoryTitle').textContent()).trim(), 'Health & access');
  assert.equal(await page.locator('#iphoneWidgetCard').isVisible(), true);
  assert.equal(await page.locator('.widget-size-options>div').count(), 3);
  assert.match(await page.locator('#iphoneWidgetCard').textContent(), /Daily Routine/);
  assert.equal(await page.locator('#appleNativeCard').isVisible(), true);
  assert.equal(await page.locator('#earnedAccessCard').isVisible(), true);
  assert.equal(await page.locator('#appleWatchCard').isVisible(), true);
  assert.equal(await page.locator('#appleNativeCard #earnedAccessCard').count(), 0);
  assert.equal(await page.locator('#appleNativeCard #appleWatchCard').count(), 0);
  assert.ok(await page.locator('#appleWatchQuickActionInput option').count() > 1);
  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'earned.access.status', value: {
      protectionEnabled: 'true', shielding: 'true', allowanceActive: 'false', allowanceMinutes: '0',
      allowanceRemainingMinutes: '', allowanceRedemptionID: '', lastConsumedRedemptionID: '', morningGateEnabled: 'true',
      morningFoundationCompleteToday: 'true', selectionCount: '3', essentialCount: '2', dailyResetScheduled: 'true', morningGateScheduled: 'true', notificationsAllowed: 'true'
    } } }));
  });
  assert.match(await page.locator('#earnedAccessGateStatus').textContent(), /locked/i);
  assert.equal((await page.locator('#earnedAccessScreenTimeStatus').textContent()).trim(), 'Apps are shielded');
  assert.equal((await page.locator('#earnedAccessScheduleStatus').textContent()).trim(), 'Daily protection armed');
  assert.equal((await page.locator('#earnedAccessNotificationStatus').textContent()).trim(), 'Allowed');
  if (process.env.DAILY_ROUTINE_SCREENSHOT_DIR) {
    await page.locator('#earnedAccessCard').scrollIntoViewIfNeeded();
    await page.locator('#earnedAccessCard').screenshot({ path: `${process.env.DAILY_ROUTINE_SCREENSHOT_DIR}/daily-routine-build16-earned-access.png` });
  }
  await page.getByText('Automation and daily limits', { exact: true }).click();
  assert.equal(await page.locator('#earnedAccessAutomaticUseInput').isChecked(), true);
  await page.locator('#earnedAccessAutomaticUseInput').uncheck();
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
  assert.equal(await page.locator('#earnedAccessAutomaticStepsInput').isChecked(), true);
  assert.equal(await page.locator('#earnedAccessStepsInput').inputValue(), '8000');
  assert.equal(await page.locator('#earnedAccessMinutesInput').inputValue(), '60');
  await page.locator('#earnedAccessAutomaticStepsInput').uncheck();

  await page.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 4820, sleepHours: 0, workoutCount: 0, sourceNames: ['Garmin Connect', 'Apple Watch'] } } }));
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'routine.snapshot.saved', value: { revision: 42 } } }));
  });
  assert.match(await page.locator('#healthSourceDetail').textContent(), /Garmin Connect/);
  assert.match(await page.locator('#earnedAccessHealthSyncStatus').textContent(), /Updated just now/);
  assert.equal((await page.locator('#earnedAccessStepSampleStatus').textContent()).trim(), 'No sample today');
  assert.match(await page.locator('#earnedAccessWidgetStatus').textContent(), /Synced just now · r42/);
  await page.locator('#earnedAccessLabelInput').fill('Reddit');
  await page.locator('#earnedAccessStepsInput').fill('1000');
  await page.locator('#earnedAccessMinutesInput').fill('20');
  await page.locator('#startEarnedAccessButton').click();
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), 'Reddit step goal');
  assert.match(await page.locator('.earned-access-disclosure').textContent(), /Current protection/);
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
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '25 of 60 minutes available');
  assert.equal(await page.locator('#useEarnedAccessButton').isDisabled(), false);
  await page.locator('#useEarnedAccessButton').click();
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), '15 minutes available');
  assert.equal((await page.locator('#earnedAccessBadge').textContent()).trim(), 'Open');
  const nativeAllowance = await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'earned.access.allow'));
  assert.equal(nativeAllowance?.value?.minutes, 15);
  assert.match(nativeAllowance?.value?.redemptionId, /^allowance-/);
  await page.evaluate(redemptionId => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'earned.access.status', value: {
      protectionEnabled: 'true', shielding: 'false', allowanceActive: 'true', allowanceMinutes: '15',
      allowanceRemainingMinutes: '9', allowanceRedemptionID: redemptionId, lastConsumedRedemptionID: '', morningGateEnabled: 'true',
      morningFoundationCompleteToday: 'true', selectionCount: '3', essentialCount: '2', dailyResetScheduled: 'true', morningGateScheduled: 'true', notificationsAllowed: 'true'
    } } }));
  }, nativeAllowance.value.redemptionId);
  assert.equal((await page.locator('#earnedAccessStatus').textContent()).trim(), 'About 9 of 15 minutes remaining');
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '19 of 60 minutes available');
  assert.equal((await page.locator('#earnedAccessAvailableNow').textContent()).trim(), '19 min');
  assert.match(await page.locator('#earnedAccessDetail').textContent(), /five-minute usage checkpoints/);
  const earnedWidgetSnapshot = await page.evaluate(() => [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'routine.snapshot.publish')?.value);
  assert.equal(earnedWidgetSnapshot.earnedAccessRemainingMinutes, 19);
  assert.equal(earnedWidgetSnapshot.earnedAccessDailyLimitMinutes, 60);
  assert.equal(earnedWidgetSnapshot.convictionsEnabled, true);
  assert.equal(JSON.stringify(earnedWidgetSnapshot).includes('Reddit'), false);
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
  assert.equal(await page.locator('#convictionIntroInput').count(), 0);
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
  assert.equal(await page.locator('#pageContext').isHidden(), true);
  assert.equal(await page.locator('#truthHeroEyebrow').isHidden(), true);
  assert.equal(await page.locator('#truthStepLabel').isHidden(), true);
  assert.equal(await page.locator('#truthStepTitle').isHidden(), true);
  assert.equal((await page.locator('.truth-gospel-note').textContent()).trim(), 'Not for righteousness. Because of righteousness.');
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
    localStorage.setItem('dailyRoutine.earnedAccess.device.v1', JSON.stringify({ automaticSteps: true, automaticAccess: false }));
  }, today);
  await page.reload({ waitUntil: 'networkidle' });
  await page.locator('[data-view="setup"]').click();
  await page.locator('[data-setup-target="health"]').click();
  assert.equal((await page.locator('#earnedAccessMorningStatus').textContent()).trim(), '3 of 3 complete · 15 min added today');
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '15 of 60 minutes available');
  await page.reload({ waitUntil: 'networkidle' });
  await page.locator('[data-view="setup"]').click();
  await page.locator('[data-setup-target="health"]').click();
  assert.equal((await page.locator('#earnedAccessBankStatus').textContent()).trim(), '15 of 60 minutes available');
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

  const automaticPage = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  await automaticPage.addInitScript(() => {
    window.__dailyRoutineNativeMessages = [];
    window.DailyRoutineNative = { postMessage(message) { window.__dailyRoutineNativeMessages.push(message); } };
  });
  await automaticPage.goto(baseURL, { waitUntil: 'networkidle' });
  await automaticPage.evaluate(() => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: { date: new Date().toISOString(), stepCount: 4000, sleepHours: 0, workoutCount: 0 } } }));
  });
  const automaticReward = await automaticPage.evaluate(key => {
    const settings = JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1'));
    const nativeConfiguration = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'health.step-rewards.configure');
    const nativeLock = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'earned.access.lock');
    return { bank: settings.bankByDate[key], earned: settings.earnedByDate[key], walking: settings.movementCreditedByDate[key], activeAllowance: settings.activeAllowance, nativeConfiguration, nativeLock };
  }, today);
  assert.deepEqual({ bank: automaticReward.bank, earned: automaticReward.earned, walking: automaticReward.walking }, { bank: 30, earned: 30, walking: 30 });
  assert.equal(automaticReward.activeAllowance, null);
  assert.ok(automaticReward.nativeLock);
  assert.deepEqual(automaticReward.nativeConfiguration.value, { enabled: true, goalSteps: 8000, maxMinutes: 60 });
  await automaticPage.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    state.settings.truthBeforeTasks.completions[key] = new Date().toISOString();
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
  }, today);
  await automaticPage.reload({ waitUntil: 'networkidle' });
  const openedAfterFoundation = await automaticPage.evaluate(key => {
    const settings = JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1'));
    const nativeAllowance = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'earned.access.allow');
    return { bank: settings.bankByDate[key], activeAllowance: settings.activeAllowance, nativeAllowance };
  }, today);
  assert.equal(openedAfterFoundation.bank, 0);
  assert.equal(openedAfterFoundation.activeAllowance.minutes, 30);
  assert.equal(openedAfterFoundation.nativeAllowance.value.minutes, 30);
  await automaticPage.evaluate(redemptionId => {
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'earned.access.status', value: {
      protectionEnabled: 'true', shielding: 'false', allowanceActive: 'true', allowanceMinutes: '30',
      allowanceRemainingMinutes: '20', allowanceRedemptionID: redemptionId, lastConsumedRedemptionID: '', morningGateEnabled: 'true',
      morningFoundationCompleteToday: 'true', selectionCount: '3', essentialCount: '2', dailyResetScheduled: 'true', morningGateScheduled: 'true', notificationsAllowed: 'true'
    } } }));
    window.dispatchEvent(new CustomEvent('dailyRoutine:native', { detail: { name: 'health.summary', value: {
      date: new Date().toISOString(), stepCount: 4800, sleepHours: 0, workoutCount: 0
    } } }));
  }, openedAfterFoundation.activeAllowance.id);
  const extendedAutomaticAllowance = await automaticPage.evaluate(key => {
    const settings = JSON.parse(localStorage.getItem('dailyRoutine.earnedAccess.device.v1'));
    const nativeAllowance = [...window.__dailyRoutineNativeMessages].reverse().find(message => message.action === 'earned.access.allow');
    return { bank: settings.bankByDate[key], activeAllowance: settings.activeAllowance, nativeAllowance };
  }, today);
  assert.equal(extendedAutomaticAllowance.bank, 0);
  assert.equal(extendedAutomaticAllowance.activeAllowance.minutes, 26);
  assert.notEqual(extendedAutomaticAllowance.activeAllowance.id, openedAfterFoundation.activeAllowance.id);
  assert.equal(extendedAutomaticAllowance.nativeAllowance.value.minutes, 26);
  assert.match(await automaticPage.locator('#earnedAccessBankStatus').textContent(), /26 of 60 minutes available/);
  await automaticPage.close();

  const exportedFiles = await page.evaluate(() => {
    window.__dailyRoutineNativeMessages = [];
    document.querySelector('#exportCsvButton').click();
    document.querySelector('#exportJsonButton').click();
    return window.__dailyRoutineNativeMessages.filter(message => message.action === 'share.file');
  });
  assert.equal(exportedFiles.length, 2);
  assert.match(exportedFiles[0].value.filename, /^daily-routine-progress-\d{4}-\d{2}-\d{2}\.csv$/);
  assert.match(exportedFiles[0].value.content, /^Date,Day Mode,Actual Wake/);
  assert.match(exportedFiles[1].value.filename, /^daily-routine-backup-\d{4}-\d{2}-\d{2}\.json$/);
  assert.match(exportedFiles[1].value.content, /"state"/);

  const migrationContext = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const migrationPage = await migrationContext.newPage();
  await migrationPage.goto(baseURL, { waitUntil: 'networkidle' });
  const historicalDate = await migrationPage.evaluate(() => {
    const date = new Date();
    date.setDate(date.getDate() - 2);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    delete state.settings.build27HistoricalTargetsMigrated;
    state.settings.firstUseDate = key;
    state.items.find(item => item.id === 'day-water').target = 8;
    state.days[key] = { entries: { 'day-water': 6 }, skippedItems: {}, mode: 'normal' };
    localStorage.setItem('dailyRoutineApp.v1', JSON.stringify(state));
    localStorage.setItem('dailyRoutineApp.convictionRecovery.v1', JSON.stringify([{
      createdAt: new Date().toISOString(),
      label: 'Before private sync changed convictions',
      convictions: { intro: '', items: [{ id: 'recovered', text: 'Recovered conviction', scripture: '' }] }
    }]));
    return key;
  });
  await migrationPage.reload({ waitUntil: 'networkidle' });
  const migratedHistory = await migrationPage.evaluate(key => {
    const state = JSON.parse(localStorage.getItem('dailyRoutineApp.v1'));
    return {
      currentWaterTarget: state.items.find(item => item.id === 'day-water').target,
      historicalWaterTarget: state.days[key].targets['day-water'],
      migrated: state.settings.build27HistoricalTargetsMigrated
    };
  }, historicalDate);
  assert.deepEqual(migratedHistory, { currentWaterTarget: 6, historicalWaterTarget: 6, migrated: true });
  assert.equal(await migrationPage.locator('#convictionRecoveryPanel').evaluate(element => element.hidden), false);
  assert.match(await migrationPage.locator('#convictionRecoveryStatus').textContent(), /pre-sync copy of 1 conviction/);
  await migrationContext.close();

  assert.deepEqual(errors, []);
  await browser.close();
  console.log('App UI regression tests passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
