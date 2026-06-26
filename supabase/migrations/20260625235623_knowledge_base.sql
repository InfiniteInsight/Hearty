-- Knowledge Base RAG v1 (Spec 11 Layer 1): curated health-research corpus +
-- top-k cosine retrieval RPC. Service-key only (not user data).
create extension if not exists vector;

create table if not exists knowledge_base (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'manual',     -- 'manual' (v1), later 'pubmed'/'nhs'/'nih'
  source_id text,
  title text,
  content text not null,
  content_embedding vector(3072),            -- Gemini gemini-embedding-001 (3072 dims)
  conditions text[] not null default '{}',   -- e.g. {'ibs','gerd','celiac'}; NOT NULL so the
                                             -- conditions = '{}' eligibility test below can't be
                                             -- defeated by a null (which would hide the row from
                                             -- every query).
  tags text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table knowledge_base enable row level security;
-- No ANN index in v1: an exact sequential scan over a tiny corpus is instant and gives perfect
-- recall (ivfflat with lists=100 would hurt recall at this size). Note: at 3072 dims a future
-- ANN index can't use plain ivfflat/hnsw (2000-dim cap) — use a halfvec cast once the corpus
-- reaches thousands of rows:
--   create index knowledge_base_embedding_idx on knowledge_base
--     using hnsw ((content_embedding::halfvec(3072)) halfvec_cosine_ops);

-- Top-k cosine retrieval (PostgREST can't do vector ops via the query builder).
create or replace function match_knowledge(
  query_embedding vector(3072),
  match_count int default 4,
  filter_conditions text[] default null
) returns table (id uuid, source text, title text, content text, conditions text[], similarity float)
language sql stable as $$
  select kb.id, kb.source, kb.title, kb.content, kb.conditions,
         1 - (kb.content_embedding <=> query_embedding) as similarity
  from knowledge_base kb
  where kb.active
    and kb.content_embedding is not null         -- never return un-embedded rows (would sort by null)
    and (filter_conditions is null               -- caller has no conditions: no filter
         or kb.conditions = '{}'                 -- untagged = general research, always eligible
         or kb.conditions && filter_conditions)  -- else require a condition overlap
  order by kb.content_embedding <=> query_embedding
  limit match_count;
$$;
