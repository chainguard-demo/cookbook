const apiURL = "/v1/diff/" + encodeURIComponent(repo)
  + "/" + encodeURIComponent(oldRef)
  + "/" + encodeURIComponent(newRef);

fetch(apiURL, { headers: { "Accept": "application/json" } })
  .then(async (r) => {
    if (!r.ok) {
      // Error responses are {"error": "..."} JSON; fall back to status text
      // if the body isn't JSON for any reason (older deploy, proxy in the way).
      let message = `${r.status} ${r.statusText}`;
      try {
        const body = await r.json();
        if (body && body.error) message = body.error;
      } catch (_) { /* keep status fallback */ }
      throw new ApiError(message, r.status, r.statusText);
    }
    return r.json();
  })
  .then(render)
  .catch(showError);

class ApiError extends Error {
  constructor(message, status, statusText) {
    super(message);
    this.status = status;
    this.statusText = statusText;
  }
}

function fillRefCard(side, ref) {
  setField(side + "-digest", ref.digest);
  setField(side + "-ts", ref.timestamp);
  setField(side + "-platform", ref.platform);
  setField(side + "-main", ref.mainPackage);
}

function setField(id, value) {
  const el = document.getElementById(id);
  if (value) {
    el.textContent = value;
    el.classList.remove("muted-empty");
  } else {
    el.textContent = "—";
    el.classList.add("muted-empty");
  }
}

function showError(err) {
  document.getElementById("loading").hidden = true;
  const el = document.getElementById("error");
  el.innerHTML = "";
  const main = document.createElement("div");
  main.textContent = err.message;
  el.appendChild(main);
  if (err instanceof ApiError) {
    const sub = document.createElement("div");
    sub.className = "error-status";
    sub.textContent = `HTTP ${err.status} ${err.statusText}`;
    el.appendChild(sub);
  }
  el.hidden = false;
}

function render(data) {
  document.getElementById("loading").hidden = true;
  document.getElementById("content").hidden = false;

  fillRefCard("from", data.from);
  fillRefCard("to", data.to);

  // Build the set of "main" apk names — usually one, but if from and to
  // diverge we treat both as main so rows on either side stay highlighted.
  const mainSet = new Set();
  if (data.from.mainPackage) mainSet.add(data.from.mainPackage);
  if (data.to.mainPackage) mainSet.add(data.to.mainPackage);

  renderPackages(data.packages || {}, mainSet);
  renderSources(data.sources || {}, mainSet);
  renderConfig(data.config || []);
}

// sortMainFirst returns a copy of items with main entries pulled to the top,
// preserving the relative order of everything else (Array.sort is stable
// in modern engines).
function sortMainFirst(items, isMain) {
  return [...items].sort((a, b) => {
    const am = isMain(a) ? 0 : 1;
    const bm = isMain(b) ? 0 : 1;
    return am - bm;
  });
}

function renderPackages(pkg, mainSet) {
  const sec = document.getElementById("packages");
  const parts = [];
  const isMain = (item) => mainSet.has(item.name);
  const u = sortMainFirst(pkg.updated || [], isMain);
  const a = sortMainFirst(pkg.added || [], isMain);
  const r = sortMainFirst(pkg.removed || [], isMain);
  const cls = (item, kind) => "row " + kind + (isMain(item) ? " main" : "");
  const badge = (item) => isMain(item) ? '<span class="main-badge">main</span>' : "";
  if (u.length) {
    parts.push("<h3>Updated (" + u.length + ")</h3>");
    for (const item of u) {
      parts.push(
        `<div class="${cls(item, 'updated')}">
          <span class="name">${esc(item.name)}</span>${badge(item)}
          <span class="mono"><span class="from-val">${esc(item.from)}</span><span class="arrow">→</span><span class="to-val">${esc(item.to)}</span></span>
        </div>`
      );
    }
  }
  if (a.length) {
    parts.push("<h3>Added (" + a.length + ")</h3>");
    for (const item of a) {
      parts.push(
        `<div class="${cls(item, 'added')}">
          <span class="name">${esc(item.name)}</span>${badge(item)}
          <span class="mono to-val">${esc(item.version)}</span>
        </div>`
      );
    }
  }
  if (r.length) {
    parts.push("<h3>Removed (" + r.length + ")</h3>");
    for (const item of r) {
      parts.push(
        `<div class="${cls(item, 'removed')}">
          <span class="name">${esc(item.name)}</span>${badge(item)}
          <span class="mono from-val">${esc(item.version)}</span>
        </div>`
      );
    }
  }
  sec.innerHTML = parts.length ? parts.join("") : '<p class="empty">No package changes.</p>';
}

