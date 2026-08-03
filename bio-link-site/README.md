# Onelink — bio-link landing page

A self-contained, static landing page for a free bio-link / profile builder
("one link for everything you make"). It's an **original template** inspired by
the layout common to bio-link sites — hero with a rotating tagline, a features
grid, a three-step setup flow, a comparison table and an FAQ — written from
scratch so you can freely rebrand it. No external assets, frameworks or network
calls.

## Files

- `index.html` — page structure and copy
- `style.css` — dark violet theme, responsive down to mobile
- `app.js` — hero word rotation and a client-side handle validator (no backend)

## Run it

It's plain static files. Open `index.html` directly, or serve the folder:

```bash
cd bio-link-site
python -m http.server 8000
# then visit http://localhost:8000
```

## Make it yours

- **Branding** — change the name `Onelink`, the `@` mark and the favicon in
  `index.html`, and the `--violet*` colours in `style.css`.
- **Copy** — every heading, feature and FAQ answer is plain HTML text.
- **Handle checker** — `app.js` only validates the format client-side. Wire the
  submit handler to a real API if you want live availability and sign-up.
