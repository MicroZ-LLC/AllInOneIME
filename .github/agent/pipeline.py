#!/usr/bin/env python3
# Works on one GitHub issue end to end, unattended, on the Mac mini's Actions runner (.github/workflows/agent.yml):
#
#   python3 .github/agent/pipeline.py ISSUE
#   python3 .github/agent/pipeline.py --finish [ISSUE]    merge what passed its checks (every agent:merging issue)
#
# An issue labelled agent:build (a feature) or agent:fix (a bug) by a maintainer is built on a branch X.Y.Z/issue-N
# off the open release branch (the newest release-X.Y.Z with no vX.Y.Z tag), by Claude Code agents that share no
# session:
#   build: implementer → independent acceptance-test author → checks → verifier
#   fix:   reproducer (a failing test) → fixer → checks → verifier
# The checks (`swift build`, `make lint`, `make test`) run here, not on the agents' word: no test that passed on the
# release branch may fail, and `make lint` may not fail where it passed. The test author's files and the acceptance
# tests are put back if anyone else touches them, and nothing under .github/ changes.
# A failed check or a "fail" from the verifier goes back to the implementer, twice at most. When the verifier passes
# the branch, it goes into a PR to the release branch, which merges like everyone's: only once the required checks
# pass (CI's quality gate and the independent review, .github/workflows/quality.yml and review.yml, which this script
# starts, since a PR made with the job's token starts no workflow). The issue gets agent:merging, and this job ends
# (the gates need this runner). Then `pipeline.py --finish`, run every hour by agent-queue.yml, merges the PR once its
# required checks pass and closes the issue; a required check that fails gets the
# issue agent:stuck with a comment saying which, and once it is run again and passes, the PR still merges. Otherwise
# the work is left in a draft PR and the issue gets agent:stuck with a comment saying why. Out of usage (the Max plan's
# limit), or no open release branch: agent:queued, and agent-queue.yml starts it again later. AGENT_BASE names another
# branch to build on, for trying the pipeline out.
#
# The agents run on the Max plan through this Mac's Claude Code sign-in, never an API key, and without the GitHub
# token. They don't commit or push: this script commits their work (author from AGENT_GIT_AUTHOR, dated when it
# commits) and pushes it.

from __future__ import annotations

import base64
import datetime as dt
import json
import os
import re
import signal
import string
import subprocess
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = os.environ["GITHUB_REPOSITORY"]
OWNER, NAME = REPO.split("/")
WORK = Path.home() / ".agent-pipeline" / NAME
SCRATCH = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "agent-scratch"
RUN_URL = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{REPO}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

BUILD, FIX = "agent:build", "agent:fix"
WORKING, QUEUED, STUCK, DONE = "agent:working", "agent:queued", "agent:stuck", "agent:done"
MERGING = "agent:merging"
# What a PR has to pass before it merges, whatever the branch protection says (it adds any other check it requires):
# the quality gate's last job (a check run) and the independent review (a commit status), the workflows that run them.
GATE, REVIEW = "Quality gate", "review"
GATE_WORKFLOWS = ("quality.yml", "review.yml")
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
ROUNDS = 3  # the first try, then two more after a failed check or verdict
MINUTES = {"implement": 120, "fix": 90, "acceptance": 60, "reproduce": 60, "verify": 60}
# Where the test author and the reproducer write: the macOS app's tests, and the core's (Core/, its own package, since
# 0.6.5; Tests/AllInOneIMECoreTests on a branch from before).
TESTS = ("Tests/", "Core/Tests/")
# The acceptance tests, the test authors' alone: whatever an implementer or fixer changes there is put back.
ACCEPTANCE = ("Core/Tests/AllInOneIMECoreTests/Acceptance/", "Core/Tests/AllInOneIMETestSupport/Acceptance/",
              "Tests/AllInOneIMEMacTests/Acceptance/",
              "Tests/AllInOneIMECoreTests/Acceptance/", "Tests/AllInOneIMERimeTests/Acceptance/")


class Queued(Exception):
    """Try again later: no open release branch, or the plan's usage is used up."""


class Stuck(Exception):
    """A person has to look: the reason, then details for the issue comment."""

    def __init__(self, reason: str, details: str = ""):
        super().__init__(reason)
        self.reason, self.details = reason, details


def log(message: str) -> None:
    print(f"[{dt.datetime.now():%H:%M:%S}] {scrub(message)}", flush=True)


def scrub(text: str) -> str:
    """Text that goes to GitHub or the log, without the job's token in any form."""
    token = os.environ.get("GH_TOKEN", "")
    if token:
        text = text.replace(token, "***").replace(basic_auth(token), "***")
    return re.sub(r"(?i)(authorization:\s*\w+\s+)\S+", r"\1***", text)


