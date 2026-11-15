import { inject } from '@angular/core';
import { ActivatedRouteSnapshot, CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { Role } from '../../models/director.models';

// Page réservée aux utilisateurs connectés. Les rôles autorisés se déclarent dans la route : data: { roles: [...] }.
// Tant que le mot de passe provisoire n'est pas changé, seule la page profil est accessible.
export const authGuard: CanActivateFn = async (route: ActivatedRouteSnapshot) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (!auth.isAuthenticated) return router.createUrlTree(['/login']);
  await auth.ensureProfile();
  if (!auth.user()) return router.createUrlTree(['/login']);
  if (auth.mustChangePassword && route.routeConfig?.path !== 'profil') return router.createUrlTree(['/profil']);
  const roles = route.data['roles'] as Role[] | undefined;
  if (roles && !auth.hasRole(...roles)) return router.createUrlTree(['/']);
  return true;
};

export const guestGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  if (!auth.isAuthenticated) return true;
  return inject(Router).createUrlTree(['/']);
};
