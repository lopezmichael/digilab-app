-- Scene Naming & Slug Standardization
-- Phase 5 of Discord Restructure
--
-- Changes:
-- 1. display_name: remove country/state prefix → clean metro name
-- 2. slug: acronyms → full city names for readability
--
-- Run inside a transaction so it's all-or-nothing.

BEGIN;

-- =============================================
-- DISPLAY NAME: strip "Country (Metro)" → "Metro"
-- =============================================

-- Argentina
UPDATE scenes SET display_name = 'Buenos Aires' WHERE scene_id = 70;

-- Australia
UPDATE scenes SET display_name = 'Hobart' WHERE scene_id = 32;
UPDATE scenes SET display_name = 'Sydney' WHERE scene_id = 24;

-- Brazil
UPDATE scenes SET display_name = 'Belém' WHERE scene_id = 62;
UPDATE scenes SET display_name = 'Brasília' WHERE scene_id = 75;
UPDATE scenes SET display_name = 'Goiás' WHERE scene_id = 57;
UPDATE scenes SET display_name = 'Minas Gerais' WHERE scene_id = 30;
UPDATE scenes SET display_name = 'Paraná' WHERE scene_id = 56;
UPDATE scenes SET display_name = 'Rio Grande do Sul' WHERE scene_id = 76;
UPDATE scenes SET display_name = 'Santa Catarina' WHERE scene_id = 21;
UPDATE scenes SET display_name = 'São Paulo' WHERE scene_id = 13;
UPDATE scenes SET display_name = 'Teresina' WHERE scene_id = 77;

-- Canada
UPDATE scenes SET display_name = 'Alberta' WHERE scene_id = 79;
UPDATE scenes SET display_name = 'Metro Vancouver' WHERE scene_id = 6;
UPDATE scenes SET display_name = 'Ottawa' WHERE scene_id = 78;

-- Chile
UPDATE scenes SET display_name = 'Antofagasta' WHERE scene_id = 71;

-- Colombia
UPDATE scenes SET display_name = 'Barranquilla' WHERE scene_id = 60;

-- Costa Rica
UPDATE scenes SET display_name = 'Heredia' WHERE scene_id = 52;

-- Croatia
UPDATE scenes SET display_name = 'Split' WHERE scene_id = 72;

-- Denmark
UPDATE scenes SET display_name = 'Copenhagen' WHERE scene_id = 16;

-- France
UPDATE scenes SET display_name = 'Paris' WHERE scene_id = 35;
UPDATE scenes SET display_name = 'Toulouse' WHERE scene_id = 61;

-- Germany
UPDATE scenes SET display_name = 'Aachen' WHERE scene_id = 48;
UPDATE scenes SET display_name = 'Berlin' WHERE scene_id = 43;
UPDATE scenes SET display_name = 'Frankfurt' WHERE scene_id = 37;
UPDATE scenes SET display_name = 'Hamburg' WHERE scene_id = 36;
UPDATE scenes SET display_name = 'Hannover' WHERE scene_id = 51;
UPDATE scenes SET display_name = 'Karlsruhe' WHERE scene_id = 84;
UPDATE scenes SET display_name = 'Osnabrück' WHERE scene_id = 45;
UPDATE scenes SET display_name = 'Rhein-Ruhr' WHERE scene_id = 44;

-- Indonesia
UPDATE scenes SET display_name = 'Bali' WHERE scene_id = 64;

-- Italy
UPDATE scenes SET display_name = 'Lombardia' WHERE scene_id = 54;
UPDATE scenes SET display_name = 'Rome' WHERE scene_id = 38;

-- Mexico
UPDATE scenes SET display_name = 'Monterrey' WHERE scene_id = 86;

-- New Zealand
UPDATE scenes SET display_name = 'Wellington' WHERE scene_id = 27;

-- Portugal
UPDATE scenes SET display_name = 'Azores' WHERE scene_id = 17;
UPDATE scenes SET display_name = 'Lisbon' WHERE scene_id = 34;
UPDATE scenes SET display_name = 'Porto' WHERE scene_id = 31;

-- Saudi Arabia
UPDATE scenes SET display_name = 'Riyadh' WHERE scene_id = 66;

-- Spain
UPDATE scenes SET display_name = 'Asturias' WHERE scene_id = 74;
UPDATE scenes SET display_name = 'Catalonia' WHERE scene_id = 50;
UPDATE scenes SET display_name = 'Cádiz' WHERE scene_id = 46;
UPDATE scenes SET display_name = 'Galicia' WHERE scene_id = 49;
UPDATE scenes SET display_name = 'Granada' WHERE scene_id = 18;
UPDATE scenes SET display_name = 'Madrid' WHERE scene_id = 40;
UPDATE scenes SET display_name = 'Mallorca' WHERE scene_id = 47;
UPDATE scenes SET display_name = 'Seville' WHERE scene_id = 73;
UPDATE scenes SET display_name = 'Valencia' WHERE scene_id = 65;