def basic_auth(token: str) -> str:
    return base64.b64encode(f"x-access-token:{token}".encode()).decode()


def run(args: list[str], cwd: Path | None = None, env: dict | None = None, input: str | None = None,
        timeout: float | None = None, check: bool = False, stderr_apart: bool = False) -> subprocess.CompletedProcess:
    """Runs a command in its own process group, so a timeout stops everything it started.
    Its stderr goes into stdout unless `stderr_apart`."""
    process = subprocess.Popen(args, cwd=cwd, env=env, text=True, start_new_session=True,
                               stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE if stderr_apart else subprocess.STDOUT)
    try:
        out, err = process.communicate(input, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        out, err = process.communicate()
        err = (err or "") + f"\n[timed out after {timeout / 60:.0f} min]"
        process.returncode = 124
    result = subprocess.CompletedProcess(args, process.returncode, out, err or "")
    if check and result.returncode:
        raise RuntimeError(f"{' '.join(args[:3])} failed ({result.returncode}):\n{(out + result.stderr)[-3000:]}")
    return result


def git(*args: str, check: bool = True, env: dict | None = None, input: str | None = None) -> str:
    return run(["git", *args], cwd=WORK, check=check, env=env, input=input).stdout.strip()


def gh(*args: str, input: str | None = None):
    out = run(["gh", *args], input=input, check=True, stderr_apart=True).stdout
    return json.loads(out) if out.strip() else None


def commit_env() -> dict:
    """The environment the pipeline commits and merges in: git dates them as it makes them (no date from outside)."""
    env = dict(os.environ)
    env.pop("GIT_AUTHOR_DATE", None)
    env.pop("GIT_COMMITTER_DATE", None)
    return env


# MARK: GitHub

def labels(number: int, add: list[str] = (), remove: list[str] = ()) -> None:
    if add:
        gh("api", "-X", "POST", f"repos/{REPO}/issues/{number}/labels", "--input", "-",
           input=json.dumps({"labels": list(add)}))
    for name in remove:
        run(["gh", "api", "-X", "DELETE", f"repos/{REPO}/issues/{number}/labels/{name}"])  # absent is fine


def comment(number: int, body: str) -> None:
    gh("api", "-X", "POST", f"repos/{REPO}/issues/{number}/comments", "--input", "-",
       input=json.dumps({"body": scrub(body)}))


def permission(login: str) -> str:
    result = run(["gh", "api", f"repos/{REPO}/collaborators/{login}/permission", "--jq", ".permission"],
                 stderr_apart=True)
    return result.stdout.strip() if result.returncode == 0 else "none"


APPROVAL = """query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    lastEditedAt authorAssociation
    timelineItems(itemTypes: [LABELED_EVENT], last: 50) {
      nodes { ... on LabeledEvent { createdAt actor { login } label { name } } } } } } }"""


def approval(issue: dict) -> str:
    """build or fix, from the latest agent label a maintainer put on the issue."""
    data = gh("api", "graphql", "-f", f"query={APPROVAL}", "-f", f"owner={OWNER}", "-f", f"name={NAME}",
              "-F", f"number={issue['number']}")["data"]["repository"]["issue"]
    current = {label["name"] for label in issue["labels"]} & {BUILD, FIX}
    events = [e for e in data["timelineItems"]["nodes"] if e and e["label"]["name"] in current]
    if not events:
        raise Stuck("The issue has no agent:build or agent:fix label.")
    last = events[-1]
    actor = (last.get("actor") or {}).get("login", "")
    if permission(actor) not in ("admin", "maintain"):
        raise Stuck(f"The label was added by @{actor}, who isn't a maintainer of this repository.")
    edited = data.get("lastEditedAt")
    if data["authorAssociation"] not in TRUSTED and edited and edited > last["createdAt"]:
        raise Stuck("The issue was edited after it was labelled. A maintainer has to read it and label it again.")
    return "fix" if last["label"]["name"] == FIX else "build"


def issue_text(issue: dict) -> str:
    """The issue and the comments the agents may read: maintainers' and this pipeline's own."""
    parts = [f"# #{issue['number']} {issue['title']}\n\n{(issue.get('body') or '').strip() or '(no description)'}"]
    for c in gh("api", f"repos/{REPO}/issues/{issue['number']}/comments?per_page=100") or []:
        own = c["user"]["login"] == "github-actions[bot]"
        if c["author_association"] in TRUSTED or own:
            who = "an earlier run of this pipeline" if own else f"@{c['user']['login']} (maintainer)"
            parts.append(f"## Comment by {who}, {c['created_at'][:10]}\n\n{c['body'].strip()}")
    return "\n\n".join(parts)


def ensure_pr(branch: str, base: str, title: str, body: str, draft: bool) -> dict | None:
    """The branch's open PR, made or updated. None where Actions may not create PRs (an organization setting)."""
    body = scrub(body)
    prs = gh("api", f"repos/{REPO}/pulls?head={OWNER}:{branch}&state=open")
    if not prs:
        result = run(["gh", "api", "-X", "POST", f"repos/{REPO}/pulls", "--input", "-"], stderr_apart=True,
                     input=json.dumps({"title": title, "head": branch, "base": base, "body": body, "draft": draft}))
        if result.returncode and "not permitted to create" in result.stdout + result.stderr:
            log("Actions may not create pull requests here: merging without one")
            return None
        if result.returncode:
            raise RuntimeError(f"creating the PR failed: {(result.stdout + result.stderr)[-2000:]}")
        return json.loads(result.stdout)
    pr = prs[0]
    gh("api", "-X", "PATCH", f"repos/{REPO}/pulls/{pr['number']}", "--input", "-",
       input=json.dumps({"title": title, "body": body}))
    if pr["draft"] and not draft:
        gh("api", "graphql", "-f", f"id={pr['node_id']}", "-f",
           "query=mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id}) { clientMutationId } }")
    return pr


# MARK: git

def push(*refspecs: str, force: bool = False) -> None:
    """Pushes with the job's token, which is never stored in the clone nor on a command line."""
    env = dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
               GIT_CONFIG_VALUE_0=f"AUTHORIZATION: basic {basic_auth(os.environ['GH_TOKEN'])}")
    git("push", "-q", *(["--force"] if force else []), "origin", *refspecs, env=env)


