// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";

// Pure static output — Astro emits a plain /dist directory that maps 1:1 to
// the S3 origin behind CloudFront. No adapter, no server, no cold-start
// surprises. The one dynamic piece (the contact form) POSTs cross-origin to
// an API Gateway + Lambda that lives in the same Terraform stack.
export default defineConfig({
  site: "https://showcase.dram-soc.org",
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
