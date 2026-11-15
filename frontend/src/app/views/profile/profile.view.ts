import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';
import { ROLE_LABELS } from '../../models/director.models';

@Component({
  selector: 'app-profile',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './profile.view.html',
  styleUrl: './profile.view.css',
})
export class ProfileView {
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly roleLabels = ROLE_LABELS;
  ancienMotDePasse = '';
  nouveauMotDePasse = '';
  confirmation = '';
  readonly message = signal('');
  readonly error = signal('');
  loading = false;
  telephone = '';
  profileMessage = signal('');
  profileError = signal('');

  constructor() {
    void this.loadProfile();
  }

  private async loadProfile(): Promise<void> {
    await this.auth.loadProfile();
    this.telephone = this.auth.user()?.telephone ?? '';
  }

  async saveTelephone(): Promise<void> {
    this.profileMessage.set('');
    this.profileError.set('');
    try {
      await this.auth.updateProfile(this.telephone);
      this.telephone = this.auth.user()?.telephone ?? '';
      this.profileMessage.set('Votre numéro de téléphone a été enregistré.');
    } catch (error) {
      this.profileError.set(error instanceof Error ? error.message : 'Impossible d’enregistrer le numéro.');
    }
  }

  async changePassword(): Promise<void> {
    this.message.set('');
    this.error.set('');
    if (this.nouveauMotDePasse !== this.confirmation) {
      this.error.set('La confirmation du mot de passe ne correspond pas.');
      return;
    }
    const passwordChecks = [
      [this.nouveauMotDePasse.length >= 10, 'Le nouveau mot de passe doit contenir au moins 10 caractères.'],
      [/[a-z]/.test(this.nouveauMotDePasse), 'Ajoutez au moins une lettre minuscule.'],
      [/[A-Z]/.test(this.nouveauMotDePasse), 'Ajoutez au moins une lettre majuscule.'],
      [/[0-9]/.test(this.nouveauMotDePasse), 'Ajoutez au moins un chiffre.'],
    ];
    const failedCheck = passwordChecks.find(([valid]) => !valid);
    if (failedCheck) {
      this.error.set(failedCheck[1] as string);
      return;
    }
    this.loading = true;
    const firstLogin = this.auth.mustChangePassword;
    try {
      await this.auth.changePassword(this.ancienMotDePasse, this.nouveauMotDePasse);
      this.message.set('Votre mot de passe a été modifié avec succès. Vos autres appareils ont été déconnectés.');
      this.ancienMotDePasse = '';
      this.nouveauMotDePasse = '';
      this.confirmation = '';
      if (firstLogin) await this.router.navigateByUrl('/');
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      this.error.set(message === 'Ancien mot de passe incorrect'
        ? 'Le mot de passe actuel est incorrect.'
        : message || 'Impossible de modifier le mot de passe.');
    } finally {
      this.loading = false;
    }
  }
}
