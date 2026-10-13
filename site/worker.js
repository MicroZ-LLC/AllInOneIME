// allinoneime.com, a Cloudflare Worker with the site's files (public/), deployed with
// `npx wrangler@4 deploy` in this folder.
//
// allinoneime.com (and www.): the site; /download, the newest release's disk image; /docs, the wiki.
// plugins.allinoneime.com: the plugin library (PluginLibrary.defaultBaseURL), the files of the
// AllInOneIME-plugins repository as they are on its main branch; a push there is live within minutes.
// The index is signed and the app checks every file against it, so this host is trusted with nothing.

const PLUGINS = "https://raw.githubusercontent.com/MicroZ-LLC/AllInOneIME-plugins/main";
const PLUGINS_REPO = "https://github.com/MicroZ-LLC/AllInOneIME-plugins";
const REPO = "https://github.com/MicroZ-LLC/AllInOneIME";

const TYPES = { json: "application/json", js: "text/javascript", md: "text/markdown; charset=utf-8", txt: "text/plain; charset=utf-8" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname === "plugins.allinoneime.com") return plugins(request, url);
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

async function plugins(request, url) {
  if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method Not Allowed", { status: 405 });
  if (url.pathname === "/") return Response.redirect(PLUGINS_REPO, 302);
  const upstream = await fetch(PLUGINS + url.pathname, { method: request.method, cf: { cacheTtl: 300, cacheEverything: true } });
  const headers = new Headers({ "cache-control": "public, max-age=300", "x-content-type-options": "nosniff" });
  const extension = url.pathname.split(".").pop().toLowerCase();
  headers.set("content-type", upstream.ok ? (TYPES[extension] ?? "application/octet-stream") : "text/plain; charset=utf-8");
  const etag = upstream.headers.get("etag");
  if (etag) headers.set("etag", etag);
  return new Response(upstream.ok ? upstream.body : `${upstream.status}`, { status: upstream.ok ? 200 : upstream.status, headers });
}
