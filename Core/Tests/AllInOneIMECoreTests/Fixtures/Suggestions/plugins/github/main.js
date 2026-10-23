// GitHub issues for the "issues" completion source: the open and recently closed issues of the repositories in the
// "repos" preference (load), and one looked up by its number as it is typed (query). Only api.github.com is reachable.

function headers(ctx) {
  const h = { "Accept": "application/vnd.github+json", "User-Agent": "AllInOneIME" };
  if (ctx.preferences.token) h["Authorization"] = "Bearer " + ctx.preferences.token;
  return h;
}

function repos(ctx) {
  return String(ctx.preferences.repos || "").split(",").map(s => s.trim()).filter(s => /^[\w.-]+\/[\w.-]+$/.test(s));
}

function item(issue) {
  return { match: "#" + issue.number, title: issue.title, subtitle: issue.state,
           variables: { url: issue.html_url } };
}

function load(ctx) {
  const urls = repos(ctx).map(r => "https://api.github.com/repos/" + r + "/issues?state=all&per_page=100");
  const items = [];
  for (const response of fetch(urls, { headers: headers(ctx) })) {
    if (!response.ok) throw new Error("GitHub said " + response.status);
    for (const issue of response.json()) items.push(item(issue));
  }
  return { items: items, fetchedAt: Math.floor(Date.now() / 1000) };
}

function query(text, ctx) {
  if (!/^\d+$/.test(text)) return { items: [] };
  const urls = repos(ctx).map(r => "https://api.github.com/repos/" + r + "/issues/" + text);
  const items = [];
  for (const response of fetch(urls, { headers: headers(ctx) })) {
    if (response.ok) items.push(item(response.json()));
  }
  return { items: items };
}
