/*
 * PowerOIDC — UI wiring + full test engine.
 * Faithful port of the PowerShell Invoke-OidcTest 12-step flow (Section 0..11).
 */
import {
  getDiscovery, getJwks, buildAuthorizationUrl, exchangeCodeForTokens,
  refreshTokens, getUserInfo, decodeJwt, getQueryParameterValue, newGuid,
} from "./oidc.js";

// WebExtension API (Chrome/Edge expose `chrome`, Firefox exposes `browser`).
const api = globalThis.browser ?? globalThis.chrome;

const STORAGE_KEY = "poweroidc.config";
const DEFAULT_CONFIG = {
  clientId: "",
  clientSecret: "",
  issuer: "",
  redirectUri: "http://localhost:44300/signin-oidc",
  scope: "openid profile email",
  redirectMode: "manual", // "manual" | "auto"
};

const $ = (id) => document.getElementById(id);
const results = {}; // ordered-ish result object; insertion order preserved

/* ----------------------------- config storage ----------------------------- */

async function loadConfig() {
  try {
    const stored = await api.storage.local.get(STORAGE_KEY);
    return { ...DEFAULT_CONFIG, ...(stored?.[STORAGE_KEY] || {}) };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}
async function saveConfig(cfg) {
  await api.storage.local.set({ [STORAGE_KEY]: cfg });
}

function readForm() {
  return {
    clientId: $("clientId").value.trim(),
    clientSecret: $("clientSecret").value.trim(),
    issuer: $("issuer").value.trim().replace(/\/+$/, ""),
    redirectUri: $("redirectUri").value.trim(),
    scope: $("scope").value.trim(),
    redirectMode: document.querySelector('input[name="redirectMode"]:checked')?.value || "manual",
  };
}
function writeForm(cfg) {
  $("clientId").value = cfg.clientId || "";
  $("clientSecret").value = cfg.clientSecret || "";
  $("issuer").value = cfg.issuer || "";
  $("redirectUri").value = cfg.redirectUri || "";
  $("scope").value = cfg.scope || "";
  const radio = document.querySelector(`input[name="redirectMode"][value="${cfg.redirectMode || "manual"}"]`);
  if (radio) radio.checked = true;
  updateRedirectModeHint();
}

/* ----------------------------- tabs ----------------------------- */

function selectTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.tab === name));
  document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("active", p.dataset.panel === name));
}

/* ----------------------------- step rendering ----------------------------- */

const STATUS_LABEL = { Success: "OK", Error: "ERROR", Warning: "WARNING", Info: "INFO" };

function addStepResult({ title, message, status = "Info", json }) {
  const panel = $("stepResults");
  const row = document.createElement("div");
  row.className = `step step-${status.toLowerCase()}`;

  const head = document.createElement("div");
  head.className = "step-head";

  const badge = document.createElement("span");
  badge.className = "step-badge";
  badge.textContent = STATUS_LABEL[status] || status;

  const titleEl = document.createElement("span");
  titleEl.className = "step-title";
  titleEl.textContent = title;

  head.appendChild(badge);
  head.appendChild(titleEl);

  let jsonBadge = null;
  if (json !== undefined) {
    jsonBadge = document.createElement("span");
    jsonBadge.className = "json-badge";
    jsonBadge.textContent = "JSON";
    head.appendChild(jsonBadge);
  }

  const msg = document.createElement("div");
  msg.className = "step-msg";
  msg.textContent = message;

  row.appendChild(head);
  row.appendChild(msg);

  if (json !== undefined) {
    const pre = document.createElement("pre");
    pre.className = "step-json hidden";
    pre.textContent = JSON.stringify(json, null, 2);
    jsonBadge.addEventListener("click", () => pre.classList.toggle("hidden"));
    row.appendChild(pre);
  }

  panel.appendChild(row);
  panel.scrollTop = panel.scrollHeight;
}

function updateProgress(step, total, detail) {
  const pct = Math.round((step / total) * 100);
  $("progressBar").style.width = `${pct}%`;
  $("progressCount").textContent = `${step} / ${total} steps`;
  $("progressDetail").textContent = detail || "";
}

function setResult(key, value) {
  results[key] = value;
  $("resultsJson").value = JSON.stringify(results, null, 2);
}

function resetRun() {
  $("stepResults").replaceChildren();
  $("resultsJson").value = "";
  for (const k of Object.keys(results)) delete results[k];
  updateProgress(0, 12, "Ready to start test...");
}

/* ----------------------------- redirect capture ----------------------------- */

