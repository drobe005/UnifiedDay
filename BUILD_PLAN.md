# UnifiedDay Build Plan

Phases for Claude Code. Do one phase at a time. Each phase is done only when its
acceptance criteria pass on a real iPhone. The product spec is the authority;
this plan is the order of work.

## Phase 0 - Project setup (done 2026-10-17, verified on iPhone 16 Pro Max)

- Xcode iOS app project `UnifiedDay`, iOS 18+, SwiftUI, no Core Data.
- `Sources/` files added to target, template files removed.
- `NSCalendarsUsageDescription` and `NSRemindersUsageDescription` set.
- App launches, onboarding requests access, Today shows real data.

Acceptance: on device, grant access, see today's real events and reminders.

## Phase 1 - Detail and edit (done 2026-10-17, verified on iPhone 16 Pro Max)

- Tap a timeline row opens a detail sheet: title, date/time, source calendar/list,
  notes, delete.
- Editable fields save back through `EventKitService`. Read-only items (shared
  calendars) hide edit controls.
- Add `updateEvent` and `updateReminder` to the service.

Acceptance: edit a title and time in the app, see the change in Apple Calendar
or Reminders within 5 seconds, and vice versa.

## Phase 2 - Reschedule gestures (done 2026-10-17, verified on iPhone 16 Pro Max; drag-to-time deferred)

- Swipe a reminder row: "Tomorrow" and "Next week" actions.
- Optional: drag a reminder onto a time in the Today view (time-blocking).
- Overdue behavior per the decided rule (pinned until acted on, or auto-roll).

Acceptance: reschedule from the app, verify in Apple Reminders.

## Phase 3 - Search and polish (done 2026-10-31, verified on iPhone 16 Pro Max)

- Search across events and reminders for the next 30 days (reminders search
  exists; extend to events).
- Empty, loading, and denied-permission states reviewed on device.
- App icon badge count setting wired up.
- Accessibility pass: labels on all buttons, Dynamic Type sanity.

Acceptance: the v0.1 success metrics in the spec (sub-second Today view,
10-second quick add, zero sync surprises).

## Phase 4 - TestFlight

- App icon, launch screen, version number.
- Archive, upload to App Store Connect, TestFlight internal build.
- Install on the daily iPhone and use for a week before calling v0.1 done.

Acceptance: daily use for 7 days with no data loss or sync surprises.

## Phase 5 - v0.2 integrations (in build order, TBD)

1. Notion: OAuth, database picker, property mapping, poll-based two-way sync.
2. Google Drive: file picker, attachments row, shared Google sign-in.
3. Video meetings: Google Meet via Calendar API conference data, Zoom via API.
   Needs a Zoom OAuth app registered in the Zoom marketplace.

Each integration gets its own sub-phase with the same rule: device-tested
before done. Integrations stay additive; the timeline works with none
connected.

## Phase 6 - Redesign (branch `redesign`, verified on iPhone 16 Pro Max 2026-11-12, not yet merged)

Rebuild the look to match the Figma page "Redesign (Untitled UI)" in the Unified Day
file. Colors come from the app icon and live in `Assets.xcassets/Colors`, each with
a light and dark version, named like the "UnifiedDay" styles in Figma. Shared pieces
live in `Sources/DesignSystem`. Decisions: keep San Francisco (no Inter), keep
Apple's tab bar, navigation and sheets (tinted), derive dark mode colors.

1. Foundation: color sets, `UD` tokens, shared components, brand tint, Settings.
   (done 2026-11-12, checked in the Simulator in light and dark)
2. Today and Calendar: timeline cards, section headers, summary badges.
   (done 2026-11-12, checked in the Simulator in light and dark)
3. Reminders and Needs Attention.
   (done 2026-11-12, checked in the Simulator in light and dark)
4. Notes: list, folders, editor.
   (done 2026-11-12, checked in the Simulator in light and dark)
5. Composer sheets, item detail, onboarding, access and empty states, Tab Order.
   (done 2026-11-12, checked in the Simulator in light and dark. The error banner
   and the Move sheet were restyled but not seen on screen.)

Acceptance per step: matches the Figma screen in light mode, reads well in dark
mode, Dynamic Type still works, and nothing behaves differently. Run on a real
iPhone before merging to `main`.

## Phase 7 - Mac app (branch `mac`, planned 2026-11-12, not started)

A native Mac version built from the same code. Starts after Phase 6 is merged to
`main`. Layout follows the "UnifiedDay for Mac" mockup:
https://claude.ai/artifact/1gFLrUoBpjuyG6iPxZJCuY

Decisions: add Mac as a second destination on the existing `UnifiedDay` target
(not Mac Catalyst, not a second project), so the bundle ID and iCloud container
stay the same and notes sync between the two. `Models`, `Services` and
`DesignSystem` are shared as they are. Screens that differ on the Mac live in
`Sources/Mac`. Platform differences go behind small shared helpers, not `#if`
blocks spread through the views. No new dependencies.

1. Opens on the Mac. Add the Mac destination and a Mac entitlements file (App
   Sandbox, calendar access, iCloud, network). Give the iPhone-only calls a Mac
   path: navigation bar colors and `UIColor` in `UD.swift`, `UIImage` in
   `Note.swift` and `NoteEditorView`, `UIDevice` in `Feedback.swift`, shake to
   undo in `UnifiedDayApp.swift`, `UIApplication`, `UIPasteboard` and `editMode`
   in `SettingsView` and `TodayView`, and the `.topBar` toolbar placements and
   `navigationBarTitleDisplayMode` in the views. Keep the tab view for now, shown
   as a sidebar. Touches entitlements and Info.plist keys.
   Check against Apple's docs first: which sandbox entitlement covers Reminders
   on macOS, the push entitlement name on macOS, and the lowest macOS version the
   note editor builds for.
   Acceptance: the app launches on the Mac, asks for access, and Today shows real
   events and reminders. The iPhone build is unchanged.
2. Window and menus. The mockup's sidebar (search, four sections, mini month,
   Settings), a New button in the toolbar, a sensible minimum window size, and
   Settings as a standard Mac settings window. Menu commands with shortcuts: New
   (Cmd N), Search (Cmd F), Refresh (Cmd R), Undo (Cmd Z, replaces shake), and
   Cmd 1 to 4 to switch sections.
3. Today with the details panel. Item detail opens in a panel on the right, not
   a sheet. Reschedule and delete move from swipes to hover buttons and the
   right-click menu. Needs Attention opens as a popover from the bell.
4. Calendar. Month grid with items inside each day and the selected day's list
   beside it. Week mode, the filters and the custom range carry over.
5. Reminders. One column per Apple Reminders list, with sort, filter and New
   List. Dragging a reminder between lists is optional and can wait.
6. Notes. List and editor side by side, the formatting bar on top, folders,
   photos from the picker or dragged in, attach to events and reminders.
7. Daily use. Dock badge, alerts through Notification Center, and notes syncing
   with the iPhone. A Mac build run from Xcode reads iCloud's development data,
   while the TestFlight iPhone app reads production data, so notes only match
   once the Mac app is also installed through TestFlight. Set that up here.

Acceptance per step: works on the Mac with real calendar and reminder data in
light and dark mode, and the iPhone app still builds and behaves the same. Phase
done after a week of daily use on the Mac with no data loss or sync surprises.
