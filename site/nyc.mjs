// New York City ZIP codes by borough. Shared by the page and the waitlist server.
const RANGES = [
  ['Manhattan', 10001, 10282],
  ['Staten Island', 10301, 10314],
  ['The Bronx', 10451, 10475],
  ['Queens', 11004, 11005],
  ['Queens', 11101, 11120],
  ['Brooklyn', 11201, 11256],
  ['Queens', 11351, 11499],
  ['Queens', 11690, 11697],
];

export const BOROUGHS = ['Manhattan', 'Brooklyn', 'Queens', 'The Bronx', 'Staten Island'];

/** Returns the borough name for a five-digit NYC ZIP, or null when the ZIP is outside the city. */
export function boroughForZip(zip) {
  if (!/^\d{5}$/.test(String(zip))) return null;
  const n = Number(zip);
  for (const [name, lo, hi] of RANGES) if (n >= lo && n <= hi) return name;
  return null;
}