def commit(message: str, start: str) -> str | None:
    """Commits whatever the agent left (its own commits since `start` folded in). None if it changed nothing."""
    if git("rev-parse", "HEAD") != start:
        git("reset", "-q", "--soft", start)
    git("add", "-A")
    if not git("diff", "--cached", "--name-only"):
        return None
    git("commit", "-q", "-F", "-", env=commit_env(), input=f"{message.strip()}\n\n{TRAILER}\n")
    return git("rev-parse", "HEAD")


def changed_since(at: str) -> list[str]:
    """Paths that differ from commit `at`: committed since, staged, unstaged or untracked (not ignored)."""
    tracked = git("diff", "--name-only", at).splitlines()
    untracked = git("ls-files", "--others", "--exclude-standard").splitlines()
    return sorted(set(tracked) | set(untracked))


def put_back(paths: list[str], at: str) -> list[str]:
    """Restores these paths as they were at commit `at` (deleting ones that didn't exist). Returns those that differed."""
    differed = []
    for path in paths:
        if run(["git", "cat-file", "-e", f"{at}:{path}"], cwd=WORK).returncode == 0:
            if run(["git", "diff", "--quiet", at, "--", path], cwd=WORK).returncode:
                git("checkout", at, "--", path)
                differed.append(path)
        elif (WORK / path).exists():
            git("rm", "-q", "-f", "--cached", "--ignore-unmatch", "--", path)
            (WORK / path).unlink()
            differed.append(path)
    return differed


def guard(protected: list[str], protected_at: str | None, base_sha: str, start: str) -> list[str]:
    """Puts back what an implementer may not change: the test author's files, the acceptance tests already there when
    it started (`start`), and anything under .github/."""
    notes = [f"{p} (written by the test author)" for p in put_back(protected, protected_at)] if protected_at else []
    accepted = [p for p in changed_since(start) if p.startswith(ACCEPTANCE) and p not in protected]
    notes += [f"{p} (an acceptance test)" for p in put_back(accepted, start)]
    workflow = [p for p in changed_since(base_sha) if p.startswith(".github/")]
    return notes + [f"{p} (.github/ is off limits)" for p in put_back(workflow, base_sha)]


def tests_only(start: str) -> list[str]:
    """For the test author and the reproducer: drops their changes outside the tests (TESTS), returns the test files."""
    put_back([p for p in changed_since(start) if not p.startswith(TESTS)], start)
    return changed_since(start)


def prepare(base: str, branch: str) -> str:
    if not (WORK / ".git").exists():
        WORK.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "-q", f"https://github.com/{REPO}.git", str(WORK)], check=True)
    git("remote", "set-url", "origin", f"https://github.com/{REPO}.git")
    if m := re.fullmatch(r"\s*(.+?)\s*<(.+)>\s*", os.environ.get("AGENT_GIT_AUTHOR", "")):
        git("config", "user.name", m.group(1))
        git("config", "user.email", m.group(2))
    git("merge", "--abort", check=False)
    git("fetch", "-q", "--prune", "--tags", "--force", "origin")
    git("checkout", "-q", "-f", "-B", branch, f"origin/{base}")
    git("clean", "-q", "-ffdx", "-e", "ThirdParty/", "-e", ".build/")
    SCRATCH.mkdir(parents=True, exist_ok=True)
    return git("rev-parse", "HEAD")


