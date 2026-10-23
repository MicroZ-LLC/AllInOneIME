// allinoneime.com, a Cloudflare Worker with the site's files (public/), deployed with
// `npx wrangler@4 deploy` in this folder.
//
// allinoneime.com (and www.): the site; /download, the newest release's disk image; /docs, the wiki;
// /update.json and /update.json.sig, the in-app updater's manifest (public/, written and signed by `make update-manifest`
// with the releases' own key: the app checks the signature, then the download against it, so this host is trusted
// with nothing there either).
// plugins.allinoneime.com: the plugin library (PluginLibrary.defaultBaseURL), the files of the
// AllInOneIME-plugins repository as they are on its main branch; a push there is live within minutes.
// The index is signed and the app checks every file against it, so this host is trusted with nothing.
// languages.allinoneime.com: the language pack library (LanguagePackLibrary.defaultBaseURL), the same way
// from the AllInOneIME-languages repository: packs.json and its signature (the archives are its release assets), and
// coding-packs.json and its signature, the Code input's coding language packs (CodingPackLibrary; a JSON file each).

const PLUGINS = "https://raw.githubusercontent.com/MicroZ-LLC/AllInOneIME-plugins/main";
const PLUGINS_REPO = "https://github.com/MicroZ-LLC/AllInOneIME-plugins";
const LANGUAGES = "https://raw.githubusercontent.com/MicroZ-LLC/AllInOneIME-languages/main";
const LANGUAGES_REPO = "https://github.com/MicroZ-LLC/AllInOneIME-languages";
const REPO = "https://github.com/MicroZ-LLC/AllInOneIME";

const TYPES = { json: "application/json", js: "text/javascript", md: "text/markdown; charset=utf-8", txt: "text/plain; charset=utf-8" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === "plugins.allinoneime.com") return library(request, url, PLUGINS, PLUGINS_REPO);
    if (url.hostname === "languages.allinoneime.com") return library(request, url, LANGUAGES, LANGUAGES_REPO);
    if (url.hostname === "www.allinoneime.com") return Response.redirect(`https://allinoneime.com${url.pathname}${url.search}`, 301);
    if (url.pathname === "/docs" || url.pathname.startsWith("/docs/")) return Response.redirect(`${REPO}/wiki`, 302);
    if (url.pathname === "/download") return download();
    return env.ASSETS.fetch(request);
  },
};

/// The newest release's disk image (asked of GitHub, cached for 5 minutes); its page if there is none.
async function download() {
  const latest = await fetch("https://api.github.com/repos/MicroZ-LLC/AllInOneIME/releases/latest", {
    headers: { "user-agent": "allinoneime.com", accept: "application/vnd.github+json" },
    cf: { cacheTtl: 300, cacheEverything: true },
  });
  if (latest.ok) {
    const release = await latest.json();
    const dmg = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));
    if (dmg) return Response.redirect(dmg.browser_download_url, 302);
  }
  return Response.redirect(`${REPO}/releases/latest`, 302);
}

/// A library's files as they are on its repository's main branch (`raw`); its root, the repository.
async function library(request, url, raw, repo) {
  if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method Not Allowed", { status: 405 });
  if (url.pathname === "/") return Response.redirect(repo, 302);
  const upstream = await fetch(raw + url.pathname, { method: request.method, cf: { cacheTtl: 300, cacheEverything: true } });
  const headers = new Headers({ "cache-control": "public, max-age=300", "x-content-type-options": "nosniff" });
  const extension = url.pathname.split(".").pop().toLowerCase();
  headers.set("content-type", upstream.ok ? (TYPES[extension] ?? "application/octet-stream") : "text/plain; charset=utf-8");
  const etag = upstream.headers.get("etag");
  if (etag) headers.set("etag", etag);
  return new Response(upstream.ok ? upstream.body : `${upstream.status}`, { status: upstream.ok ? 200 : upstream.status, headers });
}
