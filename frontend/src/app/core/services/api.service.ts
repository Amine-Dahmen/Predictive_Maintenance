import { Injectable, signal } from '@angular/core';

export interface ApiError {
  erreur?: {
    code?: string;
    message?: string;
    details?: Array<{ champ?: string; message?: string }>;
  };
}

interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

// Adresse de l'API : même machine que le front, port 3000 (fonctionne aussi depuis un autre PC du réseau).
// Pour une autre adresse, définir window.PREDIMAINT_API_URL dans index.html.
function defaultApiUrl(): string {
  const custom = (window as unknown as { PREDIMAINT_API_URL?: string }).PREDIMAINT_API_URL;
  return custom ?? `${location.protocol}//${location.hostname}:3000/api`;
}

@Injectable({ providedIn: 'root' })
export class ApiService {
  readonly apiUrl = defaultApiUrl();
  // Passe à true quand la session ne peut plus être renouvelée : l'application renvoie vers /login
  readonly sessionExpired = signal(false);
  private refreshing: Promise<boolean> | null = null;

  get accessToken(): string | null {
    return localStorage.getItem('accessToken');
  }

  setTokens({ accessToken, refreshToken }: TokenPair): void {
    localStorage.setItem('accessToken', accessToken);
    localStorage.setItem('refreshToken', refreshToken);
    this.sessionExpired.set(false);
  }

  clearTokens(): void {
    localStorage.removeItem('accessToken');
    localStorage.removeItem('refreshToken');
  }

  async request<T>(path: string, options: RequestInit = {}, retry = true): Promise<T> {
    const token = this.accessToken;
    const headers = new Headers(options.headers);
    headers.set('Content-Type', 'application/json');
    if (token) headers.set('Authorization', `Bearer ${token}`);
    const response = await fetch(`${this.apiUrl}${path}`, { ...options, headers });
    const data = (await response.json().catch(() => ({}))) as T & ApiError;
    if (!response.ok) {
      // Jeton d'accès expiré (15 min) : on le renouvelle une fois avec le refresh token puis on rejoue la requête
      if (response.status === 401 && data.erreur?.code === 'JETON_EXPIRE' && retry && (await this.refresh())) {
        return this.request<T>(path, options, false);
      }
      if (response.status === 401 && token && !path.startsWith('/auth/login')) {
        this.clearTokens();
        this.sessionExpired.set(true);
      }
      const details = data.erreur?.details
        ?.map((detail) => detail.message)
        .filter((message): message is string => Boolean(message));
      const message = details?.length
        ? details.join(' ')
        : data.erreur?.message ?? 'Une erreur serveur est survenue.';
      throw new Error(message);
    }
    return data;
  }

  // Rotation du refresh token (POST /auth/refresh). Plusieurs requêtes simultanées partagent le même appel.
  refresh(): Promise<boolean> {
    this.refreshing ??= (async () => {
      const refreshToken = localStorage.getItem('refreshToken');
      if (!refreshToken) return false;
      try {
        const response = await fetch(`${this.apiUrl}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
        });
        if (!response.ok) return false;
        this.setTokens((await response.json()) as TokenPair);
        return true;
      } catch {
        return false;
      }
    })().finally(() => (this.refreshing = null));
    return this.refreshing;
  }

  // Fichier protégé par le JWT (rapport CSV / HTML) : récupéré en Blob avec l'en-tête Authorization
  async blob(path: string, retry = true): Promise<Blob> {
    const headers = new Headers();
    if (this.accessToken) headers.set('Authorization', `Bearer ${this.accessToken}`);
    const response = await fetch(`${this.apiUrl}${path}`, { headers });
    if (response.status === 401 && retry && (await this.refresh())) return this.blob(path, false);
    if (!response.ok) throw new Error('Téléchargement impossible.');
    return response.blob();
  }

  get<T>(path: string): Promise<T> { return this.request<T>(path); }
  post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: 'POST', body: JSON.stringify(body) });
  }
  patch<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PATCH', body: JSON.stringify(body) });
  }
  put<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>(path, { method: 'PUT', body: JSON.stringify(body) });
  }
}
