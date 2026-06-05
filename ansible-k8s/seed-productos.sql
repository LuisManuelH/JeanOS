-- Esquema y seed JeanOS Shop — catálogo de hardware con clases y especificaciones.
-- Idempotente: CREATE IF NOT EXISTS + INSERT ON CONFLICT DO NOTHING.
-- Referencias estables por slug (clase) y modelo (producto), sin depender de SERIAL.

-- Migración desde esquema legado productos(id, nombre, precio) sin clase_id.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'productos'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'productos'
      AND column_name = 'clase_id'
  ) THEN
    DROP TABLE IF EXISTS producto_specs CASCADE;
    DROP TABLE IF EXISTS spec_definitions CASCADE;
    DROP TABLE IF EXISTS productos CASCADE;
    DROP TABLE IF EXISTS clases_producto CASCADE;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS clases_producto (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(64) UNIQUE NOT NULL,
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT
);

CREATE TABLE IF NOT EXISTS productos (
  id SERIAL PRIMARY KEY,
  clase_id INTEGER NOT NULL REFERENCES clases_producto(id),
  nombre VARCHAR(255) NOT NULL,
  marca VARCHAR(128) NOT NULL,
  modelo VARCHAR(128) NOT NULL,
  precio NUMERIC(10,2) NOT NULL,
  UNIQUE (clase_id, modelo)
);

CREATE TABLE IF NOT EXISTS spec_definitions (
  id SERIAL PRIMARY KEY,
  clase_id INTEGER NOT NULL REFERENCES clases_producto(id),
  spec_key VARCHAR(64) NOT NULL,
  label VARCHAR(255) NOT NULL,
  unit VARCHAR(32),
  data_type VARCHAR(32) NOT NULL,
  sort_order INTEGER NOT NULL,
  UNIQUE (clase_id, spec_key)
);

CREATE TABLE IF NOT EXISTS producto_specs (
  producto_id INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  spec_definition_id INTEGER NOT NULL REFERENCES spec_definitions(id) ON DELETE CASCADE,
  valor_texto TEXT,
  valor_numero NUMERIC,
  valor_booleano BOOLEAN,
  PRIMARY KEY (producto_id, spec_definition_id)
);

-- Compatibilidad si productos existía sin UNIQUE (CREATE IF NOT EXISTS no altera la tabla)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.productos'::regclass
      AND conname = 'productos_clase_id_modelo_key'
  ) THEN
    ALTER TABLE productos
      ADD CONSTRAINT productos_clase_id_modelo_key UNIQUE (clase_id, modelo);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Clases (mínimo 5) — conflicto por slug
-- ---------------------------------------------------------------------------

INSERT INTO clases_producto (slug, nombre, descripcion) VALUES
  ('gpu', 'GPU', 'Tarjetas gráficas para gaming y cómputo'),
  ('ram', 'RAM', 'Memoria RAM para equipos de escritorio'),
  ('ssd', 'SSD', 'Unidades de estado sólido NVMe y SATA'),
  ('motherboard', 'Motherboard', 'Placas base para procesadores AMD e Intel'),
  ('psu', 'PSU', 'Fuentes de poder certificadas 80 Plus')
ON CONFLICT (slug) DO NOTHING;

SELECT setval(
  pg_get_serial_sequence('clases_producto', 'id'),
  GREATEST((SELECT COALESCE(MAX(id), 1) FROM clases_producto), 1)
);

-- ---------------------------------------------------------------------------
-- Definiciones de especificaciones — clase_id resuelto por slug
-- ---------------------------------------------------------------------------

