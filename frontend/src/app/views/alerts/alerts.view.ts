import { Component, DestroyRef, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ApiService } from '../../core/services/api.service';
import { RealtimeService } from '../../core/services/realtime.service';
import { ALERT_STATUS_LABELS, Alert, SENSOR_LABELS } from '../../models/director.models';

@Component({ selector: 'app-alerts', standalone: true, imports: [DatePipe], templateUrl: './alerts.view.html', styleUrl: '../machines/machines.view.css' })
export class AlertsView {
  private readonly api = inject(ApiService);
  private readonly realtime = inject(RealtimeService);
  protected readonly sensorLabels = SENSOR_LABELS;
  protected readonly statusLabels = ALERT_STATUS_LABELS;
  readonly alerts = signal<Alert[]>([]);
  readonly error = signal('');
  readonly loading = signal(true);

  constructor() {
    void this.load();
    // Les alertes créées par le backend (dépassement de seuil) apparaissent sans recharger la page
    this.realtime.on<Alert>('alerte.creee', 'alerte.maj').pipe(takeUntilDestroyed(inject(DestroyRef))).subscribe((a) => {
      this.alerts.update((list) => [a, ...list.filter((x) => x.id !== a.id)]
        .sort((x, y) => y.createdAt.localeCompare(x.createdAt)));
    });
  }

  async load(): Promise<void> {
    try {
      this.alerts.set(await this.api.get<Alert[]>('/alertes'));
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Chargement impossible');
    } finally {
      this.loading.set(false);
    }
  }
}
