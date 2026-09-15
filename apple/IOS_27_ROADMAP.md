# iOS 27 opportunities roadmap

Status: planning and evaluation only. This document does not commit Daily Routine to an iOS 27 feature, change the current shipping architecture, or replace the current product rules.

## Purpose and recommendation

The safest direction is to extend the working app incrementally with small native surfaces. A full SwiftUI rewrite is not justified by these opportunities.

The current product is a SwiftUI iPhone shell around a bundled, offline `WKWebView` experience, with a narrow native bridge for read-only HealthKit, Watch Connectivity, reminders, sharing, and device-only Earned Access. The watchOS app and its WidgetKit extension consume limited snapshots and send queued quick actions. Optional Private sync remains the only cross-device routine document store; Health data, Screen Time selections, and Earned Access state remain device-only.

Before any native surface may change routine state while `WKWebView` is absent, Daily Routine needs one safe command/state boundary. That foundation is the first priority because it supports widgets, App Intents, NFC-triggered Shortcuts, and later Siri work without creating a competing source of truth.

## Non-negotiable product and privacy constraints

All phases must preserve:

- The existing phone UI, navigation, local-first behavior, backup/import compatibility, and optional Private sync rules.
- Truth Before Tasks and configured Convictions Before Circumstances as the grace-centered Morning Foundation. The governing posture remains “Not for righteousness. Because of righteousness.”
- A minimum three-minute Truth Before Tasks meditation that cannot be silently completed, shortened, or bypassed by a widget, Shortcut, App Intent, Siri, NFC, Watch action, or generated reflection.
- Local calendar-day semantics, including day rollover and time-zone changes.
- Watch quick actions remaining locked until the phone records completion of the entire configured Morning Foundation for that local day.
- HealthKit as optional and read-only. Health summaries, automatic step values, Screen Time selections, and Earned Access state remain device-only and excluded from Private sync.
- Existing Watch behavior, supported complication families, exact-item actions, offline queuing, and manual phone fallbacks.
- User review before generated text is saved or an action with meaningful consequences is performed.
- No competing authoritative routine database. The existing web state and its current Private sync document remain authoritative until an explicitly approved migration changes that boundary.

Hard constraint: Apple Watch is not a general-purpose NFC tag reader for the proposed alarm/routine flow. The iPhone NFC tap is primary. Watch may remain a companion notification and quick-action surface, but this roadmap must not reopen a Watch tag-scanning design based on Wallet or Apple Pay NFC behavior.

## Roadmap at a glance

| Priority | Opportunity | Decision sought |
| --- | --- | --- |
| Now — P0 | Native command/state feasibility | Prove native actions can safely read and mutate the existing routine state without `WKWebView` being active. |
| Now — P1 | Interactive iPhone widget command center | Validate the exact iOS 27 widget families and design a private-by-default concept on the P0 boundary; prototype it Next. |
| Now — P1 | iPhone NFC morning flow | Map an NFC → Shortcut/App Intent → Morning Foundation flow without overstating alarm control; prototype it Next. |
| Next — P2 | Private Daily Reflection assistant | Evaluate a strictly on-device, source-grounded Foundation Models helper with no silent cloud fallback. |
| Later — P3 | Siri screen awareness and actions | Add only useful, opted-in App Intent actions and native entity/view mappings. |
| Later — adjacent | HomeKit / Home Assistant | Prefer a separable Shortcuts handoff; keep home infrastructure optional. |
| Personal note | Safari Notify Me | Use Safari’s page-change monitoring independently of Daily Routine when useful. |

## Now — P0: safe native command/state foundation

### Opportunity

Create a narrow native boundary that can accept a routine command, validate it against current state and Morning Foundation rules, apply it exactly once, and publish a refreshed snapshot even when the web view is not running.

This is feasibility work first. It is not permission to move all routine logic into Swift or to add another persistent routine database.

### Evaluation deliverables

1. Document the current authoritative state lifecycle: bundled web storage, optional Private sync, native device-only stores, Watch snapshot creation, and reconciliation on app launch.
2. Define a versioned `RoutineCommand` contract with stable action IDs. Candidate commands should be intentionally small, such as open the Morning Foundation, capture an unsaved note draft, or toggle an eligible checkbox by stable routine-item ID.
3. Define a versioned, privacy-minimized `RoutineSnapshot` for widgets, Watch, and App Intents. It should carry only the local date key, foundation state, completion totals, selected next/eligible item metadata, and an update revision/date.
4. Prototype a shared command journal in the existing App Group with:
   - unique command IDs and origin IDs;
   - expected local date and optional expected revision;
   - pending, applied, rejected, and superseded states;
   - idempotent replay and duplicate rejection;
   - atomic file replacement or equivalent coordinated persistence;
   - a bounded retention policy that never stores full Health or sensitive note content unnecessarily.
