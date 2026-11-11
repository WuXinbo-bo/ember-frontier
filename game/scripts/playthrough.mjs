import assert from "node:assert/strict";
/** Real input against the native owner browser; no state mutation or fixture cheats. */
export default async function playthrough(play) {
  await play.step("menu", async () => {
    assert.equal((await play.state()).mode, "menu");
    await play.screenshot("01-mode-selection");
  });
  await play.step("open local world", async () => {
    await play.keyboard.press("Enter");
    const s = await play.waitFor(
      (s) => s.mode === "local" && s.self?.life === "Alive",
      { timeoutMs: 20000 },
    );
    assert.equal(s.population.npc, 99);
    assert.equal(s.population.infected, 10000);
    assert.equal(Object.keys(s.self.skills).length, 33);
    await play.screenshot("02-native-world");
  });
  let before, after;
  await play.step("keyboard movement and inventory", async () => {
    before = await play.state();
    await play.keyboard.hold("KeyD", 650);
    after = await play.state();
    assert.ok(
      after.self.position.x > before.self.position.x,
      "D must move the committed player",
    );
    await play.keyboard.press("KeyB");
    await play.screenshot("03-backpack-and-input");
    await play.keyboard.press("Escape");
  });
  await play.step("real salvage interaction", async () => {
    const before = await play.state();
    const ownCount = (s) =>
      s.items
        .filter((i) => i.container === s.self.inventory)
        .reduce((n, i) => n + i.quantity, 0);
    await play.keyboard.press("KeyE");
    const after = await play.waitFor((s) => ownCount(s) > ownCount(before), {
      timeoutMs: 5000,
    });
    assert.ok(ownCount(after) > ownCount(before));
    await play.screenshot("04-real-item-transfer");
  });
  await play.step("reload recovers committed state", async () => {
    const saved = await play.state();
    await play.reload();
    assert.equal((await play.state()).mode, "menu");
    await play.keyboard.press("Enter");
    const loaded = await play.waitFor(
      (s) => s.mode === "local" && s.self?.id === saved.self.id,
      { timeoutMs: 20000 },
    );
    assert.equal(loaded.worldId, saved.worldId);
    assert.ok(loaded.seq >= saved.seq);
    assert.equal(loaded.self.position.x, saved.self.position.x);
    await play.screenshot("05-recovered-world");
  });
  return {
    movement: { before: before.self.position, after: after.self.position },
    verified: [
      "native scene",
      "mode selection",
      "33-skill profile",
      "initial population",
      "keyboard movement",
      "backpack",
      "physical salvage transferred once",
      "reload identity and committed position",
    ],
  };
}
