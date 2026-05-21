import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';
 
export interface Producto {
  id: number;
  nombre: string;
  precio: string;
}
 
export interface ProductosResponse {
  source: 'redis' | 'postgresql';
  ttl_seconds: number;
  data: Producto[];
}
 
export interface ComparacionData {
  requested_ids: number[];
  count: number;
  cheapest: Producto;
  most_expensive: Producto;
  price_difference: number;
  products: Producto[];
}
 
export interface ComparacionResponse {
  source: 'redis' | 'postgresql';
  ttl_seconds: number;
  data: ComparacionData;
}
 
@Injectable({ providedIn: 'root' })
export class ProductService {
  private api = environment.apiUrl;
 
  constructor(private http: HttpClient) {}
 
  getProducts(): Observable<ProductosResponse> {
    return this.http.get<ProductosResponse>(`${this.api}/api/products`);
  }
 
  compare(ids: number[]): Observable<ComparacionResponse> {
    return this.http.post<ComparacionResponse>(`${this.api}/api/compare`, { ids });
  }
}
