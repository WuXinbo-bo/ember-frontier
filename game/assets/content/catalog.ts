export const SKILLS = {
  learning: "学习",
  gathering: "采集",
  stealth: "潜行",
  scouting: "侦察",
  construction: "建造",
  carpentry: "木工",
  fitting: "钳工",
  smithing: "打铁",
  mining: "挖矿",
  tailoring: "裁缝",
  electrical: "电工",
  mechanics: "机械维修",
  electronics: "电子技术",
  hunting: "猎人",
  logging: "伐木",
  herbalism: "采药",
  fishing: "钓鱼",
  trapping: "捕获",
  taming: "驯兽",
  traps: "陷阱",
  farming: "种田",
  herding: "放牧",
  cooking: "烹饪",
  preservation: "食品保存",
  pharmacy: "制药",
  firstaid: "急救",
  veterinary: "兽医",
  melee: "格斗",
  shooting: "射击",
  driving: "驾驶",
  negotiation: "交涉",
  leadership: "领导",
  trading: "交易",
} as const;
export type SkillId = keyof typeof SKILLS;
export interface ItemDef {
  name: string;
  mass: number;
  food?: number;
  water?: number;
  heal?: number;
  knowledge?: string;
  damage?: number;
  ammo?: string;
  range?: number;
  noise?: number;
}
export const ITEMS: Record<string, ItemDef> = {
  ...Object.fromEntries(
    Object.entries(SKILLS).map(([id, name]) => [
      `book_skill_${id}`,
      { name: `${name}实务手册`, mass: 200, knowledge: `skill.${id}` },
    ]),
  ),
  vehicle_chassis: { name: "陆行底盘", mass: 12000 },
  boat_chassis: { name: "船艇底盘", mass: 10000 },
  engine_module: { name: "动力模块", mass: 18000 },
  gun_module: { name: "武器模块", mass: 22000 },
  armor_module: { name: "载具装甲", mass: 30000 },
  produce: { name: "鲜蔬", mass: 200, food: 20 },
  meat: { name: "鲜肉", mass: 300 },
  wood: { name: "木材", mass: 700 },
  stone: { name: "碎石", mass: 500 },
  scrap: { name: "废金属", mass: 500 },
  cloth: { name: "布料", mass: 100 },
  food: { name: "罐头", mass: 250, food: 35 },
  water: { name: "净水", mass: 500, water: 40 },
  dirty_water: { name: "原水", mass: 500 },
  herb: { name: "草药", mass: 50 },
  bandage: { name: "绷带", mass: 60, heal: 20 },
  medicine: { name: "药品", mass: 50, heal: 35 },
  fuel: { name: "燃料", mass: 500 },
  battery: { name: "储能单元", mass: 400 },
  wire: { name: "导线", mass: 100 },
  gear: { name: "机械零件", mass: 250 },
  nutrient: { name: "营养培养物", mass: 250 },
  reagent: { name: "研究试剂", mass: 100 },
  sample: { name: "生物样本", mass: 100 },
  stabilizer: { name: "稳定剂", mass: 100 },
  control_core: { name: "控制核心", mass: 200 },
  seed: { name: "种子", mass: 20 },
  ammo: { name: "标准弹药", mass: 20 },
  bio_charge: { name: "生物载荷", mass: 50 },
  club: { name: "木棒", mass: 1000, damage: 18, range: 1.8, noise: 5 },
  spear: { name: "短矛", mass: 1400, damage: 25, range: 2.5, noise: 6 },
  pistol: {
    name: "简易手枪",
    mass: 1200,
    damage: 35,
    range: 16,
    noise: 36,
    ammo: "ammo",
  },
  biolance: {
    name: "共生投射器",
    mass: 1400,
    damage: 30,
    range: 12,
    noise: 22,
    ammo: "bio_charge",
  },
  servo: {
    name: "动力臂组件",
    mass: 2000,
    damage: 40,
    range: 2.2,
    noise: 12,
    ammo: "battery",
  },
  saddle: { name: "鞍具", mass: 2500 },
  armor: { name: "复合护甲", mass: 3000 },
  raft: { name: "轻型筏", mass: 5000 },
  book_survival: { name: "荒野生存手册", mass: 200, knowledge: "survival" },
  book_tech: { name: "基础工程笔记", mass: 200, knowledge: "tech" },
  book_bio: { name: "生物研究笔记", mass: 200, knowledge: "bio" },
  book_aug: { name: "个体适配手册", mass: 200, knowledge: "augmentation" },
};
export interface Recipe {
  name: string;
  cost: Record<string, number>;
  output: Record<string, number>;
  ticks: number;
  skill: SkillId;
  workstation?: string;
  knowledge?: string;
}
export const RECIPES: Record<string, Recipe> = {
  vehicle_chassis: {
    name: "制造陆行底盘",
    cost: { scrap: 10, gear: 4 },
    output: { vehicle_chassis: 1 },
    ticks: 600,
    skill: "mechanics",
    workstation: "workbench",
    knowledge: "tech.vehicles.1",
  },
  boat_chassis: {
    name: "制造船艇底盘",
    cost: { wood: 10, scrap: 4, cloth: 4 },
    output: { boat_chassis: 1 },
    ticks: 500,
    skill: "carpentry",
    workstation: "workbench",
    knowledge: "tech.vehicles.1",
  },
  engine_module: {
    name: "制造动力模块",
    cost: { scrap: 6, gear: 3, wire: 2 },
    output: { engine_module: 1 },
    ticks: 450,
    skill: "mechanics",
    workstation: "workbench",
    knowledge: "tech.vehicles.1",
  },
  gun_module: {
    name: "制造车载武器",
    cost: { scrap: 8, gear: 3, wire: 2 },
    output: { gun_module: 1 },
    ticks: 500,
    skill: "smithing",
    workstation: "workbench",
    knowledge: "tech.precision.2",
  },
  armor_module: {
    name: "制造载具装甲",
    cost: { scrap: 10, cloth: 4 },
    output: { armor_module: 1 },
    ticks: 400,
    skill: "smithing",
    workstation: "workbench",
    knowledge: "tech.defense.1",
  },
  harvest: {
    name: "耕种与收获",
    cost: { seed: 1, water: 1 },
    output: { produce: 4, seed: 2 },
    ticks: 1200,
    skill: "farming",
    workstation: "farm",
  },
  cook_meat: {
    name: "烹饪肉食",
    cost: { meat: 1, wood: 1 },
    output: { food: 2 },
    ticks: 120,
    skill: "cooking",
    workstation: "campfire",
  },
  spear: {
    name: "制作短矛",
    cost: { wood: 2, stone: 1 },
    output: { spear: 1 },
    ticks: 120,
    skill: "carpentry",
  },
  bandage: {
    name: "制作绷带",
    cost: { cloth: 2 },
    output: { bandage: 1 },
    ticks: 80,
    skill: "firstaid",
  },
  water: {
    name: "煮水",
    cost: { dirty_water: 1, wood: 1 },
    output: { water: 1 },
    ticks: 100,
    skill: "cooking",
    workstation: "campfire",
  },
  gear: {
    name: "加工零件",
    cost: { scrap: 2 },
    output: { gear: 1 },
    ticks: 150,
    skill: "fitting",
    workstation: "workbench",
  },
  wire: {
    name: "制造导线",
    cost: { scrap: 1 },
    output: { wire: 2 },
    ticks: 100,
    skill: "electrical",
    workstation: "workbench",
  },
  ammo: {
    name: "制造弹药",
    cost: { scrap: 1, reagent: 1 },
    output: { ammo: 8 },
    ticks: 180,
    skill: "smithing",
    workstation: "workbench",
    knowledge: "tech.precision.1",
  },
  pistol: {
    name: "制作手枪",
    cost: { scrap: 4, gear: 2 },
    output: { pistol: 1 },
    ticks: 300,
    skill: "fitting",
    workstation: "workbench",
    knowledge: "tech.precision.1",
  },
  nutrient: {
    name: "培养营养物",
    cost: { food: 1, water: 1 },
    output: { nutrient: 2 },
    ticks: 160,
    skill: "pharmacy",
    workstation: "biolab",
  },
  bio_charge: {
    name: "培养生物载荷",
    cost: { nutrient: 1, sample: 1 },
    output: { bio_charge: 4 },
    ticks: 160,
    skill: "pharmacy",
    workstation: "biolab",
    knowledge: "bio.armaments.1",
  },
  biolance: {
    name: "培养共生投射器",
    cost: { sample: 3, reagent: 2, nutrient: 2 },
    output: { biolance: 1 },
    ticks: 300,
    skill: "pharmacy",
    workstation: "biolab",
    knowledge: "bio.armaments.1",
  },
  servo: {
    name: "装配动力臂",
    cost: { scrap: 3, gear: 2, battery: 1 },
    output: { servo: 1 },
    ticks: 300,
    skill: "mechanics",
    workstation: "clinic",
    knowledge: "augmentation.cyborg.1",
  },
  medicine: {
    name: "合成药品",
    cost: { herb: 2, reagent: 1 },
    output: { medicine: 1 },
    ticks: 150,
    skill: "pharmacy",
    workstation: "biolab",
  },
  stabilizer: {
    name: "配制稳定剂",
    cost: { herb: 1, reagent: 2, water: 1 },
    output: { stabilizer: 2 },
    ticks: 160,
    skill: "pharmacy",
    workstation: "biolab",
  },
  control_core: {
    name: "制造控制核心",
    cost: { wire: 2, sample: 2, reagent: 2 },
    output: { control_core: 1 },
    ticks: 240,
    skill: "electronics",
    workstation: "biolab",
    knowledge: "bio.control.1",
  },
  saddle: {
    name: "缝制鞍具",
    cost: { cloth: 4, wood: 2 },
    output: { saddle: 1 },
    ticks: 160,
    skill: "tailoring",
  },
  raft: {
    name: "制作轻型筏",
    cost: { wood: 6, cloth: 2 },
    output: { raft: 1 },
    ticks: 240,
    skill: "carpentry",
  },
  armor: {
    name: "制作复合护甲",
    cost: { scrap: 3, cloth: 3 },
    output: { armor: 1 },
    ticks: 240,
    skill: "smithing",
    workstation: "workbench",
  },
  battery: {
    name: "制作储能单元",
    cost: { scrap: 2, reagent: 1, wire: 1 },
    output: { battery: 1 },
    ticks: 160,
    skill: "electrical",
    workstation: "workbench",
  },
};
export interface BuildingDef {
  name: string;
  cost: Record<string, number>;
  ticks: number;
  hp: number;
  solid: boolean;
  noise: number;
  power?: number;
  occupation?: number;
}
export const BUILDINGS: Record<string, BuildingDef> = {
  campfire: {
    name: "营火",
    cost: { wood: 3, stone: 2 },
    ticks: 160,
    hp: 80,
    solid: false,
    noise: 2,
  },
  shelter: {
    name: "简易庇护所",
    cost: { wood: 6, cloth: 3 },
    ticks: 300,
    hp: 240,
    solid: false,
    noise: 8,
    occupation: 6,
  },
  crate: {
    name: "储物箱",
    cost: { wood: 3 },
    ticks: 140,
    hp: 120,
    solid: false,
    noise: 4,
  },
  workbench: {
    name: "工作台",
    cost: { wood: 5, scrap: 2 },
    ticks: 240,
    hp: 180,
    solid: true,
    noise: 10,
  },
  door: {
    name: "木门",
    cost: { wood: 3, gear: 1 },
    ticks: 160,
    hp: 160,
    solid: true,
    noise: 6,
  },
  wall: {
    name: "木栅墙",
    cost: { wood: 3 },
    ticks: 140,
    hp: 200,
    solid: true,
    noise: 8,
  },
  generator: {
    name: "发电机",
    cost: { scrap: 5, gear: 2, wire: 2 },
    ticks: 400,
    hp: 200,
    solid: true,
    noise: 30,
  },
  biolab: {
    name: "生物实验台",
    cost: { wood: 4, scrap: 2, sample: 1 },
    ticks: 300,
    hp: 180,
    solid: true,
    noise: 8,
    power: 1,
  },
  clinic: {
    name: "适配工作站",
    cost: { wood: 4, scrap: 3, cloth: 2 },
    ticks: 300,
    hp: 180,
    solid: true,
    noise: 8,
    power: 1,
  },
  isolation: {
    name: "隔离栏",
    cost: { wood: 4, scrap: 3 },
    ticks: 260,
    hp: 300,
    solid: false,
    noise: 10,
  },
  farm: {
    name: "种植床",
    cost: { wood: 2, seed: 2, water: 1 },
    ticks: 180,
    hp: 80,
    solid: false,
    noise: 3,
  },
  bridge: {
    name: "木桥",
    cost: { wood: 8, scrap: 2 },
    ticks: 400,
    hp: 200,
    solid: false,
    noise: 12,
  },
  radio: {
    name: "联络电台",
    cost: { gear: 4, wire: 6, battery: 2 },
    ticks: 600,
    hp: 160,
    solid: true,
    noise: 24,
    power: 1,
  },
};
export const BRANCHES = [
  ["tech.precision", "精密火力", "tech", "workbench"],
  ["tech.vehicles", "重装载具", "tech", "workbench"],
  ["tech.drones", "无人战术", "tech", "workbench"],
  ["tech.defense", "工程防御", "tech", "workbench"],
  ["bio.armaments", "生物军械", "bio", "biolab"],
  ["bio.beasts", "战兽共生", "bio", "biolab"],
  ["bio.ecology", "生态控场", "bio", "biolab"],
  ["bio.medicine", "战地生化", "bio", "biolab"],
  ["bio.control", "感染体改造", "bio", "biolab"],
  ["augmentation.cyborg", "机械义体", "augmentation", "clinic"],
  ["augmentation.genetics", "基因体能", "augmentation", "clinic"],
  ["augmentation.neural", "神经战术", "augmentation", "clinic"],
  ["augmentation.environment", "环境适应", "augmentation", "clinic"],
] as const;
export interface ResearchDef {
  name: string;
  route: string;
  prerequisites: string[];
  workstation: string;
  cost: Record<string, number>;
  ticks: number;
  tier: number;
}
export const RESEARCH: Record<string, ResearchDef> = Object.fromEntries(
  BRANCHES.flatMap(([id, name, route, station]) =>
    [1, 2, 3].map((tier) => [
      `${id}.${tier}`,
      {
        name: `${name} · ${["基础", "专业", "高阶"][tier - 1]}`,
        route,
        workstation: station,
        tier,
        prerequisites: [tier === 1 ? route : `${id}.${tier - 1}`],
        cost: (route === "bio"
          ? { sample: tier * 2, nutrient: tier, reagent: tier }
          : route === "tech"
            ? { scrap: tier * 2, wire: tier, reagent: tier }
            : { gear: tier, cloth: tier, reagent: tier * 2 }) as Record<
          string,
          number
        >,
        ticks: 300 * tier,
      },
    ]),
  ),
);
export const CONTENT_VERSION = "ember-content-1";
export function validateContent(): string[] {
  const errors: string[] = [];
  if (Object.keys(SKILLS).length !== 33)
    errors.push("Skills must be exactly 33");
  for (const [id, d] of Object.entries({
    ...RECIPES,
    ...BUILDINGS,
    ...RESEARCH,
  })) {
    if (d.ticks <= 0 || Object.keys(d.cost).length === 0)
      errors.push(`${id}: free production`);
    for (const [item, quantity] of Object.entries(d.cost))
      if (!ITEMS[item] || !Number.isSafeInteger(quantity) || quantity <= 0)
        errors.push(`${id}: invalid input ${item}`);
  }
  const visit = (id: string, path: string[]) => {
    if (path.includes(id)) {
      errors.push(`${id}: research cycle`);
      return;
    }
    for (const p of RESEARCH[id]?.prerequisites ?? [])
      if (RESEARCH[p]) visit(p, [...path, id]);
      else if (!["tech", "bio", "augmentation"].includes(p))
        errors.push(`${id}: missing knowledge ${p}`);
  };
  for (const id of Object.keys(RESEARCH)) visit(id, []);
  for (const [id, r] of Object.entries(RECIPES))
    for (const output of Object.keys(r.output))
      if (!ITEMS[output]) errors.push(`${id}: invalid output`);
  return errors;
}
