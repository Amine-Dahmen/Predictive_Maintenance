import { Component, inject, signal } from '@angular/core';
import { ApiService } from '../../core/services/api.service';
@Component({selector:'app-interventions',standalone:true,templateUrl:'./interventions.view.html',styleUrl:'../machines/machines.view.css'})
export class InterventionsView {private readonly api=inject(ApiService); readonly interventions=signal<Record<string,unknown>[]>([]); error=signal(''); constructor(){void this.load();} async load():Promise<void>{try{this.interventions.set(await this.api.get<Record<string,unknown>[]>('/interventions'));}catch(e){this.error.set(e instanceof Error?e.message:'Chargement impossible');}}}
