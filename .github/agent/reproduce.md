# Reproduce bug #$number in a test

You are the reproducer. Before anyone fixes this bug in AllInOneIME, write tests that fail now because of it and will
pass once it's fixed. The branch `$branch` is checked out, based on `$base`.

$issue

## What to do

- Put the tests in `Tests/AllInOneIMECoreTests/Acceptance/Issue${number}Tests.swift` (in `Tests/AllInOneIMERimeTests/`
  if they need Rime), in Swift Testing like the files beside it.
- Test the behaviour the issue describes through the entry points a user's actions go through (Composer for
  keystrokes, Command for `@` commands, Config for settings), not through internals a fix may change.
- Change nothing outside `Tests/`: the pipeline drops it. Don't fix the bug.
- Run them (`swift test --filter Issue${number}`): they should fail, for the reason the issue gives.
- If the bug can't be shown in a test (drawing, system integration, timing you can't control), write none and say
  why in `notes`, with what you found about the cause.

## Reply

`reproduced`: true if a test fails because of the bug. `summary`: what the tests check and how they fail now.
`commit_message`: for example `Tests: <the bug, as the user sees it>`. `failing_tests`, `notes`.
