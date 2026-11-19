const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const modelUtilsSource = fs.readFileSync(require.resolve("../ModelUtils.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const utilsCtx = { Array };
vm.createContext(utilsCtx);
vm.runInContext(modelUtilsSource, utilsCtx);

// Verify QML sequence-like artist arrays normalize cleanly without nested-array corruption.
const seqArtists = { length: 2, 0: "Lumen", 1: "Kairo" };
assert.deepStrictEqual(Array.from(utilsCtx.asArray(seqArtists)), ["Lumen", "Kairo"]);

const mediaModelQml = fs.readFileSync(require.resolve("../MediaModel.qml"), "utf8");
assert(mediaModelQml.includes("normalizeArtists(current.artists, current.artist)"),
  "MediaModel must normalize array artist fields from noxd");
assert(mediaModelQml.includes("normalizeMediaUrl("),
  "MediaModel must normalize local artwork paths to file:// URLs");
assert(mediaModelQml.includes("property bool canSeek:"), "MediaModel must track canSeek");
assert(mediaModelQml.includes("property double positionReceivedAtMs:"),
  "MediaModel must record snapshot timestamp for live playback interpolation");

const mediaPanelQml = fs.readFileSync(require.resolve("../surfaces/media/MediaPanel.qml"), "utf8");
assert(mediaPanelQml.includes('.toLowerCase() === "playing"'),
  "MediaPanel must match noxd PascalCase playback_status case-insensitively");
assert(mediaPanelQml.includes("id: playbackTickTimer"),
  "MediaPanel must interpolate position smoothly while playing");
assert(mediaPanelQml.includes("function resetSeek()"),
  "MediaPanel must reset pending seek state on track/player changes");
assert(mediaPanelQml.includes("readOnly: !root.canSeek"),
  "MediaPanel slider must respect player canSeek");

const sliderQml = fs.readFileSync(require.resolve("../components/Slider.qml"), "utf8");
assert(sliderQml.includes("x: root.travel * root.fraction"),
  "Slider knob x must use root.travel * root.fraction");
assert(!sliderQml.includes("x: root.knobRadius + root.travel * root.fraction"),
  "Slider knob x must not offset by +knobRadius past track bounds");

console.log("ok - media model, media panel, and slider alignment fixtures passed");
