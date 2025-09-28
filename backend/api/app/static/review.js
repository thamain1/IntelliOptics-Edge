(function () {
  const config = window.REVIEW_CONFIG || { apiBase: "/v1" };
  const state = {
    limit: 50,
    offset: 0,
    pendingOnly: true,
    detectorId: "",
    total: 0,
    items: [],
    currentId: null,
    loading: false,
  };

  const queueBody = document.getElementById("queue-body");
  const queueMeta = document.getElementById("queue-meta");
  const rowTemplate = document.getElementById("row-template");
  const prevBtn = document.getElementById("prev-page");
  const nextBtn = document.getElementById("next-page");
  const refreshBtn = document.getElementById("refresh-btn");
  const filtersForm = document.getElementById("filters-form");
  const detectorInput = document.getElementById("detector-filter");
  const pendingInput = document.getElementById("pending-filter");
  const limitSelect = document.getElementById("limit-select");

  const detailPanel = document.getElementById("detail-panel");
  const detailEmpty = document.getElementById("detail-empty");
  const detailContent = document.getElementById("detail-content");
  const detailImage = document.getElementById("detail-image");
  const detailFields = {
    id: document.getElementById("detail-id"),
    detector: document.getElementById("detail-detector"),
    modelLabel: document.getElementById("detail-model-label"),
    modelConfidence: document.getElementById("detail-model-confidence"),
    resultType: document.getElementById("detail-result-type"),
    status: document.getElementById("detail-status"),
    count: document.getElementById("detail-count"),
    received: document.getElementById("detail-received"),
    updated: document.getElementById("detail-updated"),
    humanLabel: document.getElementById("detail-human-label"),
    humanConfidence: document.getElementById("detail-human-confidence"),
    humanUser: document.getElementById("detail-human-user"),
    humanNotes: document.getElementById("detail-human-notes"),
    humanTs: document.getElementById("detail-human-ts"),
  };

  const labelForm = document.getElementById("label-form");
  const labelButtons = Array.from(document.querySelectorAll(".label-btn"));
  const labelChoice = document.getElementById("label-choice");
  const labelStatus = document.getElementById("label-status");
  const clearFormBtn = document.getElementById("clear-form");
  const labelUser = document.getElementById("label-user");
  const labelConfidenceInput = document.getElementById("label-confidence");
  const labelNotes = document.getElementById("label-notes");
  const labelCount = document.getElementById("label-count");

  function setQueueMeta(text, className = "") {
    queueMeta.textContent = text;
    queueMeta.className = `status-chip ${className}`.trim();
  }

  function formatConfidence(value) {
    if (value === null || value === undefined) return "–";
    return `${(value * 100).toFixed(1)}%`;
  }

  function formatTimestamp(value) {
    if (!value) return "–";
    try {
      const date = new Date(value);
      return `${date.toLocaleString()}`;
    } catch (err) {
      console.warn("Unable to parse timestamp", value, err);
      return value;
    }
  }

  function renderQueue() {
    queueBody.innerHTML = "";
    if (!state.items.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 6;
      cell.className = "empty";
      cell.textContent = state.loading ? "Loading…" : "No items found.";
      row.appendChild(cell);
      queueBody.appendChild(row);
      return;
    }

    state.items.forEach((item) => {
      const clone = document.importNode(rowTemplate.content, true);
      const row = clone.querySelector("tr");
      row.dataset.id = item.id;
      if (state.currentId === item.id) {
        row.classList.add("active");
      }
      clone.querySelector(".id").textContent = item.id;
      clone.querySelector(".detector").textContent = item.detector_id || "–";
      clone.querySelector(".model-label").textContent = item.model_label || "–";
      clone
        .querySelector(".model-confidence")
        .textContent = formatConfidence(item.model_confidence);
      clone.querySelector(".received").textContent = formatTimestamp(item.received_ts);
      const statusCell = clone.querySelector(".status");
      statusCell.textContent = item.human_label ? `Labeled (${item.human_label})` : "Pending";
      statusCell.className = `status ${item.human_label ? "status-labeled" : "status-pending"}`;

      row.addEventListener("click", () => {
        selectItem(item.id);
      });

      queueBody.appendChild(clone);
    });
  }

  async function fetchJSON(url, options = {}) {
    const fetchOptions = { ...options };
    const headers = { Accept: "application/json", ...(fetchOptions.headers || {}) };
    if (fetchOptions.body && !headers["content-type"]) {
      headers["content-type"] = "application/json";
    }
    fetchOptions.headers = headers;

    const response = await fetch(url, fetchOptions);
    if (!response.ok) {
      const errorText = await response.text();
      const error = new Error(`Request failed: ${response.status}`);
      error.detail = errorText;
      throw error;
    }
    return response.json();
  }

  async function loadQueue() {
    state.loading = true;
    renderQueue();
    setQueueMeta("Loading queue…");
    const params = new URLSearchParams();
    params.set("limit", String(state.limit));
    params.set("offset", String(state.offset));
    if (state.pendingOnly) {
      params.set("pending_only", "true");
    }
    if (state.detectorId) {
      params.set("detector_id", state.detectorId);
    }

    try {
      const data = await fetchJSON(`${config.apiBase}/review/image-queries?${params.toString()}`);
      state.items = data.items;
      state.total = data.total;
      if (state.offset >= state.total && state.offset > 0 && data.items.length === 0) {
        state.offset = Math.max(0, state.total - state.limit);
        return loadQueue();
      }
      setQueueMeta(`Showing ${data.items.length} of ${data.total} items`, "success");
      renderQueue();
      updatePagination();
      if (state.currentId) {
        const stillExists = state.items.some((item) => item.id === state.currentId);
        if (!stillExists) {
          state.currentId = null;
          showEmptyDetail();
        }
      }
    } catch (error) {
      console.error("Failed to load queue", error);
      setQueueMeta("Failed to load queue", "error");
      queueBody.innerHTML = "";
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 6;
      cell.className = "empty";
      cell.textContent = "Unable to load queue.";
      row.appendChild(cell);
      queueBody.appendChild(row);
    } finally {
      state.loading = false;
    }
  }

  function updatePagination() {
    prevBtn.disabled = state.offset === 0;
    nextBtn.disabled = state.offset + state.limit >= state.total;
  }

  async function selectItem(id) {
    try {
      const item = await fetchJSON(`${config.apiBase}/review/image-queries/${id}`);
      state.currentId = id;
      renderQueue();
      populateDetail(item);
    } catch (error) {
      console.error("Failed to load item", error);
      labelStatus.textContent = "Unable to load selected item.";
      labelStatus.className = "error";
    }
  }

  function showEmptyDetail() {
    detailContent.classList.add("hidden");
    detailEmpty.classList.remove("hidden");
  }

  function populateDetail(item) {
    detailEmpty.classList.add("hidden");
    detailContent.classList.remove("hidden");
    labelChoice.value = "";
    labelButtons.forEach((btn) => btn.classList.remove("active-choice"));
    detailImage.src = item.image_uri || "";
    detailImage.alt = item.model_label || "Review item";
    detailFields.id.textContent = item.id;
    detailFields.detector.textContent = item.detector_id || "–";
    detailFields.modelLabel.textContent = item.model_label || "–";
    detailFields.modelConfidence.textContent = formatConfidence(item.model_confidence);
    detailFields.resultType.textContent = item.result_type || "–";
    detailFields.status.textContent = item.status || "–";
    detailFields.count.textContent = item.count != null ? String(item.count) : "–";
    detailFields.received.textContent = formatTimestamp(item.received_ts);
    detailFields.updated.textContent = formatTimestamp(item.updated_ts);
    detailFields.humanLabel.textContent = item.human_label || "–";
    detailFields.humanConfidence.textContent =
      item.human_confidence != null ? formatConfidence(item.human_confidence) : "–";
    detailFields.humanUser.textContent = item.human_user || "–";
    detailFields.humanNotes.textContent = item.human_notes || "–";
    detailFields.humanTs.textContent = formatTimestamp(item.human_labeled_at);

    if (item.human_label) {
      labelStatus.textContent = `Last decision: ${item.human_label}`;
      labelStatus.className = "success";
    } else {
      labelStatus.textContent = "";
      labelStatus.className = "";
    }

    if (item.human_user) {
      labelUser.value = item.human_user;
    }
    if (item.human_confidence != null) {
      labelConfidenceInput.value = item.human_confidence;
    } else {
      labelConfidenceInput.value = "";
    }
    if (item.human_notes) {
      labelNotes.value = item.human_notes;
    } else {
      labelNotes.value = "";
    }
    if (item.count != null) {
      labelCount.value = item.count;
    } else {
      labelCount.value = "";
    }
  }

  function clearLabelForm() {
    labelChoice.value = "";
    labelConfidenceInput.value = "";
    labelNotes.value = "";
    labelCount.value = "";
    labelStatus.textContent = "";
    labelStatus.className = "";
    labelButtons.forEach((btn) => btn.classList.remove("active-choice"));
  }

  labelButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const value = btn.dataset.label;
      labelChoice.value = value;
      labelButtons.forEach((other) => other.classList.remove("active-choice"));
      btn.classList.add("active-choice");
      labelStatus.textContent = `Selected label: ${value}`;
      labelStatus.className = "";
    });
  });

  clearFormBtn.addEventListener("click", () => {
    clearLabelForm();
  });

  labelForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!state.currentId) {
      labelStatus.textContent = "Select an item before submitting.";
      labelStatus.className = "error";
      return;
    }
    if (!labelChoice.value) {
      labelStatus.textContent = "Choose a label to submit.";
      labelStatus.className = "error";
      return;
    }
    labelStatus.textContent = "Submitting…";
    labelStatus.className = "";

    const payload = {
      label: labelChoice.value,
    };
    const confidenceRaw = labelConfidenceInput.value;
    const notes = labelNotes.value.trim();
    const user = labelUser.value.trim();
    const countRaw = labelCount.value;

    if (confidenceRaw) {
      payload.confidence = Number(confidenceRaw);
    }
    if (notes) {
      payload.notes = notes;
    }
    if (user) {
      payload.user = user;
    }
    if (countRaw) {
      payload.count = Number(countRaw);
    }

    try {
      const result = await fetchJSON(
        `${config.apiBase}/review/image-queries/${state.currentId}/label`,
        {
          method: "POST",
          body: JSON.stringify(payload),
        },
      );
      labelStatus.textContent = `Saved label ${result.human_label || labelChoice.value}`;
      labelStatus.className = "success";
      await loadQueue();
      populateDetail(result);
    } catch (error) {
      console.error("Failed to submit label", error);
      labelStatus.textContent = "Failed to save label.";
      labelStatus.className = "error";
    }
  });

  prevBtn.addEventListener("click", () => {
    state.offset = Math.max(0, state.offset - state.limit);
    loadQueue();
  });

  nextBtn.addEventListener("click", () => {
    state.offset = state.offset + state.limit;
    loadQueue();
  });

  refreshBtn.addEventListener("click", () => {
    loadQueue();
  });

  filtersForm.addEventListener("submit", (event) => {
    event.preventDefault();
    state.detectorId = detectorInput.value.trim();
    state.pendingOnly = pendingInput.checked;
    state.limit = Number(limitSelect.value);
    state.offset = 0;
    loadQueue();
  });

  detectorInput.addEventListener("change", () => {
    state.detectorId = detectorInput.value.trim();
  });

  pendingInput.addEventListener("change", () => {
    state.pendingOnly = pendingInput.checked;
  });

  limitSelect.addEventListener("change", () => {
    state.limit = Number(limitSelect.value);
  });

  // Initial bootstrap
  loadQueue();
})();