5. Define one command applier. During the feasibility stage, the safest candidate is a scoped native service that can apply only explicitly extracted operations. Commands it cannot safely apply remain queued for the web app to reconcile at launch.
6. Add reconciliation rules for app termination, extension timeouts, duplicate delivery, old local-day commands, Private sync conflicts, and partial writes.
7. Define snapshot refresh behavior for WidgetKit, Watch Connectivity, and the foreground web UI after a command is applied.
8. Produce a staged migration and fallback plan before implementation begins.

### Proposed boundary

```text
Widget / App Intent / Shortcut / Watch
                 |
          versioned command
                 v
     App Group command journal
                 |
       one validated applier
          /             \
safe native operation   queue for web reconciliation
          \             /
       existing authoritative state
                 |
       privacy-minimized snapshot
                 v
Widget / Watch / native status / WKWebView refresh
```

The command contract should include at least:

- `commandID`: globally unique and stable across retries.
- `actionID`: stable semantic action, not display text.
- `origin`: widget, App Intent, Shortcut, Watch, or web.
- `createdAt`, `localDateKey`, and time-zone identifier.
- `targetID` and a tightly typed payload when required.
- `expectedRevision` when stale execution would be unsafe.
- `requiresFoundationComplete` and other policy metadata derived by the applier, not trusted solely from the caller.

### Gate and side-effect rules

- Every mutation rechecks the current local day and Morning Foundation state at execution time.
- No external surface may mark Truth Before Tasks or Convictions complete.
- Retrying the same command ID returns the stored result; it does not toggle a second time.
- A stale command for yesterday is rejected or converted to a non-mutating open-app action.
- Medication, Earned Access consumption, Health-derived values, and other sensitive or irreversible operations are not part of the first prototype.
- An extension canceled by the system must leave either the old state or the fully committed new state, never a partial update.
- “Undo” is available only where the app can prove a local inverse is safe. It must never reverse already-consumed Earned Access minutes or automatically undo an external side effect.

### Staged migration and fallback

1. **Observe:** add no new writer; compare native snapshots with the existing web-derived snapshot.
2. **Queue only:** native surfaces enqueue commands, then open the app for the current web handler to apply them.
3. **Extract one reversible action:** move one low-risk checkbox mutation behind the shared applier and test duplicate/retry behavior.
4. **Expand deliberately:** add only actions with explicit validation and rollback/failure semantics.
5. **Retain fallback:** if shared state is unavailable, corrupt, stale, or version-incompatible, open Daily Routine at the relevant screen and let the existing UI complete the action.

Rollback means disabling native mutation and returning to queue-and-open behavior. Existing routine data must remain readable by the current web app throughout the experiment.

### Acceptance criteria

- Replaying the same command 100 times produces one state transition.
- Two near-simultaneous commands do not lose an update or corrupt the snapshot.
- Commands created before midnight, after a time-zone change, or during reboot are validated against the correct local day.
- A locked Morning Foundation prevents every gated command outside the phone opening flow.
- Offline commands reconcile deterministically after the app returns, including when optional Private sync has a newer revision.
- Widget and Watch snapshots refresh after an applied command without containing Health details, notes, prayers, medication details, or Screen Time tokens.
- Disabling the experiment restores the existing app behavior without data migration or loss.

### Dependencies and material architecture impact

Dependencies: App Group coordination, versioned Codable models, file/data coordination tests, current web-state migration rules, WidgetKit reload policy, and Watch reconciliation behavior.

Material impact: a small native state/command service and a corresponding narrow JavaScript bridge adapter. This is the enabling architectural change for the rest of the roadmap, but it is not a full native rewrite and not a second database.

## Now — P1: interactive iPhone widget command center

### Opportunity

Evaluate an extra-large or full-page interactive Home Screen widget as a calm Daily Routine / Truth Before Tasks command center using the existing visual language.

The exact extra-large/full-page iPhone widget API and shipping-device support have **not yet been established** from the inspected Apple material. Treat that presentation as a requested opportunity with an SDK and device verification gate, not as a promised iOS 27 capability.

