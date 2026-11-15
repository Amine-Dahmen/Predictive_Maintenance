import { Routes } from '@angular/router';
import { LoginView } from './views/login/login.view';
import { DashboardView } from './views/dashboard/dashboard.view';
import { MachinesView } from './views/machines/machines.view';
import { AlertsView } from './views/alerts/alerts.view';
import { ResponsablesView } from './views/responsables/responsables.view';
import { OrdresView } from './views/ordres/ordres.view';
import { IndicateursView } from './views/indicateurs/indicateurs.view';
import { InterventionsView } from './views/interventions/interventions.view';
import { authGuard, guestGuard } from './core/guards/auth.guard';
import { ProfileView } from './views/profile/profile.view';
import { NotificationsView } from './views/notifications/notifications.view';

// data.roles : rôles autorisés (mêmes règles que l'API). Sans data.roles, la page est ouverte à tous les rôles.
export const routes: Routes = [
  { path: 'login', component: LoginView, canActivate: [guestGuard] },
  { path: '', component: DashboardView, canActivate: [authGuard] },
  { path: 'machines', component: MachinesView, canActivate: [authGuard] },
  { path: 'alertes', component: AlertsView, canActivate: [authGuard] },
  { path: 'interventions', component: InterventionsView, canActivate: [authGuard] },
  { path: 'responsables', component: ResponsablesView, canActivate: [authGuard], data: { roles: ['DIRECTEUR'] } },
  { path: 'ordres-fabrication', component: OrdresView, canActivate: [authGuard], data: { roles: ['DIRECTEUR', 'RESPONSABLE'] } },
  { path: 'indicateurs', component: IndicateursView, canActivate: [authGuard], data: { roles: ['DIRECTEUR', 'RESPONSABLE'] } },
  { path: 'notifications', component: NotificationsView, canActivate: [authGuard], data: { roles: ['DIRECTEUR'] } },
  { path: 'profil', component: ProfileView, canActivate: [authGuard] },
  { path: '**', redirectTo: '' },
];
