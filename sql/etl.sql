USE zirconia_conductivity;

-- 为了防止脏数据报错，先清空目标表

INSERT INTO material_samples (sample_id, reference, material_source_and_purity, synthesis_method, processing_route, operating_temperature, conductivity)
SELECT
    sample_id,
    reference,
    material_source_and_purity,
    -- 清洗制备方法：'/' 转为 NULL
    NULLIF(TRIM(synthesis_method), '/') AS synthesis_method,
    -- 清洗工艺路线：'/' 转为 NULL
    NULLIF(TRIM(processing_route), '/') AS processing_route,
    -- 清洗工作温度：提取数字
    CAST(REGEXP_SUBSTR(operating_temperature, '[0-9.]+') AS FLOAT) AS operating_temperature,
    -- 【核心清洗】电导率：去空格 -> 替换中文'×'为'E' -> 替换'*'为'E' -> 转双精度
    CAST(
            REPLACE(
                    REPLACE(
                            REPLACE(conductivity, ' ', ''),
                            '×10', 'E'),
                    '*10', 'E')
        AS DOUBLE) AS conductivity
FROM
    raw_conductivity_samples;

SELECT CONCAT('主表加载完成，共 ', COUNT(*), ' 条数据') AS Result FROM material_samples;

INSERT INTO sample_dopants (sample_id, dopant_element, dopant_ionic_radius, dopant_valence, dopant_molar_fraction)
SELECT
    sample_id,
    elt AS dopant_element,
    NULLIF(rad, '/') AS dopant_ionic_radius, -- 处理空值
    -- 处理价态：去掉'+'，处理'或'的情况(这里简化取第一个值，如需复杂逻辑可调整)
    CAST(SUBSTRING_INDEX(REPLACE(val, '或', '/'), '/', 1) AS DECIMAL(10,2)) AS dopant_valence,
    -- 处理比例：去掉'%'，如果是百分数则除以100，如果是小数则保留
    CASE
        WHEN frac LIKE '%\%%' THEN CAST(REPLACE(frac, '%', '') AS DECIMAL(10,4)) / 100
        WHEN frac = '/' THEN NULL
        ELSE CAST(frac AS DECIMAL(10,4))
        END AS dopant_molar_fraction
FROM (
         -- 使用 UNION ALL 模拟遍历，提取第 1 到第 5 个位置的掺杂元素
         SELECT
             sample_id,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_element, '/', n), '/', -1)) AS elt,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_ionic_radius, '/', n), '/', -1)) AS rad,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_valence, '/', n), '/', -1)) AS val,
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(dopant_molar_fraction, '/', n), '/', -1)) AS frac,
             n,
             -- 计算该行实际有多少个掺杂元素 (通过计算 '/' 的数量 + 1)
             LENGTH(dopant_element) - LENGTH(REPLACE(dopant_element, '/', '')) + 1 AS total_dopants
         FROM raw_conductivity_samples
                  CROSS JOIN (
             SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
         ) numbers
         WHERE dopant_element IS NOT NULL AND dopant_element != '/'
     ) AS extracted
WHERE n <= total_dopants; -- 只保留有效的层级

SELECT CONCAT('掺杂表加载完成，共 ', COUNT(*), ' 条数据') AS Result FROM sample_dopants;




INSERT INTO sintering_steps (sample_id, step_order, sintering_temperature, sintering_duration)
SELECT
    sample_id,
    n AS step_order,
    -- 提取温度
    CAST(NULLIF(temp_str, '/') AS FLOAT) AS sintering_temperature,
    -- 【核心清洗】时间换算逻辑
    CASE
        WHEN dur_str LIKE '%h%' THEN CAST(REPLACE(dur_str, 'h', '') AS DECIMAL(10,2)) * 60
        WHEN dur_str LIKE '%min%' THEN CAST(REPLACE(dur_str, 'min', '') AS DECIMAL(10,2))
        WHEN dur_str = '/' THEN NULL
        WHEN dur_str = '' THEN NULL
        ELSE CAST(dur_str AS DECIMAL(10,2)) -- 默认为分钟
        END AS sintering_duration
FROM (
         SELECT
             sample_id,
             n,
             -- 根据逗号 ',' 或斜杠 '/' 拆分温度 (有些数据可能混用，这里主要针对逗号)
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(sintering_temperature, ',', n), ',', -1)) AS temp_str,
             -- 根据逗号 ',' 拆分时间
             TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(sintering_duration, ',', n), ',', -1)) AS dur_str,
             -- 计算总步骤数
             LENGTH(sintering_temperature) - LENGTH(REPLACE(sintering_temperature, ',', '')) + 1 AS total_steps
         FROM raw_conductivity_samples
                  CROSS JOIN (
             SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 -- 假设最多3步烧结
         ) numbers
         WHERE sintering_temperature != '/' AND sintering_temperature IS NOT NULL
     ) AS steps
WHERE n <= total_steps;

SELECT CONCAT('烧结步骤表加载完成，共 ', COUNT(*), ' 条数据') AS Result FROM sintering_steps;


INSERT INTO sample_crystal_phases (sample_id, crystal_id, is_major_phase)
SELECT
    r.sample_id,
    d.id AS crystal_id,
    -- 简单的逻辑：如果只包含一种晶型，或者是第一个出现的，则为主相 (需根据实际业务调整)
    CASE WHEN n = 1 THEN TRUE ELSE FALSE END AS is_major_phase
FROM (
         SELECT
             sample_id,
             -- 将 '+' 统一替换为 '/' 以便统一分割
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


SELECT CONCAT('晶型关联表加载完成，共 ', COUNT(*), ' 条数据') AS Result FROM sample_crystal_phases;

-- 验证样本 193 的烧结步骤拆分
SELECT * FROM sintering_steps WHERE sample_id = 193 ORDER BY step_order;

-- 验证样本 8 (复杂掺杂 Y/Fe/Zn) 的拆分
SELECT * FROM sample_dopants WHERE sample_id = 8;