def open_release() -> str | None:
    """The newest release-X.Y.Z branch newer than every vX.Y.Z tag."""
    def versions(listing: str, prefix: str) -> list[tuple]:
        found = []
        for line in listing.splitlines():
            ref = line.split("\t")[-1].removesuffix("^{}")
            if m := re.fullmatch(prefix + r"(\d+)\.(\d+)\.(\d+)", ref):
                found.append(tuple(int(n) for n in m.groups()))
        return found
    url = f"https://github.com/{REPO}.git"
    branches = versions(run(["git", "ls-remote", "--heads", url], check=True).stdout, "refs/heads/release-")
    released = versions(run(["git", "ls-remote", "--tags", url], check=True).stdout, "refs/tags/v")
    newer = [v for v in branches if not released or v > max(released)]
    return "release-" + ".".join(map(str, max(newer))) if newer else None


# MARK: checks

class Checks:
    def __init__(self, built: bool, passed: bool, failures: set[str], log: str, linted: bool = False,
                 lint_log: str = ""):
        self.built, self.passed, self.failures, self.log = built, passed, failures, log
        self.linted, self.lint_log = linted, lint_log

    def summary(self) -> str:
        # make test runs several packages (Core/, then the macOS shell): each prints its own total.
        m = re.findall(r"Test run with (\d+) tests? in \d+ suites? (?:passed|failed)", self.log)
        return f"{sum(map(int, m))} tests" if m else "the tests"


FAILURE = [re.compile(r"^✘ Test (?!run with )(.+?)(?: with \d+ test cases?)? failed after", re.M),
           re.compile(r"^Test Case '-\[(\S+ \S+)\]' failed", re.M)]


def checks(base: str) -> Checks:
    """Builds, lints (its baselines compared with the base branch's, as CI does) and tests what the agents left, in an
    environment without the job's GitHub token: their code runs here."""
    env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}
    build = run(["make", "deps"], cwd=WORK, env=env, timeout=1800)
    if build.returncode == 0:
        build = run(["swift", "build"], cwd=WORK, env=env, timeout=1800)
    if build.returncode:
        return Checks(False, False, set(), build.stdout[-8000:])
    lint = run(["make", "-k", "lint", f"LINT_BASE=origin/{base}"], cwd=WORK, env=env, timeout=1800)
    test = run(["make", "test"], cwd=WORK, env=env, timeout=3600)
    failures = {name for pattern in FAILURE for name in pattern.findall(test.stdout)}
    return Checks(True, test.returncode == 0, failures, test.stdout, lint.returncode == 0, lint.stdout)


def regressions(baseline: Checks, now: Checks, base: str) -> str | None:
    """What fails now that didn't on the release branch: `make lint`, and the tests (one that fails only once is run
    again)."""
    if not now.built:
        return f"`swift build` fails:\n\n```\n{now.log[-6000:]}\n```"
    lint = None
    if baseline.linted and not now.linted:
        noise = re.compile(r"^\[\d+/\d+\]|^(?:Building|Build complete|Compiling|Fetch|Comput|Creating|Working copy"
                           r"|Planning)")
        lines = "\n".join(line for line in now.lint_log.splitlines() if not noise.match(line))
        lint = f"`make lint` fails:\n\n```\n{lines[-4000:]}\n```"
    tests = test_regressions(baseline, now, base)
    return "\n\n".join(problem for problem in (lint, tests) if problem) or None


def test_regressions(baseline: Checks, now: Checks, base: str) -> str | None:
    if now.passed or (now.failures and not now.failures - baseline.failures):
        return None
    again = checks(base)
    new = (again.failures - baseline.failures) & ((now.failures - baseline.failures) or again.failures)
    if again.passed or (again.failures and not new):
        return None
    lines = [line for line in again.log.splitlines() if line.startswith(("✘", "error:", "Test Case"))]
    names = ", ".join(sorted(new)) if new else "the test run itself (a crash, or a build error in the tests)"
    return f"`make test` fails: {names}\n\n```\n{chr(10).join(lines)[-6000:] or again.log[-6000:]}\n```"


# MARK: agents

