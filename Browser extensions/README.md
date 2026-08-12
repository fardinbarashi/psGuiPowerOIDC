# PowerOIDC — Browser extensions

Browser ports of PowerOIDC. Each runs the same 12-step OIDC verification flow
(Section 0–11) as the PowerShell/WPF tool, but inside the browser — with both
**manual paste** and **automatic** redirect capture.

**Links to the web stores coming soon.**

Everything runs locally in the browser. No configuration or token data leaves the
machine except the calls to the OIDC provider you point it at.

## Folder layout

```
Browser extensions/
├── Chrome/     Loadable, unpacked extension (Chromium MV3)
├── Edge/       Loadable, unpacked extension (identical Chromium build)
└── Firefox/    Loadable, unpacked extension (Firefox MV3)
```

Each folder is a complete, editable extension with `manifest.json` at its root —
point "Load unpacked" (Chrome/Edge) or "Load Temporary Add-on" (Firefox) directly
at it. Chrome, Edge and Firefox share the same `oidc.js`, `app.js`, `background.js`,
`poweroidc.html`, `poweroidc.css` and `icons/`; only `manifest.json` differs between
the Chromium (Chrome/Edge) and Firefox builds.

## What it tests

Discovery metadata, JWKS, authorization URL, authorization code flow, token
exchange (`client_secret_basic`), ID token decoding + claim validation
(`iss`, `aud`, `nonce`, `exp`, `iat`, `alg`, `kid` vs JWKS), UserInfo, refresh
token flow, refreshed ID token / UserInfo, old refresh-token reuse check, and
JSON export.

## Quick-fill buttons

The Configuration tab has **Auth0** and **Google** buttons that load the
[openidconnect.net](https://openidconnect.net/) playground defaults with one click,
so you can run a test without typing the values by hand. The **Auth0** preset works
end to end in manual mode; the **Google** preset fills the same demo values shown on
openidconnect.net (a real Google login needs your own registered OAuth client).

## Install (developer / unpacked)

### Chrome
1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. **Load unpacked** → select the `Chrome` folder.

### Edge
1. Open `edge://extensions`.
2. Enable **Developer mode**.
3. **Load unpacked** → select the `Edge` folder.

### Firefox
1. Open `about:debugging#/runtime/this-firefox`.
2. **Load Temporary Add-on…** → select `Firefox/manifest.json`.
   (Temporary add-ons are removed on restart. For a permanent install, sign the
   package via addons.mozilla.org.)

Click the PowerOIDC toolbar icon to open the tool in its own tab.

## Redirect handling

- **Manual paste** (default) — the authorization URL opens in a new tab; after
  login you paste the full redirected URL back. Works with any redirect URI already
  registered at your IdP.
- **Automatic capture** — uses `identity.launchWebAuthFlow`. The redirect URI is
  forced to the extension's own URI; click **Use extension redirect URI** to fill
  it in, then register that URI at your IdP.

## Security note

Like the desktop tool, these extensions **display sensitive data** — client
secrets, authorization codes, access/ID/refresh tokens and user claims. Use only
in test/lab environments, and handle exported JSON carefully.

## Notes

- The ID token is decoded and **structurally** validated (alg, kid vs JWKS,
  standard claims) but the signature is not cryptographically verified — same as
  the original PowerOIDC.
- Token requests use `client_secret_basic`. Providers requiring PKCE-only or
  `client_secret_post` need small tweaks in `oidc.js`.
- `host_permissions` is `<all_urls>` so the tool page can reach any
  issuer/token/userinfo endpoint without CORS friction.
