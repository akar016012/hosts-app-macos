# Hosts — landing page

A single-page, dependency-free marketing site for the Hosts macOS app. Pure
HTML + CSS (one small inline `IntersectionObserver` for scroll reveals), styled
to match the app's Midnight theme.

```
web/
├── index.html      # the page
├── styles.css      # all styles (CSS variables mirror native/UI/Theme.swift)
├── server.cjs      # tiny static server for local preview
└── assets/
    └── logo.svg    # the app's network-topology mark
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