SCHEMAS = {
    "work": {"type": "object", "required": ["status", "summary", "commit_message"], "properties": {
        "status": {"type": "string", "enum": ["done", "blocked"]},
        "summary": {"type": "string"}, "commit_message": {"type": "string"},
        "question": {"type": "string"}}},
    "tests": {"type": "object", "required": ["summary", "commit_message"], "properties": {
        "summary": {"type": "string"}, "commit_message": {"type": "string"},
        "reproduced": {"type": "boolean"}, "failing_tests": {"type": "array", "items": {"type": "string"}},
        "notes": {"type": "string"}}},
    "verdict": {"type": "object", "required": ["verdict", "summary", "problems"], "properties": {
        "verdict": {"type": "string", "enum": ["pass", "fail"]},
        "summary": {"type": "string"}, "problems": {"type": "array", "items": {"type": "string"}}}},
}
OUT_OF_USAGE = re.compile(r"usage limit|limit (?:reached|will reset)|hit your (?:usage )?limit|out of (?:extra )?usage"
                          r"|rate.?limit|\b429\b", re.I)
ENV = ("HOME", "USER", "LOGNAME", "PATH", "SHELL", "TMPDIR", "LANG", "LC_ALL", "TERM", "DEVELOPER_DIR")


def agent(role: str, schema: str, read_only: bool = False, **values) -> dict:
    prompt = string.Template((HERE / f"{role}.md").read_text()).safe_substitute(values, scratch=SCRATCH)
    denied = ["Bash(git push:*)", "Bash(gh:*)"] + (["Edit", "Write", "NotebookEdit"] if read_only else [])
    args = ["claude", "-p", "--permission-mode", "bypassPermissions",
            "--append-system-prompt", (HERE / "rules.md").read_text(),
            "--output-format", "json", "--json-schema", json.dumps(SCHEMAS[schema]),
            "--disallowedTools", *denied]
    env = {k: os.environ[k] for k in ENV if k in os.environ}  # no GitHub or Actions tokens
    env["AGENT_SCRATCH"] = str(SCRATCH)
    log(f"{role}: started")
    result = run(args, cwd=WORK, env=env, input=prompt, timeout=MINUTES[role] * 60, stderr_apart=True)
    try:
        out = json.loads(result.stdout)
    except ValueError:
        out = {}
    reply = out.get("structured_output")
    if result.returncode == 0 and not out.get("is_error") and isinstance(reply, dict):
        log(f"{role}: {json.dumps(reply, ensure_ascii=False)[:2000]}")
        return reply
    text = f"{out.get('result') or result.stdout[-2000:]}\n{result.stderr[-2000:]}".strip()
    if OUT_OF_USAGE.search(text):
        raise Queued("The Max plan's usage is used up for now.")
    raise Stuck(f"The {role} agent stopped without an answer (exit {result.returncode}).", f"```\n{text[-3000:]}\n```")


# MARK: the run

