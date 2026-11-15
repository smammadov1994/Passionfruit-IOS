import type { WebSocket } from 'ws';
import type { ServerMessage } from './protocol.js';

export interface Connection {
  userId: string;
  socket: WebSocket;
  lastSeen: number;
  /** Flood control window. */
  windowStart: number;
  windowCount: number;
  /** Serialises this connection's inbound messages. */
  chain: Promise<void>;
}

/**
 * Who is connected to THIS process and how to reach them. One socket per user.
 * With several instances, `send` becomes "deliver locally or publish to the user's channel"
 * (README "Scaling beyond one instance").
 */
export class Hub {
  private readonly connections = new Map<string, Connection>();

  /** Registers a socket; returns the connection it replaced, if any. */
  attach(userId: string, socket: WebSocket, nowMs: number): { connection: Connection; replaced: Connection | null } {
    const replaced = this.connections.get(userId) ?? null;
    const connection: Connection = {
      userId,
      socket,
      lastSeen: nowMs,
      windowStart: nowMs,
      windowCount: 0,
      chain: Promise.resolve(),
    };
    this.connections.set(userId, connection);
    return { connection, replaced };
  }

  /** Unregisters the socket if it is still the user's current one. Returns whether it was. */
  detach(connection: Connection): boolean {
    if (this.connections.get(connection.userId) !== connection) return false;
    this.connections.delete(connection.userId);
    return true;
  }

  isConnected(userId: string): boolean {
    return this.connections.has(userId);
  }

  get(userId: string): Connection | undefined {
    return this.connections.get(userId);
  }

  all(): Connection[] {
    return [...this.connections.values()];
  }

  size(): number {
    return this.connections.size;
  }

  /** Best-effort delivery. Returns false when the user has no open socket. */
  send(userId: string, message: ServerMessage): boolean {
    const connection = this.connections.get(userId);
    if (!connection) return false;
    return Hub.sendTo(connection.socket, message);
  }

  static sendTo(socket: WebSocket, message: ServerMessage): boolean {
    if (socket.readyState !== socket.OPEN) return false;
    try {
      socket.send(JSON.stringify(message));
      return true;
    } catch {
      return false;
    }
  }

  close(userId: string, code: number, reason: string): void {
    const connection = this.connections.get(userId);
    if (!connection) return;
    try {
      connection.socket.close(code, reason);
    } catch {
      connection.socket.terminate();
    }
  }
}
