/**
 * tessera gallery — the built-in interactive component-gallery runtime.
 *
 * Framework-agnostic (vanilla DOM, no build-time magic): reads a Custom
 * Elements Manifest (`custom-elements.json`, schemaVersion "1.0.0", produced
 * by `mix tessera.cem` / `mix tessera.manifest` / `Noizu.Tessera.Package.cem/0`)
 * and renders, per component:
 *
 *   - a LIVE demo element (the package's own registered custom element),
 *   - typed attribute editors (kebab-case DOM attrs; boolean = presence),
 *   - typed property editors (camelCase DOM props; json props edit as JSON),
 *   - slot-content editors (light-DOM text per slot),
 *   - CSS custom-property editors (live `style.setProperty` theming) and a
 *     read-only `::part()` listing,
 *   - an event log: every declared event, name + camelCase detail JSON.
 *
 * The gallery never imports the components itself — the generated entry
 * (`mix tessera.gen.gallery`) imports each component `.mjs`, whose
 * load-bearing top-level `register()` defines the elements (CONTRACT.md §3).
 *
 * Every control carries a `data-cy` hook (`gallery-attr-<tag>-<name>`,
 * `gallery-prop-<tag>-<name>`, `gallery-slot-<tag>-<name>`,
 * `gallery-css-<tag>-<name>`, `gallery-log-<tag>`, `gallery-log-line`) so
 * host e2e suites can drive the gallery without touching its internals.
 */

const LOG_LIMIT = 100;

/**
 * Fetch the CEM at `cemUrl` and render the gallery into `root`
 * (default: the element with id "gallery"). Resolves with the parsed CEM.
 *
 * @param {{cemUrl?: string, root?: HTMLElement}} [options]
 * @returns {Promise<object>} the parsed Custom Elements Manifest
 */
export async function mountGallery({ cemUrl = "./custom-elements.json", root } = {}) {
  const target = root ?? document.getElementById("gallery");
  if (!target) throw new Error("tessera gallery: no root element (expected #gallery)");

  const response = await fetch(cemUrl);
  if (!response.ok) {
    throw new Error(`tessera gallery: failed to load ${cemUrl} (HTTP ${response.status})`);
  }
  const cem = await response.json();

  // The generated entry imports every component module, so registration has
  // already happened; wait for upgrade anyway so the first paint is live.
  const tags = componentDeclarations(cem).map((d) => d.tagName);
  await Promise.all(tags.map((tag) => customElements.whenDefined(tag)));

  renderGallery(cem, target);
  return cem;
}

/**
 * Render `cem` into `target` synchronously (no fetch). Exported for tests
 * and for hosts that already hold the manifest in memory.
 *
 * @param {object} cem a Custom Elements Manifest
 * @param {HTMLElement} target container the gallery is rendered into
 */
export function renderGallery(cem, target) {
  target.textContent = "";
  const declarations = componentDeclarations(cem);

  if (declarations.length === 0) {
    const empty = document.createElement("p");
    empty.dataset.cy = "gallery-empty";
    empty.textContent = "No components in this manifest.";
    target.appendChild(empty);
    return;
  }

  for (const declaration of declarations) {
    target.appendChild(renderComponent(declaration));
  }
}

// -- internals ---------------------------------------------------------------

function componentDeclarations(cem) {
  return (cem?.modules ?? [])
    .flatMap((mod) => mod?.declarations ?? [])
    .filter((d) => d && typeof d.tagName === "string");
}

