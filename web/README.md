# Hosts — landing page

A single-page, dependency-free marketing site for the Hosts macOS app. Pure
HTML + CSS (one small inline `IntersectionObserver` for scroll reveals), styled
to match the app's Midnight theme.

The canonical URL is **<https://etc-hosts.com/>** (apex). SEO metadata
(`canonical`, Open Graph, Twitter card, and `SoftwareApplication` JSON-LD) lives in
the `<head>` of `index.html` and references that domain — update them together if the
domain ever changes.

```
web/
├── index.html      # the page (incl. SEO meta + JSON-LD structured data)
├── styles.css      # all styles (CSS variables mirror etc-hosts/UI/Theme.swift)
├── server.cjs      # tiny static server for local preview
├── robots.txt      # allows all crawlers, points to the sitemap
├── sitemap.xml     # single-URL sitemap for the apex
├── CNAME           # custom domain (etc-hosts.com) for GitHub Pages
├── favicon.ico     # 32×32 favicon (the app mark)
└── assets/
    ├── logo.svg            # the app's network-topology mark
    ├── apple-touch-icon.png # 180×180 home-screen icon
    └── og-card.png         # 1200×630 social-share card (og:image / twitter:image)
```

## Preview locally

Any static server works — no build step:

```bash
cd web
node server.cjs          # → http://localhost:4599
# or
python3 -m http.server 8000
```

## Deploy

It's fully static, so drop the `web/` folder on any host:

- **GitHub Pages** — push `web/` (or set Pages to the `/web` folder) and it's live.
- **Netlify / Vercel / Cloudflare Pages** — set the publish directory to `web`,
  no build command.

## Editing

- **Colors** — the `:root` variables at the top of `styles.css`.
- **Copy** — all content is inline in `index.html`, section by section.
- **GitHub link** — search `index.html` for `github.com/akar016012/hosts-app-macos`.
