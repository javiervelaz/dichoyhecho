-- migrate:up
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Personas y mandatos
CREATE TABLE persons (
  id            bigserial PRIMARY KEY,
  full_name     text NOT NULL,
  slug          text UNIQUE NOT NULL,
  hcdn_id       text UNIQUE,                 -- id del padrón datos.hcdn.gob.ar
  aliases       text[] NOT NULL DEFAULT '{}', -- para matchear menciones y taquigráficas
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX persons_name_trgm ON persons USING gin (full_name gin_trgm_ops);

CREATE TABLE person_terms (
  person_id  bigint NOT NULL REFERENCES persons(id),
  chamber    text NOT NULL CHECK (chamber IN ('diputados','senado','ejecutivo','provincial','otro')),
  bloc       text,
  district   text,
  starts_on  date NOT NULL,
  ends_on    date,
  PRIMARY KEY (person_id, chamber, starts_on)
);

-- Fuentes y material
CREATE TYPE source_kind AS ENUM ('yt_oficial','acta_votacion','boletin','indicador','expediente','red_social','rss_titular');
CREATE TABLE sources (
  id            bigserial PRIMARY KEY,
  kind          source_kind NOT NULL,
  external_id   text NOT NULL,               -- videoId, nº de acta, etc.
  url           text NOT NULL,
  title         text,
  channel       text,
  published_at  timestamptz,
  usage_rights  text NOT NULL,               -- 'publico_oficial', 'solo_senal', ...
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','downloaded','transcribed','indexed','error')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, external_id)
);

CREATE TABLE media_assets (
  id           bigserial PRIMARY KEY,
  source_id    bigint NOT NULL REFERENCES sources(id),
  kind         text NOT NULL CHECK (kind IN ('audio','video','clip','render')),
  r2_key       text NOT NULL,
  sha256       text,
  duration_ms  int
);

CREATE TABLE transcript_segments (
  id                  bigserial PRIMARY KEY,
  source_id           bigint NOT NULL REFERENCES sources(id),
  start_ms            int NOT NULL,
  end_ms              int NOT NULL,
  speaker_person_id   bigint REFERENCES persons(id),
  speaker_confidence  real,                  -- < 0.9 obliga revisión humana
  text                text NOT NULL,
  embedding           vector(1024),          -- bge-m3
  tsv                 tsvector GENERATED ALWAYS AS (to_tsvector('spanish', text)) STORED,
  CHECK (end_ms > start_ms)
);
CREATE INDEX transcript_segments_source ON transcript_segments (source_id, start_ms);
CREATE INDEX transcript_segments_speaker ON transcript_segments (speaker_person_id);
CREATE INDEX transcript_segments_embedding ON transcript_segments USING hnsw (embedding vector_cosine_ops);
CREATE INDEX transcript_segments_tsv ON transcript_segments USING gin (tsv);

-- Legislación y votos
CREATE TABLE bills (
  id           bigserial PRIMARY KEY,
  expediente   text UNIQUE,
  title        text,
  topic_slugs  text[] NOT NULL DEFAULT '{}'
);

CREATE TABLE votes (
  id            bigserial PRIMARY KEY,
  hcdn_acta_id  int UNIQUE,
  bill_id       bigint REFERENCES bills(id),
  voted_at      timestamptz,
  description   text,
  result        text,
  source_id     bigint NOT NULL REFERENCES sources(id)
);

CREATE TYPE vote_value AS ENUM ('afirmativo','negativo','abstencion','ausente','presidente');
CREATE TABLE vote_records (
  vote_id    bigint NOT NULL REFERENCES votes(id),
  person_id  bigint NOT NULL REFERENCES persons(id),
  value      vote_value NOT NULL,
  PRIMARY KEY (vote_id, person_id)
);
CREATE INDEX vote_records_person ON vote_records (person_id);

-- Economía y causas judiciales
CREATE TABLE indicators (
  code      text PRIMARY KEY,
  name      text NOT NULL,
  unit      text,
  provider  text
);

CREATE TABLE indicator_values (
  code          text NOT NULL REFERENCES indicators(code),
  period        date NOT NULL,
  value         numeric NOT NULL,
  published_at  timestamptz,
  source_id     bigint REFERENCES sources(id),
  PRIMARY KEY (code, period)
);

CREATE TABLE legal_cases (
  id              bigserial PRIMARY KEY,
  person_id       bigint NOT NULL REFERENCES persons(id),
  court           text,
  case_number     text,
  status          text NOT NULL CHECK (status IN ('denuncia','imputado','procesado','elevado_a_juicio','condenado','sobreseido','absuelto')),
  status_doc_url  text NOT NULL,
  status_as_of    date NOT NULL
);

-- Afirmaciones y enlaces (el corazón de "Dijo / Votó")
CREATE TABLE claims (
  id          bigserial PRIMARY KEY,
  segment_id  bigint NOT NULL REFERENCES transcript_segments(id),
  person_id   bigint REFERENCES persons(id),
  claim_text  text NOT NULL,
  topic_slug  text,
  claim_type  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE link_relation AS ENUM ('contradice','respalda','contexto');
CREATE TABLE claim_links (
  id           bigserial PRIMARY KEY,
  claim_id     bigint NOT NULL REFERENCES claims(id),
  target_kind  text NOT NULL CHECK (target_kind IN ('vote_record','indicator_value','segment','legal_case')),
  target_ref   jsonb NOT NULL,
  relation     link_relation NOT NULL,
  confidence   real CHECK (confidence BETWEEN 0 AND 1),
  rationale    text
);

-- Producción y publicación
CREATE TYPE story_status AS ENUM ('nuevo','aprobado','descartado','en_guion','verificado','renderizado','publicado','corregido');
CREATE TABLE stories (
  id             bigserial PRIMARY KEY,
  claim_id       bigint REFERENCES claims(id),
  format         text NOT NULL CHECK (format IN ('dijo_voto','dato_del_dia','semana_congreso','expediente','ficha_candidato','chequeo_debate')),
  score          real,
  score_detail   jsonb,
  status         story_status NOT NULL DEFAULT 'nuevo',
  script_md      text,
  script_author  text CHECK (script_author IN ('plantilla','humano')),
  verified_by    text,
  verified_at    timestamptz,
  sensitive      boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now(),
  -- nada pasa a verificado/publicado sin verificación humana registrada
  CHECK (status NOT IN ('verificado','renderizado','publicado','corregido') OR verified_at IS NOT NULL)
);

CREATE TABLE publications (
  story_id                  bigint NOT NULL REFERENCES stories(id),
  platform                  text NOT NULL CHECK (platform IN ('youtube','tiktok','facebook','instagram')),
  platform_post_id          text,
  url                       text,
  published_at              timestamptz,
  contains_synthetic_media  boolean NOT NULL DEFAULT true,
  PRIMARY KEY (story_id, platform)
);

CREATE TABLE metrics_daily (
  story_id      bigint NOT NULL REFERENCES stories(id),
  platform      text NOT NULL,
  day           date NOT NULL,
  views         int,
  watch_time_s  int,
  avg_view_pct  real,
  subs_gained   int,
  revenue_usd   numeric(10,4),
  PRIMARY KEY (story_id, platform, day)
);

CREATE TABLE corrections (
  id            bigserial PRIMARY KEY,
  story_id      bigint NOT NULL REFERENCES stories(id),
  what          text NOT NULL,
  published_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE election_calendar (
  id            bigserial PRIMARY KEY,
  jurisdiction  text NOT NULL,
  event         text NOT NULL,
  event_date    date NOT NULL,
  source_url    text NOT NULL
);

-- Operación
CREATE TABLE jobs (
  id         bigserial PRIMARY KEY,
  type       text NOT NULL,
  payload    jsonb NOT NULL,
  status     text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','done','failed')),
  run_at     timestamptz NOT NULL DEFAULT now(),
  attempts   int NOT NULL DEFAULT 0,
  locked_at  timestamptz,
  error      text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX jobs_ready ON jobs (run_at) WHERE status = 'queued';

CREATE TABLE llm_usage (
  id             bigserial PRIMARY KEY,
  model          text NOT NULL,
  purpose        text NOT NULL,
  input_tokens   int NOT NULL,
  output_tokens  int NOT NULL,
  cost_usd       numeric(10,4) NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX llm_usage_month ON llm_usage (created_at);

-- Calendario inicial (fuentes en la columna source_url)
INSERT INTO election_calendar (jurisdiction, event, event_date, source_url) VALUES
  ('nacional', 'Elecciones generales', '2027-10-24', 'https://chequeado.com/el-explicador/elecciones-2027-en-argentina-cuando-se-vota-para-presidente-y-que-provincias-ya-confirmaron-que-desdoblaran-los-comicios/'),
  ('neuquen', 'Elecciones provinciales', '2027-02-14', 'https://chequeado.com/el-explicador/elecciones-2027-en-argentina-cuando-se-vota-para-presidente-y-que-provincias-ya-confirmaron-que-desdoblaran-los-comicios/'),
  ('tucuman', 'Elecciones provinciales', '2027-05-09', 'https://www.airedesantafe.com.ar/politica/elecciones-2027-que-provincias-desdoblan-y-cuales-tienen-fecha-confirmada-n665155');

-- migrate:down
DROP TABLE IF EXISTS llm_usage, jobs, election_calendar, corrections, metrics_daily, publications, stories,
  claim_links, claims, legal_cases, indicator_values, indicators, vote_records, votes, bills,
  transcript_segments, media_assets, sources, person_terms, persons CASCADE;
DROP TYPE IF EXISTS story_status, link_relation, vote_value, source_kind;
