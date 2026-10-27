# ADR 0041: Magenda is an iPad app

## Status

Accepted — 2026-10-27. Implemented.
Amends [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md): item 7's iPhone preview is gone.

## Context

The binder and its Pencil ink are the product (ADR 0020). The iPhone has no Pencil, so the iPhone
build only ever showed a read-only PDF preview of the rendered day. The app has shipped only through
TestFlight, there has been no App Store release, and it has no iPhone users; the maintainer
confirmed this on 2026-10-26.

Keeping the iPhone family still cost real time. CI tested it on two runtimes, and the pull-request
run took over three hours: sixteen macOS jobs queued behind the account's cap of five concurrent
macOS jobs (run 40294684850). Each UI test also carried a branch for the iPhone path or a skip for
the iPad-only paths.

## Decision

1. The app targets the iPad only: `TARGETED_DEVICE_FAMILY` is `"2"` in `project.yml`, and the
   iPhone orientation key is gone.
2. `AgendaView` shows the binder, or the "No binder yet" placeholder, and nothing else. The
   iPhone-only `PreviewView` and `PDFKitView` are deleted, and so are the `userInterfaceIdiom`
   branches in the app and in the UI tests.
3. Views keep their `horizontalSizeClass` logic: an iPad window is compact in Slide Over and Split
   View.
4. `scripts/simulator.py` still accepts `--family iphone`, because its picker is device-agnostic,
   but its default is `ipad`.

## Alternatives considered

- **Keep the app universal and drop only the iPhone CI** — that ships an iPhone build nobody tests.
- **Keep `PreviewView` for a later use** — no later use is planned, and dead views still have to
  compile and be tested.

## Consequences

- Simulator tests run on one device family, which is what makes four shards enough
  ([ADR 0043](0043-simulator-tests-run-in-four-timed-shards.md)).
- Anyone with an iPhone can no longer install a build. There are no such users today; an iPhone app
  later would be a new decision with its own ADR.
- `AgendaController.render` still writes a PDF on every Render, which only the deleted preview read.
  The PDF is also the export (ADR 0020), so it stays; removing the redundant write is a separate
  change.

## Verification

- `project.yml`: `TARGETED_DEVICE_FAMILY: "2"`.
- `git grep -n userInterfaceIdiom -- App AppUITests` prints nothing.
- `CHANGELOG.md` lists the removal under "Removed".

## Related

- [ADR 0020](0020-on-ipad-the-agenda-is-a-binder-of-native-pages-with-pencilkit-ink.md)
- [ADR 0042](0042-pull-requests-test-the-newest-ipad-runtime.md)
