// Tests for generated spritesheets and Frames.js catalog consistency.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
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
