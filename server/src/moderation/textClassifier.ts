import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

const DATA_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../data/explicit-terms.json');

const TermsFileSchema = z.object({
  terms: z.array(z.string().min(1)),
  phrases: z.array(z.string().min(1)),
});

export interface TextVerdict {
  explicit: boolean;
  /** How many distinct terms/phrases matched. The matched words themselves are never stored. */
  matchCount: number;
  /** Indices into the term/phrase lists, for audit ("term:12", "phrase:4"). */
  matches: string[];
}

const LEET: Record<string, string> = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '8': 'b',
  '9': 'g',
};

/** `null` in a pattern slot means "up to two arbitrary words". */
type PatternSlot = Set<string> | null;
const MAX_WILDCARD_WORDS = 2;

/**
 * Lowercases, strips diacritics, undoes common obfuscation (leetspeak, symbols standing in for
 * letters, s p a c e d  o u t letters, streeeetched letters) and splits into words.
 * Every word is a whole token, so matching is word-boundary matching by construction
 * ("Scunthorpe" and "cocktail" never match).
 */
export function normalizeToTokens(text: string): string[] {
  let s = text.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase();
  // Symbols used as letters, only when attached to a letter.
  s = s.replace(/(?<=[a-z])@|@(?=[a-z])/g, 'a').replace(/(?<=[a-z])\$|\$(?=[a-z])/g, 's');
  s = s.replace(/(?<=[a-z])!(?=[a-z])/g, 'i');
  // In-word separators used to dodge filters: f.u.c.k, f*ck is not recoverable, f-u-c-k is.
  s = s.replace(/['’`]/g, '');
  const raw = s.split(/[^a-z0-9]+/).filter((t) => t.length > 0);

  const words: string[] = [];
  for (const token of raw) {
    let t = token;
    if (/[a-z]/.test(t) && /[0-9]/.test(t)) {
      t = t.replace(/[0-9]/g, (d) => LEET[d] ?? d);
    }
    words.push(t);
  }

  // Join runs of three or more single letters: "f u c k" -> "fuck".
  const joined: string[] = [];
  let run: string[] = [];
  const flush = (): void => {
    if (run.length >= 3) joined.push(run.join(''));
    else joined.push(...run);
    run = [];
  };
  for (const w of words) {
    if (w.length === 1 && /[a-z]/.test(w)) run.push(w);
    else {
      flush();
      joined.push(w);
    }
  }
  flush();
  return joined;
}

/** A stretched word ("fuuuuck") is also tried with each run of 3+ letters cut to two and to one. */
function variants(token: string): string[] {
  if (!/(.)\1\1/.test(token)) return [token];
  return [token, token.replace(/(.)\1{2,}/g, '$1$1'), token.replace(/(.)\1{2,}/g, '$1')];
}

export class ExplicitTextClassifier {
  private readonly terms = new Map<string, number>();
  private readonly phrases: PatternSlot[][] = [];

  constructor(data: { terms: string[]; phrases: string[] }) {
    data.terms.forEach((term, i) => {
      for (const t of normalizeToTokens(term)) this.terms.set(t, i);
    });
    for (const phrase of data.phrases) {
      const slots: PatternSlot[] = phrase
        .trim()
        .split(/\s+/)
        .map((slot) => (slot === '*' ? null : new Set(slot.split('|').map((w) => w.toLowerCase()))));
      this.phrases.push(slots);
    }
  }

  static fromFile(file: string = DATA_PATH): ExplicitTextClassifier {
    const parsed = TermsFileSchema.parse(JSON.parse(readFileSync(file, 'utf8')));
    return new ExplicitTextClassifier(parsed);
  }

  classify(text: string): TextVerdict {
    const tokens = normalizeToTokens(text).map(variants);
    const matches = new Set<string>();

    for (const options of tokens) {
      for (const option of options) {
        const idx = this.terms.get(option);
        if (idx !== undefined) matches.add(`term:${idx}`);
      }
    }
    this.phrases.forEach((slots, p) => {
      for (let start = 0; start < tokens.length; start++) {
        if (this.matchFrom(slots, 0, tokens, start)) {
          matches.add(`phrase:${p}`);
          break;
        }
      }
    });
    return { explicit: matches.size > 0, matchCount: matches.size, matches: [...matches] };
  }

  private matchFrom(slots: PatternSlot[], slotIdx: number, tokens: string[][], tokenIdx: number): boolean {
    if (slotIdx === slots.length) return true;
    const slot = slots[slotIdx];
    if (slot === null) {
      for (let skip = 0; skip <= MAX_WILDCARD_WORDS; skip++) {
        if (this.matchFrom(slots, slotIdx + 1, tokens, tokenIdx + skip)) return true;
      }
      return false;
    }
    const options = tokens[tokenIdx];
    if (options === undefined || slot === undefined) return false;
    return options.some((o) => slot.has(o)) && this.matchFrom(slots, slotIdx + 1, tokens, tokenIdx + 1);
  }
}
