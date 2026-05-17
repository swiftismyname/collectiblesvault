-- ─────────────────────────────────────────────────────────────────────────────
-- Collectibles Vault — Supabase Schema
-- Run this migration once; Supabase will apply it automatically if you have
-- the GitHub integration set up (it watches supabase/migrations/).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Main collectibles table ──────────────────────────────────────────────────
-- All records from every sheet type live here.
-- `sheet`  = which worksheet category (gradedUS, rawSilver, ancient, etc.)
-- `id`     = the record's unique ID (same as was in the Google Sheet)
-- `data`   = JSONB blob of all field values — flexible, no schema changes needed

CREATE TABLE IF NOT EXISTS collectibles (
  id          TEXT        NOT NULL,
  sheet       TEXT        NOT NULL,
  data        JSONB       NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (sheet, id)
);

CREATE INDEX IF NOT EXISTS idx_collectibles_sheet ON collectibles (sheet);
CREATE INDEX IF NOT EXISTS idx_collectibles_data  ON collectibles USING GIN (data);

-- ── Row Level Security ───────────────────────────────────────────────────────
-- This is a personal single-user app. We allow all operations via the anon key.
-- If you want multi-user access, replace this with user-scoped policies.
ALTER TABLE collectibles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_all" ON collectibles;
CREATE POLICY "allow_all" ON collectibles
  FOR ALL USING (true) WITH CHECK (true);

-- ── Auto-update updated_at ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _vault_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_collectibles_updated_at ON collectibles;
CREATE TRIGGER trg_collectibles_updated_at
  BEFORE UPDATE ON collectibles
  FOR EACH ROW EXECUTE FUNCTION _vault_set_updated_at();

-- ── patch_collectible RPC ────────────────────────────────────────────────────
-- Merges a partial update into the data JSONB column using the || operator,
-- so callers only need to send the fields that changed.
-- Called by the app as: POST /rest/v1/rpc/patch_collectible
CREATE OR REPLACE FUNCTION patch_collectible(
  p_sheet   TEXT,
  p_id      TEXT,
  p_updates JSONB
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE collectibles
    SET data       = data || p_updates,
        updated_at = NOW()
    WHERE sheet = p_sheet
      AND id    = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Record not found: sheet=%, id=%', p_sheet, p_id;
  END IF;
END;
$$;

-- ── Coin reference table (optional) ─────────────────────────────────────────
-- Import your US Coin Reference sheet here so you're fully off Google.
-- Each row is one reference coin entry; all fields stored as JSONB.
CREATE TABLE IF NOT EXISTS coin_reference (
  id         BIGSERIAL   PRIMARY KEY,
  data       JSONB       NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE coin_reference ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "allow_all" ON coin_reference;
CREATE POLICY "allow_all" ON coin_reference
  FOR ALL USING (true) WITH CHECK (true);
