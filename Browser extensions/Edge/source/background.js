/*
 * PowerOIDC background.
 * Opens the full-page tool in a tab when the toolbar icon is clicked.
 * Works both as a Chromium MV3 service worker and a Firefox background script.
 */
const api = globalThis.browser ?? globalThis.chrome;

const PAGE = "poweroidc.html";

function openTool() {
  const url = api.runtime.getURL(PAGE);
  // Reuse an existing PowerOIDC tab if one is already open.
  api.tabs.query({}, (tabs) => {
    const existing = (tabs || []).find((t) => t.url && t.url.startsWith(url));
    if (existing) {
      api.tabs.update(existing.id, { active: true });
      if (existing.windowId != null && api.windows) api.windows.update(existing.windowId, { focused: true });
    } else {
      api.tabs.create({ url });
    }
  });
}

// MV3 action click (no default_popup set).
if (api.action && api.action.onClicked) {
  api.action.onClicked.addListener(openTool);
}

// Open the tool once on install so the user sees it immediately.
api.runtime.onInstalled.addListener((details) => {
  if (details.reason === "install") openTool();
});
