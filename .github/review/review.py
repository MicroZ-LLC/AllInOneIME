#!/usr/bin/env python3
# The independent review of one PR (.github/workflows/review.yml): another model than the one that likely wrote the
# change reads its diff with the fixed prompt in .github/review/prompt.md (the base branch's copy, so a PR can't soften
# its own review) and answers in JSON; this posts that as one comment on the PR (edited in place on later pushes) and
# sets the commit status `review` on the PR's head: failure only for a high-confidence correctness or privacy finding
# of high or medium severity, success otherwise, error when no reviewer could run. The reviewer is Codex CLI (its
# ChatGPT sign-in on the runner, no API key), else Claude Code (the Max plan's sign-in); it runs read-only, with no
# GitHub token. Never for a PR from a fork.
#
#   python3 .github/review/review.py PR                  review PR (GITHUB_REPOSITORY, GH_TOKEN set)
#   python3 .github/review/review.py --dry-run BASE HEAD  review `git diff BASE...HEAD` here, print, post nothing

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# The checkout: the workflow runs the base branch's copy of this script from elsewhere.
ROOT = Path(os.environ.get("GITHUB_WORKSPACE") or Path(__file__).resolve().parents[2])
MARKER = "<!-- allinoneime-review -->"
MAX_DIFF = 150_000  # characters of diff given inline; the reviewer can read the rest with git
MINUTES = 25
CATEGORIES = ["correctness", "privacy", "main-thread", "rules", "tests", "other"]
LEVELS = ["high", "medium", "low"]
SCHEMA = {"type": "object", "additionalProperties": False, "required": ["summary", "findings"], "properties": {
    "summary": {"type": "string"},
    "findings": {"type": "array", "items": {
        "type": "object", "additionalProperties": False,
        "required": ["category", "severity", "confidence", "file", "line", "title", "detail"],
        "properties": {"category": {"type": "string", "enum": CATEGORIES},
                       "severity": {"type": "string", "enum": LEVELS},
                       "confidence": {"type": "string", "enum": LEVELS},
                       "file": {"type": "string"}, "line": {"type": "integer"},
                       "title": {"type": "string"}, "detail": {"type": "string"}}}}}}
