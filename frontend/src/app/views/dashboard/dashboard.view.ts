import { Component, DestroyRef, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { debounceTime } from 'rxjs';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { RealtimeService } from '../../core/services/realtime.service';
import { Alert, Machine, MachineState, SENSOR_LABELS, STATE_LABELS } from '../../models/director.models';

interface DashboardIndicators { disponibilite?: number | null; trs?: number | null }
interface DashboardResponse { indicateurs?: DashboardIndicators }

@Component({ selector: 'app-dashboard', standalone: true, imports: [RouterLink, DatePipe], templateUrl: './dashboard.view.html', styleUrl: './dashboard.view.css' })
export class DashboardView {
  private readonly api = inject(ApiService);
  protected readonly auth = inject(AuthService);
  protected readonly sensorLabels = SENSOR_LABELS;
  readonly machines = signal<Machine[]>([]);
  readonly alerts = signal<Alert[]>([]);
  readonly stats = signal<DashboardIndicators>({});
  readonly loading = signal(true);
  readonly error = signal('');

  constructor() {
    void this.load();
    // Rechargement quand l'état d'une machine change ou qu'une alerte arrive (regroupé sur 1 s)
    inject(RealtimeService).on('machine.etat', 'alerte.creee', 'alerte.maj')
      .pipe(debounceTime(1000), takeUntilDestroyed(inject(DestroyRef)))
      .subscribe(() => void this.load());
  }

  async load(): Promise<void> {
    try {
      // Les indicateurs globaux sont réservés au directeur et au responsable
      const withIndicators = this.auth.hasRole('DIRECTEUR', 'RESPONSABLE');
      const [m, a, d] = await Promise.all([
        this.api.get<Machine[]>('/machines'),
        this.api.get<Alert[]>('/alertes?statut=OUVERTE'),
        withIndicators ? this.api.get<DashboardResponse>('/indicateurs/dashboard') : Promise.resolve({} as DashboardResponse),
      ]);
      this.machines.set(m);
      this.alerts.set(a);
      this.stats.set(d.indicateurs ?? {});
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Impossible de charger le tableau de bord');
    } finally {
      this.loading.set(false);
    }
  }

  percent(v: number | null | undefined): string {
    return v === null || v === undefined ? '—' : (v * 100).toFixed(1);
  }

  stateLabel(v: MachineState): string {
    return STATE_LABELS[v] ?? v;
  }
}
