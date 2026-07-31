import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";

const shortHash = (bytes) =>
  createHash("sha256").update(bytes).digest("hex").slice(0, 12);

export default async function (eleventyConfig) {
  const styleVersion = shortHash(readFileSync("src/css/style.css"));

  eleventyConfig.addGlobalData("styleVersion", styleVersion);
  eleventyConfig.addPassthroughCopy("src/css");
  eleventyConfig.addPassthroughCopy("src/img");
  eleventyConfig.addPassthroughCopy("src/press");
  eleventyConfig.addPassthroughCopy("src/CNAME");
  eleventyConfig.addPassthroughCopy("src/robots.txt");

  // Stamp every local asset URL with a hash of its own bytes.
  //
  // The stylesheet has done this since the cached-CSS incident, but images
  // never did, so replacing a screenshot left every returning visitor (and
  // Cloudflare) serving the old picture indefinitely. Doing it as a transform
  // rather than a template filter means no markup has to remember to opt in,
  // and a file whose contents have not changed keeps its existing URL.
  const versionCache = new Map();
  const versionFor = (assetPath) => {
    if (versionCache.has(assetPath)) return versionCache.get(assetPath);
    const source = `src${assetPath}`;
    const version = existsSync(source) ? shortHash(readFileSync(source)) : null;
    versionCache.set(assetPath, version);
    return version;
  };

  eleventyConfig.addTransform("bustAssetUrls", function (content) {
    if (!this.page.outputPath?.endsWith(".html")) return content;
    return content.replace(
      /(src|href)="(\/(?:img|press)\/[^"?#]+)"/g,
      (whole, attribute, assetPath) => {
        const version = versionFor(assetPath);
        return version ? `${attribute}="${assetPath}?v=${version}"` : whole;
      }
    );
  });

  return {
    dir: {
      input: "src",
      output: "docs",
      includes: "_includes",
      layouts: "_layouts",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}
