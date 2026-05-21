import { Component, OnInit, Output, Input, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ProductService, Producto } from '../../services/product.service';
 
@Component({
  selector: 'app-catalogo',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="catalogo">
      <div class="section-header">
        <div class="section-label">CATÁLOGO · {{ productos.length }} productos</div>
        <div class="source-tag" [class.redis]="source === 'redis'" [class.pg]="source === 'postgresql'" *ngIf="source">
          <span class="source-dot"></span>
          {{ source === 'redis' ? 'Redis cache' : 'PostgreSQL' }}
          <span class="ttl" *ngIf="ttl">· TTL {{ ttl }}s</span>
        </div>
      </div>
 
      <div class="hint" *ngIf="selectedIds.length < 3 && !loading">
        Selecciona hasta 3 productos para comparar
        <span *ngIf="selectedIds.length > 0"> · {{ selectedIds.length }}/3 seleccionados</span>
      </div>
      <div class="hint hint-ready" *ngIf="selectedIds.length === 3">
        ✓ 3 productos seleccionados — ve al comparador
      </div>
 
      <div class="loading" *ngIf="loading">
        <div class="spinner"></div>
        Cargando catálogo...
      </div>
 
      <div class="error" *ngIf="error">
        ⚠ {{ error }}
        <button (click)="load()">Reintentar</button>
      </div>
 
      <div class="grid" *ngIf="!loading && !error">
        <div
          class="card"
          *ngFor="let p of productos"
          [class.selected]="isSelected(p.id)"
          [class.disabled]="selectedIds.length >= 3 && !isSelected(p.id)"
          (click)="toggle(p)"
        >
          <div class="card-id">ID · {{ p.id }}</div>
          <div class="card-name">{{ p.nombre }}</div>
          <div class="card-price">\${{ formatPrice(p.precio) }}</div>
          <div class="card-check" *ngIf="isSelected(p.id)">✓</div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .catalogo {
      --accent: #84cc16;
      --accent2: #22d3ee;
    }
 
    .section-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 16px;
    }
 
    .section-label {
      font-size: 0.65rem;
      letter-spacing: 0.2em;
      color: #5a5c72;
    }
 
    .source-tag {
      font-size: 0.65rem;
      letter-spacing: 0.1em;
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 100px;
      border: 1px solid #1c1e2a;
    }
 
    .source-tag.redis { color: #22d3ee; border-color: rgba(34,211,238,0.2); }
    .source-tag.pg { color: #a78bfa; border-color: rgba(167,139,250,0.2); }
 
    .source-dot {
      width: 5px;
      height: 5px;
      border-radius: 50%;
      background: currentColor;
    }
 
    .hint {
      font-size: 0.72rem;
      color: #5a5c72;
      margin-bottom: 20px;
      letter-spacing: 0.05em;
    }
 
    .hint-ready { color: var(--accent); }
 
    .loading {
      display: flex;
      align-items: center;
      gap: 12px;
      color: #5a5c72;
      font-size: 0.8rem;
      padding: 40px 0;
    }
 
    .spinner {
      width: 16px;
      height: 16px;
      border: 2px solid #1c1e2a;
      border-top-color: var(--accent);
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
 
    @keyframes spin { to { transform: rotate(360deg); } }
 
    .error {
      color: #f87171;
      font-size: 0.8rem;
      padding: 20px;
      background: rgba(248,113,113,0.05);
      border: 1px solid rgba(248,113,113,0.2);
      border-radius: 8px;
      display: flex;
      align-items: center;
      gap: 12px;
    }
 
    .error button {
      background: none;
      border: 1px solid rgba(248,113,113,0.4);
      color: #f87171;
      font-family: inherit;
      font-size: 0.72rem;
      padding: 4px 10px;
      border-radius: 4px;
      cursor: pointer;
    }
 
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 2px;
    }
 
    .card {
      background: #0f1017;
      border: 1px solid #1c1e2a;
      border-radius: 10px;
      padding: 18px;
      cursor: pointer;
      transition: all 0.15s;
      position: relative;
      overflow: hidden;
    }
 
    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 1px;
      background: transparent;
      transition: background 0.15s;
    }
 
    .card:hover:not(.disabled) {
      border-color: rgba(132,204,22,0.3);
      background: #12141c;
    }
 
    .card:hover:not(.disabled)::before {
      background: var(--accent);
    }
 
    .card.selected {
      border-color: var(--accent);
      background: rgba(132,204,22,0.06);
    }
 
    .card.selected::before {
      background: var(--accent);
    }
 
    .card.disabled {
      opacity: 0.35;
      cursor: not-allowed;
    }
 
    .card-id {
      font-size: 0.6rem;
      color: #5a5c72;
      letter-spacing: 0.15em;
      margin-bottom: 8px;
    }
 
    .card-name {
      font-size: 0.85rem;
      font-weight: 700;
      line-height: 1.3;
      margin-bottom: 12px;
      color: #e8eaf2;
    }
 
    .card-price {
      font-size: 1.1rem;
      color: var(--accent);
      font-weight: 700;
      letter-spacing: -0.02em;
    }
 
    .card-check {
      position: absolute;
      top: 10px;
      right: 10px;
      width: 20px;
      height: 20px;
      background: var(--accent);
      color: #000;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.65rem;
      font-weight: 900;
    }
  `]
})
export class CatalogoComponent implements OnInit {
  @Input() selectedIds: number[] = [];
  @Output() selectionChange = new EventEmitter<number[]>();
 
  productos: Producto[] = [];
  loading = true;
  error = '';
  source = '';
  ttl: number | null = null;
 
  constructor(private svc: ProductService) {}
 
  ngOnInit() { this.load(); }
 
  load() {
    this.loading = true;
    this.error = '';
    this.svc.getProducts().subscribe({
      next: (r) => {
        this.productos = r.data;
        this.source = r.source;
        this.ttl = r.ttl_seconds;
        this.loading = false;
      },
      error: (e) => {
        this.error = e.message || 'Error al conectar con el backend';
        this.loading = false;
      }
    });
  }
 
  isSelected(id: number): boolean {
    return this.selectedIds.includes(id);
  }
 
  toggle(p: Producto) {
    if (this.isSelected(p.id)) {
      this.selectionChange.emit(this.selectedIds.filter(id => id !== p.id));
    } else if (this.selectedIds.length < 3) {
      this.selectionChange.emit([...this.selectedIds, p.id]);
    }
  }
 
  formatPrice(precio: string): string {
    return Number(precio).toLocaleString('es-MX', { minimumFractionDigits: 2 });
  }
}
