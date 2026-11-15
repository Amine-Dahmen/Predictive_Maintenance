import { Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { RealtimeService } from '../../core/services/realtime.service';
import {
  Machine, MachineState, SENSOR_LABELS, SENSOR_TYPES, STATE_LABELS, SensorType, Threshold,
} from '../../models/director.models';

interface MeasureEvent { machineId: number; capteurId: number; valeur: number; horodatage: string }
interface StateEvent { machineId: number; etat: MachineState }
interface SensorStateEvent { machineId: number; capteurId?: number; enLigne: boolean }

@Component({
  selector: 'app-machines',
  standalone: true,
  imports: [FormsModule, DatePipe],
  templateUrl: './machines.view.html',
  styleUrl: './machines.view.css',
})
export class MachinesView {
  private readonly api = inject(ApiService);
  private readonly realtime = inject(RealtimeService);
  protected readonly auth = inject(AuthService);
  protected readonly stateLabels = STATE_LABELS;
  protected readonly sensorLabels = SENSOR_LABELS;
  protected readonly sensorTypes = SENSOR_TYPES;

  readonly machines = signal<Machine[]>([]);
  readonly selected = signal<Machine | null>(null);
  readonly loading = signal(true);
  readonly error = signal('');
  readonly notice = signal('');
  query = '';

  // Le responsable de maintenance déclare les machines et les capteurs (US-23)
  readonly canManage = computed(() => this.auth.hasRole('RESPONSABLE'));
  readonly showMachineForm = signal(false);
  machineForm = { code: '', nom: '', emplacement: '', kitPredimaint: true };
  sensorForm: { type: SensorType; identifiant: string; unite: string } = { type: 'COURANT', identifiant: '', unite: '' };
  readonly saving = signal(false);

  constructor() {
    void this.load();
    const destroyRef = inject(DestroyRef);
    // Mises à jour en direct : nouvelles mesures, état des machines, capteurs en / hors ligne
    this.realtime.on<MeasureEvent>('mesure.recue').pipe(takeUntilDestroyed(destroyRef)).subscribe((e) => {
      this.patchSelected(e.machineId, (m) => ({
        ...m,
        capteurs: m.capteurs?.map((c) => c.id === e.capteurId
          ? { ...c, derniereValeur: e.valeur, derniereMesureAt: e.horodatage, enLigne: true } : c),
      }));
    });
    this.realtime.on<StateEvent>('machine.etat').pipe(takeUntilDestroyed(destroyRef)).subscribe((e) => {
      this.machines.update((list) => list.map((m) => (m.id === e.machineId ? { ...m, etat: e.etat } : m)));
      this.patchSelected(e.machineId, (m) => ({ ...m, etat: e.etat }));
    });
    this.realtime.on<SensorStateEvent>('capteur.etat').pipe(takeUntilDestroyed(destroyRef)).subscribe((e) => {
      this.patchSelected(e.machineId, (m) => ({
        ...m,
        capteurs: m.capteurs?.map((c) => (e.capteurId === undefined || c.id === e.capteurId ? { ...c, enLigne: e.enLigne } : c)),
      }));
    });
  }

  async load(): Promise<void> {
    try {
      this.machines.set(await this.api.get<Machine[]>('/machines'));
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Chargement impossible');
    } finally {
      this.loading.set(false);
    }
  }

  get filtered(): Machine[] {
    const q = this.query.toLowerCase();
    return this.machines().filter((m) => `${m.nom} ${m.code} ${m.emplacement ?? ''}`.toLowerCase().includes(q));
  }

  async select(m: Machine): Promise<void> {
    this.error.set('');
    try {
      this.selected.set(await this.api.get<Machine>(`/machines/${m.id}`));
      this.resetSensorForm();
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Chargement impossible');
    }
  }

  close(): void {
    this.selected.set(null);
  }

  threshold(type: SensorType): Threshold | undefined {
    return this.selected()?.seuils?.find((s) => s.typeMesure === type);
  }

  // Niveau de la dernière valeur par rapport aux seuils : colore la carte du capteur
  level(type: SensorType, value: number | null | undefined): '' | 'alerte' | 'panne' {
    const s = this.threshold(type);
    if (!s || value === null || value === undefined) return '';
    if (value >= s.seuilCritique) return 'panne';
    if (value >= s.seuilAlerte) return 'alerte';
    return '';
  }

  async createMachine(): Promise<void> {
    if (this.saving()) return;
    this.saving.set(true);
    this.error.set('');
    this.notice.set('');
    try {
      const { code, nom, emplacement, kitPredimaint } = this.machineForm;
      const created = await this.api.post<Machine>('/machines', {
        code, nom, ...(emplacement ? { emplacement } : {}), kitPredimaint,
      });
      this.notice.set(`Machine ${created.code} créée. Créez son compte MQTT sur le broker (utilisateur « ${created.code} ») puis renseignez MACHINE_CODE = "${created.code}" dans la carte ESP32.`);
      this.machineForm = { code: '', nom: '', emplacement: '', kitPredimaint: true };
      this.showMachineForm.set(false);
      await this.load();
      await this.select(created);
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Création impossible');
    } finally {
      this.saving.set(false);
    }
  }

  resetSensorForm(): void {
    const code = this.selected()?.code ?? '';
    const used = new Set(this.selected()?.capteurs?.map((c) => c.type));
    const type = this.sensorTypes.find((t) => !used.has(t)) ?? 'COURANT';
    this.sensorForm = { type, identifiant: `${code}-${type}`, unite: '' };
  }

  onSensorTypeChange(): void {
    this.sensorForm.identifiant = `${this.selected()?.code ?? ''}-${this.sensorForm.type}`;
  }

  async addSensor(): Promise<void> {
    const machine = this.selected();
    if (!machine || this.saving()) return;
    this.saving.set(true);
    this.error.set('');
    try {
      const { type, identifiant, unite } = this.sensorForm;
      await this.api.post(`/machines/${machine.id}/capteurs`, { type, identifiant, ...(unite ? { unite } : {}) });
      await this.select(machine);
      await this.load();
    } catch (e) {
      this.error.set(e instanceof Error ? e.message : 'Ajout impossible');
    } finally {
      this.saving.set(false);
    }
  }

  value(v: number | null | undefined): string {
    return v === null || v === undefined ? '—' : v.toLocaleString('fr-FR', { maximumFractionDigits: 2 });
  }

  private patchSelected(machineId: number, fn: (m: Machine) => Machine): void {
    const current = this.selected();
    if (current && current.id === machineId) this.selected.set(fn(current));
  }
}
