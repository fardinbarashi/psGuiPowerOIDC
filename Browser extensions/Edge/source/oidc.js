/*
 * PowerOIDC — core OIDC logic.
 * Ported from the PowerShell/WPF PowerOIDC (Beta 3.0) Invoke-OidcTest flow.
 * Pure, framework-free functions. No secrets are stored; everything lives in memory.
 */

/* ----------------------------- base64url + JWT ----------------------------- */

// Decode a base64url string to a UTF-8 string.
export function base64UrlDecode(input) {
  let s = String(input).replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4;
  if (pad === 2) s += "==";
  else if (pad === 3) s += "=";
  else if (pad === 1) throw new Error("Invalid base64url string");
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder("utf-8").decode(bytes);
}

export function base64UrlToJson(input) {
  return JSON.parse(base64UrlDecode(input));
}

// Decode a JWT into { header, payload, signature }. Does NOT verify the signature.
export function decodeJwt(jwt) {
  if (!jwt || typeof jwt !== "string") throw new Error("JWT is empty");
  const parts = jwt.split(".");
  if (parts.length < 2) throw new Error("JWT does not have the expected header.payload.signature structure");
  return {
    header: base64UrlToJson(parts[0]),
    payload: base64UrlToJson(parts[1]),
    signature: parts[2] || null,
  };
}

/* ----------------------------- helpers ----------------------------- */

// Extract a query/fragment parameter from a full URL, a query string, or return
// the raw text if it already looks like the bare value. Mirrors Get-QueryParameterValue.
export function getQueryParameterValue(inputText, paramName) {
  if (!inputText) return null;
  const text = String(inputText).trim();

  // Try to parse as a URL (covers both ?query and #fragment).
  const tryParse = (u) => {
    try {
      const url = new URL(u);
      const fromSearch = url.searchParams.get(paramName);
      if (fromSearch != null) return fromSearch;
      if (url.hash && url.hash.length > 1) {
        const frag = new URLSearchParams(url.hash.replace(/^#/, ""));
        const v = frag.get(paramName);
        if (v != null) return v;
      }
      return null;
    } catch {
      return undefined; // not a URL
    }
  };

  let v = tryParse(text);
  if (v !== undefined && v !== null) return v;

  // Maybe it's a bare query string like "code=abc&state=xyz"
  if (text.includes("=")) {
    const qs = new URLSearchParams(text.replace(/^[?#]/, ""));
    const val = qs.get(paramName);
    if (val != null) return val;
  }
  return null;
}

// HTTP Basic auth header value for client_secret_basic. Mirrors Get-BasicAuthHeader.
export function getBasicAuthHeader(clientId, clientSecret) {
  const raw = `${clientId}:${clientSecret}`;
  // btoa needs Latin1; encode UTF-8 safely.
  const bytes = new TextEncoder().encode(raw);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return "Basic " + btoa(bin);
}

export function newGuid() {
  if (globalThis.crypto && crypto.randomUUID) return crypto.randomUUID();
  // Fallback
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, "0"));
  return `${h[0]}${h[1]}${h[2]}${h[3]}-${h[4]}${h[5]}-${h[6]}${h[7]}-${h[8]}${h[9]}-${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}`;
}

/* ----------------------------- network ----------------------------- */

async function fetchJson(url, options = {}) {
  const res = await fetch(url, options);
  const contentType = res.headers.get("content-type") || "";
  let body;
  const text = await res.text();
  if (contentType.includes("json") || (text && (text.trim().startsWith("{") || text.trim().startsWith("[")))) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  } else {
    body = text;
  }
  if (!res.ok) {
    let msg = `HTTP ${res.status} ${res.statusText}`;
    if (body && typeof body === "object") {
      const parts = [];
      if (body.error) parts.push(body.error);
      if (body.error_description) parts.push(body.error_description);
      if (parts.length) msg += ` — ${parts.join(": ")}`;
    } else if (typeof body === "string" && body.trim()) {
      msg += ` — ${body.slice(0, 300)}`;
    }
    const err = new Error(msg);
    err.status = res.status;
    err.body = body;
    throw err;
  }
  return body;
}

export function getDiscovery(issuer) {
  const base = String(issuer).replace(/\/+$/, "");
  const discoveryUrl = `${base}/.well-known/openid-configuration`;
  return fetchJson(discoveryUrl, { method: "GET" });
}

export function getJwks(jwksUri) {
  return fetchJson(jwksUri, { method: "GET" });
}

// Build the authorization URL. Mirrors Section 3.
export function buildAuthorizationUrl({ authorizationEndpoint, clientId, scope, redirectUri, state, nonce, extraParams }) {
  const p = new URLSearchParams();
  p.set("client_id", clientId);
  p.set("response_type", "code");
  p.set("scope", scope);
  p.set("redirect_uri", redirectUri);
  p.set("state", state);
  p.set("nonce", nonce);
  if (extraParams && typeof extraParams === "object") {
    for (const [k, v] of Object.entries(extraParams)) {
      if (v != null && v !== "") p.set(k, v);
    }
  }
  return `${authorizationEndpoint}?${p.toString()}`;
}

// Exchange authorization code for tokens (client_secret_basic). Mirrors Section 5.
export function exchangeCodeForTokens({ tokenEndpoint, clientId, clientSecret, code, redirectUri }) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
  });
  return fetchJson(tokenEndpoint, {
    method: "POST",
    headers: {
      Authorization: getBasicAuthHeader(clientId, clientSecret),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  });
}

// Refresh token grant. Mirrors Sections 8 / 11.
export function refreshTokens({ tokenEndpoint, clientId, clientSecret, refreshToken }) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });
  return fetchJson(tokenEndpoint, {
    method: "POST",
    headers: {
      Authorization: getBasicAuthHeader(clientId, clientSecret),
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  });
}

// UserInfo endpoint with a bearer access token. Mirrors Sections 7 / 10.
export function getUserInfo({ userInfoEndpoint, accessToken }) {
  return fetchJson(userInfoEndpoint, {
    method: "GET",
    headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" },
  });
}
