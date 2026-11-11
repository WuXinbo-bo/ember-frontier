export function hash(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
export function stable(value: unknown): string {
  if (value === undefined) return "null";
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  return `{${Object.keys(value)
    .sort()
    .filter((k) => (value as Record<string, unknown>)[k] !== undefined)
    .map(
      (k) =>
        `${JSON.stringify(k)}:${stable((value as Record<string, unknown>)[k])}`,
    )
    .join(",")}}`;
}
/** Corruption detector, not an authentication or anti-rollback mechanism. */
export const checksum = (value: unknown) =>
  hash(stable(value)).toString(16).padStart(8, "0");
export function boundedInt(
  value: unknown,
  min: number,
  max: number,
): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= min &&
    value <= max
  );
}
