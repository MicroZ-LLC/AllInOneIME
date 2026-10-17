# Verify the change for issue #$number

You are the verifier, the last check before this branch merges into `$base` with no human review. Decide whether
`$branch` does what the issue asks, correctly, and is fit to ship. Pass it only if you would merge it yourself.

$issue

## The change

- The diff: `git diff $base_sha...HEAD`; the commits: `git log $base_sha..HEAD`.
- The implementer's summary: $implementation
- Tests by a separate agent: $acceptance
- Files the pipeline put back because the implementer may not change them: $put_back

The pipeline has run `swift build` and `make test`: they pass, apart from tests that already failed on `$base`.

## Check

- It does all of what the issue asks, and nothing it doesn't: no extra commands, settings or shortcuts, no unrelated
  changes.
- It is correct: read the code for edge cases, errors, concurrency, and what happens to existing users' settings and
  data.
- The tests test the issue's behaviour and would catch it breaking; none were weakened or removed to pass.
- Both changelogs (and the READMEs where they describe it) say what changed; English docs are English only.
- It reads like the code around it; no debugging leftovers, secrets, or files that don't belong.

Run whatever helps you judge: tests, `--settings-image` renders, small programs in `$AGENT_SCRATCH`. Don't change the
repository's files.

## Reply

`verdict`: "pass" or "fail". `summary`: a few sentences on what you checked and found. `problems`: each one concrete
enough to fix (the file, what's wrong, what it should do); empty when it passes.
