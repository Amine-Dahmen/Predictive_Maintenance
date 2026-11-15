import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';

interface Indicator {
  tempsArretH?: number | null;
  coutArret?: number | null;
  nbPannes?: number;
  frequencePannes30j?: number | null;
  dureeMoyennePanneH?: number | null;
  mtbfH?: number | null;
  mttrH?: number | null;
  nbReparations?: number;
  disponibilite?: number | null;
  performance?: number | null;
  qualite?: number | null;
  trs?: number | null;
  trsIncomplet?: boolean;
  production?: { produite?: number; rebutee?: number; ofTermines?: number };
}

interface MachineIndicator extends Indicator {
  machineId: number;
  code: string;
  nom: string;
}

interface IndicatorsResponse {
  periode?: { from?: string; to?: string };
  global?: Indicator;
  machines?: MachineIndicator[];
}

interface DashboardResponse {
  machines?: { total?: number; parEtat?: Record<string, number>; disponibles?: number };
  alertes?: { ouvertes?: number; critiques?: number };
  interventions?: { parStatut?: Record<string, number>; enRetard?: number };
  production?: { ofEnCours?: number };
  topArrets?: Array<{ machineId: number; code: string; nom: string; tempsArretH: number; nbPannes: number; coutArret: number }>;
}

interface PannesPoint { periode: string; nbPannes: number; tempsArretH: number; dureeMoyenneH: number | null; coutArret: number }
interface MachineRow { id: number; coutHoraireArret?: number }
// US-22 : dernière prédiction du modèle d'IA par machine
export interface Prediction {
  machineId: number; code: string; nom: string; probabilite: number | null;
  niveau: 'FAIBLE' | 'MOYEN' | 'ELEVE' | 'INCONNU'; facteurs: Array<{ canal: string; ecart: number; libelle: string }>;
  modele: string; createdAt: string;
}

// US-15 disponibilité, US-16 durée et fréquence des pannes, US-33 synthèse, US-34 coût des arrêts, US-17 rapport
@Component({
  selector: 'app-indicateurs',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './indicateurs.view.html',
  styleUrl: './indicateurs.view.css',
})
export class IndicateursView {
  private readonly api = inject(ApiService);
  private readonly auth = inject(AuthService);
  readonly data = signal<IndicatorsResponse>({});
  readonly dashboard = signal<DashboardResponse>({});
  readonly pannes = signal<PannesPoint[]>([]);
  readonly couts = signal<Record<number, number>>({});
  readonly predictions = signal<Prediction[]>([]);
  readonly error = signal('');
  readonly message = signal('');
  readonly loading = signal(false);
  periodeJours = 30;
  grain: 'week' | 'month' = 'week';

  constructor() {
    void this.load();
  }

  get canEditCost(): boolean {
    return this.auth.role() === 'DIRECTEUR' || this.auth.role() === 'RESPONSABLE';
  }

  private query(): string {
    const to = new Date();
    const from = new Date(to.getTime() - this.periodeJours * 86400000);
    return `from=${from.toISOString()}&to=${to.toISOString()}`;
  }

  async load(): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      const q = this.query();
      const [indicators, dashboard, pannes, machines] = await Promise.all([
        this.api.get<IndicatorsResponse>(`/indicateurs?${q}`),
        this.api.get<DashboardResponse>(`/indicateurs/dashboard?${q}`),
        this.api.get<{ series: PannesPoint[] }>(`/indicateurs/pannes?${q}&grain=${this.grain}`),
        this.api.get<MachineRow[]>('/machines'),
      ]);
      this.data.set(indicators);
      this.dashboard.set(dashboard);
      this.pannes.set(pannes.series);
      this.couts.set(Object.fromEntries(machines.map((m) => [m.id, m.coutHoraireArret ?? 0])));
      // US-22 : facultatif, la page reste utilisable si le service d'IA ne répond pas
      this.api.get<Prediction[]>('/predictions').then(
        (p) => this.predictions.set([...p].sort((a, b) => (b.probabilite ?? -1) - (a.probabilite ?? -1))),
        () => this.predictions.set([]),
      );
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Chargement impossible');
    } finally {
      this.loading.set(false);
    }
  }

  // US-34 : coût horaire d'arrêt d'une machine
  async saveCost(machine: MachineIndicator, value: string | number): Promise<void> {
    const cout = Number(value);
    if (!Number.isFinite(cout) || cout < 0) { this.error.set('Coût horaire invalide'); return; }
    try {
      await this.api.patch(`/machines/${machine.machineId}/cout`, { coutHoraireArret: cout });
      this.message.set(`Coût horaire de ${machine.code} enregistré.`);
      await this.load();
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Enregistrement impossible');
    }
  }

  // US-17 : rapport sur la période affichée ou sur le mois / la semaine précédente
  async report(format: 'csv' | 'html', periode?: 'mois-precedent' | 'semaine-precedente'): Promise<void> {
    try {
      const q = periode ? `periode=${periode}` : this.query();
      const blob = await this.api.blob(`/rapports/maintenance?format=${format}&${q}`);
      const url = URL.createObjectURL(blob);
      if (format === 'html') {
        window.open(url, '_blank', 'noopener');
      } else {
        const a = document.createElement('a');
        a.href = url;
        a.download = `rapport-maintenance-${new Date().toISOString().slice(0, 10)}.csv`;
        a.click();
      }
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Rapport indisponible');
    }
  }

  get global(): Indicator {
    return this.data().global ?? {};
  }

  get machines(): MachineIndicator[] {
    return this.data().machines ?? [];
  }

  get maxArret(): number {
    return Math.max(1, ...this.pannes().map((p) => p.tempsArretH));
  }

  percent(value: number | null | undefined): string {
    return value === null || value === undefined ? '—' : `${(value * 100).toFixed(1)} %`;
  }

  number(value: number | null | undefined): string {
    return value === null || value === undefined ? '—' : value.toLocaleString('fr-FR');
  }

  money(value: number | null | undefined): string {
    return value === null || value === undefined ? '—' : value.toLocaleString('fr-FR', { maximumFractionDigits: 0 });
  }

  date(value: string | undefined): string {
    return value
      ? new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
      : '—';
  }

  label(p: PannesPoint): string {
    const d = new Date(p.periode);
    return this.grain === 'month'
      ? new Intl.DateTimeFormat('fr-FR', { month: 'short', year: 'numeric' }).format(d)
      : `Sem. du ${new Intl.DateTimeFormat('fr-FR', { day: '2-digit', month: '2-digit' }).format(d)}`;
  }

  riskLabel(niveau: Prediction['niveau']): string {
    return { ELEVE: 'Risque élevé', MOYEN: 'Risque moyen', FAIBLE: 'Risque faible', INCONNU: 'Historique insuffisant' }[niveau];
  }

  statusLabel(status: string): string {
    const labels: Record<string, string> = {
      NORMAL: 'Normales',
      ALERTE: 'En alerte',
      PANNE: 'En panne',
      EN_MAINTENANCE: 'En maintenance',
      SANS_DONNEES: 'Sans données',
    };
    return labels[status] ?? status;
  }

  statusSummary(): string {
    const states = this.dashboard().machines?.parEtat ?? {};
    return Object.entries(states)
      .map(([status, count]) => `${this.statusLabel(status)} : ${count}`)
      .join(' · ') || 'Aucun état disponible';
  }
}
