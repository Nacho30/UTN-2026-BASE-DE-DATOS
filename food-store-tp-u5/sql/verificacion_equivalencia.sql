-- =====================================================================
-- verificacion_equivalencia.sql — Parte D, puntos 2 y 3
-- Consulta de agregación sobre usuario_anon y su equivalente sobre
-- usuario: cantidad de usuarios activos por rol y por mes de alta.
-- Las dos diferencias (EXCEPT en ambos sentidos) deben ser vacías.
-- =====================================================================

\echo '===== Consulta 1 — sobre usuario_anon (la que se le especifica a la IA) ====='
-- Como reportes_bi: demuestra que el reporte se puede hacer sin ver datos reales
SET ROLE reportes_bi;
SELECT rol,
       to_char(mes_alta, 'YYYY-MM') AS mes_alta,
       count(*)                     AS usuarios
FROM usuario_anon
WHERE eliminado = FALSE
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;
RESET ROLE;

\echo '===== Consulta 2 — equivalente sobre usuario (tabla real) ====='
SELECT rol,
       to_char(date_trunc('month', fecha_alta), 'YYYY-MM') AS mes_alta,
       count(*)                                            AS usuarios
FROM usuario
WHERE eliminado = FALSE
GROUP BY rol, date_trunc('month', fecha_alta)
ORDER BY rol, mes_alta;

\echo '===== Lado a lado (FULL OUTER JOIN): diferencia esperada 0 en todas las filas ====='
WITH anon AS (
    SELECT rol, to_char(mes_alta, 'YYYY-MM') AS mes, count(*) AS n
    FROM usuario_anon WHERE eliminado = FALSE GROUP BY 1, 2
), real AS (
    SELECT rol, to_char(date_trunc('month', fecha_alta), 'YYYY-MM') AS mes, count(*) AS n
    FROM usuario WHERE eliminado = FALSE GROUP BY 1, 2
)
SELECT COALESCE(a.rol, r.rol) AS rol, COALESCE(a.mes, r.mes) AS mes,
       a.n AS usuarios_anon, r.n AS usuarios_real,
       COALESCE(a.n, 0) - COALESCE(r.n, 0) AS diferencia
FROM anon a FULL OUTER JOIN real r ON r.rol = a.rol AND r.mes = a.mes
ORDER BY 1, 2;

\echo '===== Diferencias (anon EXCEPT real) ∪ (real EXCEPT anon) — esperado: 0 filas ====='
(SELECT rol, to_char(mes_alta, 'YYYY-MM'), count(*) FROM usuario_anon WHERE eliminado = FALSE GROUP BY 1, 2
 EXCEPT
 SELECT rol, to_char(date_trunc('month', fecha_alta), 'YYYY-MM'), count(*) FROM usuario WHERE eliminado = FALSE GROUP BY 1, 2)
UNION ALL
(SELECT rol, to_char(date_trunc('month', fecha_alta), 'YYYY-MM'), count(*) FROM usuario WHERE eliminado = FALSE GROUP BY 1, 2
 EXCEPT
 SELECT rol, to_char(mes_alta, 'YYYY-MM'), count(*) FROM usuario_anon WHERE eliminado = FALSE GROUP BY 1, 2);

\echo '===== Totales de control ====='
SELECT (SELECT count(*) FROM usuario_anon WHERE eliminado = FALSE) AS total_anon,
       (SELECT count(*) FROM usuario      WHERE eliminado = FALSE) AS total_real,
       (SELECT count(DISTINCT (rol, mes_alta)) FROM usuario_anon WHERE eliminado = FALSE) AS grupos_anon,
       (SELECT count(DISTINCT (rol, date_trunc('month', fecha_alta))) FROM usuario WHERE eliminado = FALSE) AS grupos_real;
