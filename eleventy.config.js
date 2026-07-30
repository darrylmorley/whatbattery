import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

export default async function (eleventyConfig) {
  const styleVersion = createHash("sha256")
    .update(readFileSync("src/css/style.css"))
    .digest("hex")
    .slice(0, 12);

  eleventyConfig.addGlobalData("styleVersion", styleVersion);
  eleventyConfig.addPassthroughCopy("src/css");
  eleventyConfig.addPassthroughCopy("src/img");
  eleventyConfig.addPassthroughCopy("src/CNAME");
  eleventyConfig.addPassthroughCopy("src/robots.txt");

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
