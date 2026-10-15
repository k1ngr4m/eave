// Geometry and interaction adapted from lolPing's WheelEditor (MIT; see ../LICENSE).
const post = (body) => window.webkit.messageHandlers.editor.postMessage(body);
const svg = document.getElementById('wheel');
const pool = document.getElementById('signals');
const ns = 'http://www.w3.org/2000/svg';
let state;
let picked = null;
let dragID = null;
const point = (r, angle) => `${150 + r * Math.sin(angle)},${150 - r * Math.cos(angle)}`;
const wedge = (i) => {
  const a = (i - .5) * Math.PI / 4 + .035;
  const b = (i + .5) * Math.PI / 4 - .035;
  return `M${point(52, a)} A52,52 0 0 1 ${point(52, b)} L${point(146, b)} A146,146 0 0 0 ${point(146, a)}Z`;
};
const el = (name, attrs, parent) => {
  const node = document.createElementNS(ns, name);
  Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
  parent.append(node);
  return node;
};
function selection() {
  document.querySelectorAll('[data-source]').forEach((node) => node.classList.toggle('picked', node.dataset.source === picked?.source));
  document.getElementById('hint').textContent = picked ? `${state.names[picked.id]} · ${state.labels.placeHint}` : '';
}
function choose(id, source, preview) {
  picked = picked?.source === source ? null : { id, source };
  if (preview) post({ type: 'preview', id });
  selection();
}
function assign(id, slot) {
  if (!state.items.some((ping) => ping.id === id)) return;
  post({ type: 'assign', id, slot });
  picked = null;
  selection();
}
function activate(node, action) {
  node.addEventListener('click', action);
  // HTML buttons provide keyboard activation themselves; SVG groups need it explicitly.
  if (node.namespaceURI === ns) node.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); action(); }
  });
}
function draggable(node, id) {
  node.setAttribute('draggable', 'true');
  node.addEventListener('dragstart', (event) => {
    dragID = id;
    event.dataTransfer.effectAllowed = 'copyMove';
    event.dataTransfer.setData('text/plain', id);
  });
  node.addEventListener('dragend', () => { dragID = null; clearHot(); });
}
function clearHot() { svg.querySelectorAll('.hot').forEach((node) => node.classList.remove('hot')); }
function target(slot, id, center = false) {
  const node = el('g', { role: 'button', tabindex: 0, 'data-slot': slot, 'data-source': `slot:${slot}`,
    'aria-label': `${center ? state.labels.center : state.directions[slot]}: ${state.names[id]}` }, svg);
  if (center) {
    node.classList.toggle('off', !state.clickPing);
    el('circle', { cx: 150, cy: 150, r: 48, class: 'segment' }, node);
  } else { el('path', { d: wedge(slot), class: 'segment' }, node); }
  const angle = slot * Math.PI / 4;
  const x = center ? 150 : 150 + 100 * Math.sin(angle);
  const y = center ? 141 : 150 - 100 * Math.cos(angle);
  const ping = state.items.find((item) => item.id === id);
  // HTML inside foreignObject provides native WebKit dragging, including from SVG slots.
  const object = el('foreignObject', { x: x - 21, y: y - 21, width: 42, height: 42 }, node);
  const image = document.createElement('img');
  image.src = ping.icon; image.alt = ''; image.style.cssText = 'width:100%;height:100%;object-fit:contain;display:block';
  object.append(image);
  draggable(image, id);
  if (center) el('text', { x: 150, y: 173, 'text-anchor': 'middle' }, node).textContent = state.labels.click;
  activate(node, () => picked ? assign(picked.id, slot) : choose(id, `slot:${slot}`, false));
  node.addEventListener('dragover', (event) => {
    if (!dragID) return;
    event.preventDefault(); clearHot(); node.classList.add('hot');
  });
  node.addEventListener('dragleave', (event) => { if (!node.contains(event.relatedTarget)) node.classList.remove('hot'); });
  node.addEventListener('drop', (event) => {
    event.preventDefault();
    if (dragID) assign(dragID, slot);
    dragID = null; clearHot();
  });
}
window.updateEditor = (value) => {
  state = value;
  document.getElementById('editor').classList.toggle('emotes', !!state.emotes);
  if (picked && !state.items.some((i) => i.id === picked.id)) picked = null;
  const labels = state.labels;
  for (const name of ['title', 'description', 'poolTitle', 'poolDescription', 'reset']) document.getElementById(name).textContent = labels[name];
  svg.setAttribute('aria-label', labels.title);
  svg.replaceChildren(); pool.replaceChildren();
  state.wheel.forEach((id, i) => target(i, id));
  target(8, state.clickPingID, true);
  state.items.forEach((ping) => {
    const button = document.createElement('button');
    button.type = 'button'; button.className = 'tile'; button.dataset.source = `pool:${ping.id}`;
    const where = document.createElement('span'); where.className = 'where';
    const slot = state.wheel.indexOf(ping.id);
    where.textContent = slot < 0 ? '' : state.directions[slot];
    const icon = document.createElement('img'); icon.src = ping.icon; icon.alt = '';
    const name = document.createElement('span'); name.className = 'name'; name.textContent = state.names[ping.id];
    button.append(where, icon, name); pool.append(button);
    activate(button, () => choose(ping.id, `pool:${ping.id}`, true));
    draggable(button, ping.id);
  });
  selection();
};
// WebKit consumes wheel events even where this embedded page cannot scroll.
// Keep the palette's own scrolling; hand everything else to the native settings page.
document.addEventListener('wheel', (event) => {
  if (!event.deltaY || event.ctrlKey) return;
  const insidePool = event.target instanceof Node && pool.contains(event.target);
  const canScrollPool = pool.scrollHeight > pool.clientHeight &&
    (event.deltaY < 0 ? pool.scrollTop > 0 : pool.scrollTop + pool.clientHeight < pool.scrollHeight - 1);
  if (insidePool && canScrollPool) return;
  event.preventDefault();
  const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 :
    event.deltaMode === WheelEvent.DOM_DELTA_PAGE ? window.innerHeight : 1;
  post({ type: 'scroll', delta: event.deltaY * unit });
}, { passive: false });
document.getElementById('reset').addEventListener('click', () => { picked = null; post({ type: 'reset' }); selection(); });
document.addEventListener('keydown', (event) => { if (event.key === 'Escape') { picked = null; selection(); } });
new ResizeObserver(() => post({ type: 'height', value: Math.ceil(document.getElementById('editor').getBoundingClientRect().height) }))
  .observe(document.getElementById('editor'));
post({ type: 'ready' });
