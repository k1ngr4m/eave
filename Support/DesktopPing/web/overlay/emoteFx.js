// Local-only adaptation of lolPing's emote stage (MIT; see ../LICENSE).
const layer = document.getElementById('emotes');
let current;
let timer;
let sequence = 0;
export function clearEmote() {
  clearTimeout(timer);
  if (current) current.onload = current.onerror = null;
  current = null;
  layer.replaceChildren();
}
export function showEmote(item, x, y, size, onSound) {
  clearEmote();
  const root = document.createElement('div');
  root.className = 'emote';
  root.style.cssText = `left:${x}px;top:${y}px;--size:${size}px`;
  const image = new Image();
  current = image;
  image.alt = item.name;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  image.className = item.id.startsWith('c:') || reduced ? 'custom' : 'sheet';
  // A distinct URL restarts the animation for each send; the native scheme ignores the query.
  image.src = `${reduced ? item.icon : item.art}?play=${++sequence}`;
  image.onload = () => {
    if (current !== image) return;
    layer.append(root);
    onSound();
    clearTimeout(timer);
    timer = setTimeout(clearEmote, 3150);
  };
  image.onerror = clearEmote;
  root.append(image);
  timer = setTimeout(clearEmote, 10000);
}
