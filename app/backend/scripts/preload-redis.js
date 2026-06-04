/**
 * Precarga el catálogo desde PostgreSQL hacia Redis (init container / one-shot).
 * Claves alineadas con app/backend/index.js: productos:all, producto:{id}
 */
require('dotenv').config();

const { Pool } = require('pg');
const { createClient } = require('redis');

const CACHE_TTL_SECONDS = parseInt(process.env.CACHE_TTL_SECONDS || '3600', 10);
const CATALOG_KEY = 'productos:all';

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
  console.error('[preload] Redis error:', err.message);
});

function productKey(id) {
  return `producto:${id}`;
}

async function shutdown(exitCode) {
  try {
    if (redisClient.isReady) await redisClient.quit();
  } catch (_) {
    /* ignore */
  }
  try {
    await pool.end();
  } catch (_) {
    /* ignore */
  }
  process.exit(exitCode);
}

async function main() {
  const pgHost = process.env.DB_HOST || 'localhost';
  const pgPort = process.env.DB_PORT || '5432';
  const pgDb = process.env.DB_NAME || 'jeanosdb';
  const redisHost = process.env.REDIS_HOST || 'localhost';
  const redisPort = process.env.REDIS_PORT || '6379';

  console.log('[preload] Iniciando precarga Redis');
  console.log(`[preload] PostgreSQL → ${pgHost}:${pgPort}/${pgDb}`);
  console.log(`[preload] Redis → ${redisHost}:${redisPort}`);

  try {
    console.log('[preload] Conectando PostgreSQL...');
    await pool.query('SELECT 1');
    console.log('[preload] PostgreSQL conectado');

    const result = await pool.query(`
      SELECT id, nombre, precio
      FROM productos
      ORDER BY id;
    `);
    const rows = result.rows;
    console.log(`[preload] Productos encontrados: ${rows.length}`);

    if (rows.length === 0) {
      console.error('[preload] No hay productos en la tabla; abortando');
      await shutdown(1);
      return;
    }

    console.log('[preload] Conectando Redis...');
    await redisClient.connect();
    console.log('[preload] Redis conectado');

    await redisClient.setEx(CATALOG_KEY, CACHE_TTL_SECONDS, JSON.stringify(rows));
    console.log(`[preload] Clave cargada: ${CATALOG_KEY} (catálogo completo, ${rows.length} filas)`);

    for (const row of rows) {
      const key = productKey(row.id);
      await redisClient.setEx(key, CACHE_TTL_SECONDS, JSON.stringify(row));
    }
    console.log(`[preload] Claves cargadas: ${rows.length} individuales (producto:{id})`);
    console.log(`[preload] Total claves escritas: ${1 + rows.length}`);
    console.log(`[preload] TTL aplicado: ${CACHE_TTL_SECONDS} segundos`);

    const ttlCatalog = await redisClient.ttl(CATALOG_KEY);
    console.log(`[preload] Verificación TTL ${CATALOG_KEY}: ${ttlCatalog}s restantes`);

    console.log('[preload] Precarga completada correctamente');
    await shutdown(0);
  } catch (err) {
    console.error('[preload] Fallo:', err.message);
    await shutdown(1);
  }
}

main();
