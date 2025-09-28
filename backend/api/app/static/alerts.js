const config = window.__ALERTS_CONFIG__ || { apiBase: "/v1" };
const apiBase = config.apiBase.replace(/\/$/, "");

const state = {
  detectors: [],
  rules: [],
  filteredRules: [],
  selectedId: null,
  search: "",
};

const dom = {
  list: document.getElementById("alert-list"),
  search: document.getElementById("alert-search"),
  emptyCopy: document.getElementById("empty-copy"),
  createBtn: document.getElementById("create-alert"),
  form: document.getElementById("alert-form"),
  backBtn: document.getElementById("back-to-list"),
  deleteBtn: document.getElementById("delete-alert"),
  status: document.getElementById("form-status"),
  detectorSelect: document.getElementById("detector-select"),
  customDetector: document.getElementById("custom-detector"),
  conditionAnswer: document.getElementById("condition-answer"),
  conditionComparator: document.getElementById("condition-comparator"),
  conditionConsecutive: document.getElementById("condition-consecutive"),
  confirmWithCloud: document.getElementById("confirm-with-cloud"),
  includeImage: document.getElementById("include-image"),
  headersJson: document.getElementById("headers-json"),
  recipientList: document.getElementById("recipient-list"),
  addRecipient: document.getElementById("add-recipient"),
  messageTemplate: document.getElementById("message-template"),
  templateFormat: document.getElementById("template-format"),
  primaryChannel: document.getElementById("primary-channel"),
  primaryTarget: document.getElementById("primary-target"),
  notificationUrl: document.getElementById("notification-url"),
  snoozeEnabled: document.getElementById("snooze-enabled"),
  snoozeMinutes: document.getElementById("snooze-minutes"),
};

function getField(id) {
  return document.getElementById(id);
}

function resetStatus(msg = "") {
  dom.status.textContent = msg;
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!response.ok) {
    let detail = response.statusText;
    try {
      const data = await response.json();
      detail = data.detail || JSON.stringify(data);
    } catch (err) {
      // ignore JSON parse errors
    }
    throw new Error(detail || `Request failed with ${response.status}`);
  }
  if (response.status === 204) {
    return null;
  }
  return response.json();
}

function ensureDetectorOption(value, label) {
  if (!value) return;
  const exists = Array.from(dom.detectorSelect.options).some(
    (opt) => opt.value === value,
  );
  if (!exists) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label || value;
    dom.detectorSelect.appendChild(option);
  }
}

function populateDetectorOptions(selectedId = "") {
  dom.detectorSelect.innerHTML = "";
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "Choose detector";
  placeholder.disabled = true;
  placeholder.hidden = true;
  if (!selectedId) {
    placeholder.selected = true;
  }
  dom.detectorSelect.appendChild(placeholder);
  state.detectors.forEach((det) => {
    const option = document.createElement("option");
    option.value = det.id;
    option.textContent = det.label || det.id;
    if (det.id === selectedId) {
      option.selected = true;
    }
    dom.detectorSelect.appendChild(option);
  });
  if (selectedId && !state.detectors.some((det) => det.id === selectedId)) {
    ensureDetectorOption(selectedId, selectedId);
    dom.detectorSelect.value = selectedId;
  }
  toggleCustomDetector();
}

function toggleCustomDetector() {
  if (dom.detectorSelect.value === "__manual__") {
    dom.customDetector.classList.remove("hidden");
    dom.customDetector.focus();
  } else {
    dom.customDetector.classList.add("hidden");
  }
}

function renderRecipientRow(data = {}) {
  const template = document.getElementById("recipient-row-template");
  const node = template.content.firstElementChild.cloneNode(true);
  const channel = node.querySelector(".recipient-channel");
  const address = node.querySelector(".recipient-address");
  const country = node.querySelector(".recipient-country");
  channel.value = data.channel || "sms";
  address.value = data.address || "";
  country.value = data.country_code || "";
  node
    .querySelector(".remove-recipient")
    .addEventListener("click", () => node.remove());
  dom.recipientList.appendChild(node);
}

function clearRecipients() {
  dom.recipientList.innerHTML = "";
}

function renderList() {
  const term = state.search.trim().toLowerCase();
  const filtered = state.rules.filter((rule) => {
    if (!term) return true;
    return (
      rule.name.toLowerCase().includes(term) ||
      (rule.detector_id || "").toLowerCase().includes(term)
    );
  });
  state.filteredRules = filtered;
  dom.list.innerHTML = "";
  filtered.forEach((rule) => {
    const item = document.createElement("li");
    item.dataset.id = rule.id;
    if (rule.id === state.selectedId) {
      item.classList.add("active");
    }
    const title = document.createElement("h3");
    title.textContent = rule.name;
    const meta = document.createElement("span");
    const condition = `${rule.condition.answer} x${rule.condition.consecutive}`;
    meta.textContent = `${rule.detector_id} • ${condition} • ${rule.enabled ? "Enabled" : "Disabled"}`;
    item.appendChild(title);
    item.appendChild(meta);
    dom.list.appendChild(item);
  });
  dom.emptyCopy.style.display = filtered.length ? "none" : "block";
}