The current `DailyRoutineWatchWidgets` target is watchOS-only. It is not automatically an iPhone widget and cannot embed the existing web UI.

### Scoped concept

- **Foundation:** private status such as “Begin Morning Foundation” or “Foundation complete,” plus a launch action. Do not display conviction or Scripture content on the Home Screen by default.
- **Today’s commitments:** a small count or user-selected, non-sensitive labels. Hide details until the user opts in.
- **Next routine action:** show only an eligible action from the P0 snapshot; allow completion only for a validated, reversible routine item.
- **Progress:** completion count and restrained progress treatment matching the current app.
- **Privacy default:** `.privacySensitive()` where supported, generic locked-state copy, and no notes, prayers, medications, Health summaries, or Screen Time selections on the widget.

### Evaluation deliverables

**Now — evaluate and scope**

1. Verify in the target Xcode/iOS 27 SDK which iPhone widget families, full-page placements, interactive controls, deep links, and privacy-redaction behaviors are actually available.
2. Produce device-size wireframes for the largest verified family plus existing smaller fallbacks.
3. Specify a new native iPhone WidgetKit target and its App Group configuration; do not repurpose the watchOS widget target.
4. Map each proposed button to a P0 command or safe deep link.

**Next — build one validated prototype before any broader redesign**

1. Build a small prototype containing foundation launch/status, progress, and at most one reversible routine action.
2. Measure refresh latency, stale-state behavior, extension memory, and action cancellation on a physical device.

### Acceptance criteria

- No widget action can mark the three-minute meditation complete or bypass the Morning Foundation.
- Private details are hidden by default on the Home Screen and lock screen.
- A stale or unavailable snapshot results in “Open Daily Routine to refresh,” not an incorrect completion.
- Repeated taps produce one action through P0 idempotency.
- The prototype retains working supported sizes and deep-link fallbacks if the requested full-page family is unavailable.
- Existing watchOS complications remain unchanged.

### Dependencies and material architecture impact

Dependencies: completion of the P0 contract, target iOS 27 SDK validation, WidgetKit/App Intents availability, App Group access, and physical-device testing.

Material impact: a separate native iPhone WidgetKit extension, widget-specific presentation models, and safe shared actions/state. The `WKWebView` cannot be placed inside a widget.

## Now — P1: iPhone NFC morning alarm and routine flow

### Opportunity

Revisit a morning flow where an iPhone NFC tap launches a supported Shortcut or App Intent, opens or starts Truth Before Tasks, and then continues into eligible morning routines.

An NFC tap may be a helpful intentional trigger, but it must not be described as an unavoidable NFC-only alarm dismissal until Apple’s actual alarm-control APIs and locked-phone automation behavior are verified. Dismissing an alarm is separate from completing the Morning Foundation.

### Target flow

```text
iPhone reads NFC tag
        |
supported Personal Automation / Shortcut
        |
Daily Routine App Intent or deep link
        |
open/start Truth Before Tasks on iPhone
        |
user completes the full Morning Foundation
        |
continue to eligible morning routine actions
```

### Evaluation deliverables

**Now — map and verify**

1. Record the supported behavior for NFC Personal Automations, App Intents, alarm controls, locked-phone execution, confirmation requirements, background execution, and app launch in the target OS.
2. Define once-per-local-day behavior using the P0 date/revision rules.
3. Map repeat taps, retries, reboot, midnight, travel/time-zone change, and a tag scanned while the phone is locked.
4. Provide a manual fallback from the app, notification, and Watch that never requires the NFC tag to use the routine.
5. Evaluate iOS 27 widget/Shortcut execution, background continuation, cancellation, and undo only for actions whose semantics fit.
6. Optionally evaluate natural-language Shortcut generation as setup convenience. It must not become a runtime dependency.

**Next — validate physically**

1. Prototype the complete flow on the physical iPhone with at least one real NFC tag.

### Execution rules

- Background execution is OS-managed and time-limited, never guaranteed or unlimited.
- Cancellation must leave unfinished work pending or rejected cleanly.
- Repeat scans must not complete or toggle an item twice.
- The NFC event may open Truth Before Tasks, but only the existing timed user experience may complete it.
- No undo operation may reverse an external side effect or restore already-consumed Earned Access minutes.
- If the phone is locked or automation permission is unavailable, surface a notification/deep-link fallback instead of pretending the action completed.

### Acceptance criteria