def main(number: int) -> int:
    issue = gh("api", f"repos/{REPO}/issues/{number}")
    if issue["state"] != "open" or "pull_request" in issue:
        log("not an open issue")
        return 0
    base = branch = None
    try:
        kind = approval(issue)
        base = os.environ.get("AGENT_BASE") or open_release()
        if base is None:
            raise Queued("There's no open release branch (a release-X.Y.Z without its vX.Y.Z tag) to build on.")
        if not re.fullmatch(r"\w[\w.-]*(?:/[\w.-]+)*", base) or run(
                ["git", "ls-remote", "--exit-code", "--heads", f"https://github.com/{REPO}.git", base]).returncode:
            raise Stuck(f"There's no branch `{base}` to build on.")
        version = base.removeprefix("release-")
        # 0.6.5/issue-N beside release-0.6.5; another base can't have branches under its own name.
        branch = f"{version}/issue-{number}" if base.startswith("release-") else f"{base}-issue-{number}"
        labels(number, add=[WORKING], remove=[QUEUED, STUCK, DONE, MERGING])
        log(f"#{number} ({kind}) on {branch} off {base}")
        base_sha = prepare(base, branch)
        values = dict(number=number, title=issue["title"], issue=issue_text(issue), base=base, branch=branch,
                      base_sha=base_sha, version=version, protected="(none yet)", reproduction="")
        baseline = checks(base)
        if not baseline.built or (not baseline.passed and not baseline.failures):
            raise Stuck(f"`{base}` itself doesn't build or test here.", f"```\n{baseline.log[-4000:]}\n```")
        log(f"baseline: {baseline.summary()}, {len(baseline.failures)} failing")

        protected, protected_at, test_notes = [], None, ""
        if kind == "fix":
            start = git("rev-parse", "HEAD")
            tests = agent("reproduce", "tests", **values)
            protected = tests_only(start)
            protected_at = commit(tests["commit_message"], start)
            test_notes = tests["summary"]
            if not tests.get("reproduced", True):
                test_notes += "\n\nNo test could reproduce it: " + tests.get("notes", "")
            values.update(protected="\n".join(f"- {p}" for p in protected) or "(none)", reproduction=test_notes)

        feedback, tests_written = "", kind == "fix"
        for round in range(1, ROUNDS + 1):
            start = git("rev-parse", "HEAD")
            work = agent("implement" if kind == "build" else "fix", "work",
                         feedback=f"\n## What the last round got wrong\n\n{feedback}\n" if feedback else "", **values)
            if work["status"] == "blocked":
                raise Stuck("The agent needs an answer before it can go on.", work.get("question") or work["summary"])
            notes = guard(protected, protected_at, base_sha, start)
            commit(work["commit_message"], start)

            if not tests_written:
                start = git("rev-parse", "HEAD")
                tests = agent("acceptance", "tests", implementation=work["summary"], **values)
                protected = tests_only(start)
                protected_at = commit(tests["commit_message"], start)
                test_notes, tests_written = tests["summary"], True
                values["protected"] = "\n".join(f"- {p}" for p in protected) or "(none)"

            problem = regressions(baseline, checks(base), base)
            if problem is None:
                verdict = agent("verify", "verdict", read_only=True, implementation=work["summary"],
                                acceptance=test_notes or "(none)", put_back="\n".join(notes) or "(nothing)", **values)
                git("reset", "-q", "--hard", "HEAD")
                git("clean", "-q", "-fd")
                if verdict["verdict"] == "pass":
                    break
                problem = verdict["summary"] + "\n\n" + "\n".join(f"- {p}" for p in verdict["problems"])
            if notes:
                problem += "\n\nPut back, because you may not change them:\n" + "\n".join(f"- {n}" for n in notes)
            log(f"round {round} failed: {problem[:1000]}")
            if round == ROUNDS:
                raise Stuck(f"Still not right after {ROUNDS} rounds.", problem)
            feedback = problem

        merge(number, issue["title"], base, branch, base_sha, baseline, work, test_notes, verdict)
        return 0
    except Queued as reason:
        log(f"queued: {reason}")
        labels(number, add=[QUEUED], remove=[WORKING])
        if QUEUED not in {label["name"] for label in issue["labels"]}:
            comment(number, f"Queued: {reason} It starts again on its own. ([run]({RUN_URL}))")
        return 0
    except Stuck as stuck:
        log(f"stuck: {stuck.reason}\n{stuck.details}")
        give_up(number, issue["title"], base, branch, stuck.reason, stuck.details)
        return 1
    except Exception:
        details = f"```\n{traceback.format_exc()[-3000:]}\n```"
        log(details)
        give_up(number, issue["title"], base, branch, "The pipeline itself failed.", details)
        return 1


def give_up(number: int, title: str, base: str | None, branch: str | None, reason: str, details: str) -> None:
    """Leaves the work so far in a draft PR, says why on the issue, labels it agent:stuck."""
    link = ""
    try:
        if branch and git("rev-parse", "--abbrev-ref", "HEAD", check=False) == branch and \
                git("rev-list", "--count", f"origin/{base}..HEAD", check=False) not in ("", "0"):
            push(f"HEAD:refs/heads/{branch}", force=True)
            pr = ensure_pr(branch, base, title, f"Work on #{number} by the agent pipeline, stopped: {reason}\n\n"
                                                f"{details}\n\n[Run]({RUN_URL})", draft=True)
            link = f" The work so far is in #{pr['number']}." if pr else \
                f" The work so far is on [`{branch}`](https://github.com/{REPO}/compare/{base}...{branch})."
    except Exception as error:
        log(f"couldn't push the work so far: {error}")
    comment(number, f"**Stopped:** {reason}{link}\n\n{details}\n\nAnswer here and add the label again to start over "
                    f"(maintainers' comments are read). ([run]({RUN_URL}))")
    labels(number, add=[STUCK], remove=[WORKING])


