(function () {
  const { invoke } = window.__TAURI__.core;
  const { getCurrentWindow } = window.__TAURI__.window;

  const source = document.getElementById("source");
  const message = document.getElementById("message");
  const groups = document.getElementById("groups");

  function esc(text) {
    return String(text).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]));
  }

  function renderKeys(keys) {
    return keys
      .map((k) => `<span class="key">${esc(k)}</span>`)
      .join("");
  }

  function render(viewer) {
    if (viewer.source || viewer.config_path && viewer.config_path !== "no cheatsheet file found") {
      source.textContent = "from " + viewer.config_path;
      source.hidden = false;
    }

    if (viewer.error) {
      message.innerHTML = `<p class="error">${esc(viewer.error)}</p>`;
      return;
    }

    if (!viewer.groups || viewer.groups.length === 0) {
      message.innerHTML = `<p class="empty">Nothing to show.</p>`;
      return;
    }

    source.textContent = "from " + viewer.config_path;
    source.hidden = false;

    const html = viewer.groups
      .map(
        (group) =>
          `<section><h2>${esc(group.name)}</h2>` +
          group.items
            .map(
              (item) =>
                `<div class="item"><span class="action">${esc(item.action)}</span>` +
                `<span class="keys">${renderKeys(item.keys)}</span></div>`
            )
            .join("") +
          `</section>`
      )
      .join("");

    groups.innerHTML = html;
  }

  async function close() {
    try {
      await getCurrentWindow().close();
    } catch (_) {}
  }

  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      close();
    } else if ((e.metaKey || e.ctrlKey) && (e.key === "w" || e.key === "W")) {
      e.preventDefault();
      close();
    }
  });

  document.getElementById("close").addEventListener("click", close);

  invoke("get_cheatsheet").then(render).catch((err) => {
    message.innerHTML = `<p class="error">${esc(err)}</p>`;
  });
})();