- The first valid tap of the local day opens the correct foundation state; later taps reopen or continue it without resetting completion.
- Repeated scans and Shortcut retries are idempotent.
- Reboot, midnight, daylight-saving, and time-zone test cases follow local-day rules.
- The user can always begin and complete the routine without NFC.
- Product copy distinguishes alarm dismissal, routine launch, and foundation completion.
- Physical-device results document which locked/background cases require confirmation or foreground app launch.

### Dependencies and material architecture impact

Dependencies: P0 command/state contract, App Intents and Shortcuts implementation, real NFC hardware, permissions, and current-OS alarm capability verification.

Material impact: native App Intents plus the same shared command/state path. A few web-only routine operations may need scoped native extraction; this does not justify moving the whole UI to SwiftUI.

## Next — P2: private on-device Daily Reflection assistant

### Opportunity

Evaluate an optional assistant for Daily Reflection and Truth Before Tasks using Apple Foundation Models. It may generate source-grounded reflection prompts or summaries, but it must remain subordinate to the user’s chosen Scripture and existing practice.

Foundation Models now supports on-device model access and can also work with other/cloud providers. Using the framework name alone therefore does not establish privacy. This feature must explicitly select an on-device model and must not silently fall back to cloud inference.

### Permitted context

Only content the user explicitly enables:

- selected routine history;
- licensed or otherwise permitted Scripture supplied by the app/user;
- selected notes or reflections;
- user-chosen sleep and activity summaries already permitted by Health access.

Existing device-only and Private sync exclusions remain in force. Sensitive notes, prayers, medication details, and Health data are excluded unless separately and clearly opted in for this feature.

### Evaluation deliverables

1. Define a Swift `ReflectionModelService` that is explicitly on-device and exposes availability, eligibility, cancellation, and memory/latency status.
2. Define a narrow, user-approved context envelope passed from the existing UI; do not hand the model the full routine database.
3. Prototype two source-grounded operations: a reflection prompt and a draft summary.
4. Render quoted Scripture separately from generated reflection and attach a source reference for every quotation.
5. Require user review before saving generated text or initiating any action.
6. Test disabled, unavailable, ineligible, offline, missing-context, revoked-permission, cancellation, and low-resource cases.
7. Inspect network behavior and ensure no inference request leaves the device.
8. Validate Scripture quotations against the supplied source and record failure handling when exact source text is unavailable.

### Acceptance criteria

- Network-disabled testing still works when the on-device model is eligible; network inspection shows no inference traffic.
- No cloud provider or silent cloud fallback is configured.
- Standard non-AI reflection remains fully usable when the feature is disabled, unavailable, slow, canceled, or ineligible.
- Generated wording is visually and semantically separated from Scripture.
- No quoted Scripture is presented without matching the permitted source.
- The assistant cannot complete Truth Before Tasks, change routine completion, make a medical inference, or change the foundation’s duration/content rules.
- Revoking Health or content permission removes that context from future requests.
- Latency, memory, cancellation, and output quality are acceptable on Taylor’s physical device before broader work.

### Dependencies and material architecture impact

Dependencies: target SDK/device eligibility, permitted Scripture source/license, explicit consent design, privacy/network verification, and the existing local-state privacy map.

Material impact: one native Swift model service plus a narrow context/result bridge to the current web UI. It does not require a full native UI rewrite or cloud-AI dependency.

## Later — P3: Siri screen awareness and useful actions

### Opportunity

Evaluate Siri integrations only where they make a routine action meaningfully easier, such as opening the next eligible routine, capturing a note draft, or referring to an item currently displayed with the user’s consent.

Do not assume Siri automatically understands a `WKWebView`. Reuse the App Intents foundation and investigate native entity schemas and View Annotations for selected web-backed views.

### Evaluation deliverables

1. Identify three high-value, low-risk utterances and their safe App Intent/deep-link behavior.
2. Define native entities for only the minimum eligible routine metadata.
3. Prototype View Annotation or equivalent mapping for one displayed item and document what Siri can actually resolve.
4. Create an explicit indexing/visibility preference with sensitive categories off by default.
5. Test stale screen state, multiple similarly named routines, locked Morning Foundation, and offline behavior.

### Acceptance criteria

- No blanket indexing of notes, prayers, medications, Health information, or other sensitive content.
- Siri cannot bypass the Morning Foundation or silently complete the meditation.
- Ambiguous or stale references open the relevant app screen for confirmation.
- Captured speech remains a user-reviewable draft until saved.
- The feature demonstrates real value before any broader native redesign is considered.

