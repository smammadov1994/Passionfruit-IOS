export interface PushMessage {
  title?: string;
  body: string;
  /** Collapses repeat notifications of the same kind on the device. */
  collapseId?: string;
  /** Custom payload keys delivered alongside `aps`. */
  data?: Record<string, string>;
}

export interface PushResult {
  ok: boolean;
  /** The device token is no longer valid and should be forgotten. */
  unregistered?: boolean;
  reason?: string;
}

export interface PushProvider {
  send(deviceToken: string, message: PushMessage): Promise<PushResult>;
  close(): Promise<void>;
}

/** Dev/test provider: records what would have been sent. */
export class NoopPushProvider implements PushProvider {
  readonly sent: Array<{ deviceToken: string; message: PushMessage }> = [];

  async send(deviceToken: string, message: PushMessage): Promise<PushResult> {
    this.sent.push({ deviceToken, message });
    if (this.sent.length > 1000) this.sent.shift();
    return { ok: true };
  }

  async close(): Promise<void> {}
}
