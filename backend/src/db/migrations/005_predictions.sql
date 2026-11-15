-- US-22 (bonus) : probabilité de panne calculée par le modèle d'IA (service ml/).
CREATE TABLE IF NOT EXISTS predictions (
  id           BIGSERIAL PRIMARY KEY,
  machine_id   INTEGER NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  probabilite  DOUBLE PRECISION CHECK (probabilite BETWEEN 0 AND 1),  -- NULL : historique insuffisant
  niveau       VARCHAR(10) NOT NULL,                                  -- FAIBLE, MOYEN, ELEVE, INCONNU
  facteurs     JSONB NOT NULL DEFAULT '[]',
  modele       VARCHAR(60) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_predictions_machine ON predictions(machine_id, created_at DESC);