INSERT INTO spec_definitions (clase_id, spec_key, label, unit, data_type, sort_order)
SELECT cp.id, v.spec_key, v.label, v.unit, v.data_type, v.sort_order
FROM (VALUES
  -- GPU
  ('gpu', 'vram_gb', 'Memoria VRAM', 'GB', 'number', 10),
  ('gpu', 'chipset', 'Chipset', NULL, 'text', 20),
  ('gpu', 'memory_type', 'Tipo de memoria', NULL, 'text', 30),
  ('gpu', 'tdp_w', 'TDP', 'W', 'number', 40),
  ('gpu', 'interface', 'Interfaz', NULL, 'text', 50),
  -- RAM
  ('ram', 'capacity_gb', 'Capacidad', 'GB', 'number', 10),
  ('ram', 'type', 'Tipo', NULL, 'text', 20),
  ('ram', 'frequency_mhz', 'Frecuencia', 'MHz', 'number', 30),
  ('ram', 'modules', 'Módulos', NULL, 'number', 40),
  ('ram', 'latency', 'Latencia CAS', NULL, 'text', 50),
  -- SSD
  ('ssd', 'capacity_tb', 'Capacidad', 'TB', 'number', 10),
  ('ssd', 'interface', 'Interfaz', NULL, 'text', 20),
  ('ssd', 'form_factor', 'Factor de forma', NULL, 'text', 30),
  ('ssd', 'read_mb_s', 'Lectura secuencial', 'MB/s', 'number', 40),
  ('ssd', 'write_mb_s', 'Escritura secuencial', 'MB/s', 'number', 50),
  -- Motherboard
  ('motherboard', 'socket', 'Socket', NULL, 'text', 10),
  ('motherboard', 'chipset', 'Chipset', NULL, 'text', 20),
  ('motherboard', 'form_factor', 'Factor de forma', NULL, 'text', 30),
  ('motherboard', 'ram_slots', 'Ranuras RAM', NULL, 'number', 40),
  ('motherboard', 'm2_slots', 'Ranuras M.2', NULL, 'number', 50),
  -- PSU
  ('psu', 'watts', 'Potencia', 'W', 'number', 10),
  ('psu', 'certification', 'Certificación 80 Plus', NULL, 'text', 20),
  ('psu', 'modularity', 'Modularidad', NULL, 'text', 30),
  ('psu', 'pcie_5', 'Soporte PCIe 5.0', NULL, 'boolean', 40),
  ('psu', 'warranty_years', 'Garantía', 'años', 'number', 50)
) AS v(slug, spec_key, label, unit, data_type, sort_order)
JOIN clases_producto cp ON cp.slug = v.slug
ON CONFLICT (clase_id, spec_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Productos (5 por clase) — conflicto por (clase_id, modelo)
-- ---------------------------------------------------------------------------

INSERT INTO productos (clase_id, nombre, marca, modelo, precio)
SELECT cp.id, v.nombre, v.marca, v.modelo, v.precio
FROM (VALUES
  ('gpu', 'GeForce RTX 4070', 'NVIDIA', 'RTX 4070', 8999.00),
  ('gpu', 'GeForce RTX 4060 Ti', 'NVIDIA', 'RTX 4060 Ti', 6499.00),
  ('gpu', 'Radeon RX 7800 XT', 'AMD', 'RX 7800 XT', 7499.00),
  ('gpu', 'Radeon RX 7700 XT', 'AMD', 'RX 7700 XT', 5999.00),
  ('gpu', 'GeForce RTX 4080 Super', 'NVIDIA', 'RTX 4080 Super', 12999.00),
  ('ram', 'Vengeance DDR5 32GB', 'Corsair', 'CMK32GX5M2B6000C36', 1899.00),
  ('ram', 'Trident Z5 DDR5 32GB', 'G.Skill', 'F5-6000J3636F16GX2-TZ5RK', 2199.00),
  ('ram', 'Fury Beast DDR5 16GB', 'Kingston', 'KF556C40BBK2-16', 899.00),
  ('ram', 'Ripjaws S5 DDR5 64GB', 'G.Skill', 'F5-5200J3636A16GX2-RS5K', 3499.00),
  ('ram', 'T-Create Classic DDR5 48GB', 'TeamGroup', 'CTCCD548G5200HC38ADC01', 2799.00),
  ('ssd', '990 PRO 1TB', 'Samsung', 'MZ-V9P1T0BW', 1299.00),
  ('ssd', 'SN850X 2TB', 'Western Digital', 'WDS200T2X0E', 2499.00),
  ('ssd', 'MP600 PRO XT 1TB', 'Corsair', 'CSSD-F1000GBMP600PXT', 1399.00),
  ('ssd', 'P41 Platinum 2TB', 'Solidigm', 'SSDPFKNU020TZ', 1999.00),
  ('ssd', 'KC3000 2TB', 'Kingston', 'SKC3000D/2048G', 1899.00),
  ('motherboard', 'ROG Strix B650E-F', 'ASUS', 'ROG STRIX B650E-F GAMING WIFI', 4599.00),
  ('motherboard', 'MAG B650 Tomahawk WiFi', 'MSI', 'MAG B650 TOMAHAWK WIFI', 3899.00),
  ('motherboard', 'X670E Steel Legend', 'ASRock', 'X670E Steel Legend', 5299.00),
  ('motherboard', 'Z790 Aorus Elite AX', 'Gigabyte', 'Z790 AORUS ELITE AX', 4999.00),
  ('motherboard', 'B760M Mortar WiFi', 'MSI', 'MAG B760M MORTAR WIFI', 2999.00),
  ('psu', 'RM850e 850W', 'Corsair', 'CP-9020266-NA', 2199.00),
  ('psu', 'Focus GX-750', 'Seasonic', 'SSR-750FX', 1899.00),
  ('psu', 'SuperNOVA 1000 G6', 'EVGA', '100-G6-1000-LR', 3299.00),
  ('psu', 'Straight Power 12 850W', 'be quiet!', 'BN345', 2499.00),
  ('psu', 'V Gold i 750W', 'Cooler Master', 'V750i', 1699.00)
) AS v(slug, nombre, marca, modelo, precio)
JOIN clases_producto cp ON cp.slug = v.slug
ON CONFLICT (clase_id, modelo) DO NOTHING;

SELECT setval(
  pg_get_serial_sequence('productos', 'id'),
  GREATEST((SELECT COALESCE(MAX(id), 1) FROM productos), 1)
);

-- ---------------------------------------------------------------------------
-- Especificaciones por producto — slug + modelo + spec_key; sd.clase_id = p.clase_id
-- ---------------------------------------------------------------------------

INSERT INTO producto_specs (producto_id, spec_definition_id, valor_texto, valor_numero, valor_booleano)
SELECT p.id, sd.id, v.valor_texto, v.valor_numero, v.valor_booleano
FROM (VALUES
  -- GPU · RTX 4070
  ('gpu', 'RTX 4070', 'vram_gb', NULL::text, 12::numeric, NULL::boolean),
  ('gpu', 'RTX 4070', 'chipset', 'AD104', NULL, NULL),
  ('gpu', 'RTX 4070', 'memory_type', 'GDDR6X', NULL, NULL),
  ('gpu', 'RTX 4070', 'tdp_w', NULL, 200, NULL),
  ('gpu', 'RTX 4070', 'interface', 'PCIe 4.0 x16', NULL, NULL),
  -- GPU · RTX 4060 Ti
  ('gpu', 'RTX 4060 Ti', 'vram_gb', NULL, 8, NULL),
  ('gpu', 'RTX 4060 Ti', 'chipset', 'AD106', NULL, NULL),
  ('gpu', 'RTX 4060 Ti', 'memory_type', 'GDDR6', NULL, NULL),
  ('gpu', 'RTX 4060 Ti', 'tdp_w', NULL, 160, NULL),
  ('gpu', 'RTX 4060 Ti', 'interface', 'PCIe 4.0 x16', NULL, NULL),
  -- GPU · RX 7800 XT
  ('gpu', 'RX 7800 XT', 'vram_gb', NULL, 16, NULL),
  ('gpu', 'RX 7800 XT', 'chipset', 'Navi 32', NULL, NULL),
  ('gpu', 'RX 7800 XT', 'memory_type', 'GDDR6', NULL, NULL),
  ('gpu', 'RX 7800 XT', 'tdp_w', NULL, 263, NULL),
  ('gpu', 'RX 7800 XT', 'interface', 'PCIe 4.0 x16', NULL, NULL),
  -- GPU · RX 7700 XT
  ('gpu', 'RX 7700 XT', 'vram_gb', NULL, 12, NULL),
  ('gpu', 'RX 7700 XT', 'chipset', 'Navi 32', NULL, NULL),
  ('gpu', 'RX 7700 XT', 'memory_type', 'GDDR6', NULL, NULL),
  ('gpu', 'RX 7700 XT', 'tdp_w', NULL, 245, NULL),
  ('gpu', 'RX 7700 XT', 'interface', 'PCIe 4.0 x16', NULL, NULL),
  -- GPU · RTX 4080 Super
  ('gpu', 'RTX 4080 Super', 'vram_gb', NULL, 16, NULL),
  ('gpu', 'RTX 4080 Super', 'chipset', 'AD103', NULL, NULL),
  ('gpu', 'RTX 4080 Super', 'memory_type', 'GDDR6X', NULL, NULL),
  ('gpu', 'RTX 4080 Super', 'tdp_w', NULL, 320, NULL),
  ('gpu', 'RTX 4080 Super', 'interface', 'PCIe 4.0 x16', NULL, NULL),
  -- RAM
  ('ram', 'CMK32GX5M2B6000C36', 'capacity_gb', NULL, 32, NULL),
  ('ram', 'CMK32GX5M2B6000C36', 'type', 'DDR5', NULL, NULL),
  ('ram', 'CMK32GX5M2B6000C36', 'frequency_mhz', NULL, 6000, NULL),
  ('ram', 'CMK32GX5M2B6000C36', 'modules', NULL, 2, NULL),
  ('ram', 'CMK32GX5M2B6000C36', 'latency', 'CL36', NULL, NULL),
  ('ram', 'F5-6000J3636F16GX2-TZ5RK', 'capacity_gb', NULL, 32, NULL),
  ('ram', 'F5-6000J3636F16GX2-TZ5RK', 'type', 'DDR5', NULL, NULL),
  ('ram', 'F5-6000J3636F16GX2-TZ5RK', 'frequency_mhz', NULL, 6000, NULL),
  ('ram', 'F5-6000J3636F16GX2-TZ5RK', 'modules', NULL, 2, NULL),
  ('ram', 'F5-6000J3636F16GX2-TZ5RK', 'latency', 'CL36', NULL, NULL),
  ('ram', 'KF556C40BBK2-16', 'capacity_gb', NULL, 16, NULL),
  ('ram', 'KF556C40BBK2-16', 'type', 'DDR5', NULL, NULL),
  ('ram', 'KF556C40BBK2-16', 'frequency_mhz', NULL, 5600, NULL),
  ('ram', 'KF556C40BBK2-16', 'modules', NULL, 2, NULL),
  ('ram', 'KF556C40BBK2-16', 'latency', 'CL40', NULL, NULL),
  ('ram', 'F5-5200J3636A16GX2-RS5K', 'capacity_gb', NULL, 64, NULL),
  ('ram', 'F5-5200J3636A16GX2-RS5K', 'type', 'DDR5', NULL, NULL),
  ('ram', 'F5-5200J3636A16GX2-RS5K', 'frequency_mhz', NULL, 5200, NULL),
  ('ram', 'F5-5200J3636A16GX2-RS5K', 'modules', NULL, 2, NULL),
  ('ram', 'F5-5200J3636A16GX2-RS5K', 'latency', 'CL36', NULL, NULL),
  ('ram', 'CTCCD548G5200HC38ADC01', 'capacity_gb', NULL, 48, NULL),
  ('ram', 'CTCCD548G5200HC38ADC01', 'type', 'DDR5', NULL, NULL),
  ('ram', 'CTCCD548G5200HC38ADC01', 'frequency_mhz', NULL, 5200, NULL),
  ('ram', 'CTCCD548G5200HC38ADC01', 'modules', NULL, 2, NULL),
  ('ram', 'CTCCD548G5200HC38ADC01', 'latency', 'CL38', NULL, NULL),
  -- SSD
  ('ssd', 'MZ-V9P1T0BW', 'capacity_tb', NULL, 1, NULL),
  ('ssd', 'MZ-V9P1T0BW', 'interface', 'PCIe 4.0 x4 NVMe', NULL, NULL),
  ('ssd', 'MZ-V9P1T0BW', 'form_factor', 'M.2 2280', NULL, NULL),
  ('ssd', 'MZ-V9P1T0BW', 'read_mb_s', NULL, 7450, NULL),
  ('ssd', 'MZ-V9P1T0BW', 'write_mb_s', NULL, 6900, NULL),
  ('ssd', 'WDS200T2X0E', 'capacity_tb', NULL, 2, NULL),
  ('ssd', 'WDS200T2X0E', 'interface', 'PCIe 4.0 x4 NVMe', NULL, NULL),
  ('ssd', 'WDS200T2X0E', 'form_factor', 'M.2 2280', NULL, NULL),
  ('ssd', 'WDS200T2X0E', 'read_mb_s', NULL, 7300, NULL),
  ('ssd', 'WDS200T2X0E', 'write_mb_s', NULL, 6600, NULL),
  ('ssd', 'CSSD-F1000GBMP600PXT', 'capacity_tb', NULL, 1, NULL),
  ('ssd', 'CSSD-F1000GBMP600PXT', 'interface', 'PCIe 4.0 x4 NVMe', NULL, NULL),
  ('ssd', 'CSSD-F1000GBMP600PXT', 'form_factor', 'M.2 2280', NULL, NULL),
  ('ssd', 'CSSD-F1000GBMP600PXT', 'read_mb_s', NULL, 7100, NULL),
  ('ssd', 'CSSD-F1000GBMP600PXT', 'write_mb_s', NULL, 5800, NULL),
  ('ssd', 'SSDPFKNU020TZ', 'capacity_tb', NULL, 2, NULL),
  ('ssd', 'SSDPFKNU020TZ', 'interface', 'PCIe 4.0 x4 NVMe', NULL, NULL),
  ('ssd', 'SSDPFKNU020TZ', 'form_factor', 'M.2 2280', NULL, NULL),
  ('ssd', 'SSDPFKNU020TZ', 'read_mb_s', NULL, 7000, NULL),
  ('ssd', 'SSDPFKNU020TZ', 'write_mb_s', NULL, 6000, NULL),
  ('ssd', 'SKC3000D/2048G', 'capacity_tb', NULL, 2, NULL),
  ('ssd', 'SKC3000D/2048G', 'interface', 'PCIe 4.0 x4 NVMe', NULL, NULL),
  ('ssd', 'SKC3000D/2048G', 'form_factor', 'M.2 2280', NULL, NULL),
  ('ssd', 'SKC3000D/2048G', 'read_mb_s', NULL, 7000, NULL),
  ('ssd', 'SKC3000D/2048G', 'write_mb_s', NULL, 6000, NULL),
  -- Motherboard
  ('motherboard', 'ROG STRIX B650E-F GAMING WIFI', 'socket', 'AM5', NULL, NULL),
  ('motherboard', 'ROG STRIX B650E-F GAMING WIFI', 'chipset', 'B650E', NULL, NULL),
  ('motherboard', 'ROG STRIX B650E-F GAMING WIFI', 'form_factor', 'ATX', NULL, NULL),
  ('motherboard', 'ROG STRIX B650E-F GAMING WIFI', 'ram_slots', NULL, 4, NULL),
  ('motherboard', 'ROG STRIX B650E-F GAMING WIFI', 'm2_slots', NULL, 3, NULL),
  ('motherboard', 'MAG B650 TOMAHAWK WIFI', 'socket', 'AM5', NULL, NULL),
  ('motherboard', 'MAG B650 TOMAHAWK WIFI', 'chipset', 'B650', NULL, NULL),
  ('motherboard', 'MAG B650 TOMAHAWK WIFI', 'form_factor', 'ATX', NULL, NULL),
  ('motherboard', 'MAG B650 TOMAHAWK WIFI', 'ram_slots', NULL, 4, NULL),
  ('motherboard', 'MAG B650 TOMAHAWK WIFI', 'm2_slots', NULL, 2, NULL),
  ('motherboard', 'X670E Steel Legend', 'socket', 'AM5', NULL, NULL),
  ('motherboard', 'X670E Steel Legend', 'chipset', 'X670E', NULL, NULL),
  ('motherboard', 'X670E Steel Legend', 'form_factor', 'ATX', NULL, NULL),
  ('motherboard', 'X670E Steel Legend', 'ram_slots', NULL, 4, NULL),
  ('motherboard', 'X670E Steel Legend', 'm2_slots', NULL, 4, NULL),
  ('motherboard', 'Z790 AORUS ELITE AX', 'socket', 'LGA1700', NULL, NULL),
  ('motherboard', 'Z790 AORUS ELITE AX', 'chipset', 'Z790', NULL, NULL),
  ('motherboard', 'Z790 AORUS ELITE AX', 'form_factor', 'ATX', NULL, NULL),
  ('motherboard', 'Z790 AORUS ELITE AX', 'ram_slots', NULL, 4, NULL),
  ('motherboard', 'Z790 AORUS ELITE AX', 'm2_slots', NULL, 3, NULL),
  ('motherboard', 'MAG B760M MORTAR WIFI', 'socket', 'LGA1700', NULL, NULL),
  ('motherboard', 'MAG B760M MORTAR WIFI', 'chipset', 'B760', NULL, NULL),
  ('motherboard', 'MAG B760M MORTAR WIFI', 'form_factor', 'Micro-ATX', NULL, NULL),
  ('motherboard', 'MAG B760M MORTAR WIFI', 'ram_slots', NULL, 4, NULL),
  ('motherboard', 'MAG B760M MORTAR WIFI', 'm2_slots', NULL, 2, NULL),
  -- PSU
  ('psu', 'CP-9020266-NA', 'watts', NULL, 850, NULL),
  ('psu', 'CP-9020266-NA', 'certification', 'Gold', NULL, NULL),
  ('psu', 'CP-9020266-NA', 'modularity', 'Semi-modular', NULL, NULL),
  ('psu', 'CP-9020266-NA', 'pcie_5', NULL, NULL, true),
  ('psu', 'CP-9020266-NA', 'warranty_years', NULL, 7, NULL),
  ('psu', 'SSR-750FX', 'watts', NULL, 750, NULL),
  ('psu', 'SSR-750FX', 'certification', 'Gold', NULL, NULL),
  ('psu', 'SSR-750FX', 'modularity', 'Full modular', NULL, NULL),
  ('psu', 'SSR-750FX', 'pcie_5', NULL, NULL, false),
  ('psu', 'SSR-750FX', 'warranty_years', NULL, 10, NULL),
  ('psu', '100-G6-1000-LR', 'watts', NULL, 1000, NULL),
  ('psu', '100-G6-1000-LR', 'certification', 'Gold', NULL, NULL),
  ('psu', '100-G6-1000-LR', 'modularity', 'Full modular', NULL, NULL),
  ('psu', '100-G6-1000-LR', 'pcie_5', NULL, NULL, true),
  ('psu', '100-G6-1000-LR', 'warranty_years', NULL, 10, NULL),
  ('psu', 'BN345', 'watts', NULL, 850, NULL),
  ('psu', 'BN345', 'certification', 'Platinum', NULL, NULL),
  ('psu', 'BN345', 'modularity', 'Full modular', NULL, NULL),
  ('psu', 'BN345', 'pcie_5', NULL, NULL, true),
  ('psu', 'BN345', 'warranty_years', NULL, 10, NULL),
  ('psu', 'V750i', 'watts', NULL, 750, NULL),
  ('psu', 'V750i', 'certification', 'Gold', NULL, NULL),
  ('psu', 'V750i', 'modularity', 'Full modular', NULL, NULL),
  ('psu', 'V750i', 'pcie_5', NULL, NULL, true),
  ('psu', 'V750i', 'warranty_years', NULL, 5, NULL)
) AS v(slug, modelo, spec_key, valor_texto, valor_numero, valor_booleano)
JOIN clases_producto cp ON cp.slug = v.slug
JOIN productos p ON p.clase_id = cp.id AND p.modelo = v.modelo
JOIN spec_definitions sd ON sd.clase_id = p.clase_id AND sd.spec_key = v.spec_key
ON CONFLICT (producto_id, spec_definition_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Verificación (conteos + integridad)
-- ---------------------------------------------------------------------------

SELECT COUNT(*) AS total_clases FROM clases_producto;
SELECT COUNT(*) AS total_productos FROM productos;
SELECT COUNT(*) AS total_spec_definitions FROM spec_definitions;
SELECT COUNT(*) AS total_producto_specs FROM producto_specs;

SELECT
  cp.slug,
  COUNT(DISTINCT p.id) AS productos_por_clase,
  COUNT(DISTINCT sd.id) AS specs_definidas,
  COUNT(DISTINCT ps.producto_id) AS productos_con_al_menos_una_spec
FROM clases_producto cp
LEFT JOIN productos p ON p.clase_id = cp.id
LEFT JOIN spec_definitions sd ON sd.clase_id = cp.id
LEFT JOIN producto_specs ps ON ps.producto_id = p.id
GROUP BY cp.id, cp.slug
ORDER BY cp.id;

-- Productos sin el número esperado de specs (5 por clase en este seed)
SELECT
  p.id,
  cp.slug,
  p.modelo,
  COUNT(ps.spec_definition_id) AS specs_asignadas
FROM productos p
JOIN clases_producto cp ON cp.id = p.clase_id
LEFT JOIN producto_specs ps ON ps.producto_id = p.id
GROUP BY p.id, cp.slug, p.modelo
HAVING COUNT(ps.spec_definition_id) <> (
  SELECT COUNT(*) FROM spec_definitions sd WHERE sd.clase_id = p.clase_id
);

-- Specs ligadas a definición de otra clase
SELECT COUNT(*) AS specs_clase_incorrecta
FROM producto_specs ps
JOIN productos p ON p.id = ps.producto_id
JOIN spec_definitions sd ON sd.id = ps.spec_definition_id
WHERE p.clase_id <> sd.clase_id;

DO $$
DECLARE
  n_clases INTEGER;
  n_productos INTEGER;
  n_spec_defs INTEGER;
  n_producto_specs INTEGER;
  n_incompletos INTEGER;
  n_clase_mal INTEGER;
BEGIN
  SELECT COUNT(*) INTO n_clases FROM clases_producto;
  SELECT COUNT(*) INTO n_productos FROM productos;
  SELECT COUNT(*) INTO n_spec_defs FROM spec_definitions;
  SELECT COUNT(*) INTO n_producto_specs FROM producto_specs;

  IF n_clases < 5 THEN
    RAISE EXCEPTION 'Seed inválido: se esperaban >= 5 clases, hay %', n_clases;
  END IF;

  IF n_productos < 25 THEN
    RAISE EXCEPTION 'Seed inválido: se esperaban >= 25 productos, hay %', n_productos;
  END IF;

  IF n_spec_defs < 25 THEN
    RAISE EXCEPTION 'Seed inválido: se esperaban >= 25 spec_definitions, hay %', n_spec_defs;
  END IF;

  IF n_producto_specs < 125 THEN
    RAISE EXCEPTION 'Seed inválido: se esperaban >= 125 producto_specs, hay %', n_producto_specs;
  END IF;

  SELECT COUNT(*) INTO n_incompletos
  FROM productos p
  JOIN clases_producto cp ON cp.id = p.clase_id
  LEFT JOIN producto_specs ps ON ps.producto_id = p.id
  GROUP BY p.id, p.clase_id
  HAVING COUNT(ps.spec_definition_id) <> (
    SELECT COUNT(*) FROM spec_definitions sd WHERE sd.clase_id = p.clase_id
  );

  IF n_incompletos > 0 THEN
    RAISE EXCEPTION 'Seed inválido: % producto(s) sin todas las specs de su clase', n_incompletos;
  END IF;

  SELECT COUNT(*) INTO n_clase_mal
  FROM producto_specs ps
  JOIN productos p ON p.id = ps.producto_id
  JOIN spec_definitions sd ON sd.id = ps.spec_definition_id
  WHERE p.clase_id <> sd.clase_id;

  IF n_clase_mal > 0 THEN
    RAISE EXCEPTION 'Seed inválido: % producto_specs con clase incorrecta', n_clase_mal;
  END IF;
END $$;
