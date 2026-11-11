import { definePack, definePackageId } from '@forgeax/engine/pack/source';
import { ok } from '@forgeax/engine/types';
import { createBoxGeometry } from '@forgeax/engine/geometry';
import { Materials } from '@forgeax/engine/render';
import { COLORS } from './presentation/palette.ts';
export { sceneOwner } from './presentation/scene.ts';
export default definePack({
  schemaVersion: '2.0.0', plugins: true,
  packageId: definePackageId('019fb7ce-1100-7000-8000-000000000000'),
  build: () => ok({
    'mesh/box': createBoxGeometry(1, 1, 1).unwrap(),
    ...Object.fromEntries(Object.entries(COLORS).map(([id, color]) => [`material/${id.toLowerCase()}`, Materials.standard({ baseColor: color, roughness: 1 })])),
    'plugin/scene': { kind: 'plugin' as const, module: { specifier: './scene-owner.pack.ts', export: 'sceneOwner' }, config: {} },
  }),
});
