import { Injectable, inject, signal } from '@angular/core';
import { Observable, Subject, filter, map } from 'rxjs';
import { ApiService } from './api.service';

// Flux temps réel du backend (Server-Sent Events, GET /api/stream?token=...), voir backend/docs/API.md §5.
// Les vues s'abonnent avec on('mesure.recue'), on('machine.etat'), on('alerte.creee')...
export const REALTIME_EVENTS = [
  'mesure.recue',
  'machine.etat',
  'capteur.etat',
  'capteur.mesure_invalide',
  'alerte.creee',
  'alerte.maj',
  'intervention.maj',
  'intervention.affectee',
  'intervention.retiree',
] as const;
export type RealtimeEventType = (typeof REALTIME_EVENTS)[number];

export interface RealtimeEvent {
  type: RealtimeEventType;
  data: Record<string, unknown>;
}

const RECONNECT_MS = 5000;

@Injectable({ providedIn: 'root' })
export class RealtimeService {
  private readonly api = inject(ApiService);
  private readonly events = new Subject<RealtimeEvent>();
  private source: EventSource | null = null;
  private retry: ReturnType<typeof setTimeout> | null = null;
  readonly connected = signal(false);

  on<T = Record<string, unknown>>(...types: RealtimeEventType[]): Observable<T> {
    return this.events.pipe(
      filter((e) => types.includes(e.type)),
      map((e) => e.data as T),
    );
  }

  connect(): void {
    this.disconnect();
    const token = this.api.accessToken;
    if (!token) return;
    const source = new EventSource(`${this.api.apiUrl}/stream?token=${encodeURIComponent(token)}`);
    this.source = source;
    source.addEventListener('connecte', () => this.connected.set(true));
    for (const type of REALTIME_EVENTS) {
      source.addEventListener(type, (e) => {
        try {
          this.events.next({ type, data: JSON.parse((e as MessageEvent<string>).data) });
        } catch {
          // message illisible : ignoré
        }
      });
    }
    // Coupure réseau ou jeton expiré (le serveur répond 401) : on renouvelle le jeton puis on se reconnecte
    source.onerror = () => {
      this.connected.set(false);
      source.close();
      this.retry = setTimeout(async () => {
        if (source !== this.source) return;
        await this.api.refresh();
        this.connect();
      }, RECONNECT_MS);
    };
  }

  disconnect(): void {
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.source?.close();
    this.source = null;
    this.connected.set(false);
  }
}