def merge(number: int, title: str, base: str, branch: str, base_sha: str, baseline: Checks, work: dict,
          test_notes: str, verdict: dict) -> None:
    """Puts the verified branch in a ready PR to `base` and starts its required checks. It never merges here: the change
    goes in through the same gate as everyone's, by `finish`, once they pass."""
    git("fetch", "-q", "origin", base)
    if git("rev-parse", f"origin/{base}") != base_sha:
        log(f"{base} moved: merging it in")
        if run(["git", "merge", "--no-ff", "-q", "-m", f"Merge branch '{base}' into {branch}", f"origin/{base}"],
               cwd=WORK, env=commit_env()).returncode:
            git("merge", "--abort", check=False)
            raise Stuck(f"`{base}` changed while this ran, and merging it in conflicts.")
        problem = regressions(baseline, checks(base), base)
        if problem:
            raise Stuck(f"After merging the newer `{base}` in, the checks fail.", problem)

    push(f"HEAD:refs/heads/{branch}", force=True)
    pr = ensure_pr(branch, base, title, draft=False, body=(
        f"Closes #{number}. Built by the agent pipeline ([run]({RUN_URL})).\n\n"
        f"**Change** (implementer): {work['summary']}\n\n"
        f"**Tests** (a separate agent): {test_notes or '(none)'}\n\n"
        f"**Verifier:** pass. {verdict['summary']}\n\n"
        f"Checked on the Mac mini: `swift build`, `make lint`, `make test`. It merges once its required checks pass.\n\n"
        f"🤖 Generated with [Claude Code](https://claude.com/claude-code)"))
    if pr is None:
        raise Stuck("Actions may not create pull requests in this repository, and a change merges only through one, "
                    "once its required checks pass. Allow it (Settings → Actions → General → Workflow permissions → "
                    "Allow GitHub Actions to create and approve pull requests), then add the label again.")
    start_checks(pr["number"], branch, base, git("rev-parse", "HEAD"))
    # No GitHub auto-merge: it would merge on whatever the branch protection requires, which may not be both gates;
    # `finish` merges only once both passed (gate_state).
    comment(number, f"Ready in #{pr['number']}. It merges into `{base}` within the hour after its required checks pass "
                    f"(the quality gate and the independent review), and this issue closes then.\n\n"
                    f"**Change:** {work['summary']}\n\n**Tests** (a separate agent): {test_notes or '(none)'}\n\n"
                    f"**Verifier:** pass. {verdict['summary']}")
    labels(number, add=[MERGING], remove=[WORKING])
    log(f"#{pr['number']} is waiting for its required checks")


def start_checks(pr: int, branch: str, base: str, sha: str) -> dict[str, str]:
    """Starts each of the gate's workflows that hasn't run on the PR's head (a PR made, or a branch pushed, with the job's
    token starts no workflow by itself). Returns each workflow's latest run's status on it ("started" if just now)."""
    status = {}
    for workflow in GATE_WORKFLOWS:
        runs = gh("api", f"repos/{REPO}/actions/workflows/{workflow}/runs?head_sha={sha}&per_page=1") or {}
        if runs.get("workflow_runs"):
            status[workflow] = runs["workflow_runs"][0]["status"]
            continue
        inputs = {"base": base} if workflow == "quality.yml" else {"pr": str(pr)}
        gh("api", "-X", "POST", f"repos/{REPO}/actions/workflows/{workflow}/dispatches", "--input", "-",
           input=json.dumps({"ref": branch, "inputs": inputs}))
        status[workflow] = "started"
        log(f"started {workflow} on {branch}")
    return status


# MARK: merging what passed

PULL = """query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    number title state merged mergeStateStatus headRefName headRefOid baseRefName
    commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
      __typename
      ... on CheckRun { name status conclusion startedAt isRequired(pullRequestNumber: $number) }
      ... on StatusContext { context state isRequired(pullRequestNumber: $number) } } } } } } } } } }"""
WORKFLOW_OF = {GATE: "quality.yml", REVIEW: "review.yml"}


def agent_pr(number: int) -> dict | None:
    """The pipeline's PR for the issue (from its branch X.Y.Z/issue-N, or BASE-issue-N), with its checks."""
    # Every page: a PR waiting for its checks may have dropped out of the most recently updated hundred.
    pages = gh("api", "--paginate", "--slurp", f"repos/{REPO}/pulls?state=all&sort=updated&direction=desc&per_page=100")
    for pr in (pr for page in pages or [] for pr in page):
        own = (pr["head"].get("repo") or {}).get("full_name") == REPO
        if own and re.search(rf"(?:/|-)issue-{number}$", pr["head"]["ref"]):
            return gh("api", "graphql", "-f", f"query={PULL}", "-f", f"owner={OWNER}", "-f", f"name={NAME}",
                      "-F", f"number={pr['number']}")["data"]["repository"]["pullRequest"]
    return None


def gate_state(pr: dict, runs: dict[str, str]) -> tuple[list[str], list[str]]:
    """The required checks on the PR's head that failed, and those still to pass: the gate's two, and every other the
    branch protection requires. A check run again counts as its latest run."""
    commit = (pr["commits"]["nodes"] or [{}])[0].get("commit") or {}
    latest: dict[str, tuple[str, str]] = {}
    for check in ((commit.get("statusCheckRollup") or {}).get("contexts") or {}).get("nodes") or []:
        if check["__typename"] == "CheckRun":
            name, when = check["name"], check.get("startedAt") or "~"  # not started yet: the newest
            state = "pending" if check["status"] != "COMPLETED" else \
                "pass" if check["conclusion"] in ("SUCCESS", "NEUTRAL", "SKIPPED") else "fail"
        else:
            name, when = check["context"], ""
            state = {"SUCCESS": "pass", "PENDING": "pending", "EXPECTED": "pending"}.get(check["state"], "fail")
        if (check["isRequired"] or name in WORKFLOW_OF) and when >= latest.get(name, ("", ""))[0]:
            latest[name] = (when, state)
    failed = [name for name, (_, state) in latest.items() if state == "fail"]
    waiting = [name for name, (_, state) in latest.items() if state == "pending"]
    for name, workflow in WORKFLOW_OF.items():
        # A run of its workflow still queued or running (a rerun) answers anew: wait for it, whatever the old status says.
        if runs.get(workflow) not in (None, "completed"):
            failed = [n for n in failed if n != name]
            if name not in waiting:
                waiting.append(name)
            continue
        if name not in latest:  # not reported: fine while its workflow runs, a failure once it ended without it
            (failed if runs.get(workflow) == "completed" else waiting).append(name)
    return failed, waiting