function buildPayloadFromForm() {
  const form = dom.form;
  if (!form.reportValidity()) {
    throw new Error("Please complete required fields.");
  }

  const name = getField("alert-name").value.trim();
  const enabled = getField("alert-enabled").checked;
  let detectorId = dom.detectorSelect.value;
  if (detectorId === "__manual__") {
    detectorId = dom.customDetector.value.trim();
    if (!detectorId) {
      dom.customDetector.focus();
      throw new Error("Provide a detector identifier.");
    }
  }
  if (!detectorId) {
    throw new Error("Select a detector to continue.");
  }

  const headersRaw = dom.headersJson.value.trim();
  let headers = {};
  if (headersRaw) {
    try {
      const parsed = JSON.parse(headersRaw);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        headers = parsed;
      } else {
        throw new Error("Headers must be a JSON object.");
      }
    } catch (err) {
      throw new Error("Headers must be valid JSON.");
    }
  }

  const recipients = Array.from(
    dom.recipientList.querySelectorAll(".recipient-row"),
  )
    .map((row) => ({
      channel: row.querySelector(".recipient-channel").value,
      address: row.querySelector(".recipient-address").value.trim(),
      country_code: row.querySelector(".recipient-country").value.trim() || undefined,
    }))
    .filter((recipient) => recipient.address);

  const primaryTarget = dom.primaryTarget.value.trim();
  if (!primaryTarget) {
    dom.primaryTarget.focus();
    throw new Error("Provide a destination for the primary notification.");
  }

  const snoozeEnabled = dom.snoozeEnabled.checked;
  const snoozeMinutesRaw = dom.snoozeMinutes.value;
  const snoozeMinutes = snoozeMinutesRaw ? Number.parseInt(snoozeMinutesRaw, 10) : null;
  if (snoozeEnabled && (!snoozeMinutes || Number.isNaN(snoozeMinutes))) {
    throw new Error("Provide snooze minutes when snooze is enabled.");
  }

  const selected = state.detectors.find((det) => det.id === detectorId);

  return {
    name,
    enabled,
    detector_id: detectorId,
    detector_name: selected ? selected.label : detectorId,
    condition: {
      comparator: dom.conditionComparator.value,
      answer: dom.conditionAnswer.value,
      consecutive: (() => {
        const value = Number.parseInt(dom.conditionConsecutive.value || "1", 10);
        if (!Number.isFinite(value) || value < 1) {
          throw new Error("Consecutive answers must be 1 or greater.");
        }
        return value;
      })(),
    },
    confirm_with_cloud: dom.confirmWithCloud.checked,
    notification: {
      primary_channel: dom.primaryChannel.value,
      primary_target: primaryTarget,
      include_image: dom.includeImage.checked,
      message_template: dom.messageTemplate.value,
      template_format: dom.templateFormat.value,
      url: dom.notificationUrl.value.trim() || null,
      headers,
      recipients,
      snooze: {
        enabled: snoozeEnabled,
        minutes: snoozeEnabled ? snoozeMinutes : null,
      },
    },
  };
}

function fillForm(rule) {
  dom.form.reset();
  populateDetectorOptions(rule?.detector_id || "");
  if (rule) {
    getField("alert-name").value = rule.name;
    getField("alert-enabled").checked = Boolean(rule.enabled);
    if (!state.detectors.some((det) => det.id === rule.detector_id)) {
      ensureDetectorOption(rule.detector_id, rule.detector_name || rule.detector_id);
      dom.detectorSelect.value = rule.detector_id;
    }
    dom.conditionAnswer.value = rule.condition.answer;
    dom.conditionComparator.value = rule.condition.comparator;
    dom.conditionConsecutive.value = rule.condition.consecutive;
    dom.confirmWithCloud.checked = Boolean(rule.confirm_with_cloud);
    dom.primaryChannel.value = rule.notification.primary_channel;
    dom.primaryTarget.value = rule.notification.primary_target;
    dom.notificationUrl.value = rule.notification.url || "";
    dom.includeImage.checked = Boolean(rule.notification.include_image);
    dom.messageTemplate.value = rule.notification.message_template || "";
    dom.templateFormat.value = rule.notification.template_format || "plain";
    dom.headersJson.value = rule.notification.headers
      ? JSON.stringify(rule.notification.headers, null, 2)
      : "";
    dom.snoozeEnabled.checked = Boolean(rule.notification.snooze?.enabled);
    dom.snoozeMinutes.value = rule.notification.snooze?.minutes || "";
    clearRecipients();
    (rule.notification.recipients || []).forEach((recipient) =>
      renderRecipientRow(recipient),
    );
  } else {
    dom.detectorSelect.value = "";
    dom.conditionAnswer.value = "YES";
    dom.conditionComparator.value = "equals";
    dom.conditionConsecutive.value = 1;
    dom.confirmWithCloud.checked = false;
    dom.primaryChannel.value = "sms";
    dom.primaryTarget.value = "";
    dom.notificationUrl.value = "";
    dom.includeImage.checked = false;
    dom.messageTemplate.value = "";
    dom.templateFormat.value = "plain";
    dom.headersJson.value = "";
    dom.snoozeEnabled.checked = false;
    dom.snoozeMinutes.value = "15";
    clearRecipients();
  }
  toggleCustomDetector();
  resetStatus();
}