function renderComponent(declaration) {
  const tag = declaration.tagName;
  const attributes = declaration.attributes ?? [];
  const members = (declaration.members ?? []).filter((m) => m?.kind === "field");
  const slots = declaration.slots ?? [];
  const events = declaration.events ?? [];
  const cssProperties = declaration.cssProperties ?? [];
  const cssParts = declaration.cssParts ?? [];

  const section = el("section", "tsr-gallery-component");
  section.dataset.cy = "gallery-component";
  section.dataset.tag = tag;

  const header = el("header", "tsr-gallery-header");
  const heading = el("h2");
  heading.dataset.cy = "gallery-component-tag";
  heading.textContent = `<${tag}>`;
  header.appendChild(heading);
  if (declaration.description) {
    const desc = el("p", "tsr-gallery-desc");
    desc.textContent = declaration.description;
    header.appendChild(desc);
  }
  section.appendChild(header);

  const cols = el("div", "tsr-gallery-cols");

  // — left column: live demo + event log —
  const stageCol = el("div", "tsr-gallery-stage-col");
  stageCol.appendChild(groupHeading("Live demo"));
  const stage = el("div", "tsr-gallery-stage");
  stage.dataset.cy = "gallery-demo";
  stageCol.appendChild(stage);

  const element = document.createElement(tag);
  for (const attr of attributes) applyAttrDefault(element, attr);
  for (const member of members) applyPropDefault(element, member);
  stage.appendChild(element);

  if (events.length > 0) {
    stageCol.appendChild(groupHeading("Events"));
    const eventList = el("ul", "tsr-gallery-events");
    for (const event of events) {
      const item = el("li");
      const name = el("code");
      name.textContent = event.name;
      item.appendChild(name);
      const detail = event.detail ?? {};
      const keys = Object.keys(detail);
      if (keys.length > 0) {
        const schema = el("span", "tsr-gallery-detail-schema");
        schema.textContent =
          " { " + keys.map((k) => `${k}: ${detail[k]?.text ?? "any"}`).join(", ") + " }";
        item.appendChild(schema);
      }
      eventList.appendChild(item);
    }
    stageCol.appendChild(eventList);
  }

  stageCol.appendChild(groupHeading("Event log"));
  const log = el("ol", "tsr-gallery-log");
  log.dataset.cy = "gallery-log";
  log.setAttribute("aria-live", "polite");
  log.setAttribute("aria-label", `${tag} event log`);
  stageCol.appendChild(log);

  const clear = el("button", "tsr-gallery-clear");
  clear.type = "button";
  clear.dataset.cy = "gallery-log-clear";
  clear.textContent = "clear log";
  clear.addEventListener("click", () => {
    log.textContent = "";
  });
  stageCol.appendChild(clear);

  for (const event of events) {
    element.addEventListener(event.name, (e) => appendLog(log, event.name, e.detail));
  }

  // — right column: editors —
  const controls = el("div", "tsr-gallery-controls");

  if (attributes.length > 0) {
    controls.appendChild(groupHeading("Attributes"));
    for (const attr of attributes) controls.appendChild(attrEditor(element, attr));
  }
  if (members.length > 0) {
    controls.appendChild(groupHeading("Properties"));
    for (const member of members) controls.appendChild(propEditor(element, member));
  }
  if (slots.length > 0) {
    controls.appendChild(groupHeading("Slots"));
    for (const slot of slots) controls.appendChild(slotEditor(element, slot));
  }
  if (cssProperties.length > 0) {
    controls.appendChild(groupHeading("CSS custom properties"));
    for (const prop of cssProperties) controls.appendChild(cssEditor(element, prop));
  }
  if (cssParts.length > 0) {
    controls.appendChild(groupHeading("Parts"));
    const partList = el("ul", "tsr-gallery-parts");
    for (const part of cssParts) {
      const item = el("li");
      const code = el("code");
      code.textContent = `::part(${part.name})`;
      item.appendChild(code);
      partList.appendChild(item);
    }
    controls.appendChild(partList);
  }

  cols.appendChild(stageCol);
  cols.appendChild(controls);
  section.appendChild(cols);
  return section;
}

// — defaults —

/** CEM defaults are JSON-literal strings ("false", "[]", "\"x\""); parse them. */
function parseDefault(raw) {
  if (raw === undefined || raw === null) return undefined;
  try {
    return JSON.parse(raw);
  } catch {
    return raw;
  }
}

function applyAttrDefault(element, attr) {
  const type = attr.type?.text ?? "string";
  let value = parseDefault(attr.default);
  if (value === undefined && attr.required && type === "string") value = "Example";
  if (value === undefined) return;
  if (type === "boolean") {
    if (value === true) element.setAttribute(attr.name, "");
    return;
  }
  element.setAttribute(attr.name, String(value));
}

function applyPropDefault(element, member) {
  const value = parseDefault(member.default);
  if (value === undefined) return;
  element[member.name] = value;
  requestUpdate(element);
}

function requestUpdate(element) {
  if (typeof element.requestUpdate === "function") element.requestUpdate();
}

// — editors —

function attrEditor(element, attr) {
  const tag = element.tagName.toLowerCase();
  const name = attr.name;
  const type = attr.type?.text ?? "string";
  const { row, label } = editorRow(tag, "attr", name, type);

  let input;
  if (type === "boolean") {
    input = el("input");
    input.type = "checkbox";
    input.checked = element.hasAttribute(name);
    input.addEventListener("change", () => {
      if (input.checked) element.setAttribute(name, "");
      else element.removeAttribute(name);
    });
  } else {
    input = el("input");
    input.type = type === "integer" || type === "float" ? "number" : "text";
    if (type === "float") input.step = "any";
    input.value = element.getAttribute(name) ?? "";
    if (attr.required && input.value === "") input.placeholder = "required";
    input.addEventListener("input", () => {
      if (input.value === "" && input.type === "number") element.removeAttribute(name);
      else element.setAttribute(name, input.value);
    });
  }

  wireControl(label, input, `gallery-attr-${tag}-${name}`);
  row.appendChild(input);
  return row;
}

