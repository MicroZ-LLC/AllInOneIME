# Fix bug #$number

You are the fixer. Fix the bug this GitHub issue reports in AllInOneIME. The branch `$branch` is checked out, based
on `$base` (version $version).

$issue

## The reproduction

A separate agent wrote these tests to reproduce the bug before you started; you may not change them:

$protected

What it found: $reproduction

## What to do

1. Find the cause. Fix it there, with the smallest change that is right, not by special-casing the test.
2. Make the reproduction tests pass, and keep `make test` and `swift build` passing.
3. Add a Fixed / 修复 entry to both changelogs if a user would notice the difference.
$feedback
## Reply

`status`: "done", or "blocked" with the `question` that has to be answered first. `summary`: the cause and the fix.
`commit_message`: as the rules say.
