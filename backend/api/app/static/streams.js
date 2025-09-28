(function () {
  const config = window.STREAM_CONFIG || { apiBase: "/v1" };

  const state = {
    detectors: [],
    streams: [],
    editing: null,
    loading: false,
  };

  const syncStatus = document.getElementById("sync-status");
  const tableBody = document.getElementById("streams-table-body");
  const refreshBtn = document.getElementById("refresh-streams");
  const rowTemplate = document.getElementById("stream-row-template");

  const form = document.getElementById("stream-form");
  const formTitle = document.getElementById("form-title");
  const formStatus = document.getElementById("form-status");
  const resetBtn = document.getElementById("reset-form");
  const deleteBtn = document.getElementById("delete-stream");

  const inputs = {
    name: document.getElementById("stream-name"),
    detector: document.getElementById("stream-detector"),
    url: document.getElementById("stream-url"),
    sampling: document.getElementById("sampling-interval"),
    reconnect: document.getElementById("reconnect-delay"),
    backend: document.getElementById("stream-backend"),
    encoding: document.getElementById("stream-encoding"),
    submission: document.getElementById("submission-method"),
    apiBase: document.getElementById("api-base-url"),
    apiTimeout: document.getElementById("api-timeout"),
    apiTokenEnv: document.getElementById("api-token-env"),
    credUsername: document.getElementById("cred-username"),
    credPassword: document.getElementById("cred-password"),
    credUsernameEnv: document.getElementById("cred-username-env"),
    credPasswordEnv: document.getElementById("cred-password-env"),
  };

  function setStatus(text, variant = "") {
    syncStatus.textContent = text;
    syncStatus.className = `status-chip ${variant}`.trim();
  }

  function setFormStatus(text, variant = "") {
    formStatus.textContent = text;
    formStatus.className = variant;
  }

  function formatUrl(url) {
    if (!url) return "–";
    try {
      const parsed = new URL(url);
      if (parsed.username || parsed.password) {
        parsed.username = "***";
        parsed.password = "***";
      }
      return parsed.toString();
    } catch (err) {
      return url;
    }
  }

  function fetchJSON(path, options = {}) {
    const url = path.startsWith("http") ? path : `${config.apiBase}${path}`;
    const opts = { ...options };
    const headers = { Accept: "application/json", ...(opts.headers || {}) };
    if (opts.body && !(opts.body instanceof FormData)) {
      headers["Content-Type"] = "application/json";
    }
    opts.headers = headers;
    return fetch(url, opts).then(async (response) => {
      if (!response.ok) {
        const detail = await response.text();
        const error = new Error(`Request failed with ${response.status}`);
        error.status = response.status;
        error.detail = detail;
        throw error;
      }
      return response.json();
    });
  }

  function populateDetectors(detectors) {
    inputs.detector.innerHTML = "";
    if (!detectors.length) {
      const opt = document.createElement("option");
      opt.value = "";
      opt.textContent = "No detectors configured";
      inputs.detector.appendChild(opt);
      inputs.detector.disabled = true;
      return;
    }
    inputs.detector.disabled = false;
    const placeholder = document.createElement("option");
    placeholder.value = "";
    placeholder.textContent = "Select detector";
    placeholder.disabled = true;
    placeholder.selected = true;
    inputs.detector.appendChild(placeholder);
    detectors.forEach((det) => {
      const opt = document.createElement("option");
      opt.value = det.detector_id || "";
      opt.textContent = det.detector_id || "(unnamed detector)";
      inputs.detector.appendChild(opt);
    });
  }

  function renderStreams() {
    tableBody.innerHTML = "";
    if (!state.streams.length) {
      const row = document.createElement("tr");
      const cell = document.createElement("td");
      cell.colSpan = 7;
      cell.className = "empty";
      cell.textContent = state.loading ? "Loading…" : "No streams configured.";
      row.appendChild(cell);
      tableBody.appendChild(row);
      return;
    }

    state.streams.forEach((stream) => {
      const fragment = document.importNode(rowTemplate.content, true);
      const row = fragment.querySelector("tr");
      row.dataset.name = stream.name;
      fragment.querySelector(".name").textContent = stream.name;
      fragment.querySelector(".detector").textContent = stream.detector_id || "–";
      fragment.querySelector(".url").textContent = formatUrl(stream.url);
      fragment.querySelector(".sampling").textContent = stream.sampling_interval_seconds;
      fragment.querySelector(".backend").textContent = stream.backend || "auto";
      fragment.querySelector(".submission").textContent = stream.submission_method || "edge";
      fragment.querySelector(".actions .edit").addEventListener("click", () => startEdit(stream.name));
      tableBody.appendChild(fragment);
    });
  }

  function clearForm() {
    form.reset();
    state.editing = null;
    formTitle.textContent = "Add Stream";
    deleteBtn.hidden = true;
    inputs.name.disabled = false;
    setFormStatus("", "");
    if (inputs.detector.options.length) {
      inputs.detector.selectedIndex = 0;
    }
  }

  function startEdit(name) {
    const stream = state.streams.find((item) => item.name === name);
    if (!stream) return;
    state.editing = name;
    formTitle.textContent = `Edit Stream: ${name}`;
    deleteBtn.hidden = false;

    inputs.name.value = stream.name;
    inputs.name.disabled = true;
    inputs.detector.value = stream.detector_id || "";
    inputs.url.value = stream.url || "";
    inputs.sampling.value = stream.sampling_interval_seconds;
    inputs.reconnect.value = stream.reconnect_delay_seconds;
    inputs.backend.value = stream.backend || "auto";
    inputs.encoding.value = stream.encoding || "jpeg";
    inputs.submission.value = stream.submission_method || "edge";
    inputs.apiBase.value = stream.api_base_url || "";
    inputs.apiTimeout.value = stream.api_timeout_seconds || 10;
    inputs.apiTokenEnv.value = stream.api_token_env || "";

    const creds = stream.credentials || {};
    inputs.credUsername.value = creds.username || "";
    inputs.credPassword.value = creds.password || "";
    inputs.credUsernameEnv.value = creds.username_env || "";
    inputs.credPasswordEnv.value = creds.password_env || "";

    setFormStatus("Editing existing stream.", "");
  }

  function buildPayload() {
    const sampling = parseFloat(inputs.sampling.value || "0");
    const reconnect = parseFloat(inputs.reconnect.value || "0");
    if (Number.isNaN(sampling) || sampling < 0.05) {
      setFormStatus("Sampling interval must be at least 0.05 seconds.", "error");
      return null;
    }
    if (Number.isNaN(reconnect) || reconnect < 0.5) {
      setFormStatus("Reconnect delay must be at least 0.5 seconds.", "error");
      return null;
    }

    const username = inputs.credUsername.value.trim();
    const password = inputs.credPassword.value.trim();
    const usernameEnv = inputs.credUsernameEnv.value.trim();
    const passwordEnv = inputs.credPasswordEnv.value.trim();

    if (username && usernameEnv) {
      setFormStatus("Provide either a username or username env var, not both.", "error");
      return null;
    }
    if (password && passwordEnv) {
      setFormStatus("Provide either a password or password env var, not both.", "error");
      return null;
    }

    const credentials = {};
    if (username) credentials.username = username;
    if (password) credentials.password = password;
    if (usernameEnv) credentials.username_env = usernameEnv;
    if (passwordEnv) credentials.password_env = passwordEnv;

    const payload = {
      name: inputs.name.value.trim(),
      detector_id: inputs.detector.value,
      url: inputs.url.value.trim(),
      sampling_interval_seconds: sampling,
      reconnect_delay_seconds: reconnect,
      backend: inputs.backend.value,
      encoding: inputs.encoding.value,
      submission_method: inputs.submission.value,
      api_base_url: inputs.apiBase.value.trim(),
      api_timeout_seconds: parseFloat(inputs.apiTimeout.value || "10"),
      api_token_env: inputs.apiTokenEnv.value.trim() || null,
    };

    if (!payload.name) {
      setFormStatus("Stream name is required.", "error");
      return null;
    }
    if (!payload.detector_id) {
      setFormStatus("Select a detector for this stream.", "error");
      return null;
    }
    if (!payload.url) {
      setFormStatus("Stream URL is required.", "error");
      return null;
    }

    if (!Number.isFinite(payload.api_timeout_seconds) || payload.api_timeout_seconds < 1) {
      setFormStatus("API timeout must be at least 1 second.", "error");
      return null;
    }

    if (Object.keys(credentials).length) {
      payload.credentials = credentials;
    }

    return payload;
  }

  function populateFormDefaults() {
    inputs.backend.value = "auto";
    inputs.encoding.value = "jpeg";
    inputs.submission.value = "edge";
    inputs.apiTimeout.value = "10";
  }

  async function loadDetectors() {
    try {
      const response = await fetchJSON("/config/detectors");
      state.detectors = response.items || [];
      populateDetectors(state.detectors);
    } catch (error) {
      console.error("Failed to load detectors", error);
      state.detectors = [];
      populateDetectors([]);
      setStatus("Unable to load detectors", "error");
    }
  }

  async function loadStreams() {
    state.loading = true;
    renderStreams();
    setStatus("Loading streams…");
    try {
      const response = await fetchJSON("/config/streams");
      state.streams = response.items || [];
      renderStreams();
      setStatus(`Loaded ${state.streams.length} stream${state.streams.length === 1 ? "" : "s"}.`, "success");
    } catch (error) {
      console.error("Failed to load streams", error);
      state.streams = [];
      renderStreams();
      setStatus("Failed to load streams", "error");
    } finally {
      state.loading = false;
    }
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const payload = buildPayload();
    if (!payload) {
      return;
    }

    setFormStatus("Saving stream…");
    try {
      if (state.editing) {
        await fetchJSON(`/config/streams/${encodeURIComponent(state.editing)}`, {
          method: "PUT",
          body: JSON.stringify(payload),
        });
      } else {
        await fetchJSON("/config/streams", {
          method: "POST",
          body: JSON.stringify(payload),
        });
      }
      setFormStatus("Stream saved successfully.", "success");
      inputs.name.disabled = false;
      await loadStreams();
      clearForm();
    } catch (error) {
      console.error("Failed to save stream", error);
      inputs.name.disabled = false;
      const detail = error.detail || error.message || "Unable to save stream.";
      setFormStatus(detail, "error");
    }
  }

  async function handleDelete() {
    if (!state.editing) return;
    if (!confirm(`Delete stream '${state.editing}'? This cannot be undone.`)) {
      return;
    }
    setFormStatus("Deleting stream…");
    try {
      await fetchJSON(`/config/streams/${encodeURIComponent(state.editing)}`, { method: "DELETE" });
      setFormStatus("Stream deleted.", "success");
      inputs.name.disabled = false;
      await loadStreams();
      clearForm();
    } catch (error) {
      console.error("Failed to delete stream", error);
      setFormStatus(error.detail || "Unable to delete stream.", "error");
    }
  }

  refreshBtn.addEventListener("click", () => {
    clearForm();
    inputs.name.disabled = false;
    loadStreams();
  });

  form.addEventListener("submit", handleSubmit);
  resetBtn.addEventListener("click", () => {
    inputs.name.disabled = false;
    clearForm();
    populateFormDefaults();
  });
  deleteBtn.addEventListener("click", handleDelete);

  populateFormDefaults();
  Promise.all([loadDetectors(), loadStreams()]);
})();