function setSelectedRule(rule) {
  if (rule) {
    state.selectedId = rule.id;
    dom.form.dataset.ruleId = rule.id;
    dom.deleteBtn.disabled = false;
  } else {
    state.selectedId = null;
    delete dom.form.dataset.ruleId;
    dom.deleteBtn.disabled = true;
  }
  fillForm(rule || null);
  renderList();
}

async function loadDetectors() {
  try {
    const detectors = await fetchJson(`${apiBase}/alert-rules/detectors`);
    state.detectors = Array.isArray(detectors) ? detectors : [];
  } catch (err) {
    console.warn("Failed to load detectors", err);
    state.detectors = [];
  }
  let selectedDetector = "";
  if (state.selectedId) {
    const match = state.rules.find((r) => r.id === state.selectedId);
    selectedDetector = match?.detector_id || "";
  }
  populateDetectorOptions(selectedDetector);
}

async function loadRules() {
  const rules = await fetchJson(`${apiBase}/alert-rules`);
  state.rules = Array.isArray(rules) ? rules : [];
  renderList();
  if (state.rules.length === 0) {
    setSelectedRule(null);
  } else if (state.selectedId) {
    const match = state.rules.find((rule) => rule.id === state.selectedId);
    if (match) {
      setSelectedRule(match);
    }
  }
}

async function handleSave(event) {
  event.preventDefault();
  try {
    resetStatus("Saving…");
    const payload = buildPayloadFromForm();
    const ruleId = dom.form.dataset.ruleId;
    const method = ruleId ? "PUT" : "POST";
    const url = ruleId
      ? `${apiBase}/alert-rules/${encodeURIComponent(ruleId)}`
      : `${apiBase}/alert-rules`;
    const saved = await fetchJson(url, {
      method,
      body: JSON.stringify(payload),
    });
    const existingIndex = state.rules.findIndex((rule) => rule.id === saved.id);
    if (existingIndex >= 0) {
      state.rules.splice(existingIndex, 1, saved);
    } else {
      state.rules.unshift(saved);
    }
    setSelectedRule(saved);
    resetStatus("Alert saved");
  } catch (err) {
    resetStatus(err.message || "Failed to save alert");
  }
}

async function handleDelete() {
  const ruleId = dom.form.dataset.ruleId;
  if (!ruleId) return;
  if (!window.confirm("Delete this alert?")) {
    return;
  }
  try {
    resetStatus("Deleting…");
    await fetchJson(`${apiBase}/alert-rules/${encodeURIComponent(ruleId)}`, {
      method: "DELETE",
    });
    state.rules = state.rules.filter((rule) => rule.id !== ruleId);
    setSelectedRule(state.rules[0] || null);
    renderList();
    resetStatus("Alert deleted");
  } catch (err) {
    resetStatus(err.message || "Failed to delete alert");
  }
}

function handleListClick(event) {
  const item = event.target.closest("li[data-id]");
  if (!item) return;
  const rule = state.rules.find((r) => r.id === item.dataset.id);
  if (rule) {
    setSelectedRule(rule);
  }
}

function handleSearch() {
  state.search = dom.search.value;
  renderList();
}

function handleCreateNew() {
  setSelectedRule(null);
  dom.form.reset();
  fillForm(null);
  getField("alert-name").focus();
}

dom.list.addEventListener("click", handleListClick);
dom.search.addEventListener("input", handleSearch);
dom.createBtn.addEventListener("click", handleCreateNew);
dom.form.addEventListener("submit", handleSave);
dom.deleteBtn.addEventListener("click", handleDelete);
dom.addRecipient.addEventListener("click", () => renderRecipientRow());
dom.detectorSelect.addEventListener("change", toggleCustomDetector);
dom.backBtn.addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));

(async function init() {
  await loadDetectors();
  await loadRules();
  if (state.rules.length) {
    setSelectedRule(state.rules[0]);
  } else {
    setSelectedRule(null);
  }
})();
