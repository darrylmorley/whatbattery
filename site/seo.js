// Shared by page metadata and the visible breadcrumb trail. Keep this outside
// scripts/: release tooling is excluded from the public website mirror.
export function buildSeo(data) {
  const { site, page, title, description, breadcrumbLabel, articleType, noindex } = data;
  if (!site || !page?.url) return undefined;
  const canonical = new URL(page.url, site.url).href;
  const pageTitle = title ? (title.includes(site.name) ? title : `${title} · ${site.name}`) : site.name;
  const summary = description || site.tagline;
  const image = `${site.url}/img/og-whatbattery.png`;
  const breadcrumbs = [];
  if (breadcrumbLabel) {
    breadcrumbs.push({ name: "Home", url: "/" });
    const sections = { features: "Features", docs: "Guides", blog: "Blog" };
    const parts = page.url.split("/").filter(Boolean);
    if (parts.length > 1 && sections[parts[0]]) {
      breadcrumbs.push({ name: sections[parts[0]], url: `/${parts[0]}/` });
    }
    breadcrumbs.push({ name: breadcrumbLabel, url: page.url });
  }

  const publisher = {
    "@type": "Organization", "@id": `${site.url}/#publisher`,
    name: "Bitmoor Ltd", url: "https://www.bitmoor.co.uk/",
  };
  const creator = {
    "@type": "Person", "@id": `${site.url}/#creator`,
    name: "Darryl", url: "https://www.darrylmorley.co.uk/",
  };
  const website = {
    "@type": "WebSite", "@id": `${site.url}/#website`,
    name: site.name, url: `${site.url}/`, inLanguage: "en-GB",
    publisher: { "@id": publisher["@id"] },
  };
  const webpage = {
    "@type": ["/features/", "/docs/", "/blog/"].includes(page.url) ? "CollectionPage" : "WebPage",
    "@id": `${canonical}#webpage`, url: canonical, name: pageTitle,
    description: summary, inLanguage: "en-GB",
    isPartOf: { "@id": website["@id"] },
  };
  const graph = [publisher, website, webpage];
  if (breadcrumbs.length > 1) {
    webpage.breadcrumb = { "@id": `${canonical}#breadcrumbs` };
    graph.push({
      "@type": "BreadcrumbList", "@id": webpage.breadcrumb["@id"],
      itemListElement: breadcrumbs.map((crumb, index) => ({
        "@type": "ListItem", position: index + 1, name: crumb.name,
        item: new URL(crumb.url, site.url).href,
      })),
    });
  }
  if (articleType) {
    webpage.mainEntity = { "@id": `${canonical}#article` };
    graph.push(creator, {
      "@type": articleType, "@id": webpage.mainEntity["@id"],
      mainEntityOfPage: { "@id": webpage["@id"] }, url: canonical,
      headline: title, description: summary, inLanguage: "en-GB",
      author: { "@id": creator["@id"] }, publisher: { "@id": publisher["@id"] },
      // Only include article-specific images supplied by the page. A generic
      // brand card is fine for sharing, but is not an article illustration.
      ...(data.articleImage ? { image: new URL(data.articleImage, site.url).href } : {}),
      // No synthetic publication dates: the existing articles have no recorded dates.
    });
  }
  if (page.url === "/" || page.url === "/pro/") {
    webpage.mainEntity = { "@id": `${site.url}/#app` };
    graph.push(creator, {
      "@type": "SoftwareApplication", "@id": webpage.mainEntity["@id"],
      name: site.name, softwareVersion: site.version,
      operatingSystem: "macOS 14 or later, Apple Silicon",
      applicationCategory: "UtilitiesApplication",
      applicationSubCategory: "Battery health and power monitoring",
      url: `${site.url}/`, downloadUrl: site.download,
      installUrl: `${site.url}/docs/install/`, releaseNotes: site.releases,
      description: site.tagline, image,
      featureList: ["Battery health estimated from reported capacity, with the service condition macOS reports", "Live charge and discharge power in watts, with the connected adapter", "Battery runway: wear rate and a projected replacement window", "Sleep and wake diagnosis: overnight drain, wake reasons, and what is holding the Mac awake", "Per-app power use in real watts, live and historical", "Charging sessions with a verdict on each charger", "Per-cell voltage, capacity and resistance from the pack", "Long-term health history for Macs, iPhones and iPads", "Bluetooth accessory battery levels with time-to-empty estimates", "PDF report and CSV or JSON export"],
      screenshot: ["mac", "sleep", "apps", "charging", "history"].map(name => `${site.url}/img/screenshot-${name}.png`),
      author: { "@id": creator["@id"] }, publisher: { "@id": publisher["@id"] },
      offers: [
        { "@type": "Offer", name: "WhatBattery", price: "0", priceCurrency: "GBP", url: `${site.url}/` },
        { "@type": "Offer", name: "WhatBattery Pro", price: "9.99", priceCurrency: "GBP", url: `${site.url}/pro/` },
      ],
    });
  }
  return {
    title: pageTitle, description: summary, canonical, image,
    ogType: articleType ? "article" : "website", breadcrumbs,
    // JSON-LD is raw script text, not an HTML attribute. Escape script delimiters
    // after JSON serialisation so quotes, ampersands and user copy stay valid.
    schema: noindex ? null : JSON.stringify({ "@context": "https://schema.org", "@graph": graph })
      .replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026"),
  };
}

export const indexablePages = (pages) => pages.filter(item =>
  item.data.layout === "base.njk" && !item.data.noindex && item.url &&
  (item.url.endsWith("/") || item.url.endsWith(".html"))
).sort((a, b) => a.url.localeCompare(b.url));
