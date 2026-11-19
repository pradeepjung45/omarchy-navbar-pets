// Tests for generated spritesheets and Frames.js catalog consistency.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { inflateSync } from "node:zlib";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REPO = join(dirname(fileURLToPath(import.meta.url)), "..");
const framesSource = readFileSync(join(REPO, "Frames.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const Frames = new Function(
  `${framesSource}\nreturn { CELL, COUNT, INDEX, CHARACTERS, COLORFUL, CATALOG, POSES };`,
)();

function pngSize(path) {
  const buf = readFileSync(path);
  assert.equal(buf.subarray(0, 8).toString("hex"), "89504e470d0a1a0a", `${path} must be a PNG`);
  assert.equal(buf.subarray(12, 16).toString("ascii"), "IHDR");
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  };
}

test("Frames.js catalog includes themed and colorful animals across all 5 species", () => {
  const expectedIds = [
    "neko", "tora", "dog",
    "cat-ginger", "cat-calico", "cat-tuxedo",
    "dog-golden", "dog-husky", "dog-corgi",
    "rat-gray", "rat-white",
    "panda", "panda-red",
    "horse-brown", "horse-white",
    "bird-blue", "bird-parrot",
    "fairy-pixie", "fairy-unicorn", "fairy-dragon",
  ];
  for (const id of expectedIds) {
    assert.ok(Frames.CHARACTERS.includes(id), `missing character ${id}`);
  }
  assert.equal(Frames.CATALOG.length, Frames.CHARACTERS.length);
  for (const entry of Frames.CATALOG) {
    assert.ok(entry.id && entry.label && entry.group);
    assert.equal(Boolean(Frames.COLORFUL[entry.id]), Boolean(entry.colorful));
  }
});

test("every character has valid 32px and 16px PNG spritesheets", () => {
  for (const entry of Frames.CATALOG) {
    const sheets = entry.colorful
      ? [`${entry.id}32-color.png`, `${entry.id}16-color.png`]
      : [
          `${entry.id}32-fill.png`, `${entry.id}32-ink.png`,
          `${entry.id}16-fill.png`, `${entry.id}16-ink.png`,
        ];
    for (const file of sheets) {
      const fullPath = join(REPO, "assets", file);
      assert.ok(existsSync(fullPath), `missing spritesheet ${file}`);
      const cell = file.includes("32-") ? 32 : 16;
      const dim = pngSize(fullPath);
      assert.equal(dim.width, cell * Frames.COUNT, `${file} width`);
      assert.equal(dim.height, cell, `${file} height`);
    }
  }
});

test("every pose points to valid frame indices", () => {
  for (const [pose, pair] of Object.entries(Frames.POSES)) {
    assert.equal(pair.length, 2, `${pose} must have 2 frames`);
    for (const idx of pair) {
      assert.ok(Number.isInteger(idx) && idx >= 0 && idx < Frames.COUNT, `${pose} frame ${idx}`);
    }
  }
});

function readRgbaPixels(path) {
  const buf = readFileSync(path);
  let pos = 8;
  let width = 0;
  let height = 0;
  const chunks = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const tag = buf.subarray(pos + 4, pos + 8).toString("ascii");
    const data = buf.subarray(pos + 8, pos + 8 + len);
    pos += 12 + len;
    if (tag === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
    } else if (tag === "IDAT") {
      chunks.push(data);
    }
  }
  const raw = inflateSync(Buffer.concat(chunks));
  return { width, height, raw, stride: 1 + width * 4 };
}

function frameBottomY(png, frameIdx) {
  let maxY = -1;
  for (let y = 0; y < png.height; y++) {
    const rowOff = y * png.stride + 1;
    for (let x = frameIdx * 32; x < (frameIdx + 1) * 32; x++) {
      if (png.raw[rowOff + x * 4 + 3] > 0) maxY = y;
    }
  }
  return maxY;
}

test("only birds fly high in movement frames; horses and land animals stay grounded", () => {
  const flyers = new Set(["bird-blue", "bird-parrot"]);
  const hoverers = new Set(["fairy-pixie"]);
  const left1 = Frames.INDEX.left1;
  const stop = Frames.INDEX.mati2;

  for (const entry of Frames.CATALOG) {
    if (!entry.colorful) continue;
    const png = readRgbaPixels(join(REPO, "assets", `${entry.id}32-color.png`));
    const stopBottom = frameBottomY(png, stop);
    const walkBottom = frameBottomY(png, left1);
    assert.ok(stopBottom >= 27, `${entry.id} perched/stopped frame should stand on ground (got y=${stopBottom})`);
    if (flyers.has(entry.id)) {
      assert.ok(walkBottom <= 21, `${entry.id} flight frame should fly high above ground (got y=${walkBottom})`);
    } else if (hoverers.has(entry.id)) {
      assert.ok(walkBottom >= 24 && walkBottom <= 27, `${entry.id} hover frame should flutter low (got y=${walkBottom})`);
    } else {
      assert.ok(walkBottom >= 27, `${entry.id} walking frame must stay grounded, not fly (got y=${walkBottom})`);
    }
  }
});

test("Cat.qml uses its own namespaced IPC target and never tampers with IpcRegistry", () => {
  const qml = readFileSync(join(REPO, "Cat.qml"), "utf8");
  assert.ok(!qml.includes("IpcRegistry"), "plugin must not access or mutate Omarchy's shared IpcRegistry");
  assert.ok(qml.includes("target: root.pluginId"), "ShellIpc must use the plugin's own namespaced target");
  assert.ok(!qml.includes('"file://" + root.assetDir'), "assetDir already includes file:// prefix");
});
