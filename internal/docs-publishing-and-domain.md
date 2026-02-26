# Docs Publishing and Domain (Internal)

Goal: publish docs automatically from this repo and serve them at:

- `https://agent-bridge-for-photoshop.jaredverdi.com`

## Automation model

- Use Mintlify GitHub integration for deployment automation.
- One-time setup in Mintlify dashboard.
- Ongoing auto-publish on pushes to the connected branch (typically `main`).
- GitHub Actions CI (`docs-validate`) blocks bad docs/links before publish.

## One-time setup in Mintlify

1. Connect Mintlify to this repository (`jverdi/agent-bridge-for-photoshop`).
2. Set docs directory to `docs`.
3. Set production branch to `main`.
4. Add custom domain: `agent-bridge-for-photoshop.jaredverdi.com`.

References:

- https://www.mintlify.com/docs/custom-domain
- https://www.mintlify.com/docs/import-from-github

## DNS setup (Cloudflare)

Create a CNAME record:

- Name: `agent-bridge-for-photoshop`
- Target: `cname.mintlify-dns.com`
- Proxy: DNS-only (recommended while validating)

After DNS propagates, complete verification in Mintlify domain settings.

## Validation before publish

Run locally:

```bash
npm run docs:validate
```

CI runs:

- `mint validate`
- `mint broken-links`
