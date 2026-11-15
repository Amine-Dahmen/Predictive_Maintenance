-- Release 2, US-43 (délai d'envoi des alertes) : heure de la mesure qui a déclenché l'alerte.
-- created_at - mesure_at = délai entre la mesure sur l'ESP32 et la détection par le backend.
-- Conservé tel quel si l'alerte passe ensuite en CRITIQUE (mesure_id change alors).
ALTER TABLE alertes ADD COLUMN IF NOT EXISTS mesure_at TIMESTAMPTZ;
UPDATE alertes a SET mesure_at = me.horodatage FROM mesures me WHERE me.id = a.mesure_id AND a.mesure_at IS NULL;
