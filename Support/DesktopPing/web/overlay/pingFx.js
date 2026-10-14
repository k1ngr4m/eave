// Adapted from lolPing (MIT), see ../LICENSE.
import { FALLBACK_TEXTURE, textureUrl } from "./pings.js";
const MAX_PINGS = 60;
function img(name, cls = "") {
  const el = document.createElement("img");
  if (cls) el.className = cls;
  el.src = textureUrl(name);
  el.onerror = () => {
    el.onerror = null;
    el.src = textureUrl(FALLBACK_TEXTURE);
  };
  return el;
}
const div = (cls) => {
  const d = document.createElement("div");
  d.className = cls;
  return d;
};
function spawnPing(layer, def, x, y, opts) {
  const root = div("ping");
  root.style.left = `${x}px`;
  root.style.top = `${y}px`;
  root.style.setProperty("--c", def.color);
  root.style.setProperty("--size", `${opts.sizePx}px`);
  root.style.setProperty("--dur", `${opts.durationS}s`);
  root.append(div("ground"), div("ring"), div("ring r2"), div("ring r3"));
  const art = div("art");
  if (def.art.length === 2) {
    const clash = div("clash");
    clash.append(img(def.art[0], "a1"), img(def.art[1], "a2"));
    art.append(clash, div("flash"));
  } else {
    const pop = div("pop");
    pop.append(img(def.art[0]));
    art.append(pop);
  }
  root.append(art);

  while (layer.childElementCount >= MAX_PINGS) layer.firstElementChild?.remove();
  layer.append(root);
  setTimeout(() => root.remove(), opts.durationS * 1e3 + 150);
}
export {
  MAX_PINGS,
  spawnPing
};
