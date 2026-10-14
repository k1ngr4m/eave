// Adapted from lolPing (MIT), see ../LICENSE.
const WHEEL = { innerR: 86, outerR: 188, extR: 288, iconR: 137, iconSize: 48 };
function pickSlice(dx, dy, deadZone = WHEEL.innerR) {
  if (Math.hypot(dx, dy) < deadZone) return -1;
  const deg = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 22.5 + 360) % 360;
  return Math.floor(deg / 45) % 8;
}
export {
  WHEEL,
  pickSlice
};
