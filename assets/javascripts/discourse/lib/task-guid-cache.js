const STORAGE_KEY = "discourse-new-topic-field:pending-guid";

let pendingGuid = null;

function guidFromUrl(url) {
  try {
    return new URL(url, window.location.origin).searchParams.get("guid")?.trim();
  } catch {
    return null;
  }
}

function storeGuid(guid) {
  try {
    window.sessionStorage?.setItem(STORAGE_KEY, guid);
  } catch {
    // In restricted browser modes memory cache is enough for the current boot.
  }
}

function storedGuid() {
  try {
    return window.sessionStorage?.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}

function clearStoredGuid() {
  try {
    window.sessionStorage?.removeItem(STORAGE_KEY);
  } catch {
    // Ignore storage cleanup errors.
  }
}

export function captureTaskGuid(url = window.location.href) {
  const guid = guidFromUrl(url);
  if (!guid) {
    return null;
  }

  pendingGuid = guid;
  storeGuid(guid);
  return guid;
}

export function consumeTaskGuid() {
  const guid = pendingGuid || storedGuid();

  if (guid) {
    pendingGuid = null;
    clearStoredGuid();
  }

  return guid;
}