-- United Kingdom
UPDATE scenes SET display_name = 'Derby' WHERE scene_id = 8;
UPDATE scenes SET display_name = 'Manchester' WHERE scene_id = 14;

-- United States
UPDATE scenes SET display_name = 'Phoenix' WHERE scene_id = 67;
UPDATE scenes SET display_name = 'Bay Area' WHERE scene_id = 58;
UPDATE scenes SET display_name = 'Central Valley' WHERE scene_id = 59;
UPDATE scenes SET display_name = 'Orange County' WHERE scene_id = 83;
UPDATE scenes SET display_name = 'Fort Lauderdale' WHERE scene_id = 69;
UPDATE scenes SET display_name = 'Miami' WHERE scene_id = 33;
UPDATE scenes SET display_name = 'Tampa Bay' WHERE scene_id = 63;
UPDATE scenes SET display_name = 'Treasure Coast' WHERE scene_id = 29;
UPDATE scenes SET display_name = 'NW Chicago' WHERE scene_id = 28;
UPDATE scenes SET display_name = 'Kansas City' WHERE scene_id = 9;
UPDATE scenes SET display_name = 'Hudson Valley' WHERE scene_id = 15;
UPDATE scenes SET display_name = 'NYC' WHERE scene_id = 19;
UPDATE scenes SET display_name = 'Asheville' WHERE scene_id = 41;
UPDATE scenes SET display_name = 'Cincinnati Area' WHERE scene_id = 12;
UPDATE scenes SET display_name = 'Cleveland' WHERE scene_id = 55;
UPDATE scenes SET display_name = 'Columbus' WHERE scene_id = 39;
UPDATE scenes SET display_name = 'Tulsa-OKC' WHERE scene_id = 20;
UPDATE scenes SET display_name = 'NEPA' WHERE scene_id = 10;
UPDATE scenes SET display_name = 'College Station' WHERE scene_id = 82;
UPDATE scenes SET display_name = 'Dallas-Fort Worth' WHERE scene_id = 4;
UPDATE scenes SET display_name = 'Houston' WHERE scene_id = 85;
UPDATE scenes SET display_name = 'Lubbock' WHERE scene_id = 81;
UPDATE scenes SET display_name = 'DMV' WHERE scene_id = 25;
UPDATE scenes SET display_name = 'Richmond' WHERE scene_id = 11;

-- =============================================
-- SLUG: acronyms → readable city names
-- =============================================

UPDATE scenes SET slug = 'santa-catarina' WHERE scene_id = 21 AND slug = 'scbr';
UPDATE scenes SET slug = 'sao-paulo' WHERE scene_id = 13 AND slug = 'sampa';
UPDATE scenes SET slug = 'metro-vancouver' WHERE scene_id = 6 AND slug = 'gva';
UPDATE scenes SET slug = 'copenhagen' WHERE scene_id = 16 AND slug = 'cph';
UPDATE scenes SET slug = 'azores' WHERE scene_id = 17 AND slug = 'prt';
UPDATE scenes SET slug = 'manchester' WHERE scene_id = 14 AND slug = 'mcr';
UPDATE scenes SET slug = 'wellington' WHERE scene_id = 27 AND slug = 'wlg';
UPDATE scenes SET slug = 'fort-lauderdale' WHERE scene_id = 69 AND slug = 'ftlaudy';
UPDATE scenes SET slug = 'bay-area' WHERE scene_id = 58 AND slug = 'bayarea';
UPDATE scenes SET slug = 'central-valley' WHERE scene_id = 59 AND slug = 'cencal';
UPDATE scenes SET slug = 'nw-chicago' WHERE scene_id = 28 AND slug = 'nwchi';
UPDATE scenes SET slug = 'kansas-city' WHERE scene_id = 9 AND slug = 'mci';
UPDATE scenes SET slug = 'new-york-city' WHERE scene_id = 19 AND slug = 'nyc';
UPDATE scenes SET slug = 'cincinnati' WHERE scene_id = 12 AND slug = 'cvg';
UPDATE scenes SET slug = 'columbus' WHERE scene_id = 39 AND slug = 'colombus';
UPDATE scenes SET slug = 'tulsa-okc' WHERE scene_id = 20 AND slug = 'oklahoma';
UPDATE scenes SET slug = 'northeastern-pa' WHERE scene_id = 10 AND slug = 'nepa';
UPDATE scenes SET slug = 'dallas-fort-worth' WHERE scene_id = 4 AND slug = 'dfw';
UPDATE scenes SET slug = 'dc-metro' WHERE scene_id = 25 AND slug = 'dmv';
UPDATE scenes SET slug = 'richmond' WHERE scene_id = 11 AND slug = 'rva';

COMMIT;
