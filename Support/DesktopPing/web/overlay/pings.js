// Adapted from lolPing (MIT), see ../LICENSE.
const ALL_PINGS = [
  { id: "danger", name: "Danger", icon: "pingwheel_retreatrender", art: ["pingwheel_retreatrender"], sound: "SRP_12", color: "#ff3b55" },
  { id: "push", name: "Push", icon: "push", art: ["pingwheel_pushrender"], sound: "SRP_9", color: "#35d27a" },
  { id: "omw", name: "On My Way", icon: "omw", art: ["omw"], sound: "OnMyWay", color: "#2e8bff" },
  { id: "allin", name: "All In", icon: "all_in", art: ["pingwheel_allin_render_01", "pingwheel_allin_render_02"], sound: "SRP_4", color: "#f2b320" },
  { id: "assist", name: "Assist Me", icon: "assist_me", art: ["assist_me"], sound: "ComeHere", color: "#56d43c" },
  { id: "needvision", name: "Need Vision", icon: "need_vision", art: ["need_vision"], sound: "SRP_7", color: "#56d43c" },
  { id: "missing", name: "Enemy Missing", icon: "enemy_missing", art: ["enemy_missing"], sound: "MIA", color: "#f2c518" },
  { id: "enemyvision", name: "Enemy Vision", icon: "enemy_vision", art: ["pingwheel_enemyvisionrender"], sound: "AreaIsWarded", color: "#ff3b55" },
  { id: "generic", name: "Generic", icon: "generic_ping", art: ["pingwheel_basicpingrender"], sound: "Base", color: "#2e8bff" },
  { id: "bait", name: "Bait", icon: "pingwheel_baitrender", art: ["pingwheel_baitrender"], sound: "SRP_11", color: "#efbc12" },
  { id: "visioncleared", name: "Vision Cleared", icon: "vision_cleared", art: ["pingwheel_visionclearedrender"], sound: "SRP_6", color: "#2b80ff" }
];
const DEFAULT_WHEEL = ["danger", "push", "omw", "allin", "assist", "needvision", "missing", "enemyvision"];
const DEFAULT_CLICK_PING = "generic";
const WHEEL_SLOTS = 8;
const TICK_SOUND = "button";
const FALLBACK_TEXTURE = "generic_ping";
function pingById(id) {
  return ALL_PINGS.find((p) => p.id === id);
}
const isPingId = (v) => typeof v === "string" && pingById(v) !== void 0;
const pingsFor = (ids) => ids.map((id) => pingById(id));
const DEFAULT_WHEEL_PINGS = pingsFor(DEFAULT_WHEEL);
const textureUrl = (name) => `../textures/${name}.png`;
const soundUrl = (name) => `../sounds/${name}.wav`;
function allSoundNames() {
  return [.../* @__PURE__ */ new Set([...ALL_PINGS.map((p) => p.sound), TICK_SOUND])];
}
function allTextureNames() {
  return [.../* @__PURE__ */ new Set([...ALL_PINGS.flatMap((p) => [p.icon, ...p.art]), FALLBACK_TEXTURE])];
}
export {
  ALL_PINGS,
  DEFAULT_CLICK_PING,
  DEFAULT_WHEEL,
  DEFAULT_WHEEL_PINGS,
  FALLBACK_TEXTURE,
  TICK_SOUND,
  WHEEL_SLOTS,
  allSoundNames,
  allTextureNames,
  isPingId,
  pingById,
  pingsFor,
  soundUrl,
  textureUrl
};
