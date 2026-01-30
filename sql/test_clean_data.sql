
-- 这份脚本是用来测试各个字段的清洗策略

use zirconia_conductivity;


-- 清洗conductivity
-- 把 conductivity的科学计数法转为mysql可以转double的格式
SELECT
    sample_id,
    conductivity AS original_value,
    -- 第一步：去除可能存在的空格
    -- 第二步：将 '×10' 替换为 'E'
    -- 第三步：将可能存在的 '10^' (如果你的数据有 carats) 替换为 'E'
    CAST(
            REPLACE(
                    REPLACE(
                            REPLACE(conductivity, ' ', ''),  -- 去除空格
                            '×10', 'E'),                         -- 替换特殊乘号
                    '*10', 'E')                              -- 替换普通乘号 (以防万一)
        AS DOUBLE) AS cleaned_value_preview
FROM
    raw_conductivity_samples
WHERE
    conductivity LIKE '%×%';


-- 清洗sintering_temperature
-- 没有加热处理的把‘/’替换为null
SELECT
    sample_id,
    sintering_temperature AS 原数据,
    -- NULLIF(a, b) 的意思是：如果 a 等于 b，就返回 NULL，否则返回 a
    NULLIF(sintering_temperature, '/') AS 建议_变为NULL
FROM
    raw_conductivity_samples
WHERE
    sintering_temperature = '/';


-- 清洗sintering_duration
-- 清洗sintering_duration数据中的空格
SELECT
    sample_id,
    sintering_duration AS 原数据,
    REPLACE(sintering_duration, ' ', '') AS 去空格预览
FROM
    raw_conductivity_samples
WHERE
    sintering_duration LIKE '% %';
-- 没有加热时间把‘/’替换为null
SELECT
    sample_id,
    sintering_duration AS 原数据,
    -- 修正点：使用 NULLIF，含义是 "如果内容刚好是 '/'，就把它变成 NULL"
    NULLIF(sintering_duration, '/') AS 清洗后预览
FROM
    raw_conductivity_samples
WHERE
    -- 这里建议用精确匹配，防止误伤（例如防止把 "10/20" 这种范围数据也选出来）
    sintering_duration = '/';
-- h转min (小时转分钟)
SELECT
    sample_id,
    sintering_duration AS 原数据,
    -- 逻辑：去掉 'h' -> 去掉可能存在的空格 -> 转小数 -> 乘以 60
    CAST(REPLACE(REPLACE(sintering_duration, 'h', ''), ' ', '') AS DECIMAL(10, 4)) * 60 AS 转换为分钟_预览
FROM
    raw_conductivity_samples
WHERE
    sintering_duration LIKE '%h%';
-- 将 sintering_duration 中的单位 'h' 替换掉，仅保留数字
SELECT
    sample_id,
    sintering_duration AS 原数据,
    REPLACE(sintering_duration, 'h', '') AS 去掉h后的数值
FROM
    raw_conductivity_samples
WHERE
    -- 只筛选出还带有 'h' 的行
    sintering_duration LIKE '%h%';
-- 以上合并
SELECT
    sample_id,
    sintering_duration AS 原数据,
    CASE
        -- 1. 优先级最高：处理 '/' (无加热时间) -> 变 NULL
        WHEN REPLACE(sintering_duration, ' ', '') = '/' THEN NULL

        -- 2. 处理 'h' (小时 转 分钟)
        -- 逻辑：去掉 'h'，转数字，然后 * 60 (例如 '2h' -> 2 * 60 = 120)
        WHEN sintering_duration LIKE '%h%' THEN
            CAST(REPLACE(REPLACE(sintering_duration, ' ', ''), 'h', '') AS DECIMAL(10, 4)) * 60

        -- 3. 处理 'min' (单位本身就是分钟)
        -- 逻辑：去掉 'min'，数值保持不变 (例如 '30min' -> 30)
        WHEN sintering_duration LIKE '%min%' THEN
            REPLACE(REPLACE(sintering_duration, ' ', ''), 'min', '')

        -- 4. 兜底逻辑：处理仅含空格的纯数字
        -- 逻辑：假设没写单位的已经是分钟了，只去空格
        ELSE REPLACE(sintering_duration, ' ', '')
        END AS 清洗后预览_分钟

FROM
    raw_conductivity_samples
WHERE
   -- 筛选出需要处理的行
    sintering_duration LIKE '% %'      -- 含空格
   OR sintering_duration LIKE '%/%'   -- 含斜杠
   OR sintering_duration LIKE '%min%' -- 含 min
   OR sintering_duration LIKE '%h%';


-- 将 synthesis_method (制备方法) 中的 '/' 替换为 NULL
SELECT
    sample_id,
    synthesis_method AS 原数据,
    -- 逻辑：如果内容是 '/'，则返回 NULL；否则保留原值
    NULLIF(synthesis_method, '/') AS 清洗后预览
FROM
    raw_conductivity_samples
WHERE
    -- 筛选出包含 '/' 的行
    synthesis_method LIKE '%/%';


-- 将 processing_route (制备工艺路线) 中的 '/' 替换为 NULL
SELECT
    sample_id,
    processing_route AS 原数据,
    -- 逻辑：先去除可能存在的空格，如果结果是 '/'，则返回 NULL
    NULLIF(REPLACE(processing_route, ' ', ''), '/') AS 清洗后预览
FROM
    raw_conductivity_samples
WHERE
    -- 筛选出包含 '/' 的行
    processing_route LIKE '%/%';

-- 清洗dopant_valence
-- 目的：预览将 dopant_valence (掺杂价态) 中的中文 "或" 替换为 "/"
SELECT
    sample_id,
    dopant_valence AS 原数据,
    -- 逻辑：将 '或' 替换为 '/' (例如 '3或4' -> '3/4')
    REPLACE(dopant_valence, '或', '/') AS 清洗后预览
FROM
    raw_conductivity_samples
WHERE
    dopant_valence LIKE '%或%';

-- 清洗crystal_phase
-- 目的：预览将 crystal_phase 完全等于 '/' 的行替换为 NULL
SELECT
    sample_id,
    crystal_phase AS 原数据,
    NULL AS 清洗后预览 -- 因为条件是完全匹配 '/'，所以清洗后结果必然是 NULL
FROM
    raw_conductivity_samples
WHERE
    crystal_phase = '/'; -- 精确匹配，不使用 % 通配符