import { Component, inject, signal } from '@angular/core';
import { ApiService } from '../../core/services/api.service';
import { Order } from '../../models/director.models';
@Component({selector:'app-ordres',standalone:true,templateUrl:'./ordres.view.html',styleUrl:'../machines/machines.view.css'})
export class OrdresView {private readonly api=inject(ApiService); readonly orders=signal<Order[]>([]); error=signal(''); loading=signal(true); constructor(){void this.load();} async load():Promise<void>{try{this.orders.set(await this.api.get<Order[]>('/ordres-fabrication'));}catch(e){this.error.set(e instanceof Error?e.message:'Chargement impossible');}finally{this.loading.set(false);}}}
