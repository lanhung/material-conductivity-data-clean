
-- drop database zirconia_conductivity;
create database if not exists zirconia_conductivity;

use zirconia_conductivity;




-- 氧化锆基电导率样本数据表（单表，不拆掺杂维度）
CREATE TABLE raw_conductivity_samples
(

    -- 样本编号（对应 Excel 的序号）
    sample_id                  INT PRIMARY KEY,

    -- 文献来源（DOI 或期刊信息）
    reference                  VARCHAR(255),

    -- 原材料来源与纯度信息
    material_source_and_purity text,

    -- 材料制备方法（如 solid-state, sol-gel, SPS 等）
    synthesis_method           VARCHAR(255),

    -- 制备工艺路线描述
    processing_route           VARCHAR(255),

    -- 烧结/热处理温度
    sintering_temperature      VARCHAR(50),

    -- 热处理（烧结）时间
    sintering_duration         VARCHAR(50),

    -- 掺杂元素符号（Y, Sc, Dy 等）
    dopant_element             VARCHAR(50),

    -- 掺杂元素离子半径
    dopant_ionic_radius        VARCHAR(50),

    -- 掺杂元素价态（例如 3 对应 +3）
    dopant_valence             VARCHAR(50),

    -- 掺杂摩尔分数（对应形成氧化物占比）
    dopant_molar_fraction      VARCHAR(50),

    -- 晶型（c/t/m/o）
    crystal_phase              VARCHAR(20),

    -- 电导率测试时的工作温度
    operating_temperature      VARCHAR(20),

    -- 电导率（S/cm），机器学习的目标 y
    conductivity               VARCHAR(20)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4;

-- 晶型字典表 (存储标准定义)
CREATE TABLE crystal_structure_dict
(
    id          INT AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(10) NOT NULL UNIQUE, -- 例如: 'c', 't', 'm'
    full_name   VARCHAR(50)                 -- 例如: 'Cubic', 'Tetragonal'
);

-- 预插入常用晶型数据 (根据你的CSV内容)
INSERT INTO crystal_structure_dict (code, full_name)
VALUES ('c', 'Cubic'),
       ('t', 'Tetragonal'),
       ('m', 'Monoclinic'),
       ('o', 'Orthogonal'),
       ('r', 'Rhombohedral'),
       ('β', 'Beta-phase');


-- 样本主表
CREATE TABLE material_samples
(
    sample_id                  INT PRIMARY KEY,
    reference                  VARCHAR(255),
    material_source_and_purity text,
    synthesis_method           VARCHAR(255),
    processing_route           VARCHAR(255),
    operating_temperature      FLOAT,
    conductivity               DOUBLE
);

-- 掺杂明细表
CREATE TABLE sample_dopants
(
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    sample_id             INT NOT NULL,
    dopant_element        VARCHAR(10), -- 元素符号 (如 Y)
    dopant_ionic_radius   FLOAT,       -- 离子半径 (pm)
    dopant_valence        INT,         -- 价态 (如 3.0)
    dopant_molar_fraction FLOAT,       -- 摩尔分数 (如 0.08)
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE
);
-- 烧结步骤表
CREATE TABLE sintering_steps
(
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    sample_id             INT NOT NULL,
    step_order            INT COMMENT '烧结阶段序号',
    sintering_temperature FLOAT, -- 该阶段温度 (℃)
    sintering_duration    FLOAT, -- 该阶段时间 (min)
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE
);

-- 样本-晶型关联表 (解决多相混合问题)
CREATE TABLE sample_crystal_phases
(
    sample_id      INT NOT NULL,
    crystal_id     INT NOT NULL,
    is_major_phase BOOLEAN DEFAULT TRUE COMMENT '是否为主相(可选字段)',

    PRIMARY KEY (sample_id, crystal_id), -- 联合主键，防止重复
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE,
    FOREIGN KEY (crystal_id) REFERENCES crystal_structure_dict (id)
);

-- 临时表，用于存放material_source_and_purity、synthesis_method、processing_route翻译之后的结果
CREATE TABLE tmp_translate_result
(
    sample_id                  INT PRIMARY KEY,
    material_source_and_purity text,
    synthesis_method           VARCHAR(255),
    processing_route           VARCHAR(255)

)