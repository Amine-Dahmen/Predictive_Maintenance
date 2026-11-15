import { Component, computed, effect, inject } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from './core/services/auth.service';
import { RealtimeService } from './core/services/realtime.service';
import { ROLE_LABELS, Role } from './models/director.models';

interface NavItem {
  path: string;
  label: string;
  icon: string;
  roles: Role[];
  exact?: boolean;
}

const ALL: Role[] = ['DIRECTEUR', 'RESPONSABLE', 'TECHNICIEN'];

const NAV: NavItem[] = [
  { path: '/', label: 'Vue d’ensemble', icon: '⌂', roles: ALL, exact: true },
  { path: '/machines', label: 'Machines', icon: '▦', roles: ALL },
  { path: '/alertes', label: 'Alertes', icon: '!', roles: ALL },
  { path: '/interventions', label: 'Interventions', icon: '⚒', roles: ALL },
  { path: '/responsables', label: 'Chefs de production', icon: '♙', roles: ['DIRECTEUR'] },
  { path: '/ordres-fabrication', label: 'Ordres de fabrication', icon: '▤', roles: ['DIRECTEUR', 'RESPONSABLE'] },
  { path: '/indicateurs', label: 'Indicateurs', icon: '⌁', roles: ['DIRECTEUR', 'RESPONSABLE'] },
  { path: '/notifications', label: 'Notifications', icon: '✉', roles: ['DIRECTEUR'] },
];

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  protected readonly auth = inject(AuthService);
  protected readonly realtime = inject(RealtimeService);

  protected readonly nav = computed(() => {
    const role = this.auth.role();
    return role ? NAV.filter((item) => item.roles.includes(role)) : [];
  });
  protected readonly roleLabel = computed(() => {
    const role = this.auth.role();
    return role ? ROLE_LABELS[role] : '';
  });
  protected readonly workspace = computed(() => {
    const role = this.auth.role();
    return role === 'DIRECTEUR' ? 'directeur' : role === 'RESPONSABLE' ? 'maintenance' : role === 'TECHNICIEN' ? 'technicien' : '';
  });

  constructor() {
    void this.auth.ensureProfile();
    // Le flux temps réel est ouvert tant qu'un utilisateur est connecté (et a changé son mot de passe provisoire)
    const streamUser = computed(() => {
      const user = this.auth.user();
      return user && !user.doitChangerMotDePasse ? user.id : null;
    });
    effect(() => {
      if (streamUser() !== null) this.realtime.connect();
      else this.realtime.disconnect();
    });
  }

  get authenticated(): boolean { return this.auth.authenticated(); }
  logout(): void { this.auth.logout(); }
}
