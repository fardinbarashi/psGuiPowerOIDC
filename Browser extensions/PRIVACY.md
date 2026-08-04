# PowerOIDC — Privacy Policy

_Last updated: 2026-08-04_

PowerOIDC is a browser extension for testing and verifying OpenID Connect (OIDC)
configurations locally. This policy explains how it handles data.

## Summary

PowerOIDC does **not** collect, transmit, sell, or share any personal data with
the developer or any third party. Everything the extension does happens locally
in your browser.

## What data the extension handles

- **OIDC configuration you enter** (client ID, client secret, issuer URL,
  redirect URI, scope) is stored **locally** in your browser using the
  extension's local storage (`chrome.storage.local` / `browser.storage.local`).
  It never leaves your device except as part of the OIDC requests you initiate.
- **OIDC responses** (discovery metadata, JWKS, tokens, ID token claims, UserInfo
  claims) are fetched from the OIDC provider **you specify** and are shown in the
  extension and kept in memory during the test run. They are not sent anywhere
  else and are not retained after you close the tool, unless you explicitly
  export them yourself as a JSON file.

## Network requests

The extension only communicates with the OIDC provider endpoints derived from the
configuration **you** enter (discovery, JWKS, authorization, token and UserInfo
endpoints). It does not contact the developer or any analytics, advertising, or
third-party service.

## Permissions

- `identity` — to run the OIDC authorization code flow (open the provider's login
  and capture the redirect).
- `storage` — to save your OIDC test configuration locally.
- `tabs` — to open the provider's authorization URL and reuse the tool's own tab.
- Host access — to send test requests to whichever OIDC provider you configure.

## Data sharing and sale

None. PowerOIDC does not sell or transfer user data to third parties, does not use
data for any purpose unrelated to its single purpose (OIDC testing), and does not
use data to determine creditworthiness or for lending.

## Contact

For questions about this policy, contact the publisher at the email address listed
on the extension's Chrome Web Store / Firefox Add-ons page.
