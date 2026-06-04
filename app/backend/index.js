require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { createClient } = require('redis');
const client = require('prom-client');

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const app = express();

app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 3000;
const CACHE_TTL_SECONDS = parseInt(process.env.CACHE_TTL_SECONDS || '3600', 10);

// PostgreSQL
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'jeanosdb',
  user: process.env.DB_USER || 'jeanosadmin',
  password: process.env.DB_PASSWORD || 'password',
});

// Redis
const redisClient = createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
  },
});

redisClient.on('error', (err) => {
  console.error('Redis error:', err.message);
});

// Ruta base
app.get('/', (req, res) => {
  res.json({
    app: 'jeanOS Shop Backend',
    status: 'running',
    stack: ['Node.js', 'PostgreSQL', 'Redis'],
  });
});

// Métricas Prometheus (Semana 3)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Liveness probe
app.get('/healthz', (req, res) => {
  res.status(200).json({
    status: 'ok',
    service: 'jeanos-backend',
    timestamp: new Date().toISOString(),
  });
});

// Readiness probe
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

// Obtener todos los productos
app.get('/api/products', async (req, res) => {
  try {
    const cacheKey = 'productos:all';

    const cached = await redisClient.get(cacheKey);

    if (cached) {
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

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

// Obtener producto por ID
app.get('/api/products/:id', async (req, res) => {
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
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

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

// Comparador básico de productos
app.post('/api/compare', async (req, res) => {
  try {
    const { ids } = req.body;

    if (!Array.isArray(ids) || ids.length < 2) {
      return res.status(400).json({
        error: 'Envía al menos 2 IDs en el campo ids[]',
        example: { ids: [1, 2] },
      });
    }

    const cleanIds = [...new Set(ids.map(Number))]
      .filter((id) => Number.isInteger(id) && id > 0)
      .sort((a, b) => a - b);

    if (cleanIds.length < 2) {
      return res.status(400).json({
        error: 'Los IDs deben ser números enteros positivos',
      });
    }

    const cacheKey = `compare:${cleanIds.join('-')}`;

    const cached = await redisClient.get(cacheKey);

    if (cached) {
      return res.json({
        source: 'redis',
        ttl_seconds: await redisClient.ttl(cacheKey),
        data: JSON.parse(cached),
      });
    }

    const placeholders = cleanIds.map((_, i) => `$${i + 1}`).join(', ');

    const result = await pool.query(`
      SELECT id, nombre, precio
      FROM productos
      WHERE id IN (${placeholders})
      ORDER BY precio ASC;
    `, cleanIds);

    const productos = result.rows;

    if (productos.length < 2) {
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

    res.json({
      source: 'postgresql',
      ttl_seconds: CACHE_TTL_SECONDS,
      data: comparison,
    });
  } catch (err) {
    res.status(500).json({
      error: err.message,
    });
  }
});

// Arranque del backend
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
