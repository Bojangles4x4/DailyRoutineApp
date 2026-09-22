# Private accountability foundation

Build 23 adds relationship-based accountability sharing without granting access to an owner’s synchronized routine document.

Build 24 adds a dedicated partner experience. A partner-only account lands on a read-only results dashboard and does not receive the routine owner interface, Truth Before Tasks, notes, setup controls, personal analytics, or routine editing tools. Partner sign-in also skips routine-document synchronization entirely.

Build 25 adds exact routine selection for each relationship and a calmer multi-person dashboard with search, attention filters, sorting, weekly completion, 30-day completion, and per-routine trends. The additional history remains inside the same whitelist-only snapshot and does not grant access to the owner’s full routine document.

Build 26 adds a clear selected-routine count plus select-all and clear controls. Memory-style routines may now share only their routine name and completion state; the remembered text and memory identifier remain excluded from the snapshot.

## Roles and access

- A routine owner may invite one or more accountability partners.
- A partner account may support one person or a roster of several people.
- Each relationship has independent permissions and a `pending`, `active`, `paused`, or `revoked` status.
- The invited person must authenticate with the exact invited email address before the relationship becomes active.
- Paused and revoked relationships cannot read a snapshot.
- Accounts that only serve as accountability partners see only their authorized roster and shared snapshots.

## Shared data boundary

The app builds a separate whitelist-only snapshot. Depending on the owner’s switches, it may contain:

- today and week completion totals;
- Truth Before Tasks completion status;
- names and completion states for non-sensitive routine items;
- up to 30 days of completion totals and owner-selected routine completion trends;
- numeric rating averages;
- today’s step total and goal; or
- a medication-completion count.

The snapshot never contains notes, prayer text, memories, written check-ins, medication names, doses or times, raw Apple Health records, Screen Time selections, or the full `routine_documents` record.

Only preferred display names are shown in the partner roster. Client email addresses, clinical notes, diagnoses, contact details, and treatment information are not part of the partner dashboard.

## Database controls

`202609210001_accountability_foundation.sql` creates relationship and snapshot tables with row-level security. Owners manage their own relationships and snapshots. Partners can select only active relationships assigned to their authenticated user ID and only the snapshot attached to those relationships. Invitation acceptance runs through an email-checked database function, and a trigger prevents an owner from assigning acceptance fields directly.

## Clinical boundary

This foundation is designed for personal accountability. It does not claim to make Daily Routine a clinical record system or a HIPAA-ready therapist product. Clinical use requires a separate review of contracts, project configuration, audit controls, retention, incident response, staff access, and applicable law before protected health information is accepted.
