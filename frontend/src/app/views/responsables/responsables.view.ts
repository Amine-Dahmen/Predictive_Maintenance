import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../../core/services/api.service';
import { User } from '../../models/director.models';
@Component({selector:'app-responsables',standalone:true,imports:[FormsModule],templateUrl:'./responsables.view.html',styleUrl:'../machines/machines.view.css'})
export class ResponsablesView {
 private readonly api=inject(ApiService); readonly users=signal<User[]>([]); form={nom:'',prenom:'',email:'',telephone:''}; error=''; showForm=false; editing?:User; saving=false; loading=signal(true);
 // Mot de passe provisoire renvoyé une seule fois par l'API à la création (US-24)
 readonly created=signal<(User & { motDePasseProvisoire: string }) | null>(null); createdLabel='Compte créé pour';
 constructor(){void this.load();} async load():Promise<void>{this.loading.set(true);try{this.users.set(await this.api.get<User[]>('/responsables'));}catch(e){this.error=e instanceof Error?e.message:'Chargement impossible';}finally{this.loading.set(false);}}
 async create():Promise<void>{
  if(this.saving)return;
  this.saving=true;this.error='';
  try{this.createdLabel='Compte créé pour';this.created.set(await this.api.post<User & { motDePasseProvisoire: string }>('/responsables',this.form));this.form={nom:'',prenom:'',email:'',telephone:''};this.showForm=false;await this.load();}
  catch(e){this.error=e instanceof Error?e.message:'Création impossible';}
  finally{this.saving=false;}
 }
 edit(u:User):void{this.editing=u;this.form={nom:u.nom,prenom:u.prenom,email:u.email,telephone:u.telephone??''};this.showForm=true;}
 cancelEdit():void{this.editing=undefined;this.showForm=false;this.form={nom:'',prenom:'',email:'',telephone:''};}
 async save():Promise<void>{
  if(this.saving)return;
  if(!this.editing){await this.create();return;}
  this.saving=true;this.error='';
  try{await this.api.patch(`/responsables/${this.editing.id}`,this.form);this.cancelEdit();await this.load();}
  catch(e){this.error=e instanceof Error?e.message:'Modification impossible';}
  finally{this.saving=false;}
 }
 // US-35 : nouveau mot de passe provisoire ; toutes les sessions du compte sont fermées
 async resetPassword(u:User):Promise<void>{
  if(!confirm(`Réinitialiser le mot de passe de ${u.prenom} ${u.nom} ? Ses sessions ouvertes seront fermées.`))return;
  try{this.createdLabel='Mot de passe réinitialisé pour';this.created.set(await this.api.post<User & { motDePasseProvisoire: string }>(`/responsables/${u.id}/reinitialiser-mot-de-passe`,{}));}
  catch(e){this.error=e instanceof Error?e.message:'Réinitialisation impossible';}
 }
 async toggle(u:User):Promise<void>{try{await this.api.patch(`/responsables/${u.id}/statut`,{statut:u.statut==='ACTIF'?'DESACTIVE':'ACTIF'});await this.load();}catch(e){this.error=e instanceof Error?e.message:'Action impossible';}}
}
