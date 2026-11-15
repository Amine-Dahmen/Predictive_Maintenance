import { Injectable, computed, effect, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { ApiService } from './api.service';
import { Role, User } from '../../models/director.models';

interface SessionResponse {
  accessToken: string;
  refreshToken: string;
  utilisateur: User;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(ApiService);
  private readonly router = inject(Router);
  readonly user = signal<User | null>(null);
  readonly authenticated = signal(Boolean(localStorage.getItem('accessToken')));
  readonly role = computed(() => this.user()?.role ?? null);
  private profileLoad: Promise<void> | null = null;

  constructor() {
    // Session impossible à renouveler (refresh token expiré ou révoqué) : retour à la connexion
    effect(() => {
      if (this.api.sessionExpired()) this.endSession();
    });
  }

  get isAuthenticated(): boolean {
    return Boolean(this.api.accessToken);
  }

  hasRole(...roles: Role[]): boolean {
    const role = this.role();
    return role !== null && roles.includes(role);
  }

  // Un compte créé avec un mot de passe provisoire doit le changer avant tout (403 CHANGEMENT_MDP_REQUIS sinon)
  get mustChangePassword(): boolean {
    return Boolean(this.user()?.doitChangerMotDePasse);
  }

  async login(email: string, motDePasse: string): Promise<User> {
    const result = await this.api.post<SessionResponse>('/auth/login', { email, motDePasse });
    this.api.setTokens(result);
    this.user.set(result.utilisateur);
    this.authenticated.set(true);
    return result.utilisateur;
  }

  // Charge le profil une seule fois (utilisé par les guards avant d'afficher une page)
  ensureProfile(): Promise<void> {
    if (this.user() || !this.isAuthenticated) return Promise.resolve();
    this.profileLoad ??= this.loadProfile().finally(() => (this.profileLoad = null));
    return this.profileLoad;
  }

  async loadProfile(): Promise<void> {
    if (!this.isAuthenticated) return;
    try {
      this.user.set(await this.api.get<User>('/auth/me'));
    } catch {
      this.endSession();
    }
  }

  // Le backend renvoie une nouvelle paire de jetons (les autres appareils sont déconnectés)
  async changePassword(ancienMotDePasse: string, nouveauMotDePasse: string): Promise<void> {
    const result = await this.api.post<SessionResponse>('/auth/change-password', { ancienMotDePasse, nouveauMotDePasse });
    this.api.setTokens(result);
    this.user.set(result.utilisateur);
  }

  async updateProfile(telephone: string): Promise<void> {
    this.user.set(await this.api.patch<User>('/auth/me', { telephone }));
  }

  logout(): void {
    const refreshToken = localStorage.getItem('refreshToken');
    if (refreshToken) void this.api.post('/auth/logout', { refreshToken }).catch(() => undefined);
    this.endSession();
  }

  private endSession(): void {
    this.api.clearTokens();
    this.user.set(null);
    this.authenticated.set(false);
    void this.router.navigateByUrl('/login');
  }
}
