# Plate-photo relay

A Cloudflare Worker between the app and the Claude API, so the Anthropic key
never ships inside the app. It accepts one photo (plus optional LiDAR size
hints), asks Claude for each food's grams and macros, validates the JSON, and
returns it. It stores and logs nothing.

- Endpoint: `POST /v1/plate` with header `X-App-Token`
- Model: `claude-opus-5-5`, structured JSON output, refusal fallback enabled
- Cost: roughly 1-2 US cents per photo (check anthropic.com/pricing)

## Deploying

Pushing to `relay/` on the `steady-strength` branch deploys automatically
(`.github/workflows/deploy-relay.yml`), using four GitHub secrets:
`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `ANTHROPIC_API_KEY`, `APP_TOKEN`.

## Manual setup (alternative, about 10 minutes)

1. Create a free Cloudflare account at dash.cloudflare.com.
2. On your Mac, in this folder:
   ```bash
   npm install
   npx wrangler login                          # opens the browser
   npx wrangler secret put ANTHROPIC_API_KEY   # paste your Anthropic key when asked
   npx wrangler secret put APP_TOKEN           # paste a long random token (see below)
   npx wrangler deploy                         # prints your relay URL
   ```
   Make a token with `openssl rand -hex 32`.
3. Put the relay URL and the same token in `Config/Local.xcconfig`:
   ```
   PLATE_RELAY_URL = https:/$()/steady-strength-relay.<you>.workers.dev
   PLATE_RELAY_TOKEN = <the token>
   ```

To renew the Anthropic key later: create the new key, run
`npx wrangler secret put ANTHROPIC_API_KEY`, then delete the old key in the Console.

## Tests

```bash
npm test          # mocked API, no cost
npm run typecheck
```
