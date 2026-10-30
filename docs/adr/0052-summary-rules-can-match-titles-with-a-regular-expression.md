# ADR 0052: Summary rules can match meeting titles with a regular expression

## Status

Accepted — 2026-10-30. Implemented.
Amends [ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md): rules match exact titles or patterns.

## Context

A summary rule matched a meeting by its exact title. A meeting whose title carries a number or a
date, such as "Delivery Sync 2026", needed a new rule for every instance.

## Decision

1. A rule can be a **pattern**: opt-in per rule, with the Pattern switch in Settings → Binder
   rules → Meeting summaries. Patterns are stored apart from exact titles, in
   `BinderRules.summaryRoutinePatterns`.
2. A pattern is a regular expression that must match the whole meeting title, ignoring case and
   accents. It is evaluated with `NSRegularExpression` (`TitlePattern`), and a pattern that does not
   compile, is empty or is longer than 200 characters is refused.
3. A rule for the exact title wins. Only when none matches, the first pattern in sort order that
   matches the page title or the original title gives the routines.

## Alternatives considered

- **Every title as a regex** — existing titles like "Sync (temp)?" would change meaning silently.
  The maintainer chose an opt-in regex.
- **Wildcards (`*`, `#`)** — easier to type but cannot express `delivery sync [0-9]+` without a
  second syntax.
- **Swift `Regex(_:)`** — it works too, but `NSRegularExpression` takes the case-insensitive option
  without building a `Regex<AnyRegexOutput>` per match and behaves the same on Linux and iOS.

## Consequences

- One rule covers every instance of a recurring meeting whose title varies.
- Settings written by an older build decode unchanged; an older build ignores the new key.
- A badly written pattern can match more than meant; the exact-title rule is the way to override it.

## Verification

`AppCore/Sources/Settings/TitlePattern.swift`, `AppCore/Sources/Settings/BinderRules.swift`,
`AppCore/Sources/Settings/SummaryRoutine.swift`, `AppCore/Sources/Draft/AgendaDraft.swift`,
`App/Screens/RulesView.swift`, and their tests under `AppCore/Tests/`.

## Related

[ADR 0038](0038-summaries-are-written-by-dedicated-summary-routines-that-magenda-starts.md).