# Only these reach the reviewer's process: no GitHub or Actions token.
ENV = ("HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "LANG", "LC_ALL", "TERM", "DEVELOPER_DIR", "CODEX_HOME")


def sh(*args: str, input: str | None = None, check: bool = True) -> str:
    result = subprocess.run(args, cwd=ROOT, input=input, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"{' '.join(args[:4])} failed: {result.stderr.strip()[-1000:]}")
    return result.stdout


def gh(*args: str, body: dict | None = None):
    out = sh("gh", "api", *args, *(["--input", "-"] if body is not None else []),
             input=json.dumps(body) if body is not None else None)
    return json.loads(out) if out.strip().startswith(("{", "[")) else out


def prompt_for(base: str, head: str, title: str, description: str) -> str:
    fixed = sh("git", "show", f"{base}:.github/review/prompt.md", check=False) or \
        (ROOT / ".github/review/prompt.md").read_text()
    diff = sh("git", "diff", "--no-color", f"{base}...{head}")
    if len(diff) > MAX_DIFF:
        diff = diff[:MAX_DIFF] + f"\n[... cut: the whole diff is `git diff {base}...{head}`]\n"
    files = sh("git", "diff", "--stat=200", f"{base}...{head}")
    return (f"{fixed}\n\n## The pull request\n\n### Title\n\n{title}\n\n### Description\n\n{description or '(none)'}"
            f"\n\n### Files\n\n```\n{files}```\n\n### Diff (`git diff {base}...{head}`)\n\n```diff\n{diff}```\n")


def codex(prompt: str, workdir: Path) -> dict:
    schema, out = workdir / "schema.json", workdir / "answer.json"
    schema.write_text(json.dumps(SCHEMA))
    subprocess.run(["codex", "exec", "--sandbox", "read-only", "--ephemeral", "--ignore-user-config",
                    "--skip-git-repo-check", "--color", "never", "--output-schema", str(schema),
                    "--output-last-message", str(out), "-C", str(ROOT), "-"],
                   input=prompt, text=True, capture_output=True, env=clean_env(), timeout=MINUTES * 60, check=True)
    return json.loads(out.read_text())


def claude(prompt: str, workdir: Path) -> dict:
    result = subprocess.run(["claude", "-p", "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
                             "--allowedTools", "Read", "Grep", "Glob", "Bash(git diff:*)", "Bash(git log:*)",
                             "Bash(git show:*)", "--disallowedTools", "Edit", "Write", "NotebookEdit"],
                            cwd=ROOT, input=prompt, text=True, capture_output=True, env=clean_env(),
                            timeout=MINUTES * 60, check=True)
    answer = json.loads(result.stdout).get("structured_output")
    if not isinstance(answer, dict):
        raise RuntimeError(f"no structured answer: {result.stdout[-500:]}")
    return answer


def clean_env() -> dict:
    return {k: os.environ[k] for k in ENV if k in os.environ}


def review(prompt: str) -> tuple[str, dict]:
    """(who, answer) from the first reviewer that answers."""
    errors = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, reviewer in (("Codex", codex), ("Claude Code", claude)):
            if not shutil.which(reviewer.__name__):
                errors.append(f"{name}: not installed")
                continue
            try:
                answer = reviewer(prompt, Path(tmp))
                if isinstance(answer.get("findings"), list) and isinstance(answer.get("summary"), str):
                    return name, answer
                errors.append(f"{name}: an answer without the schema's fields")
            except Exception as error:  # a timeout, a sign-in or usage limit, a malformed answer: try the next one
                detail = getattr(error, "stderr", "") or ""
                errors.append(f"{name}: {error} {detail.strip()[-500:]}")
    raise RuntimeError("no reviewer could answer:\n" + "\n".join(errors))


def blocking(finding: dict) -> bool:
    return finding["category"] in ("correctness", "privacy") and finding["confidence"] == "high" \
        and finding["severity"] in ("high", "medium")


def comment_body(who: str, answer: dict, head: str, run_url: str) -> str:
    findings = answer["findings"]
    blocks = [f for f in findings if blocking(f)]
    verdict = f"**blocks the merge** ({len(blocks)} high-confidence correctness or privacy " \
              f"finding{'s' if len(blocks) != 1 else ''})" if blocks else "nothing that blocks the merge"
    lines = [MARKER, f"### Independent review: {verdict}", "",
             f"By {who}, at {head[:7]}, against [AGENTS.md](../blob/{head}/AGENTS.md) "
             f"([run]({run_url})). {answer['summary'].strip()}", ""]
    for f in findings:
        where = f"`{f['file']}:{f['line']}`" if f["line"] else f"`{f['file']}`" if f["file"] else ""
        tag = "🛑 " if blocking(f) else ""
        lines.append(f"- {tag}**{f['title'].strip()}** {where} ({f['category']}; severity {f['severity']}, "
                     f"confidence {f['confidence']})  \n  {f['detail'].strip()}")
    if not findings:
        lines.append("No findings.")
    lines += ["", "<sub>Advice from a model: the status `review` fails only for 🛑. Disagree? Say why in a reply; a "
                  "maintainer can merge over it.</sub>"]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if argv[:1] == ["--dry-run"] and len(argv) == 3:
        who, answer = review(prompt_for(argv[1], argv[2], "(dry run)", ""))
        print(comment_body(who, answer, sh("git", "rev-parse", argv[2]).strip(), "local"))
        print(f"\nstatus review: {'failure' if any(map(blocking, answer['findings'])) else 'success'}")
        return 0
    repo, number = os.environ["GITHUB_REPOSITORY"], argv[0]
    run_url = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}/actions/runs/" \
              f"{os.environ.get('GITHUB_RUN_ID', '')}"
    pr = gh(f"repos/{repo}/pulls/{number}")
    if (pr["head"].get("repo") or {}).get("full_name") != repo:
        print("A PR from a fork: not reviewed here.")
        return 0
    head, base = pr["head"]["sha"], f"origin/{pr['base']['ref']}"

    def status(state: str, description: str) -> None:
        gh(f"repos/{repo}/statuses/{head}", body={"state": state, "context": "review",
                                                    "description": description[:140], "target_url": run_url})

    status("pending", "Reviewing the change")
    try:
        prompt = prompt_for(base, head, pr["title"], pr.get("body") or "")
        sh("git", "checkout", "-q", "--detach", head)  # the reviewer reads the files as the PR has them
        who, answer = review(prompt)
    except Exception as error:
        print(error, file=sys.stderr)
        status("error", "The reviewer couldn't run: run the Review workflow again")
        return 1
    body = comment_body(who, answer, head, run_url)
    ids = sh("gh", "api", "--paginate", f"repos/{repo}/issues/{number}/comments",
             "--jq", f'.[] | select(.user.login == "github-actions[bot]" and (.body | startswith("{MARKER}"))) | .id')
    if ids.split():
        gh("-X", "PATCH", f"repos/{repo}/issues/comments/{ids.split()[0]}", body={"body": body})
    else:
        gh("-X", "POST", f"repos/{repo}/issues/{number}/comments", body={"body": body})
    blocks = [f for f in answer["findings"] if blocking(f)]
    if blocks:
        status("failure", f"{who}: {blocks[0]['title']}")
    else:
        status("success", f"{who}: {len(answer['findings'])} findings, none blocking")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
