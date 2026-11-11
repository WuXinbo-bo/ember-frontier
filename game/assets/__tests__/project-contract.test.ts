import { readFile, readdir } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { AssetGuid } from "@forgeax/engine/pack/guid";
import {
  TARGET_VISUAL_THEME,
  validateVisualTheme,
} from "../presentation/visual-contract.ts";
describe("native roots and replaceable presentation", () => {
  it("uses native engine/frontend roots with stable asset identities", async () => {
    const m = JSON.parse(await readFile("forge.json", "utf8"));
    expect(m.schemaVersion).toBe("3.0.0");
    expect(AssetGuid.parse(m.roots.engine).ok).toBe(true);
    expect(m.roots.frontend).toBeTruthy();
    expect(m.name).toBe("余烬边界");
  });
  it("keeps simulation free from browser, engine, persistence and network imports", async () => {
    for (const name of await readdir("assets/simulation"))
      if (name.endsWith(".ts")) {
        const s = await readFile(resolve("assets/simulation", name), "utf8");
        expect(s, name).not.toMatch(
          /from\s+["'](?:@forgeax|zaohua|node:|.*(?:application|adapters|presentation|ui)\/)/,
        );
        expect(s, name).not.toMatch(
          /\b(?:window|document|localStorage|indexedDB|fetch)\s*[.(]/,
        );
      }
  });
  it("records the corrected 2.5D pixel reference without treating placeholders as production assets", () => {
    expect(TARGET_VISUAL_THEME.referenceTitle).toBe("隔离区");
    expect(TARGET_VISUAL_THEME.artDirection).toBe("2.5d-pixel");
    expect(validateVisualTheme(TARGET_VISUAL_THEME)).toEqual([]);
    expect(validateVisualTheme(TARGET_VISUAL_THEME, true)).toContain(
      "NoProductionAssets",
    );
  });
});
