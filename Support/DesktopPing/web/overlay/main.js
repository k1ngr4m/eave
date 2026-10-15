import { Wheel } from './wheel.js';
import { showEmote, clearEmote } from './emoteFx.js';
import { spawnPing } from './pingFx.js';
import { DEFAULT_WHEEL, pingById, textureUrl, allTextureNames } from './pings.js';

const post = (message) => window.webkit.messageHandlers.ping.postMessage(message);
window.addEventListener('error', () => post({ type: 'error' }));
window.addEventListener('unhandledrejection', () => post({ type: 'error' }));
const layer = document.getElementById('pings');
const svg = document.getElementById('wheel');
let settings = { wheel: DEFAULT_WHEEL, size: 110, duration: 3.2, tickSound: true };
const sound = (name) => post({ type: 'sound', name });
const wheel = new Wheel(svg, '', textureUrl('generic_ping'), () => {
  if (settings.tickSound) sound('button');
});
let kind = 'ping';
const items = () => settings.emote?.items ?? [];
const configureWheel = (next) => {
  kind = next;
  svg.classList.toggle('emote-wheel', kind === 'emote');
  const emote = kind === 'emote';
  wheel.setItems(emote ? settings.emote.wheel.map((id) => ({ key: id, icon: items().find((i) => i.id === id)?.icon }))
    : settings.wheel.map((id) => ({ key: id, icon: textureUrl(pingById(id).icon) })));
  svg.querySelector('.hub').setAttribute('href', emote ? items().find((i) => i.id === settings.emote.center)?.icon : textureUrl('generic_ping'));
  svg.querySelector('.centerTxt').textContent = emote ? settings.emoteLabel : settings.wheelLabel;
  svg.querySelector('.backTxt').textContent = settings.cancelLabel;
};
const update = (value) => {
  settings = value;
  wheel.cancel(); configureWheel(kind);
};
const ping = (id, x, y) => {
  const def = pingById(id);
  if (!def) return;
  spawnPing(layer, def, x, y, { sizePx: settings.size, durationS: settings.duration });
  sound(def.sound);
};
const send = (kind, id, x, y) => {
  if (kind !== 'emote') { ping(id, x, y); return; }
  const item = items().find((i) => i.id === id);
  if (item) showEmote(item, x, y, settings.emote.size, () => {
    if (settings.emote.sound && item.sound) sound(item.sound);
  });
};
window.eavePing = (type, payload) => {
  switch (type) {
    case 'settings': update(payload); break;
    case 'wheelOpen': configureWheel(payload.wheel ?? 'ping'); wheel.open(payload.x, payload.y); break;
    case 'wheelMove': wheel.move(payload.x, payload.y); break;
    case 'wheelRelease': {
      const selected = wheel.release(payload.x, payload.y);
      if (selected) send(kind, selected.key, selected.x, selected.y);
      break;
    }
    case 'click': send(payload.wheel ?? 'ping', payload.id, payload.x, payload.y); break;
    case 'cancel': wheel.cancel(); break;
    case 'clearEmote': clearEmote(); break;
    case 'clear': wheel.cancel(); layer.replaceChildren(); clearEmote(); break;
  }
};
// Decode before arming the input helper so the first gesture never opens an empty wheel.
Promise.all(allTextureNames().map((name) => {
  const image = new Image();
  image.src = textureUrl(name);
  return image.decode();
})).then(() => post({ type: 'ready' })).catch(() => post({ type: 'error' }));
