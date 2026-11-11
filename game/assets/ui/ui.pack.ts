import { definePack, definePackageId } from "@forgeax/engine/pack/source";
import type { AssetRegistry } from "@forgeax/engine/assets-runtime";
import { uiAssetContribution } from "@forgeax/engine/ui";
import type { Plugin } from "@forgeax/engine/plugin";
import type {} from "@forgeax/engine/app";
import { ok } from "@forgeax/engine/types";
import { createHud } from "./hud.ts";
export const ui: Plugin.Object<{ hud: string }> = {
  name: "ember/ui",
  inject: ["assets", "gameHost"],
  async apply(ctx, config) {
    const assets = ctx.get("assets") as unknown as AssetRegistry;
    await ctx.effect(async function* () {
      const lease = assets.installDecoder(
        uiAssetContribution.kind,
        uiAssetContribution.decoder,
      );
      yield () => lease.dispose();
      const h = (
        await assets.load(config.hud, uiAssetContribution.kind)
      ).unwrap();
      yield () => assets.release(h).unwrap();
      const hud = await createHud(assets.read(h).unwrap(), ctx.gameHost!);
      yield () => hud.dispose();
    });
  },
};
export default definePack({
  schemaVersion: "2.0.0",
  plugins: true,
  packageId: definePackageId("019fb7ce-3d00-7000-8000-000000000000"),
  build: () =>
    ok({
      "plugin/host": {
        kind: "plugin",
        module: { specifier: "./ui.pack.ts", export: "ui" },
        config: { hud: { $asset: "bc763151-61e0-4585-a599-bdf8ab8ad660" } },
      },
    }),
});
