// GitHub issues and pull requests, for the input method's suggestions (`#12` → `#1234`) and for `@github <words>`.
// The repositories are the plugin's preference "repos" (owner/repo, comma-separated); a token (optional) reads private
// ones. Only api.github.com is contacted. The plugin never sees what you type except, for the live lookup, the part
// after "#" (`query`), and for `@github` the words after the command.

function repos(ctx) {
  const text = (ctx && ctx.preferences && ctx.preferences.repos) || "MicroZ-LLC/AllInOneIME";
  return text.split(/[\s,]+/).map(s => s.trim()).filter(s => /^[\w.-]+\/[\w.-]+$/.test(s)).slice(0, 5);
}

function headers(ctx) {
  const h = { "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };
  const token = ctx && ctx.preferences && ctx.preferences.token;
  if (token) h["Authorization"] = "Bearer " + token;
  return h;
}

/** One item from an issue or pull request of `repo`. */
function item(repo, issue) {
  const kind = issue.pull_request ? "PR" : "issue";
  const age = issue.updated_at ? ago(Date.parse(issue.updated_at)) : "";
  return {
    match: "#" + issue.number,
    title: "#" + issue.number + " " + clean(issue.title),
    subtitle: [repo, issue.state, kind, age].filter(Boolean).join(" · "),
    arg: "#" + issue.number,
    variables: { url: issue.html_url, title: clean(issue.title) },
  };
}

function clean(text) {
  return String(text || "").replace(/[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩﻿]/g, "").slice(0, 200);
}

function ago(ms) {
  const minutes = Math.max(0, Math.round((Date.now() - ms) / 60000));
  if (minutes < 60) return minutes + "m ago";
  if (minutes < 48 * 60) return Math.round(minutes / 60) + "h ago";
  return Math.round(minutes / 1440) + "d ago";
}

/** The whole list: the 100 most recently updated issues and PRs of each repository. */
function load(ctx) {
  const list = repos(ctx);
  const urls = list.map(r => "https://api.github.com/repos/" + r + "/issues?state=all&sort=updated&per_page=100");
  const answers = fetch(urls, { headers: headers(ctx) });
  const items = [];
  answers.forEach((a, i) => {
    if (!a.ok) return;
    for (const issue of a.json()) items.push(item(list[i], issue));
  });
  if (!items.length && answers.every(a => !a.ok)) throw new Error("GitHub answered " + answers.map(a => a.status || a.error).join(", "));
  return { items, fetchedAt: Math.floor(Date.now() / 1000) };
}

/** A live lookup: `text` is what follows "#": a number (that issue, and numbers starting with it among recent ones are
 * the list's job) or words (a title search). */
function query(text, ctx) {
  const list = repos(ctx);
  const h = { headers: headers(ctx) };
  if (/^\d{1,7}$/.test(text)) {
    const answers = fetch(list.map(r => "https://api.github.com/repos/" + r + "/issues/" + text), h);
    return { items: answers.flatMap((a, i) => a.ok ? [item(list[i], a.json())] : []) };
  }
  const q = encodeURIComponent(list.map(r => "repo:" + r).join(" ") + " in:title " + text);
  const a = fetch("https://api.github.com/search/issues?per_page=10&q=" + q, h);
  if (!a.ok) return { items: [] };
  return { items: a.json().items.map(issue => item(issue.repository_url.split("/repos/")[1], issue)) };
}

/** `@github <words>`: the matching issues and PRs, one per line. */
function run(input, context) {
  const words = String(input || "").trim();
  if (!words) return "Type words after @github to search the issues of your repositories";
  const found = query(words.replace(/^#/, ""), context).items;
  if (!found.length) return "No issue or PR matches “" + words + "”";
  return found.slice(0, 8).map(i => i.title + "  " + i.variables.url).join("\n");
}
