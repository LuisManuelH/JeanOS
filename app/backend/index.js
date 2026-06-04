require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { createClient } = require('redis');
const client = require('prom-client');

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'jeanos_http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'jeanos_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

const comparatorRequestsTotal = new client.Counter({
  name: 'jeanos_comparator_requests_total',
  help: 'Total comparator API requests',
  labelNames: ['status_code', 'source'],
  registers: [register],
});

const comparatorDuration = new client.Histogram({
  name: 'jeanos_comparator_duration_seconds',
  help: 'Comparator API duration in seconds',
  labelNames: ['status_code', 'source'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

const cacheHitsTotal = new client.Counter({
  name: 'jeanos_cache_hits_total',
  help: 'Cache hits served from Redis',
  labelNames: ['route', 'source'],
  registers: [register],
});

const cacheMissesTotal = new client.Counter({
  name: 'jeanos_cache_misses_total',
  help: 'Cache misses loaded from PostgreSQL',
  labelNames: ['route', 'source'],
  registers: [register],
});

function routeLabel(req) {
  if (req.route?.path) {
    const base = req.baseUrl || '';
    return `${base}${req.route.path}`;
  }
  return req.path;
}

function recordHttpMetrics(req, res, startNs) {
  const route = routeLabel(req);
  const labels = {
    method: req.method,
    route,
    status_code: String(res.statusCode),
  };
  httpRequestsTotal.inc(labels);
  const durationSec = Number(process.hrtime.bigint() - startNs) / 1e9;
  httpRequestDuration.observe(labels, durationSec);
}

function recordCacheHit(route, source = 'redis') {
  cacheHitsTotal.inc({ route, source });
}

function recordCacheMiss(route, source = 'postgresql') {
  cacheMissesTotal.inc({ route, source });
}

function recordComparatorMetrics(statusCode, source, durationSec) {
  const labels = {
    status_code: String(statusCode),
    source: source || 'none',
  };
  comparatorRequestsTotal.inc(labels);
  comparatorDuration.observe(labels, durationSec);
}

const app = express();

app.use(cors());
app.use(express.json());

app.use((req, res, next) => {
  const startNs = process.hrtime.bigint();
  res.on('finish', () => {
    recordHttpMetrics(req, res, startNs);
  });
  next();
});

const PORT = process.env.PORT || 3000;
const CACHE_TTL_SECONDS = parseInt(process.env.CACHE_TTL_SECONDS || '3600', 10);

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'jeanosdb',
  user: process.env.DB_USER || 'jeanosadmin',
  password: process.env.DB_PASSWORD || 'password',
});

const redisClient = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
  },
});

redisClient.on('error', (err) => {
  console.error('Redis error:', err.message);
});

app.get('/', (req, res) => {
  res.json({
    app: 'jeanOS Shop Backend',
    status: 'running',
    stack: ['Node.js', 'PostgreSQL', 'Redis'],
  });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/healthz', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'jeanos-backend',
    timestamp: new Date().toISOString(),
  });
});

app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');

    if (!redisClient.isReady) {
      throw new Error('Redis no está conectado');
    }

    res.status(200).json({
      status: 'ready',
      postgres: 'ok',
      redis: 'ok',
    });
  } catch (err) {
    res.status(503).json({
      status: 'not_ready',
      error: err.message,
    });
  }
});

