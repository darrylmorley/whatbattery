import assert from "node:assert/strict";
import { test } from "node:test";
import { buildSeo, indexablePages } from "./seo.js";

const site = { name: "WhatBattery", url: "https://www.whatbattery.app", tagline: "Battery health", version: "1.6.5" };

test("copy containing quotes and script delimiters survives JSON-LD without ending its script", () => {
  const description = 'A "quoted" answer & </script><script>alert(1)</script>';
  const result = buildSeo({ site, page: { url: "/features/power/" }, title: 'Power & "watts"', description, breadcrumbLabel: "Power" });
  assert.equal(result.schema.includes("</script>"), false);
  const graph = JSON.parse(result.schema)["@graph"];
  assert.equal(graph.find(node => node["@type"] === "WebPage").description, description);
  assert.equal(result.canonical, "https://www.whatbattery.app/features/power/");
  assert.deepEqual(graph.find(node => node["@type"] === "BreadcrumbList").itemListElement.map(item => item.item), [
    "https://www.whatbattery.app/", "https://www.whatbattery.app/features/", "https://www.whatbattery.app/features/power/",
  ]);
});

test("a new public page enters the sitemap automatically while noindex and non-HTML output stay out", () => {
  const page = (url, extra = {}) => ({ url, data: { layout: "base.njk", ...extra } });
  const pages = [page("/new-guide/"), page("/success/", { noindex: true }), page("/404.html", { noindex: true }), page("/feed.xml"), page("/"), { url: "/sitemap.xml", data: {} }];
  assert.deepEqual(indexablePages(pages).map(item => item.url), ["/", "/new-guide/"]);
  assert.equal(buildSeo({ site, page: { url: "/success/" }, noindex: true }).schema, null);
});
