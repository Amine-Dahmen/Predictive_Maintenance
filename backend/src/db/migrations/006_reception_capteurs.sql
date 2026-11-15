-- Présence des capteurs mesurée à la RÉCEPTION des messages (horloge du serveur), et non à l'horodatage
-- des mesures (horloge de la carte) : un décalage d'horloge entre la carte et le PC ne fait plus passer
-- les capteurs « hors ligne » en boucle (US-21).
ALTER TABLE capteurs ADD COLUMN IF NOT EXISTS derniere_reception_at TIMESTAMPTZ;
UPDATE capteurs SET derniere_reception_at = derniere_mesure_at WHERE derniere_reception_at IS NULL;
