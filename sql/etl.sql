USE zirconia_conductivity;

-- Clear target tables first to prevent dirty data errors

INSERT INTO material_samples (sample_id, reference, material_source_and_purity, synthesis_method, processing_route, operating_temperature, conductivity)
SELECT
    sample_id,
    reference,
    material_source_and_purity,
    -- Clean synthesis method: convert '/' to NULL
    NULLIF(TRIM(synthesis_method), '/') AS synthesis_method,
    -- Clean processing route: convert '/' to NULL
    NULLIF(TRIM(processing_route), '/') AS processing_route,
    -- Clean operating temperature: extract numeric value
    CAST(REGEXP_SUBSTR(operating_temperature, '[0-9.]+') AS FLOAT) AS operating_temperature,
    -- [Core cleaning] Conductivity: remove spaces -> replace Chinese 'x' with 'E' -> replace '*' with 'E' -> cast to double
    CAST(
            REPLACE(
                    REPLACE(
                            REPLACE(conductivity, ' ', ''),
                            '×10', 'E'),
                    '*10', 'E')
        AS DOUBLE) AS conductivity
FROM
    raw_conductivity_samples;

SELECT CONCAT('Main table loaded, total ', COUNT(*), ' records') AS Result FROM material_samples;

INSERT INTO sample_dopants (sample_id, dopant_element, dopant_ionic_radius, dopant_valence, dopant_molar_fraction)
SELECT
    sample_id,
    elt AS dopant_element,
    NULLIF(rad, '/') AS dopant_ionic_radius, -- Handle null values
    -- Handle valence: remove '+', handle 'or' cases (simplified to take the first value; adjust for more complex logic if needed)
    CAST(SUBSTRING_INDEX(REPLACE(val, '或', '/'), '/', 1) AS DECIMAL(10,2)) AS dopant_valence,
    -- Handle fraction: remove '%', divide by 100 if percentage, keep as-is if decimal
    CASE
        WHEN frac LIKE '%\%%' THEN CAST(REPLACE(frac, '%', '') AS DECIMAL(10,4)) / 100
        WHEN frac = '/' THEN NULL
        ELSE CAST(frac AS DECIMAL(10,4))
        END AS dopant_molar_fraction
FROM (
         -- Use UNION ALL to simulate iteration, extracting dopant elements at positions 1 through 5
         SELECT
             sample_id,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_element, '/', n), '/', -1)) AS elt,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_ionic_radius, '/', n), '/', -1)) AS rad,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_valence, '/', n), '/', -1)) AS val,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_molar_fraction, '/', n), '/', -1)) AS frac,
             n,
             -- Calculate the actual number of dopant elements per row (by counting '/' occurrences + 1)
             LENGTH(dopant_element) - LENGTH(REPLACE(dopant_element, '/', '')) + 1 AS total_dopants
         FROM raw_conductivity_samples
                  CROSS JOIN (
             SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
         ) numbers
         WHERE dopant_element IS NOT NULL AND dopant_element != '/'
     ) AS extracted
WHERE n <= total_dopants; -- Only keep valid levels

SELECT CONCAT('Dopant table loaded, total ', COUNT(*), ' records') AS Result FROM sample_dopants;




INSERT INTO sintering_steps (sample_id, step_order, sintering_temperature, sintering_duration)
SELECT
    sample_id,
    n AS step_order,
    -- Extract temperature
    CAST(NULLIF(temp_str, '/') AS FLOAT) AS sintering_temperature,
    -- [Core cleaning] Duration conversion logic
    CASE
        WHEN dur_str LIKE '%h%' THEN CAST(REPLACE(dur_str, 'h', '') AS DECIMAL(10,2)) * 60
        WHEN dur_str LIKE '%min%' THEN CAST(REPLACE(dur_str, 'min', '') AS DECIMAL(10,2))
        WHEN dur_str = '/' THEN NULL
        WHEN dur_str = '' THEN NULL
        ELSE CAST(dur_str AS DECIMAL(10,2)) -- Default unit is minutes
        END AS sintering_duration
FROM (
         SELECT
             sample_id,
             n,
             -- Split temperature by comma ',' or slash '/' (some data may mix both; here mainly targeting commas)
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(sintering_temperature, ',', n), ',', -1)) AS temp_str,
             -- Split duration by comma ','
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(sintering_duration, ',', n), ',', -1)) AS dur_str,
             -- Calculate total number of steps
             LENGTH(sintering_temperature) - LENGTH(REPLACE(sintering_temperature, ',', '')) + 1 AS total_steps
         FROM raw_conductivity_samples
                  CROSS JOIN (
             SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 -- Assume at most 3 sintering steps
         ) numbers
         WHERE sintering_temperature != '/' AND sintering_temperature IS NOT NULL
     ) AS steps
WHERE n <= total_steps;

SELECT CONCAT('Sintering steps table loaded, total ', COUNT(*), ' records') AS Result FROM sintering_steps;


INSERT INTO sample_crystal_phases (sample_id, crystal_id, is_major_phase)
SELECT
    r.sample_id,
    d.id AS crystal_id,
    -- Simple logic: if only one crystal phase, or the first one found, treat as major phase (adjust based on actual business rules)
    CASE WHEN n = 1 THEN TRUE ELSE FALSE END AS is_major_phase
FROM (
         SELECT
             sample_id,
             -- Replace '+' with '/' for uniform splitting
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(REPLACE(crystal_phase, '+', '/'), '/', n), '/', -1)) AS phase_code,
             n,
             LENGTH(REPLACE(crystal_phase, '+', '/')) - LENGTH(REPLACE(REPLACE(crystal_phase, '+', '/'), '/', '')) + 1 AS total_phases
         FROM raw_conductivity_samples
                  CROSS JOIN (
             SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3
         ) numbers
         WHERE crystal_phase != '/' AND crystal_phase IS NOT NULL
     ) r
         JOIN crystal_structure_dict d ON r.phase_code = d.code
WHERE r.n <= r.total_phases;

SET SQL_SAFE_UPDATES = 0;
UPDATE material_samples ms
    JOIN tmp_translate_result ttr ON ms.sample_id = ttr.sample_id
SET
    ms.material_source_and_purity = ttr.material_source_and_purity,
    ms.synthesis_method = ttr.synthesis_method,
    ms.processing_route = ttr.processing_route;


SELECT CONCAT('Crystal phase association table loaded, total ', COUNT(*), ' records') AS Result FROM sample_crystal_phases;

-- Verify sintering step splitting for sample 193
SELECT * FROM sintering_steps WHERE sample_id = 193 ORDER BY step_order;

-- Verify splitting for sample 8 (complex dopants Y/Fe/Zn)
SELECT * FROM sample_dopants WHERE sample_id = 8;