app.get('/api/products', async (req, res) => {
  const route = '/api/products';

  try {
    const cacheKey = 'productos:all';
    const cached = await redisClient.get(cacheKey);

    if (cached) {
      recordCacheHit(route, 'redis');
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

    recordCacheMiss(route, 'postgresql');

    const result = await pool.query(`
      SELECT id, nombre, precio
      FROM productos
      ORDER BY id;
    `);

    await redisClient.setEx(cacheKey, CACHE_TTL_SECONDS, JSON.stringify(result.rows));

    res.json({
      source: 'postgresql',
      ttl_seconds: CACHE_TTL_SECONDS,
      data: result.rows,
    });
  } catch (err) {
    res.status(500).json({
      error: err.message,
    });
  }
});

app.get('/api/products/:id', async (req, res) => {
  const route = '/api/products/:id';

  try {
    const id = Number(req.params.id);

    if (!Number.isInteger(id) || id <= 0) {
      return res.status(400).json({
        error: 'ID inválido',
      });
    }

    const cacheKey = `producto:${id}`;
    const cached = await redisClient.get(cacheKey);

    if (cached) {
      recordCacheHit(route, 'redis');
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

    recordCacheMiss(route, 'postgresql');

    const result = await pool.query(`
      SELECT id, nombre, precio
      FROM productos
      WHERE id = $1;
    `, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: 'Producto no encontrado',
      });
    }

    await redisClient.setEx(cacheKey, CACHE_TTL_SECONDS, JSON.stringify(result.rows[0]));

    res.json({
      source: 'postgresql',
      ttl_seconds: CACHE_TTL_SECONDS,
      data: result.rows[0],
    });
  } catch (err) {
    res.status(500).json({
      error: err.message,
    });
  }
});

app.post('/api/compare', async (req, res) => {
  const route = '/api/compare';
  const compareStartNs = process.hrtime.bigint();

  const finishCompare = (statusCode, source) => {
    const durationSec = Number(process.hrtime.bigint() - compareStartNs) / 1e9;
    recordComparatorMetrics(statusCode, source, durationSec);
  };

  try {
    const { ids } = req.body;

    if (!Array.isArray(ids) || ids.length < 2) {
      finishCompare(400, 'none');
      return res.status(400).json({
        error: 'Envía al menos 2 IDs en el campo ids[]',
        example: { ids: [1, 2] },
      });
    }

    const cleanIds = [...new Set(ids.map(Number))]
      .filter((id) => Number.isInteger(id) && id > 0)
      .sort((a, b) => a - b);

    if (cleanIds.length < 2) {
      finishCompare(400, 'none');
      return res.status(400).json({
        error: 'Los IDs deben ser números enteros positivos',
      });
    }

    const cacheKey = `compare:${cleanIds.join('-')}`;
    const cached = await redisClient.get(cacheKey);

    if (cached) {
      recordCacheHit(route, 'redis');
      finishCompare(200, 'redis');
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

    recordCacheMiss(route, 'postgresql');

    const placeholders = cleanIds.map((_, i) => `$${i + 1}`).join(', ');

    const result = await pool.query(`
      SELECT id, nombre, precio
      FROM productos
      WHERE id IN (${placeholders})
      ORDER BY precio ASC;
    `, cleanIds);

    const productos = result.rows;

    if (productos.length < 2) {
      finishCompare(404, 'none');
      return res.status(404).json({
        error: 'No se encontraron suficientes productos para comparar',
        requested_ids: cleanIds,
      });
    }

    const cheapest = productos[0];
    const mostExpensive = productos[productos.length - 1];

    const comparison = {
      requested_ids: cleanIds,
      count: productos.length,
      cheapest,
      most_expensive: mostExpensive,
      price_difference: Number(mostExpensive.precio) - Number(cheapest.precio),
      products: productos,
    };

    await redisClient.setEx(cacheKey, CACHE_TTL_SECONDS, JSON.stringify(comparison));

    finishCompare(200, 'postgresql');
    res.json({
      source: 'postgresql',
      ttl_seconds: CACHE_TTL_SECONDS,
      data: comparison,
    });
  } catch (err) {
    finishCompare(500, 'none');
    res.status(500).json({
      error: err.message,
    });
  }
});

async function start() {
  try {
    await redisClient.connect();
    console.log('Redis conectado');

    await pool.query('SELECT 1');
    console.log('PostgreSQL conectado');

    app.listen(PORT, '0.0.0.0', () => {
      console.log(`Backend jeanOS Shop escuchando en puerto ${PORT}`);
    });
  } catch (err) {
    console.error('Error al arrancar backend:', err.message);
    process.exit(1);
  }
}

start();
