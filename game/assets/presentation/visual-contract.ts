/** Presentation-only contract. Never import this module from SimCore or write it into saves. */
export type Facing = "n" | "ne" | "e" | "se" | "s" | "sw" | "w" | "nw";
export type Motion =
  | "idle"
  | "walk"
  | "run"
  | "attack"
  | "work"
  | "hurt"
  | "dead"
  | "ride";
export type VisualRole =
  | "player"
  | "npc"
  | "infected"
  | "animal"
  | "building"
  | "vehicle"
  | "resource"
  | "terrain"
  | "effect";
export interface SpriteClip {
  frames: number[];
  fps: number;
  loop: boolean;
}
export interface VisualAsset {
  key: string;
  role: VisualRole;
  /** Stable GUID supplied by an official Pack/importer; no URLs in the simulation. */
  sourceGuid: string | null;
  pixelsPerUnit: number;
  pivot: [number, number];
  frameSize: [number, number];
  facing: 4 | 8;
  clips: Partial<Record<Motion, Partial<Record<Facing, SpriteClip>>>>;
  /** Presentation footprint is independent of authoritative collision. */
  footprint: [number, number];
  licenseEvidence?: string;
}
export interface VisualTheme {
  id: string;
  artDirection: "2.5d-pixel";
  referenceTitle: "隔离区";
  projection: "orthographic";
  filtering: "nearest";
  pixelsPerTile: 32 | 48 | 64;
  assets: Record<string, VisualAsset>;
}
export const TARGET_VISUAL_THEME: VisualTheme = {
  id: "quarantine-inspired-pixel-v1",
  artDirection: "2.5d-pixel",
  referenceTitle: "隔离区",
  projection: "orthographic",
  filtering: "nearest",
  pixelsPerTile: 32,
  assets: {},
};
/** Asset replacement must pass this gate; temporary meshes are not final game assets. */
export function validateVisualTheme(
  theme: VisualTheme,
  production = false,
): string[] {
  const errors: string[] = [];
  if (production && !Object.keys(theme.assets).length)
    errors.push("NoProductionAssets");
  for (const [id, a] of Object.entries(theme.assets)) {
    if (
      id !== a.key ||
      a.pixelsPerUnit <= 0 ||
      a.frameSize.some((x) => !Number.isSafeInteger(x) || x <= 0)
    )
      errors.push(`${id}:InvalidDimensions`);
    if (production && (!a.sourceGuid || !a.licenseEvidence))
      errors.push(`${id}:MissingImportedAssetOrLicense`);
    if (
      a.sourceGuid &&
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        a.sourceGuid,
      )
    )
      errors.push(`${id}:InvalidGuid`);
    for (const facings of Object.values(a.clips))
      for (const clip of Object.values(facings ?? {}))
        if (
          !clip?.frames.length ||
          clip.fps <= 0 ||
          clip.frames.some((x) => !Number.isSafeInteger(x) || x < 0)
        )
          errors.push(`${id}:InvalidClip`);
  }
  return errors;
}
