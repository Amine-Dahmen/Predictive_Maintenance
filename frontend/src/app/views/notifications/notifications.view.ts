import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';

interface Canal { canal: 'APP' | 'EMAIL'; actif: boolean; niveauMin: 'ALERTE' | 'CRITIQUE'; destinataires: string | null; updatedAt: string }

const LIBELLES: Record<Canal['canal'], { titre: string; aide: string }> = {
  APP: { titre: 'Application (web et mobile)', aide: 'Notification affichée aux utilisateurs connectés quand une alerte est déclenchée.' },
  EMAIL: { titre: 'E-mail', aide: 'Envoyé aux responsables de maintenance actifs et aux destinataires ci-dessous.' },
};

// US-38 : canaux de notification des alertes (administration)
@Component({
  selector: 'app-notifications',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './notifications.view.html',
  styleUrl: '../indicateurs/indicateurs.view.css',
})
export class NotificationsView {
  private readonly api = inject(ApiService);
  readonly canaux = signal<Canal[]>([]);
  readonly error = signal('');
  readonly message = signal('');
  readonly libelles = LIBELLES;

  constructor() { void this.load(); }

  async load(): Promise<void> {
    try { this.canaux.set(await this.api.get<Canal[]>('/notifications/canaux')); }
    catch (e) { this.error.set(e instanceof Error ? e.message : 'Chargement impossible'); }
  }

  async save(c: Canal): Promise<void> {
    this.error.set(''); this.message.set('');
    try {
      const body: Partial<Canal> = { actif: c.actif, niveauMin: c.niveauMin };
      if (c.canal === 'EMAIL') body.destinataires = c.destinataires?.trim() || null;
      await this.api.put(`/notifications/canaux/${c.canal}`, body);
      this.message.set(`Canal « ${LIBELLES[c.canal].titre} » enregistré.`);
      await this.load();
    } catch (e) { this.error.set(e instanceof Error ? e.message : 'Enregistrement impossible'); }
  }
}
