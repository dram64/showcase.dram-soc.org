// The site is built under `base` (astro.config.mjs) so it can be served
// from a sub-path. Astro and Vite prefix bundled assets and CSS url()s on
// their own, but hand-written root paths in markup ("/work", "/assets/x.webp")
// would skip the prefix, so templates route them through u(). Anything that
// isn't a root path (full URLs, mailto:, #anchors) passes through untouched.
const base = import.meta.env.BASE_URL.replace(/\/$/, "");

export const u = (path: string) =>
  path.startsWith("/") && !path.startsWith("//") ? base + path : path;
