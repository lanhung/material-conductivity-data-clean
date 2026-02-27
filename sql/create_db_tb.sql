
-- drop database zirconia_conductivity;
create database if not exists zirconia_conductivity;

use zirconia_conductivity;




-- Zirconia-based conductivity sample data table (single table, without splitting dopant dimensions)
CREATE TABLE raw_conductivity_samples
(

    -- Sample ID (corresponds to the serial number in Excel)
    sample_id                  INT PRIMARY KEY,

    -- Literature source (DOI or journal information)
    reference                  VARCHAR(255),

    -- Raw material source and purity information
    material_source_and_purity text,

    -- Material synthesis method (e.g., solid-state, sol-gel, SPS, etc.)
    synthesis_method           VARCHAR(255),

    -- Processing route description
    processing_route           VARCHAR(255),

    -- Sintering / heat treatment temperature
    sintering_temperature      VARCHAR(50),

    -- Heat treatment (sintering) duration
    sintering_duration         VARCHAR(50),

    -- Dopant element symbol (Y, Sc, Dy, etc.)
    dopant_element             VARCHAR(50),

    -- Dopant element ionic radius
    dopant_ionic_radius        VARCHAR(50),

    -- Dopant element valence (e.g., 3 corresponds to +3)
    dopant_valence             VARCHAR(50),

    -- Dopant molar fraction (corresponding oxide proportion)
    dopant_molar_fraction      VARCHAR(50),

    -- Crystal phase (c/t/m/o)
    crystal_phase              VARCHAR(20),

    -- Operating temperature during conductivity measurement
    operating_temperature      VARCHAR(20),

    -- Conductivity (S/cm), target y for machine learning
    conductivity               VARCHAR(20)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4;

-- Crystal structure dictionary table (stores standard definitions)
CREATE TABLE crystal_structure_dict
(
    id          INT AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(10) NOT NULL UNIQUE, -- e.g.: 'c', 't', 'm'
    full_name   VARCHAR(50)                 -- e.g.: 'Cubic', 'Tetragonal'
);

-- Pre-insert common crystal structure data (based on CSV content)
INSERT INTO crystal_structure_dict (code, full_name)
VALUES ('c', 'Cubic'),
       ('t', 'Tetragonal'),
       ('m', 'Monoclinic'),
       ('o', 'Orthogonal'),
       ('r', 'Rhombohedral'),
       ('β', 'Beta-phase');


-- Sample main table
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

-- Dopant detail table
CREATE TABLE sample_dopants
(
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    sample_id             INT NOT NULL,
    dopant_element        VARCHAR(10), -- Element symbol (e.g., Y)
    dopant_ionic_radius   FLOAT,       -- Ionic radius (pm)
    dopant_valence        INT,         -- Valence (e.g., 3.0)
    dopant_molar_fraction FLOAT,       -- Molar fraction (e.g., 0.08)
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE
);
-- Sintering steps table
CREATE TABLE sintering_steps
(
    id                    INT AUTO_INCREMENT PRIMARY KEY,
    sample_id             INT NOT NULL,
    step_order            INT COMMENT 'Sintering step number',
    sintering_temperature FLOAT, -- Temperature for this step (C)
    sintering_duration    FLOAT, -- Duration for this step (min)
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE
);

-- Sample-crystal phase association table (resolves multi-phase mixture issue)
CREATE TABLE sample_crystal_phases
(
    sample_id      INT NOT NULL,
    crystal_id     INT NOT NULL,
    is_major_phase BOOLEAN DEFAULT TRUE COMMENT 'Whether it is the major phase (optional field)',

    PRIMARY KEY (sample_id, crystal_id), -- Composite primary key to prevent duplicates
    FOREIGN KEY (sample_id) REFERENCES material_samples (sample_id) ON DELETE CASCADE,
    FOREIGN KEY (crystal_id) REFERENCES crystal_structure_dict (id)
);

-- Temporary table for storing translated results of material_source_and_purity, synthesis_method, processing_route
CREATE TABLE tmp_translate_result
(
    sample_id                  INT PRIMARY KEY,
    material_source_and_purity text,
    synthesis_method           VARCHAR(255),
    processing_route           VARCHAR(255)

)