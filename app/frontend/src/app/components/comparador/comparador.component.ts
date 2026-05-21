import { Component, Input, Output, EventEmitter, OnChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ProductService, ComparacionData, Producto } from '../../services/product.service';
 
@Component({
  selector: 'app-comparador',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="comparador">
      <div class="section-header">
        <div class="section-label">COMPARADOR DE HARDWARE</div>
        <button class="clear-btn" (click)="onClear()" *ngIf="selectedIds.length > 0">
          Limpiar selección
        </button>
      </div>
 
      <!-- Estado vacío -->
      <div class="empty" *ngIf="selectedIds.length === 0 && !result">
        <div class="empty-icon">⬡</div>
        <div class="empty-title">Sin productos seleccionados</div>
        <div class="empty-sub">Ve al catálogo y selecciona 2 o 3 productos para comparar</div>
      </div>
 
      <!-- Selección parcial -->
      <div class="partial" *ngIf="selectedIds.length > 0 && selectedIds.length < 2 && !loading">
        <div class="partial-label">Seleccionados: {{ selectedIds.length }}/2 mínimo</div>
        <div class="id-chips">
          <span class="chip" *ngFor="let id of selectedIds">ID {{ id }}</span>
        </div>
      </div>
 
      <!-- Botón comparar -->
      <div class="compare-row" *ngIf="selectedIds.length >= 2 && !loading && !result">
        <div class="id-chips">
          <span class="chip" *ngFor="let id of selectedIds">ID {{ id }}</span>
        </div>
        <button class="compare-btn" (click)="compare()">
          Comparar {{ selectedIds.length }} productos →
        </button>
      </div>
 
      <!-- Loading -->
      <div class="loading" *ngIf="loading">
        <div class="spinner"></div>
        Consultando {{ lastSource === 'redis' ? 'Redis cache' : 'PostgreSQL' }}...
      </div>
 
      <!-- Error -->
      <div class="error" *ngIf="error">
        ⚠ {{ error }}
        <button (click)="compare()">Reintentar</button>
      </div>
 
      <!-- Resultado -->
      <div class="result" *ngIf="result && !loading">
        <!-- Fuente + latencia -->
        <div class="result-meta">
          <div class="source-badge" [class.redis]="lastSource === 'redis'" [class.pg]="lastSource === 'postgresql'">
            <span class="source-dot"></span>
            {{ lastSource === 'redis' ? '⚡ Redis cache' : '🗄 PostgreSQL' }}
            <span class="ttl">· TTL {{ result.ttl_seconds }}s</span>
          </div>
          <div class="latency" *ngIf="latencyMs !== null">
            Latencia: <strong>{{ latencyMs }}ms</strong>
          </div>
        </div>
 
        <!-- Ganador (más barato) -->
        <div class="winner-banner">
          <div class="winner-label">MEJOR PRECIO</div>
          <div class="winner-name">{{ result.data.cheapest.nombre }}</div>
          <div class="winner-price">\${{ formatPrice(result.data.cheapest.precio) }}</div>
        </div>
 
        <!-- Tabla de productos -->
        <div class="products-grid">
          <div
            class="product-card"
            *ngFor="let p of result.data.products"
            [class.cheapest]="p.id === result.data.cheapest.id"
            [class.expensive]="p.id === result.data.most_expensive.id"
          >
            <div class="product-rank" *ngIf="p.id === result.data.cheapest.id">MEJOR PRECIO</div>
            <div class="product-rank expensive-rank" *ngIf="p.id === result.data.most_expensive.id && result.data.products.length > 1">MÁS CARO</div>
            <div class="product-id">ID · {{ p.id }}</div>
            <div class="product-name">{{ p.nombre }}</div>
            <div class="product-price">\${{ formatPrice(p.precio) }}</div>
            <div class="product-diff" *ngIf="p.id !== result.data.cheapest.id">
              +\${{ formatPrice((+p.precio - +result.data.cheapest.precio).toString()) }} vs mejor
            </div>
          </div>
        </div>
 
        <!-- Diferencia de precio -->
        <div class="diff-row">
          <span class="diff-label">Diferencia máxima de precio:</span>
          <span class="diff-value">\${{ formatPrice(result.data.price_difference.toString()) }}</span>
        </div>
 
        <!-- Volver a comparar -->
        <button class="compare-btn" style="margin-top:24px" (click)="result = null">
          ← Nueva comparación
        </button>
      </div>
    </div>
  `,
  styles: [`
    .comparador {
      --accent: #84cc16;
      --accent2: #22d3ee;
    }
 
    .section-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 24px;
    }
 
    .section-label {
      font-size: 0.65rem;
      letter-spacing: 0.2em;
      color: #5a5c72;
    }
 
    .clear-btn {
      background: none;
      border: 1px solid #1c1e2a;
      color: #5a5c72;
      font-family: inherit;
      font-size: 0.7rem;
      padding: 5px 12px;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.15s;
    }
 
    .clear-btn:hover { border-color: #f87171; color: #f87171; }
 
    .empty {
      text-align: center;
      padding: 80px 24px;
    }
 
    .empty-icon {
      font-size: 3rem;
      color: #1c1e2a;
      margin-bottom: 16px;
    }
 
    .empty-title {
      font-size: 1rem;
      font-weight: 700;
      color: #5a5c72;
      margin-bottom: 8px;
    }
 
    .empty-sub {
      font-size: 0.78rem;
      color: #3a3c52;
    }
 
    .partial { margin-bottom: 20px; }
 
    .partial-label {
      font-size: 0.72rem;
      color: #5a5c72;
      margin-bottom: 10px;
    }
 
    .id-chips {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      margin-bottom: 16px;
    }
 
    .chip {
      background: rgba(132,204,22,0.08);
      border: 1px solid rgba(132,204,22,0.25);
      color: var(--accent);
      font-size: 0.68rem;
      padding: 4px 10px;
      border-radius: 6px;
    }
 
    .compare-row {
      display: flex;
      align-items: center;
      gap: 16px;
      flex-wrap: wrap;
    }
 
    .compare-btn {
      background: var(--accent);
      color: #000;
      border: none;
      font-family: inherit;
      font-size: 0.8rem;
      font-weight: 700;
      padding: 10px 24px;
      border-radius: 8px;
      cursor: pointer;
      letter-spacing: 0.03em;
      transition: opacity 0.15s;
    }
 
    .compare-btn:hover { opacity: 0.85; }
 
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
 
    .result-meta {
      display: flex;
      align-items: center;
      gap: 16px;
      margin-bottom: 24px;
    }
 
    .source-badge {
      font-size: 0.68rem;
      letter-spacing: 0.08em;
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 5px 12px;
      border-radius: 100px;
      border: 1px solid #1c1e2a;
    }
 
    .source-badge.redis { color: #22d3ee; border-color: rgba(34,211,238,0.25); background: rgba(34,211,238,0.05); }
    .source-badge.pg { color: #a78bfa; border-color: rgba(167,139,250,0.25); background: rgba(167,139,250,0.05); }
 
    .source-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background: currentColor;
      animation: pulse 2s infinite;
    }
 
    @keyframes pulse { 0%,100% { opacity:1; } 50% { opacity:0.4; } }
 
    .ttl { opacity: 0.6; }
 
    .latency {
      font-size: 0.72rem;
      color: #5a5c72;
    }
 
    .latency strong { color: var(--accent); }
 
    .winner-banner {
      background: rgba(132,204,22,0.06);
      border: 1px solid rgba(132,204,22,0.25);
      border-radius: 12px;
      padding: 24px;
      margin-bottom: 20px;
      display: flex;
      align-items: center;
      gap: 20px;
    }
 
    .winner-label {
      font-size: 0.6rem;
      letter-spacing: 0.2em;
      color: var(--accent);
      white-space: nowrap;
    }
 
    .winner-name {
      flex: 1;
      font-size: 1rem;
      font-weight: 700;
    }
 
    .winner-price {
      font-size: 1.5rem;
      font-weight: 700;
      color: var(--accent);
      letter-spacing: -0.03em;
    }
 
    .products-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 2px;
      margin-bottom: 16px;
    }
 
    .product-card {
      background: #0f1017;
      border: 1px solid #1c1e2a;
      border-radius: 10px;
      padding: 18px;
      position: relative;
    }
 
    .product-card.cheapest {
      border-color: rgba(132,204,22,0.4);
    }
 
    .product-card.expensive {
      border-color: rgba(248,113,113,0.25);
    }
 
    .product-rank {
      font-size: 0.58rem;
      letter-spacing: 0.15em;
      color: var(--accent);
      margin-bottom: 10px;
    }
 
    .expensive-rank { color: #f87171; }
 
    .product-id {
      font-size: 0.6rem;
      color: #5a5c72;
      letter-spacing: 0.15em;
      margin-bottom: 6px;
    }
 
    .product-name {
      font-size: 0.85rem;
      font-weight: 700;
      margin-bottom: 10px;
      line-height: 1.3;
    }
 
    .product-price {
      font-size: 1.1rem;
      color: var(--accent);
      font-weight: 700;
      letter-spacing: -0.02em;
    }
 
    .product-diff {
      font-size: 0.68rem;
      color: #f87171;
      margin-top: 4px;
    }
 
    .diff-row {
      display: flex;
      align-items: center;
      gap: 12px;
      padding: 12px 16px;
      background: #0f1017;
      border: 1px solid #1c1e2a;
      border-radius: 8px;
      font-size: 0.78rem;
    }
 
    .diff-label { color: #5a5c72; flex: 1; }
 
    .diff-value {
      color: var(--accent2);
      font-weight: 700;
      letter-spacing: -0.02em;
    }
  `]
})
export class ComparadorComponent implements OnChanges {
  @Input() selectedIds: number[] = [];
  @Output() clearSelection = new EventEmitter<void>();
 
  result: any = null;
  loading = false;
  error = '';
  lastSource = '';
  latencyMs: number | null = null;
 
  constructor(private svc: ProductService) {}
 
  ngOnChanges() {
    // Reset result cuando cambia selección
    if (this.result) this.result = null;
  }
 
  compare() {
    if (this.selectedIds.length < 2) return;
    this.loading = true;
    this.error = '';
    this.result = null;
    const t0 = performance.now();
 
    this.svc.compare(this.selectedIds).subscribe({
      next: (r) => {
        this.result = r;
        this.lastSource = r.source;
        this.latencyMs = Math.round(performance.now() - t0);
        this.loading = false;
      },
      error: (e) => {
        this.error = e.message || 'Error al comparar';
        this.loading = false;
      }
    });
  }
 
  onClear() {
    this.clearSelection.emit();
    this.result = null;
  }
 
  formatPrice(precio: string): string {
    return Number(precio).toLocaleString('es-MX', { minimumFractionDigits: 2 });
  }
}
