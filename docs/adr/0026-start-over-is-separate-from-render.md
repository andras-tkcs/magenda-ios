# ADR 0026: Render keeps a started day's handwriting; Start over is a separate, confirmed action that deletes it and renders the day fresh

## Status

Accepted — 2026-10-23. Implemented.
Amends [ADR 0021](0021-a-binder-day-is-stored-as-a-content-snapshot-and-ink-per-page-key.md).
Amends [ADR 0023](0023-binder-undo-uses-a-handwriting-history-kept-by-the-session.md).

## Context

Rendering a started day again keeps its handwriting and added pages (ADR 0021), so there was no way
to discard a day's notes and begin again.

## Decision

1. Render is unchanged: it keeps handwriting on its pages.
2. On iPad, once a day's binder is open, the agenda's toolbar has a Start Over button. It asks
   "Start this day over?" and says that all notes on the day will be deleted.
3. Confirming calls `AgendaController.startOver()`. It saves empty data under every ink key the
   store holds for the day, which removes each one, including keys of pages no longer shown, so
   nothing comes back on a later Render. It then saves a fresh `BinderDay` (no added pages, no
   retained pages) from the current draft, drops the open binder and renders. The render opens a
   new session over the empty store, so its undo history is empty and Undo cannot bring deleted
   handwriting back.
4. The fresh day is saved before the render, so a render that is overtaken (a day switch or an edit
   while it runs drops its result) cannot leave the old added pages stored without their ink.
5. Start Over is not in the Agenda menu: the confirmation lives in the view, and a menu item
   without it would delete notes with one keystroke.
6. If deleting fails, the binder is reopened from the store, so it shows what is really stored
   (pages whose handwriting was already deleted are blank), and a message asks the person to free
   some space. The reopened session starts with an empty undo history.

## Alternatives considered

- **Making Render itself start over, with a warning** — it would lose the handwriting-keeping
  re-render of ADR 0021, which is wanted.
- **Deleting the day's folder through a new `BinderStore` method** — removing every ink key with
  the existing API does the same without a new protocol requirement.

## Consequences

- While the render runs, the iPad detail shows the "No binder yet" placeholder, then the new
  binder.
- The same day can now get an empty undo history, besides a day switch or a relaunch (ADR 0023).
- Deleted handwriting cannot be recovered.

## Verification

`AppCore/Sources/Controller/AgendaController.swift`, `App/Screens/AgendaView.swift`,
`AppCore/Tests/Controller/AgendaControllerBinderTests.swift`, `AppUITests/StartOverUITests.swift`.

## Related

ADR 0021, ADR 0023.