function getExtensionRedirectUri() {
  try {
    return api.identity.getRedirectURL();
  } catch {
    return null;
  }
}

function updateRedirectModeHint() {
  const mode = document.querySelector('input[name="redirectMode"]:checked')?.value || "manual";
  const hint = $("redirectHint");
  const btn = $("useExtRedirect");
  if (mode === "auto") {
    const uri = getExtensionRedirectUri();
    hint.replaceChildren();
    if (uri) {
      hint.append("Automatic mode uses the browser's login window. Register this redirect URI with your IdP:");
      hint.appendChild(document.createElement("br"));
      const code = document.createElement("code");
      code.textContent = uri;
      hint.appendChild(code);
    } else {
      hint.textContent = "Automatic mode requires the identity API (could not obtain a redirect URI).";
    }
    btn.classList.remove("hidden");
  } else {
    hint.textContent = "Manual mode: the authorization URL opens in a new tab. After login, paste the full redirected URL below.";
    btn.classList.add("hidden");
  }
}

// Auto capture via the browser's built-in web auth flow.
async function captureAuthAuto(authUrl) {
  const redirect = await api.identity.launchWebAuthFlow({ url: authUrl, interactive: true });
  return redirect; // full redirect URL containing code/state (or error)
}

// Manual capture: open the auth URL in a new tab and wait for the user to paste
// the redirected URL back into the inline box.
function captureAuthManual(authUrl) {
  return new Promise((resolve, reject) => {
    try { api.tabs.create({ url: authUrl }); } catch { /* fall back to window.open */ window.open(authUrl, "_blank"); }

    const box = $("manualBox");
    const input = $("manualInput");
    const cont = $("manualContinue");
    const cancel = $("manualCancel");
    input.value = "";
    box.classList.remove("hidden");
    input.focus();

    const cleanup = () => {
      box.classList.add("hidden");
      cont.removeEventListener("click", onContinue);
      cancel.removeEventListener("click", onCancel);
    };
    const onContinue = () => {
      const val = input.value.trim();
      if (!val) { input.focus(); return; }
      cleanup();
      resolve(val);
    };
    const onCancel = () => { cleanup(); reject(new Error("Manual input cancelled")); };
    cont.addEventListener("click", onContinue);
    cancel.addEventListener("click", onCancel);
  });
}

/* ----------------------------- the 12-step run ----------------------------- */

