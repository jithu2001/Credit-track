# WholeFlow product website

The public site at **https://wholeflow.jitsuji.xyz**. Plain HTML, CSS and a little JavaScript, with no framework and no build step.

```
index.html              the page (copy, SEO tags, JSON-LD: SoftwareApplication, Organization, FAQPage)
404.html                not-found page
assets/css/site.css     styles, including the self-hosted fonts (@font-face)
assets/js/site.js       scroll-driven phone screens, count-up, reveal, contact form
assets/fonts/           Fraunces, IBM Plex Sans, IBM Plex Mono (OFL), latin + latin-ext (₹)
assets/img/             app screenshots (720 px and -360 versions), icons, og.png (1200×630)
robots.txt, sitemap.xml, site.webmanifest, favicon.ico
tools/og.html           source of assets/img/og.png (not deployed)
deploy.sh               copies the site to the server
```

## Run locally

Serve the `website` folder with any static web server. Opening `index.html`
straight from the disk (`file://…`) does not work: the pages load their files
from `/assets/…`, which needs a server whose root is this folder.

```bash
cd website
python3 -m http.server 8000      # then open http://localhost:8000
```

Edits show on reload (Ctrl+Shift+R if the browser keeps an old `site.css` or
`site.js`). Stop the server with Ctrl+C. The privacy page is
http://localhost:8000/privacy.html; any unknown path shows Python's own
404, not `404.html` (nginx serves that one on the server).

**Contact form:** locally there is no `/api/contact`, so sending shows
"Something went wrong. Please try again." That is expected. The checks in the
browser (name, mobile number, email) still work. To try the real send, use the
live site, or run the control service (`wholeflow-control serve`) and post to
`http://127.0.0.1:8100/control/leads` directly.

## Contact form

The contact section is a form (name, business, mobile, email, number of Tally companies, city, message).

- **Path:** it posts to `/api/contact` on the site. nginx (`location = /api/contact` in `wholeflow-site.conf`) forwards that to the control service (`POST /control/leads`), which stores the enquiry in `control_db.leads`.
- **Where you see it:** admin app → **Enquiries**. A badge shows new ones. You can call, WhatsApp or email from there, set a status (New / Contacted / Became a customer / Not interested), keep a note, or delete.
- **Required fields:** name, a 10-digit Indian mobile number and an email address. They are checked in the browser and again on the server (`CleanLead`).
- **Spam protection:**
  - a hidden honeypot field (bots that fill it are silently ignored);
  - 5 posts per minute per IP;
  - 5 stored enquiries per IP per day.
- **If certbot rewrites `wholeflow-site.conf`** when HTTPS is added, keep the `/api/contact` block, and copy the server's file back into the repo.

## Screenshots

These are the real app screens, rendered by a Flutter test with **invented** data: no real shop, phone number or key.

```bash
cd wholeflow_app
WF_SCREENSHOTS=1 flutter test test/marketing --update-goldens   # → test/marketing/out/*.png (1080×2400)
```

Then convert them to WebP at 720×1600 and 360×800 into `assets/img/` with the same names: the 720 px version as `<name>.webp`, the 360 px version as `<name>-360.webp`. To re-render the share image, open `tools/og.html` at 1200×630 in a browser and screenshot it (Playwright: `page.screenshot`).

## Publish

**Live since 6 October 2026** at https://wholeflow.jitsuji.xyz.

- **DNS:** GoDaddy A record `wholeflow` → `75.119.130.27`.
- **HTTPS:** Let's Encrypt via certbot (renews itself), with HTTP redirected to HTTPS and HTTP/2.
- **nginx:** `WholeFlow/deploy/server/nginx/wholeflow-site.conf`, kept in `/opt/wholeflow/nginx/` on the server and linked into `/etc/nginx/sites-enabled/`. It includes the certbot lines, security headers (HSTS and a strict content-security policy that allows only this site's own files), gzip, caching and the `/api/contact` proxy.
- **Files:** `/var/www/wholeflow-site`.

**Every change:** edit the files, bump `?v=` on `site.css` / `site.js` in the HTML if either changed (they are cached for 7 days), then run `website/deploy.sh`.

**Search engines (once):** in Google Search Console add a Domain property for `jitsuji.xyz`, verify it with the TXT record it gives you at GoDaddy, then submit `https://wholeflow.jitsuji.xyz/sitemap.xml`.

## Checked

- Lighthouse on the live site: home page 99 performance on mobile and desktop; privacy page 100. Accessibility, best practices and SEO are 100 everywhere.
- No sideways scrolling at 390 px.
- With "reduce motion" on, every animation stops and its final state is shown.
