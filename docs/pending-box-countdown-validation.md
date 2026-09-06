# Pending box countdown

## Behavior and compatibility

When an enabled race reports a valid box interval and zero remaining steps,
the existing helper above the inventory reads **Granting your next box...**.
Positive remaining steps retain the normal countdown. The normal 30-second
progress poll replaces the pending message when the next countdown arrives;
no screen reopening is needed.

Missing or invalid remaining-step fields retain the last known nonnegative
value. Without a prior value, they do not invent a pending box. A missing or
invalid interval still suppresses the helper. The inventory stays actionable.

This uses the existing server response and the shared Flutter race screen for
both iOS and Android, including solo/team races and tutorial/demo mirrors.
There is no backend change, new endpoint, feature flag, or dependency. Older
app versions remain unchanged. Users need the next app build to see the copy.

## Automated verification

Four new real-screen widget cases failed before implementation: pending copy
on first load and countdown-to-pending transitions, each on solo/team races.
The new cases also check placement above usable slots, null/invalid fields,
and automatic polling back to a positive countdown without reopening.
Existing assertions are unchanged.

The focused helper and race-detail suites pass all 51 tests. `flutter analyze`
is clean, and independent code review found no blockers or issues. The full
suite finished with 2,941 passing tests and one filesystem teardown error in `remote_asset_cache_test.dart`
(temporary directory not empty); that unchanged suite passed all 17 tests on
the prescribed isolated rerun. No tests were skipped or weakened for this fix.
Native archives and store uploads are not part of this code-only verification.

## Manual placement checklist

Run the real-race checks on both a narrow iPhone and Android screen, including
larger system text. The message should fit inside its card without clipping
or overlapping inventory slots.

- **Team race:** sync across a box threshold, then open the active race while
  processing. Verify the pending sentence appears once above the box/item
  slots. When the countdown returns, it uses the same position.
- **Regular race:** verify the positive countdown remains above the slots.
  If the API returns zero, verify the same pending placement and recovery.
- **Playable onboarding demo:** verify the helper remains above the slots
  and the coach ring still targets the inventory.
- **Tab tutorial race-detail preview:** verify one helper above the inventory
  and that the spotlight still surrounds the intended slots.

The demo and tab-tutorial fixtures currently supply a positive countdown.
Their default flows check existing placement, not the pending state; a
temporary zero-countdown fixture is needed to manually exercise that state.
Tutorial anchors attach to the inventory beneath the helper, so check their
alignment through the text change. The Races tab itself has no copy of this
helper.