async function runFullTest() {
  const btn = $("startTest");
  btn.disabled = true;
  resetRun();
  selectTab("test");

  const cfg = readForm();
  const totalSteps = 12;
  let step = 0;

  // Section 0: config validation
  try {
    step++;
    updateProgress(step, totalSteps, "Section 0 : Validating configuration...");
    if (!cfg.clientId) throw new Error("clientId is empty");
    if (!cfg.clientSecret) throw new Error("clientSecret is empty");
    if (!cfg.issuer) throw new Error("issuer is empty");
    if (!cfg.redirectUri) throw new Error("redirectUri is empty");
    if (!cfg.scope) throw new Error("scope is empty");
    addStepResult({ title: "Section 0 : Config validation", message: "All required values are present", status: "Success" });
  } catch (e) {
    addStepResult({ title: "Section 0 : Config validation", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 1: discovery
  let discovery, authorizationEndpoint, tokenEndpoint, userInfoEndpoint, jwks;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 1 : Testing discovery endpoint...");
    discovery = await getDiscovery(cfg.issuer);
    if (discovery.issuer !== cfg.issuer) throw new Error(`issuer mismatch (expected '${cfg.issuer}', got '${discovery.issuer}')`);
    if (!discovery.authorization_endpoint) throw new Error("authorization_endpoint missing");
    if (!discovery.token_endpoint) throw new Error("token_endpoint missing");
    if (!discovery.jwks_uri) throw new Error("jwks_uri missing");
    if (!discovery.userinfo_endpoint) throw new Error("userinfo_endpoint missing");
    authorizationEndpoint = discovery.authorization_endpoint;
    tokenEndpoint = discovery.token_endpoint;
    userInfoEndpoint = discovery.userinfo_endpoint;
    setResult("discovery", discovery);
    addStepResult({ title: "Section 1 : Discovery endpoint", message: "Discovery endpoint works. All required endpoints are present.", status: "Success", json: discovery });
  } catch (e) {
    addStepResult({ title: "Section 1 : Discovery endpoint", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 2: JWKS
  try {
    step++;
    updateProgress(step, totalSteps, "Section 2 : Testing JWKS endpoint...");
    jwks = await getJwks(discovery.jwks_uri);
    if (!jwks.keys || jwks.keys.length < 1) throw new Error("JWKS contains no keys");
    setResult("jwks", jwks);
    addStepResult({ title: "Section 2 : JWKS endpoint", message: `JWKS contains ${jwks.keys.length} key(s)`, status: "Success", json: jwks });
  } catch (e) {
    addStepResult({ title: "Section 2 : JWKS endpoint", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 3: build auth URL
  const state = newGuid();
  const nonce = newGuid();
  let authUrl, effectiveRedirectUri = cfg.redirectUri;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 3 : Building authorization URL...");
    if (cfg.redirectMode === "auto") {
      const extUri = getExtensionRedirectUri();
      if (!extUri) throw new Error("Could not obtain extension redirect URI for automatic mode");
      effectiveRedirectUri = extUri;
    }
    authUrl = buildAuthorizationUrl({
      authorizationEndpoint, clientId: cfg.clientId, scope: cfg.scope,
      redirectUri: effectiveRedirectUri, state, nonce,
    });
    addStepResult({
      title: "Section 3 : Build authorization URL",
      message: `Authorization URL built successfully (redirect_uri=${effectiveRedirectUri})`,
      status: "Success", json: { authUrl, state, nonce, redirect_uri: effectiveRedirectUri },
    });
  } catch (e) {
    addStepResult({ title: "Section 3 : Build authorization URL", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 4: authorization code capture (auto or manual)
  let code = null, returnedState = null;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 4 : Browser login & code capture...");
    addStepResult({
      title: "Section 4 : Browser login",
      message: cfg.redirectMode === "auto"
        ? "A login window will open. Sign in; the redirect is captured automatically."
        : "Browser tab will open. After login, copy the redirected URL and paste it into the box.",
      status: "Warning",
    });

    const redirectResult = cfg.redirectMode === "auto"
      ? await captureAuthAuto(authUrl)
      : await captureAuthManual(authUrl);

    code = getQueryParameterValue(redirectResult, "code");
    returnedState = getQueryParameterValue(redirectResult, "state");
    const loginError = getQueryParameterValue(redirectResult, "error");
    const loginErrorDescription = getQueryParameterValue(redirectResult, "error_description");

    if (loginError) throw new Error(`Login failed. error=${loginError} error_description=${loginErrorDescription || ""}`);

    if (!code) {
      if (/response_type=code/.test(redirectResult) && !/[?&#]code=/.test(redirectResult)) {
        throw new Error("You pasted the Authorization URL. Complete the login first, then paste the final redirected URL that contains code=...");
      }
      throw new Error("Authorization code is empty. Paste the full redirected URL after login or paste only the code value.");
    }

    if (returnedState) {
      if (returnedState !== state) throw new Error(`State mismatch. Expected '${state}', got '${returnedState}'`);
    } else {
      addStepResult({ title: "Section 4 : State validation", message: "State was not provided (only the code was pasted). Continuing without state validation.", status: "Warning" });
    }
    addStepResult({ title: "Section 4 : Authorization code", message: "Authorization code received", status: "Success" });
  } catch (e) {
    addStepResult({ title: "Section 4 : Authorization code", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 5: token exchange
  let idToken, accessToken, refreshToken, tokenResponse;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 5 : Exchanging code for tokens...");
    tokenResponse = await exchangeCodeForTokens({
      tokenEndpoint, clientId: cfg.clientId, clientSecret: cfg.clientSecret,
      code, redirectUri: effectiveRedirectUri,
    });
    idToken = tokenResponse.id_token;
    accessToken = tokenResponse.access_token;
    refreshToken = tokenResponse.refresh_token;
    if (!idToken) throw new Error("id_token is empty");
    if (!accessToken) throw new Error("access_token is empty");
    if (tokenResponse.token_type && String(tokenResponse.token_type).toLowerCase() !== "bearer") throw new Error("token_type is not Bearer");
    setResult("tokenResponse", tokenResponse);
    addStepResult({ title: "Section 5 : Token exchange", message: `Tokens received. token_type=Bearer, expires_in=${tokenResponse.expires_in}`, status: "Success", json: tokenResponse });
  } catch (e) {
    addStepResult({ title: "Section 5 : Token exchange", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 6: id_token claims
  try {
    step++;
    updateProgress(step, totalSteps, "Section 6 : Decoding id_token...");
    const decoded = decodeJwt(idToken);
    setResult("idTokenHeader", decoded.header);
    setResult("idTokenClaims", decoded.payload);
    if (decoded.payload.iss !== cfg.issuer) throw new Error("id_token iss mismatch");
    const aud = decoded.payload.aud;
    if (Array.isArray(aud)) {
      if (!aud.includes(cfg.clientId)) throw new Error("id_token aud does not contain clientId");
    } else if (aud !== cfg.clientId) {
      throw new Error("id_token aud mismatch");
    }
    if (decoded.payload.nonce !== nonce) throw new Error("id_token nonce mismatch");
    const nowUnix = Math.floor(Date.now() / 1000);
    if (decoded.payload.exp <= nowUnix) throw new Error("id_token is expired");
    if (decoded.payload.iat > nowUnix + 60) throw new Error("id_token iat is in the future");
    if (!["RS256", "ES256"].includes(decoded.header.alg)) throw new Error(`Unexpected id_token alg: ${decoded.header.alg}`);
    let kidStatus = "id_token kid has no value";
    if (decoded.header.kid) {
      const match = jwks.keys.find((k) => k.kid === decoded.header.kid);
      if (!match) throw new Error(`id_token kid not found in JWKS: ${decoded.header.kid}`);
      kidStatus = "kid found in JWKS";
    }
    addStepResult({ title: "Section 6 : ID token claims", message: `id_token validated. alg=${decoded.header.alg}, ${kidStatus}`, status: "Success", json: { header: decoded.header, claims: decoded.payload } });
  } catch (e) {
    addStepResult({ title: "Section 6 : ID token claims", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 7: userinfo
  let userInfo;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 7 : Testing UserInfo endpoint...");
    userInfo = await getUserInfo({ userInfoEndpoint, accessToken });
    if (!userInfo.sub) throw new Error("userinfo sub is empty");
    setResult("userinfo", userInfo);
    addStepResult({ title: "Section 7 : UserInfo endpoint", message: `UserInfo received. sub=${userInfo.sub}`, status: "Success", json: userInfo });
  } catch (e) {
    addStepResult({ title: "Section 7 : UserInfo endpoint", message: `Error: ${e.message}`, status: "Error" });
    btn.disabled = false; return;
  }

  // Section 8: refresh token (non-fatal beyond here — matches PowerShell)
  let refreshResponse = null;
  try {
    step++;
    updateProgress(step, totalSteps, "Section 8 : Testing refresh token...");
    if (!refreshToken) {
      addStepResult({ title: "Section 8 : Refresh token", message: "No refresh_token returned by provider, skipping", status: "Warning" });
    } else {
      refreshResponse = await refreshTokens({ tokenEndpoint, clientId: cfg.clientId, clientSecret: cfg.clientSecret, refreshToken });
      if (!refreshResponse.id_token) throw new Error("new id_token is empty");
      if (!refreshResponse.access_token) throw new Error("new access_token is empty");
      if (refreshResponse.token_type && String(refreshResponse.token_type).toLowerCase() !== "bearer") throw new Error("refresh token_type is not Bearer");
      setResult("refreshResponse", refreshResponse);
      const rotationMsg = refreshResponse.refresh_token === refreshToken ? "WARN: refresh token was not rotated" : "Refresh token was rotated";
      addStepResult({ title: "Section 8 : Refresh token", message: `Refresh successful. ${rotationMsg}`, status: "Success", json: refreshResponse });
    }
  } catch (e) {
    addStepResult({ title: "Section 8 : Refresh token", message: `Error: ${e.message}`, status: "Error" });
  }

  // Section 9: refreshed id_token claims
  try {
    step++;
    updateProgress(step, totalSteps, "Section 9 : Decoding refreshed id_token...");
    if (refreshResponse && refreshResponse.id_token) {
      const decoded = decodeJwt(refreshResponse.id_token);
      setResult("refreshedIdTokenHeader", decoded.header);
      setResult("refreshedIdTokenClaims", decoded.payload);
      addStepResult({ title: "Section 9 : Refreshed ID token claims", message: "Refreshed id_token decoded successfully", status: "Success", json: { header: decoded.header, claims: decoded.payload } });
    } else {
      addStepResult({ title: "Section 9 : Refreshed ID token claims", message: "Skipped (no refreshed id_token)", status: "Warning" });
    }
  } catch (e) {
    addStepResult({ title: "Section 9 : Refreshed ID token claims", message: `Error: ${e.message}`, status: "Error" });
  }

  // Section 10: userinfo with refreshed access token
  try {
    step++;
    updateProgress(step, totalSteps, "Section 10 : UserInfo with refreshed access token...");
    if (refreshResponse && refreshResponse.access_token) {
      const refreshedUserInfo = await getUserInfo({ userInfoEndpoint, accessToken: refreshResponse.access_token });
      if (refreshedUserInfo.sub !== userInfo.sub) throw new Error("refreshed userinfo sub mismatch");
      setResult("refreshedUserinfo", refreshedUserInfo);
      addStepResult({ title: "Section 10 : UserInfo with refreshed access token", message: "UserInfo verified with refreshed access token", status: "Success", json: refreshedUserInfo });
    } else {
      addStepResult({ title: "Section 10 : UserInfo with refreshed access token", message: "Skipped (no refreshed access token)", status: "Warning" });
    }
  } catch (e) {
    addStepResult({ title: "Section 10 : UserInfo with refreshed access token", message: `Error: ${e.message}`, status: "Error" });
  }

  // Section 11: old refresh token reuse
  try {
    step++;
    updateProgress(step, totalSteps, "Section 11 : Testing old refresh token reuse...");
    if (refreshToken) {
      try {
        const reuse = await refreshTokens({ tokenEndpoint, clientId: cfg.clientId, clientSecret: cfg.clientSecret, refreshToken });
        setResult("oldRefreshTokenReuse", reuse);
        addStepResult({ title: "Section 11 : Old refresh token reuse", message: "WARN: Old refresh token was accepted again. Rotation may not be enforced.", status: "Warning", json: reuse });
      } catch {
        addStepResult({ title: "Section 11 : Old refresh token reuse", message: "Old refresh token reuse failed as expected (rotation enforced)", status: "Success" });
      }
    } else {
      addStepResult({ title: "Section 11 : Old refresh token reuse", message: "Skipped (no refresh token)", status: "Warning" });
    }
  } catch (e) {
    addStepResult({ title: "Section 11 : Old refresh token reuse", message: `Error: ${e.message}`, status: "Error" });
  }

  // Summary
  updateProgress(totalSteps, totalSteps, "OIDC test completed");
  addStepResult({ title: "Summary : OIDC test completed", message: "All sections executed. See Results tab for full JSON output.", status: "Success" });
  selectTab("results");
  btn.disabled = false;
}

/* ----------------------------- wiring ----------------------------- */

function validateConfig() {
  const cfg = readForm();
  const missing = Object.entries({ "Client ID": cfg.clientId, "Client Secret": cfg.clientSecret, Issuer: cfg.issuer, "Redirect URI": cfg.redirectUri, Scope: cfg.scope })
    .filter(([, v]) => !v).map(([k]) => k);
  const el = $("configStatus");
  if (missing.length) {
    el.textContent = `Missing: ${missing.join(", ")}`;
    el.className = "status status-error";
  } else {
    el.textContent = "The configuration looks complete.";
    el.className = "status status-ok";
  }
}

async function init() {
  const cfg = await loadConfig();
  writeForm(cfg);

  document.querySelectorAll(".tab").forEach((t) => t.addEventListener("click", () => selectTab(t.dataset.tab)));
  document.querySelectorAll('input[name="redirectMode"]').forEach((r) => r.addEventListener("change", updateRedirectModeHint));

  $("saveConfig").addEventListener("click", async () => {
    await saveConfig(readForm());
    const el = $("configStatus");
    el.textContent = "Configuration saved!";
    el.className = "status status-ok";
  });
  $("restoreConfig").addEventListener("click", () => { writeForm({ ...DEFAULT_CONFIG }); });
  $("validateConfig").addEventListener("click", validateConfig);
  $("useExtRedirect").addEventListener("click", () => {
    const uri = getExtensionRedirectUri();
    if (uri) $("redirectUri").value = uri;
  });

  $("startTest").addEventListener("click", () => { runFullTest().catch((e) => addStepResult({ title: "Fatal", message: String(e && e.message || e), status: "Error" })); });

  $("copyResults").addEventListener("click", async () => {
    try { await navigator.clipboard.writeText($("resultsJson").value); flash("copyResults", "Copied!"); } catch { $("resultsJson").select(); }
  });
  $("clearResults").addEventListener("click", resetRun);
  $("exportResults").addEventListener("click", () => {
    const blob = new Blob([$("resultsJson").value || "{}"], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = "poweroidc-result.json";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  });

  updateProgress(0, 12, "Ready to start test...");
  selectTab("config");
}

function flash(id, text) {
  const el = $(id);
  const old = el.textContent;
  el.textContent = text;
  setTimeout(() => { el.textContent = old; }, 1200);
}

document.addEventListener("DOMContentLoaded", init);
