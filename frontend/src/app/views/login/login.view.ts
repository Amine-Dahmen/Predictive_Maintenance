import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({ selector:'app-login', standalone:true, imports:[FormsModule], templateUrl:'./login.view.html', styleUrl:'./login.view.css' })
export class LoginView {
  private readonly auth=inject(AuthService);
  private readonly router=inject(Router);
  email = '';
  motDePasse = '';
  readonly error = signal('');
  loading = false;
  async login(): Promise<void> {
    this.loading = true;
    this.error.set('');
    try {
      const user = await this.auth.login(this.email, this.motDePasse);
      // Premier login avec un mot de passe provisoire : changement obligatoire avant d'accéder à l'application
      await this.router.navigateByUrl(user.doitChangerMotDePasse ? '/profil' : '/');
    } catch {
      this.error.set('Adresse e-mail ou mot de passe incorrect.');
    } finally {
      this.loading = false;
    }
  }
}
