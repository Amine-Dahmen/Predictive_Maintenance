import { TestBed } from '@angular/core/testing';
import { IndicateursView } from './indicateurs.view';
import { ApiService } from '../../core/services/api.service';
import { AuthService } from '../../core/services/auth.service';
import { installMemoryStorage } from '../../../test-storage';

describe('IndicateursView (US-15 / US-16 / US-34)', () => {
  const calls: Array<{ method: string; path: string; body?: unknown }> = [];
  const api = {
    get: async (path: string) => {
      calls.push({ method: 'GET', path });
      if (path.startsWith('/indicateurs/pannes')) return { series: [{ periode: '2026-11-02T00:00:00Z', nbPannes: 2, tempsArretH: 4, dureeMoyenneH: 2, coutArret: 480 }] };
      if (path.startsWith('/indicateurs/dashboard')) return { topArrets: [{ machineId: 1, code: 'M01', nom: 'Presse', tempsArretH: 4, nbPannes: 2, coutArret: 480 }] };
      if (path.startsWith('/indicateurs')) return { global: { disponibilite: 0.95, coutArret: 480 }, machines: [{ machineId: 1, code: 'M01', nom: 'Presse', nbPannes: 2, coutArret: 480 }] };
      if (path === '/predictions') return [{ machineId: 1, code: 'M01', nom: 'Presse', probabilite: 0.27, niveau: 'ELEVE', facteurs: [{ canal: 'vibration', ecart: 2.4, libelle: 'Vibration 2.4 écart(s)-type(s) au-dessus de l’habitude' }], modele: 't', createdAt: '2026-11-12T10:00:00Z' }];
      return [{ id: 1, coutHoraireArret: 120 }];
    },
    patch: async (path: string, body: unknown) => { calls.push({ method: 'PATCH', path, body }); return {}; },
  };

  beforeEach(async () => {
    installMemoryStorage();
    calls.length = 0;
    await TestBed.configureTestingModule({
      imports: [IndicateursView],
      providers: [
        { provide: ApiService, useValue: api },
        { provide: AuthService, useValue: { role: () => 'DIRECTEUR' } },
      ],
    }).compileComponents();
  });

  it('charge les indicateurs, les pannes et les coûts horaires de la période', async () => {
    const fixture = TestBed.createComponent(IndicateursView);
    await fixture.componentInstance.load();
    fixture.detectChanges();
    const view = fixture.componentInstance;
    expect(view.couts()[1]).toBe(120);
    expect(view.pannes().length).toBe(1);
    expect(calls.some((c) => c.path.includes('/indicateurs/pannes') && c.path.includes('grain=week'))).toBe(true);
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('95.0 %');
    expect(text).toContain('2 panne(s)');
    await new Promise((r) => setTimeout(r));
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('Risque élevé'); // US-22
  });

  it('enregistre le coût horaire d’arrêt et refuse une valeur négative', async () => {
    const view = TestBed.createComponent(IndicateursView).componentInstance;
    const machine = { machineId: 1, code: 'M01', nom: 'Presse' };
    await view.saveCost(machine, '150');
    expect(calls.find((c) => c.method === 'PATCH')).toEqual({ method: 'PATCH', path: '/machines/1/cout', body: { coutHoraireArret: 150 } });
    calls.length = 0;
    await view.saveCost(machine, '-3');
    expect(calls.some((c) => c.method === 'PATCH')).toBe(false);
    expect(view.error()).toContain('invalide');
  });
});
