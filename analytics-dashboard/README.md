# Tokiri activity dashboard

This is a static Cloudflare Pages site for the owner. It reads aggregate analytics from the Worker API; it does not store event data itself.

## Deploy

1. Set a strong `ANALYTICS_DASHBOARD_SECRET` with `wrangler secret put` on the Worker. Use a randomly generated value with at least 32 characters; do not put it in this directory or commit it.
2. Create the Pages project and deploy this directory:

   ```sh
   npx wrangler pages project create tokiri-analytics --production-branch main
   npx wrangler pages deploy analytics-dashboard --project-name tokiri-analytics
   ```

3. Keep the production origin at `https://tokiri-analytics.pages.dev`, or update `ANALYTICS_DASHBOARD_ORIGIN` in `cloudflare-worker/wrangler.toml` to the chosen custom domain and redeploy the Worker.
4. Restrict the Pages hostname with a Cloudflare Access policy for the owner's identity.

The dashboard key remains in `sessionStorage` for the active tab and is sent only as a bearer header to the Worker. The Worker checks the key and the exact Pages origin. The dashboard receives daily aggregates for requests, Action errors, providers, tasks, fixed error reasons and processing stages, slow requests grouped by phase, model attempts, automatic Fix retries, and latency distributions. Error explanations distinguish model/provider failures, rejected output formats, and Worker failures by stage; raw exception text and request/response content are not retained. The app separately reports only duration plus fixed provider/task labels; it never sends text or an installation ID. For Fix and Actions, app duration minus Worker duration estimates both network directions and app overhead, not one-way latency. Peek is streamed, so its provider and Worker durations run through stream completion. App-side timings appear only after using a build containing the reporter. No per-request log or device-level drilldown is returned.

## Local preview

```sh
npx wrangler pages dev analytics-dashboard
```

For a local preview origin, temporarily set that exact origin in the local Worker configuration. Do not widen the production CORS allowlist to `*`.
