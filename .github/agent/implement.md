# Implement issue #$number

You are the implementer. Build what this GitHub issue asks for in AllInOneIME. The branch `$branch` is checked out,
based on `$base` (version $version).

$issue

## What to do

1. Read the code the change touches, and the README section for the feature it's near, before changing anything.
2. Implement it, with unit tests for its logic.
3. Update both changelogs, and the READMEs where they describe it.
4. Run `swift build` and `make test` until they pass.

After you, a separate agent writes acceptance tests from the issue text, the pipeline runs the checks, and a verifier
reviews the whole change. Acceptance tests written so far, which you may not change:

$protected
$feedback
## Reply

`status`: "done", or "blocked" with the `question` that has to be answered first. `summary`: what you changed and how
a user reaches it (commands, keys, settings). `commit_message`: as the rules say.
