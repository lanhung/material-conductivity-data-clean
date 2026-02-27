
-- This script is used to test cleaning strategies for each field

use zirconia_conductivity;


-- Clean conductivity
-- Convert conductivity scientific notation to a format MySQL can cast to DOUBLE
SELECT
    sample_id,
    conductivity AS original_value,
    -- Step 1: Remove possible spaces
    -- Step 2: Replace '×10' with 'E'
    -- Step 3: Replace possible '10^' (if data contains carats) with 'E'
    CAST(
            REPLACE(
                    REPLACE(
                            REPLACE(conductivity, ' ', ''),  -- Remove spaces
                            '×10', 'E'),                         -- Replace special multiplication sign
                    '*10', 'E')                              -- Replace regular multiplication sign (just in case)
        AS DOUBLE) AS cleaned_value_preview
FROM
    raw_conductivity_samples
WHERE
    conductivity LIKE '%×%';


-- Clean sintering_temperature
-- Replace '/' with NULL for samples without heat treatment
SELECT
    sample_id,
    sintering_temperature AS original_data,
    -- NULLIF(a, b) means: if a equals b, return NULL; otherwise return a
    NULLIF(sintering_temperature, '/') AS suggested_NULL
FROM
    raw_conductivity_samples
WHERE
    sintering_temperature = '/';


-- Clean sintering_duration
-- Remove spaces from sintering_duration data
SELECT
    sample_id,
    sintering_duration AS original_data,
    REPLACE(sintering_duration, ' ', '') AS spaces_removed_preview
FROM
    raw_conductivity_samples
WHERE
    sintering_duration LIKE '% %';
-- Replace '/' with NULL for samples without heat treatment duration
SELECT
    sample_id,
    sintering_duration AS original_data,
    -- Fix: use NULLIF, meaning "if the content is exactly '/', convert it to NULL"
    NULLIF(sintering_duration, '/') AS cleaned_preview
FROM
    raw_conductivity_samples
WHERE
    -- Use exact match here to prevent false positives (e.g., to avoid selecting range data like "10/20")
    sintering_duration = '/';
-- Convert h to min (hours to minutes)
SELECT
    sample_id,
    sintering_duration AS original_data,
    -- Logic: remove 'h' -> remove possible spaces -> cast to decimal -> multiply by 60
    CAST(REPLACE(REPLACE(sintering_duration, 'h', ''), ' ', '') AS DECIMAL(10, 4)) * 60 AS converted_to_minutes_preview
FROM
    raw_conductivity_samples
WHERE
    sintering_duration LIKE '%h%';
-- Remove the unit 'h' from sintering_duration, keeping only the number
SELECT
    sample_id,
    sintering_duration AS original_data,
    REPLACE(sintering_duration, 'h', '') AS value_after_removing_h
FROM
    raw_conductivity_samples
WHERE
    -- Only select rows that still contain 'h'
    sintering_duration LIKE '%h%';
-- Combined cleaning logic for all cases above
SELECT
    sample_id,
    sintering_duration AS original_data,
    CASE
        -- 1. Highest priority: handle '/' (no heat treatment duration) -> convert to NULL
        WHEN REPLACE(sintering_duration, ' ', '') = '/' THEN NULL

        -- 2. Handle 'h' (hours to minutes)
        -- Logic: remove 'h', cast to number, then * 60 (e.g., '2h' -> 2 * 60 = 120)
        WHEN sintering_duration LIKE '%h%' THEN
            CAST(REPLACE(REPLACE(sintering_duration, ' ', ''), 'h', '') AS DECIMAL(10, 4)) * 60

        -- 3. Handle 'min' (unit is already minutes)
        -- Logic: remove 'min', value stays the same (e.g., '30min' -> 30)
        WHEN sintering_duration LIKE '%min%' THEN
            REPLACE(REPLACE(sintering_duration, ' ', ''), 'min', '')

        -- 4. Fallback: handle pure numbers with spaces only
        -- Logic: assume values without units are already in minutes, just remove spaces
        ELSE REPLACE(sintering_duration, ' ', '')
        END AS cleaned_preview_minutes

