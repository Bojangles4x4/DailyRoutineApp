# Private accountability foundation

Build 23 adds relationship-based accountability sharing without granting access to an owner’s synchronized routine document.

## Roles and access

- A routine owner may invite one or more accountability partners.
- A partner account may support one person or a roster of several people.
- Each relationship has independent permissions and a `pending`, `active`, `paused`, or `revoked` status.
- The invited person must authenticate with the exact invited email address before the relationship becomes active.
- Paused and revoked relationships cannot read a snapshot.

## Shared data boundary

The app builds a separate whitelist-only snapshot. Depending on the owner’s switches, it may contain:

- today and week completion totals;
- Truth Before Tasks completion status;
- names and completion states for non-sensitive routine items;
- numeric rating averages;
- today’s step total and goal; or
- a medication-completion count.

The snapshot never contains notes, prayer text, memories, written check-ins, medication names, doses or times, raw Apple Health records, Screen Time selections, or the full `routine_documents` record.

## Database controls

`202609210001_accountability_foundation.sql` creates relationship and snapshot tables with row-level security. Owners manage their own relationships and snapshots. Partners can select only active relationships assigned to their authenticated user ID and only the snapshot attached to those relationships. Invitation acceptance runs through an email-checked database function, and a trigger prevents an owner from assigning acceptance fields directly.

## Clinical boundary

This foundation is designed for personal accountability. It does not claim to make Daily Routine a clinical record system or a HIPAA-ready therapist product. Clinical use requires a separate review of contracts, project configuration, audit controls, retention, incident response, staff access, and applicable law before protected health information is accepted.