### Dependencies and material architecture impact

Dependencies: P0 shared commands, App Intents from the NFC/widget work, target SDK validation, and explicit user opt-in.

Material impact is conditional: native entity definitions, intent schemas, and selective view mappings through the bridge. Siri alone is not a reason to replace the current web UI.

## Later — adjacent: HomeKit and Home Assistant

### Opportunity

Offer optional, user-controlled morning lighting/scene or routine triggers. Prefer an existing Shortcuts handoff first because it keeps failure and authorization outside the core routine.

Apple Home features and Home Assistant are separate integrations and must not be presented as interchangeable capabilities.

### Evaluation deliverables

1. Prototype a Shortcut that runs a user-owned Home scene before or after opening Daily Routine.
2. Specify explicit permission, unavailable-home, network-failure, and manual-fallback behavior.
3. Compare the architecture and maintenance cost of:
   - a Shortcuts handoff;
   - direct Apple Home authorization/integration;
   - authenticated Home Assistant service/configuration.
4. Keep secrets, tokens, home topology, and device names outside routine backups and Private sync unless a separate security design approves them.

### Acceptance criteria

- Daily Routine and the Morning Foundation work normally with no home infrastructure.
- A failed home action never blocks routine access or falsely marks a routine complete.
- Every home action is user configured and can be disabled independently.
- Permissions and credentials are scoped, revocable, and stored using the relevant native secure mechanism.

### Dependencies and material architecture impact

Dependencies vary by route. Shortcuts/App Intents reuse the P0 boundary and have the smallest impact. Direct Apple Home support adds native permissions and services. Home Assistant requires a separate authenticated integration proposal, credential storage, and failure model.

Material impact: none to the core architecture for a Shortcuts handoff; potentially substantial native/service work for direct integrations. Keep this separate from the iOS 27 core roadmap.

## Personal note — Safari Notify Me

Safari Notify Me can monitor supported page changes, such as price or restock updates. This is a personal Safari capability, not a Daily Routine feature, delivery dependency, or reason to change app architecture. No monitoring automation is requested by this roadmap.

## Suggested decision gates

### Gate A — approve the foundation

Proceed beyond documentation only after the P0 prototype proves idempotent commands, local-day validation, atomic state changes, privacy-minimized snapshots, and a no-migration fallback.

### Gate B — select one user-facing prototype

After Gate A, prototype the largest **verified** iPhone widget family and the NFC morning launch flow independently. Do not bundle a broad UI redesign into either experiment.

### Gate C — validate on Taylor’s devices

Record physical-device results for widget availability, refresh behavior, locked-phone NFC execution, Shortcut confirmation, extension cancellation, and Watch continuity. Simulator results are insufficient for a delivery promise.

### Gate D — consider private intelligence

Only after ordinary flows remain stable, evaluate the on-device reflection assistant with network, source-accuracy, consent, and model-ineligibility tests. Later Siri and home integrations should reuse the same proven boundary.

## Platform facts, proposals, and unresolved validation

### Verified from Apple material

- Apple describes Foundation Models access from Swift, including on-device models and optional other/cloud providers. The implementation must explicitly choose and test the private on-device path.
- Apple describes App Intents schemas and View Annotations as building blocks for system intelligence and screen-related experiences.
- Apple’s iOS overview describes Safari Notify Me and natural-language Shortcut creation.
- App Intents includes platform behaviors around shortcut execution, background work, cancellation, and undo that require action-specific design and device testing.

### Product proposals, not platform guarantees

- The full Daily Routine command-center widget layout.
- The exact NFC morning routine and any relationship to alarm dismissal.
- Reflection prompt/summary behavior.
- Siri routine awareness and home automation flows.

### Unresolved before implementation promises

- Exact extra-large/full-page iPhone widget API, supported devices, and App Store availability.
- Locked-phone and confirmation behavior for the proposed NFC automation.
- Which alarm controls, if any, can participate in the intended flow.
- On-device Foundation Models eligibility, performance, and source accuracy on Taylor’s target device.
- Practical View Annotation behavior for the existing `WKWebView` screens.

## References for validation

- [Apple — What’s new for iOS](https://developer.apple.com/ios/whats-new/)
- [Apple — iOS overview](https://www.apple.com/os/ios/)
- [Apple — App Intents: build an intelligence-ready app (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/345/)

These references support evaluation; they do not replace target-SDK inspection, entitlement checks, App Review review, or physical-device testing before delivery claims.
