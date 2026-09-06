# Website analytics

GA4 measures the public website at https://zephra.urandom.io only.
The desktop app and ChatGPT Sites previews do not load Google Analytics.

- Account: JamesBrink (`62780996`)
- Property: Zephra (`552967700`), Phoenix reporting time, USD
- Web stream: Zephra production website (`15729795554`)
- Measurement ID: `G-XMF63TG8ZY` (public configuration)
- Reports: https://analytics.google.com/analytics/web/#/a62780996p552967700/reports/intelligenthome

`product-mockups/public/analytics.js` loads through the shared layout. It allows
only the canonical HTTPS origin and `/`. One explicit page view runs per document;
anchor navigation, theme changes and the privacy disclosure are not page changes.
The stream's enhanced measurement enables page views and scrolls only, with browser
history page views disabled. Keep automatic file downloads, outbound clicks,
search, forms and video measurement disabled to avoid duplicate or excess data.

Release-link clicks emit `file_download` with an allowlisted, sanitized destination.
These measure clicks, not completed downloads or installations. All page query
parameters and fragments are discarded; referrers retain only their origin.
Analytics starts automatically without a popup. Advertising consent is denied,
Google signals and ad personalization are disabled, and cookies use the Zephra
host and a distinct prefix. The footer explains the website collection separately
from the app's lack of telemetry.

Run `node --test product-mockups/tests/analytics.test.mjs` before publication.
Deploy iterations to ChatGPT Sites first, then `make deploy-production` for AWS.
Check the production tag and real visits in this property's Realtime report;
a queued data-layer command alone does not prove collection.