FROM
    raw_conductivity_samples
WHERE
   -- Select rows that need processing
    sintering_duration LIKE '% %'      -- Contains spaces
   OR sintering_duration LIKE '%/%'   -- Contains slash
   OR sintering_duration LIKE '%min%' -- Contains min
   OR sintering_duration LIKE '%h%';


-- Replace '/' with NULL in synthesis_method (synthesis method)
SELECT
    sample_id,
    synthesis_method AS original_data,
    -- Logic: if content is '/', return NULL; otherwise keep the original value
    NULLIF(synthesis_method, '/') AS cleaned_preview
FROM
    raw_conductivity_samples
WHERE
    -- Select rows containing '/'
    synthesis_method LIKE '%/%';


-- Replace '/' with NULL in processing_route (processing route)
SELECT
    sample_id,
    processing_route AS original_data,
    -- Logic: first remove possible spaces, if result is '/', return NULL
    NULLIF(REPLACE(processing_route, ' ', ''), '/') AS cleaned_preview
FROM
    raw_conductivity_samples
WHERE
    -- Select rows containing '/'
    processing_route LIKE '%/%';

-- Clean dopant_valence
SELECT
    sample_id,
    dopant_element,
    dopant_valence AS original_valence,

    -- Show element count
    (CHAR_LENGTH(dopant_element) - CHAR_LENGTH(REPLACE(dopant_element, '/', '')) + 1) AS n_elem,
    -- Show valence count
    (CHAR_LENGTH(dopant_valence) - CHAR_LENGTH(REPLACE(dopant_valence, '/', '')) + 1) AS n_val,

    -- [Core fix logic preview]
    CASE
        -- Case 1: fewer valences than elements -> pad to match
        WHEN (CHAR_LENGTH(dopant_valence) - CHAR_LENGTH(REPLACE(dopant_valence, '/', '')) + 1) < (CHAR_LENGTH(dopant_element) - CHAR_LENGTH(REPLACE(dopant_element, '/', '')) + 1)
            THEN CONCAT(
                dopant_valence,
                REPEAT(
                        CONCAT('/', SUBSTRING_INDEX(dopant_valence, '/', -1)),
                        (CHAR_LENGTH(dopant_element) - CHAR_LENGTH(REPLACE(dopant_element, '/', '')) + 1) - (CHAR_LENGTH(dopant_valence) - CHAR_LENGTH(REPLACE(dopant_valence, '/', '')) + 1)
                )
                 )

        -- Case 2: more valences than elements -> truncate
        WHEN (CHAR_LENGTH(dopant_valence) - CHAR_LENGTH(REPLACE(dopant_valence, '/', '')) + 1) > (CHAR_LENGTH(dopant_element) - CHAR_LENGTH(REPLACE(dopant_element, '/', '')) + 1)
            THEN SUBSTRING_INDEX(
                dopant_valence,
                '/',
                (CHAR_LENGTH(dopant_element) - CHAR_LENGTH(REPLACE(dopant_element, '/', '')) + 1)
                 )

        ELSE dopant_valence -- Normal case
        END AS fixed_valence

FROM
    raw_conductivity_samples
WHERE
    dopant_valence IS NOT NULL AND dopant_valence != ''
HAVING
    -- Only show rows with mismatched counts
    n_val != n_elem;


-- Purpose: preview keeping content before 'or' (Chinese character), discarding 'or' and everything after it
SELECT
    sample_id,
    dopant_valence AS original_data,
    -- Logic: take all characters before the first 'or' (e.g., '3或4' -> '3')
    SUBSTRING_INDEX(dopant_valence, '或', 1) AS cleaned_preview
FROM
    raw_conductivity_samples
WHERE
    dopant_valence LIKE '%或%';

-- Clean crystal_phase
-- Purpose: preview replacing crystal_phase values that are exactly '/' with NULL
SELECT
    sample_id,
    crystal_phase AS original_data,
    NULL AS cleaned_preview -- Since the condition is exact match on '/', the cleaned result will always be NULL
FROM
    raw_conductivity_samples
WHERE
    crystal_phase = '/'; -- Exact match, not using % wildcard