function propEditor(element, member) {
  const tag = element.tagName.toLowerCase();
  const name = member.name;
  const type = member.type?.text ?? "any";
  const isJson = member.json === true || type === "list" || type === "map";
  const { row, label } = editorRow(tag, "prop", name, isJson ? `${type} · json` : type);

  let input;
  if (isJson) {
    input = el("textarea", "tsr-gallery-json");
    input.rows = 3;
    input.spellcheck = false;
    const current = element[name] ?? parseDefault(member.default);
    input.value = current === undefined ? "" : JSON.stringify(current, null, 2);
    input.addEventListener("input", () => {
      try {
        const parsed = input.value.trim() === "" ? null : JSON.parse(input.value);
        input.classList.remove("tsr-gallery-invalid");
        element[name] = parsed;
        requestUpdate(element);
      } catch {
        // Invalid JSON: flag it, keep the last good value on the element.
        input.classList.add("tsr-gallery-invalid");
      }
    });
  } else if (type === "boolean") {
    input = el("input");
    input.type = "checkbox";
    input.checked = element[name] === true;
    input.addEventListener("change", () => {
      element[name] = input.checked;
      requestUpdate(element);
    });
  } else if (type === "integer" || type === "float") {
    input = el("input");
    input.type = "number";
    if (type === "float") input.step = "any";
    input.value = element[name] ?? "";
    input.addEventListener("input", () => {
      element[name] = input.value === "" ? null : Number(input.value);
      requestUpdate(element);
    });
  } else {
    input = el("input");
    input.type = "text";
    input.value = element[name] ?? "";
    input.addEventListener("input", () => {
      element[name] = input.value;
      requestUpdate(element);
    });
  }

  wireControl(label, input, `gallery-prop-${tag}-${name}`);
  row.appendChild(input);
  return row;
}

function slotEditor(element, slot) {
  const tag = element.tagName.toLowerCase();
  const name = slot.name ?? "default";
  const { row, label } = editorRow(tag, "slot", name, name === "default" ? "default slot" : "slot");

  const input = el("textarea");
  input.rows = 2;
  input.placeholder = name === "default" ? "light-DOM content" : `slot="${name}" content`;
  input.addEventListener("input", () => {
    replaceSlotContent(element, name, input.value);
  });

  wireControl(label, input, `gallery-slot-${tag}-${name}`);
  row.appendChild(input);
  return row;
}

function cssEditor(element, prop) {
  const tag = element.tagName.toLowerCase();
  const name = prop.name;
  const { row, label } = editorRow(tag, "css", name, "css");

  const input = el("input");
  input.type = "text";
  input.placeholder = prop.default ?? "";
  input.addEventListener("input", () => {
    if (input.value === "") element.style.removeProperty(name);
    else element.style.setProperty(name, input.value);
  });

  wireControl(label, input, `gallery-css-${tag}-${name.replace(/^--/, "")}`);
  row.appendChild(input);
  return row;
}

/** Replace the light-DOM children targeting `slotName` with a text node. */
function replaceSlotContent(element, slotName, text) {
  for (const child of [...element.childNodes]) {
    const isNamed = child.nodeType === 1 && child.getAttribute("slot") === slotName;
    const isDefault =
      slotName === "default" &&
      (child.nodeType === 3 || (child.nodeType === 1 && !child.hasAttribute("slot")));
    if (isNamed || isDefault) child.remove();
  }
  if (text === "") return;
  if (slotName === "default") {
    element.appendChild(document.createTextNode(text));
  } else {
    const span = document.createElement("span");
    span.setAttribute("slot", slotName);
    span.textContent = text;
    element.appendChild(span);
  }
}

// — event log —

function appendLog(log, name, detail) {
  const item = el("li", "tsr-gallery-log-line");
  item.dataset.cy = "gallery-log-line";
  const eventName = el("span", "tsr-gallery-log-name");
  eventName.textContent = name;
  const payload = el("code");
  payload.textContent = JSON.stringify(detail ?? null);
  item.appendChild(eventName);
  item.appendChild(document.createTextNode(" → "));
  item.appendChild(payload);
  log.appendChild(item);
  while (log.children.length > LOG_LIMIT) log.removeChild(log.firstChild);
  log.scrollTop = log.scrollHeight;
}

// — small DOM helpers —

function el(tagName, className) {
  const node = document.createElement(tagName);
  if (className) node.className = className;
  return node;
}

function groupHeading(text) {
  const heading = el("h3", "tsr-gallery-group");
  heading.textContent = text;
  return heading;
}

function editorRow(tag, kind, name, typeText) {
  const row = el("div", "tsr-gallery-row");
  const label = el("label");
  label.htmlFor = `tsr-g-${tag}-${kind}-${name}`;
  const nameSpan = el("span", "tsr-gallery-control-name");
  nameSpan.textContent = name;
  const badge = el("span", "tsr-gallery-badge");
  badge.textContent = typeText;
  label.appendChild(nameSpan);
  label.appendChild(badge);
  row.appendChild(label);
  return { row, label };
}

function wireControl(label, input, cyHook) {
  input.id = label.htmlFor;
  input.dataset.cy = cyHook;
}