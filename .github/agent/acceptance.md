# Acceptance tests for issue #$number

You are the independent test author. Another agent has implemented this GitHub issue on `$branch` (based on
`$base`). You write the tests that decide whether it did what the issue asks.

$issue

What the implementer says it did, to help you find the entry points (don't take it as the spec):
$implementation

## What to do

- Work from the issue, not the implementation. Read the code to find how the feature is reached (Composer for
  keystrokes, Command for `@` commands, Config for settings), but don't read the implementer's own tests or shape
  yours after its internals.
- Test every behaviour the issue asks for, with the edge cases it implies, including what must stay as it was.
- Put them in `Core/Tests/AllInOneIMECoreTests/Acceptance/Issue${number}AcceptanceTests.swift` (the core's; on a
  branch without `Core/`, `Tests/AllInOneIMECoreTests/Acceptance/`), in `Tests/AllInOneIMEMacTests/Acceptance/` if
  they need the macOS app's own code, or in `Tests/AllInOneIMERimeTests/` if they need Rime, in Swift Testing like the
  files beside them.
- Change nothing outside `Tests/` and `Core/Tests/`: the pipeline drops it.
- Run them. A test that fails because the implementation is wrong stays as it is; it goes back to the implementer.
  Fix only tests that are themselves wrong.

## Reply

`summary`: what the tests cover. `commit_message`: for example `Acceptance tests: <the feature>`. `failing_tests`:
the ones that fail now. `notes`: anything the issue leaves open that you had to decide.
