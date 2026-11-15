-- Release 1 : la carte ESP32 PrédiMaint mesure aussi la température et l'humidité (DHT22).
-- ADD VALUE est accepté dans une transaction (PostgreSQL 12+) tant que la valeur n'est pas utilisée
-- dans cette même transaction : le seed, exécuté ensuite, peut donc s'en servir.
ALTER TYPE type_mesure ADD VALUE IF NOT EXISTS 'TEMPERATURE';
ALTER TYPE type_mesure ADD VALUE IF NOT EXISTS 'HUMIDITE';
