import type { AppConfig } from '../config.js';
import { isPremiumActive } from '../matchmaking/compat.js';
import type { Store } from '../store/Store.js';
import type { UserRecord } from '../types.js';
import { localDayBounds, type Clock } from '../util.js';

export interface Usage {
  datesToday: number;
  /** null = unlimited (premium). */
  limit: number | null;
  resetsAt: Date;
  capped: boolean;
}

/** Daily date cap. The "day" is the user's local day, derived from their stored tz offset. */
export class UsageService {
  constructor(
    private readonly store: Store,
    private readonly config: Pick<AppConfig, 'freeDailyDates'>,
    private readonly clock: Clock,
  ) {}

  async get(user: UserRecord): Promise<Usage> {
    const now = this.clock.now();
    const { start, end } = localDayBounds(now, user.tzOffsetMinutes);
    const datesToday = await this.store.countDatesStarted(user.id, new Date(start));
    const limit = isPremiumActive(user, now) ? null : this.config.freeDailyDates;
    return { datesToday, limit, resetsAt: new Date(end), capped: limit !== null && datesToday >= limit };
  }
}
