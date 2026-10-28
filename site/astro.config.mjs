// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";

// Pure static output — Astro emits a plain /dist directory that maps 1:1 to
// the S3 origin behind CloudFront. No adapter, no server, no cold-start
// surprises. The one dynamic piece (the contact form) POSTs cross-origin to
// an API Gateway + Lambda that lives in the same Terraform stack.
//
// The site is served from desiramirez.com/tokyo-zero, so every page and
// asset is built under that `base`. Root paths written in markup go
// through u() in src/lib/url.ts to pick up the same prefix.
export default defineConfig({
  site: "https://desiramirez.com",
  base: "/tokyo-zero",
  output: "static",
  integrations: [react()],
  build: {
    format: "directory",
    assets: "_assets",
  },
  vite: {
    define: {
      "import.meta.env.PUBLIC_CONTACT_API": JSON.stringify(
        process.env.PUBLIC_CONTACT_API || "",
      ),
    },
  },
});