def finish(number: int) -> None:
    """Merges an agent:merging issue's PR once its required checks pass, then closes the issue; says so on the issue
    once when a check fails (the PR still merges if it's run again and passes) or the PR was closed."""
    issue = gh("api", f"repos/{REPO}/issues/{number}")
    names = {label["name"] for label in issue["labels"]}
    if issue["state"] != "open" or MERGING not in names:
        return
    pr = agent_pr(number)
    if pr is None or (pr["state"] != "OPEN" and not pr["merged"]):
        what = "its PR is gone" if pr is None else f"#{pr['number']} was closed"
        comment(number, f"**Not merged:** {what}. Add the label again to start over. ([run]({RUN_URL}))")
        labels(number, add=[STUCK], remove=[MERGING])
        return
    if not pr["merged"]:
        runs = start_checks(pr["number"], pr["headRefName"], pr["baseRefName"], pr["headRefOid"])
        failed, waiting = gate_state(pr, runs)
        if failed:
            if STUCK not in names:
                comment(number, f"**Not merged yet:** #{pr['number']}'s required checks failed: {', '.join(failed)}. "
                                f"Fix it on the PR's branch, or run a check that failed for another reason again: the "
                                f"PR merges once they pass. ([run]({RUN_URL}))")
                labels(number, add=[STUCK])
            return
        if waiting or "started" in runs.values():
            log(f"#{number}: #{pr['number']} is waiting for {', '.join(waiting) or 'its checks'}")
            return
        if pr["mergeStateStatus"] == "BEHIND":  # the branch protection wants the base merged in: then checked again
            gh("api", "-X", "PUT", f"repos/{REPO}/pulls/{pr['number']}/update-branch", "-f",
               f"expected_head_sha={pr['headRefOid']}")
            log(f"#{number}: brought #{pr['number']} up to date with {pr['baseRefName']}")
            return
        result = run(["gh", "api", "-X", "PUT", f"repos/{REPO}/pulls/{pr['number']}/merge", "--input", "-"],
                     stderr_apart=True, input=json.dumps({
                         "merge_method": "merge", "sha": pr["headRefOid"], "commit_message": pr["title"],
                         "commit_title": f"Merge pull request #{pr['number']} from {OWNER}/{pr['headRefName']}"}))
        if result.returncode:
            if STUCK not in names:
                comment(number, f"**Not merged yet:** GitHub refused to merge #{pr['number']}:\n\n```\n"
                                f"{(result.stdout + result.stderr).strip()[-1500:]}\n```\n\n([run]({RUN_URL}))")
                labels(number, add=[STUCK])
            return
    run(["gh", "api", "-X", "DELETE", f"repos/{REPO}/git/refs/heads/{pr['headRefName']}"])  # gone already is fine
    base = pr["baseRefName"]
    comment(number, f"Merged into `{base}` in #{pr['number']}; it ships with {base.removeprefix('release-')}.")
    labels(number, add=[DONE], remove=[MERGING, STUCK, WORKING, BUILD, FIX])
    gh("api", "-X", "PATCH", f"repos/{REPO}/issues/{number}", "-f", "state=closed", "-f", "state_reason=completed")
    log(f"#{number}: #{pr['number']} merged into {base}")


def finish_all(numbers: list[str]) -> int:
    """`finish` for the issues given, or every open agent:merging one. Exit status 1 if any failed."""
    if not numbers:
        found = gh("api", f"repos/{REPO}/issues?labels={MERGING}&state=open&per_page=100") or []
        numbers = [str(issue["number"]) for issue in found if "pull_request" not in issue]
    status = 0
    for number in numbers:
        try:
            finish(int(number))
        except Exception:
            log(f"#{number}: {traceback.format_exc()[-3000:]}")
            status = 1
    return status


if __name__ == "__main__":
    if sys.argv[1] == "--finish":
        sys.exit(finish_all(sys.argv[2:]))
    sys.exit(main(int(sys.argv[1])))
