-- Esquema y datos mínimos para JeanOS Shop (init container del backend).
CREATE TABLE IF NOT EXISTS productos (
  id SERIAL PRIMARY KEY,
  nombre VARCHAR(255) NOT NULL,
  precio NUMERIC(10,2) NOT NULL
);

INSERT INTO productos (id, nombre, precio) VALUES
  (1, 'GPU RTX 4070', 8999.00),
  (2, 'RAM DDR5 32GB', 1899.00),
  (3, 'SSD NVMe 1TB', 1299.00),
  (4, 'Placa madre B650', 4599.00),
  (5, 'Fuente 850W 80+ Gold', 2199.00)
ON CONFLICT (id) DO NOTHING;

SELECT COUNT(*) AS total_productos FROM productos;