function renderSources(src, mainSet) {
  const sec = document.getElementById("sources");
  const parts = [];
  const isMain = (s) => (s.packages || []).some((p) => mainSet.has(p));
  const u = sortMainFirst(src.updated || [], isMain);
  const a = sortMainFirst(src.added || [], isMain);
  const r = sortMainFirst(src.removed || [], isMain);

  const cls = (s, kind) => "row " + kind + (isMain(s) ? " main" : "");
  const badge = (s) => isMain(s) ? '<span class="main-badge">main</span>' : "";

  const linkedName = (s) => s.url
    ? `<a href="${esc(s.url)}" target="_blank" rel="noopener">${esc(s.host)}/${esc(s.name)}</a>`
    : `${esc(s.host)}/${esc(s.name)}`;

  const compareLink = (s) => s.compareUrl
    ? `<a class="compare-link" href="${esc(s.compareUrl)}" target="_blank" rel="noopener">compare<span class="ext-arrow" aria-hidden="true">↗</span></a>`
    : "";

  const usedBy = (s, prefix) => {
    const list = s.packages || [];
    if (!list.length) return "";
    const rendered = list.map((p) => mainSet.has(p)
      ? `<strong>${esc(p)}</strong>`
      : esc(p));
    return `<div class="pkg-ref">${prefix} ${rendered.join(", ")}</div>`;
  };

  if (u.length) {
    parts.push("<h3>Updated (" + u.length + ")</h3>");
    for (const item of u) {
      parts.push(
        `<div class="${cls(item, 'updated')}">
          <span class="name">${linkedName(item)}</span>${badge(item)}
          <span class="mono"><span class="from-val">${esc(item.from)}</span><span class="arrow">→</span><span class="to-val">${esc(item.to)}</span></span>
          ${compareLink(item)}
          ${usedBy(item, "used by")}
        </div>`
      );
    }
  }
  if (a.length) {
    parts.push("<h3>Added (" + a.length + ")</h3>");
    for (const item of a) {
      parts.push(
        `<div class="${cls(item, 'added')}">
          <span class="name">${linkedName(item)}</span>${badge(item)}
          <span class="mono to-val">${esc(item.version)}</span>
          ${usedBy(item, "used by")}
        </div>`
      );
    }
  }
  if (r.length) {
    parts.push("<h3>Removed (" + r.length + ")</h3>");
    for (const item of r) {
      parts.push(
        `<div class="${cls(item, 'removed')}">
          <span class="name">${linkedName(item)}</span>${badge(item)}
          <span class="mono from-val">${esc(item.version)}</span>
          ${usedBy(item, "was used by")}
        </div>`
      );
    }
  }
  sec.innerHTML = parts.length ? parts.join("") : '<p class="empty">No source changes.</p>';
}

function renderConfig(items) {
  const sec = document.getElementById("config");
  if (!items.length) {
    sec.innerHTML = '<p class="empty">No config changes.</p>';
    return;
  }
  const parts = [];
  for (const c of items) {
    let body = "";
    if (c.type === "changed") {
      body = `<span class="from-val">${esc(c.from)}</span><span class="arrow">→</span><span class="to-val">${esc(c.to)}</span>`;
    } else if (c.type === "added") {
      body = `<span class="to-val">${esc(c.to)}</span>`;
    } else if (c.type === "removed") {
      body = `<span class="from-val">${esc(c.from)}</span>`;
    }
    parts.push(
      `<div class="row ${esc(c.type)}">
        <code class="name">${esc(c.field)}</code>
        <span class="mono">${body}</span>
      </div>`
    );
  }
  sec.innerHTML = parts.join("");
}

function esc(s) {
  if (s == null) return "";
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[c]));
}
