const STORAGE_KEY = "discourse-new-topic-field:pending-guid";

let pendingTaskGuid = null;

function taskGuidFromUrl(url) {
  try {
    const params = new URL(url, window.location.origin).searchParams;
    const guid = params.get("guid")?.trim();

    if (!guid) {
      return null;
    }

    return {
      guid,
      expires: params.get("expires")?.trim() || null,
      nonce: params.get("nonce")?.trim() || null,
      sig: params.get("sig")?.trim() || null,
    };
  } catch {
    return null;
  }
}

function storeTaskGuid(taskGuid) {
  try {
    window.sessionStorage?.setItem(STORAGE_KEY, JSON.stringify(taskGuid));
  } catch {
    // In restricted browser modes memory cache is enough for the current boot.
  }
}

function storedTaskGuid() {
  try {
    const storedValue = window.sessionStorage?.getItem(STORAGE_KEY);
    return storedValue ? JSON.parse(storedValue) : null;
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
  const taskGuid = taskGuidFromUrl(url);
  if (!taskGuid) {
    return null;
  }

  pendingTaskGuid = taskGuid;
  storeTaskGuid(taskGuid);
  return taskGuid;
}

export function consumeTaskGuid() {
  const taskGuid = pendingTaskGuid || storedTaskGuid();

  if (taskGuid) {
    pendingTaskGuid = null;
    clearStoredGuid();
  }

  return taskGuid;
}
