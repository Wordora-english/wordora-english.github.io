-- =====================================================================
--  WORDORA — Hər gün məşq və bildirişlər
--   1) 🔥 Gündəlik məşq: hər gün 5 sual + ardıcıl günlər seriyası
--   2) 📕 Səhvlərim dəftəri: sınaqlardakı və məşqdəki səhvlər bir yerdə
--   3) 🎯 Zəif mövzular: sınaqda "Mövzular" yazılıbsa, mövzu üzrə faiz
--   5) 👨‍👩‍👧 Valideyn üçün aylıq hesabat
--   7) 🔔 Telefona bildiriş (yeni sınaq, ev tapşırığı, elan, nəticə, məşq xatırlatması)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- Bakı vaxtı ilə bugünkü tarix
create or replace function public.baku_today()
returns date language sql stable set search_path = ''
as $$ select (now() at time zone 'Asia/Baku')::date; $$;

-- Yazılan cavabı müqayisə üçün sadələşdir
create or replace function public.practice_norm(p text)
returns text language sql immutable set search_path = ''
as $$
  select regexp_replace(regexp_replace(regexp_replace(
           lower(translate(trim(coalesce(p, '')), '’‘`´“”', '''''''''""')),
           '\s+', ' ', 'g'), '^[\s.,!?;:"]+', ''), '[\s.,!?;:"]+$', '');
$$;

-- =====================================================================
-- 1) GÜNDƏLİK MƏŞQ
-- =====================================================================
create table if not exists public.daily_sets (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  day       date not null,
  questions jsonb not null default '[]'::jsonb,   -- [{k, topic, text, opts, ans}]
  answers   jsonb,                                -- ["1", "went", ...]
  results   jsonb,                                -- [true, false, ...]
  correct   int,
  total     int,
  done_at   timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.daily_sets enable row level security;
drop policy if exists "daily_admin" on public.daily_sets;
create policy "daily_admin" on public.daily_sets for select to authenticated using (public.is_admin());
revoke all on public.daily_sets from anon;

-- Sual bankından bir sadə sual (variantlı və ya "= cavab") götür
create or replace function public.daily_bank_q(p_body text, p_topic text)
returns jsonb
language plpgsql volatile set search_path = ''
as $$
declare b text; ln text; v_text text; v_opts text[] := '{}'; v_ans text[] := '{}'; v_correct int := -1; v_order int[]; v_new text[] := '{}'; i int;
begin
  if p_body ~ '^\s*##' then return null; end if;          -- mətnli (reading) suallar gündəlik məşqə düşmür
  for b in select x from unnest(regexp_split_to_array(replace(p_body, E'\r', ''), E'\n\\s*\n')) x order by random() loop
    v_text := null; v_opts := '{}'; v_ans := '{}'; v_correct := -1;
    foreach ln in array regexp_split_to_array(trim(b), E'\n') loop
      ln := trim(ln);
      continue when ln = '';
      if v_text is null then
        exit when ln ~ '^#';
        v_text := ln; continue;
      end if;
      if ln ~ '^=' then v_ans := v_ans || trim(regexp_replace(ln, '^=+\s*', '')); continue; end if;
      if ln ~ '^\*' or ln ~ '\*$' then v_correct := cardinality(v_opts); end if;
      v_opts := v_opts || regexp_replace(regexp_replace(regexp_replace(ln, '^\*\s*', ''), '\s*\*$', ''), '^[A-Ea-e][).]\s+', '');
    end loop;
    if v_text is null then continue; end if;
    if cardinality(v_ans) > 0 and cardinality(v_opts) = 0 then
      return jsonb_build_object('k', 'bank', 'topic', p_topic, 'text', left(v_text, 300), 'opts', null, 'ans', array_to_string(v_ans, '/'));
    end if;
    if cardinality(v_opts) between 2 and 5 and v_correct >= 0 then
      -- variantları qarışdır
      select array_agg(g order by random()) into v_order from generate_series(1, cardinality(v_opts)) g;
      for i in 1 .. cardinality(v_order) loop v_new := v_new || v_opts[v_order[i]]; end loop;
      return jsonb_build_object('k', 'bank', 'topic', p_topic, 'text', left(v_text, 300), 'opts', to_jsonb(v_new),
                                'ans', (array_position(v_order, v_correct + 1) - 1)::text);
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function public.daily_bank_q(text, text) from public, anon, authenticated;

create or replace function public.daily_make()
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_out jsonb := '[]'::jsonb; v_q jsonb; r record; v_nb int := 0; v_need int; v_i int := 0; v_words int;
        v_opts text[]; v_order int[]; v_new text[]; v_kind text; k int;
begin
  -- 1–2 sual sual bankından
  for r in select topic, body from public.question_bank order by random() limit 8 loop
    exit when v_nb >= 2;
    v_q := public.daily_bank_q(r.body, r.topic);
    if v_q is not null then v_out := v_out || jsonb_build_array(v_q); v_nb := v_nb + 1; end if;
  end loop;
  -- qalanı söz bazasından
  select count(*) into v_words from public.words;
  v_need := 5 - v_nb;
  for r in select word, meaning from public.words order by random() limit v_need loop
    v_kind := case when v_words < 4 then 'spell' else (array['en_az', 'az_en', 'spell'])[1 + (v_i % 3)] end;
    v_i := v_i + 1;
    if v_kind = 'spell' then
      v_out := v_out || jsonb_build_array(jsonb_build_object('k', 'spell', 'topic', 'Sözlər',
                 'text', format('"%s" — ingiliscə yaz', r.meaning), 'opts', null, 'ans', r.word));
      continue;
    end if;
    if v_kind = 'en_az' then
      select array_agg(m) into v_opts from (select distinct meaning m from public.words
                                             where lower(meaning) <> lower(r.meaning) order by 1) x;
      select array_agg(m order by random()) into v_opts from (select m from unnest(v_opts) m order by random() limit 3) y;
      v_opts := r.meaning || coalesce(v_opts, '{}');
    else
      select array_agg(m) into v_opts from (select distinct word m from public.words
                                             where lower(word) <> lower(r.word) order by 1) x;
      select array_agg(m order by random()) into v_opts from (select m from unnest(v_opts) m order by random() limit 3) y;
      v_opts := r.word || coalesce(v_opts, '{}');
    end if;
    select array_agg(g order by random()) into v_order from generate_series(1, cardinality(v_opts)) g;
    v_new := '{}';
    for k in 1 .. cardinality(v_order) loop v_new := v_new || v_opts[v_order[k]]; end loop;
    v_out := v_out || jsonb_build_array(jsonb_build_object('k', v_kind, 'topic', 'Sözlər',
               'text', case when v_kind = 'en_az' then format('"%s" sözünün mənası nədir?', r.word)
                            else format('"%s" ingiliscə necədir?', r.meaning) end,
               'opts', to_jsonb(v_new), 'ans', (array_position(v_order, 1) - 1)::text));
  end loop;
  -- qarışdır
  select coalesce(jsonb_agg(e order by random()), '[]'::jsonb) into v_out from jsonb_array_elements(v_out) e;
  return v_out;
end;
$$;
revoke execute on function public.daily_make() from public, anon, authenticated;

-- Seriya: ardıcıl günlər
create or replace function public.daily_streak(p_user uuid)
returns json
language sql stable security definer set search_path = ''
as $$
  with d as (select day from public.daily_sets where user_id = p_user and done_at is not null),
       g as (select day, day - (row_number() over (order by day))::int as grp from d),
       isl as (select max(day) as e, count(*) as n from g group by grp)
  select json_build_object(
    'current', coalesce((select n from isl where e >= public.baku_today() - 1 order by e desc limit 1), 0),
    'best',    coalesce((select max(n) from isl), 0),
    'total',   (select count(*) from d),
    'today',   exists (select 1 from d where day = public.baku_today()),
    'week',    (select json_agg(json_build_object('day', x::date, 'done', exists (select 1 from d where d.day = x::date)) order by x)
                  from generate_series(public.baku_today() - 6, public.baku_today(), interval '1 day') x));
$$;
revoke execute on function public.daily_streak(uuid) from public, anon, authenticated;

create or replace function public.daily_status()
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then return null; end if;
  return public.daily_streak(auth.uid());
end;
$$;

-- Bugünkü suallar (yoxdursa — yaradılır)
create or replace function public.daily_view(p_set public.daily_sets)
returns json
language sql stable security definer set search_path = ''
as $$
  select json_build_object(
    'day', p_set.day, 'done', p_set.done_at is not null,
    'questions', (select coalesce(jsonb_agg(
                    (q - 'ans') || case when p_set.done_at is not null
                                        then jsonb_build_object('ans', q->'ans', 'my', p_set.answers->((i - 1)::int), 'ok', p_set.results->((i - 1)::int))
                                        else '{}'::jsonb end order by i), '[]'::jsonb)
                    from jsonb_array_elements(p_set.questions) with ordinality as x(q, i)),
    'correct', p_set.correct, 'total', p_set.total,
    'streak', public.daily_streak(p_set.user_id));
$$;
revoke execute on function public.daily_view(public.daily_sets) from public, anon, authenticated;

create or replace function public.daily_get()
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets; v_p public.profiles;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.status <> 'approved' then raise exception 'Hesabın aktiv deyil'; end if;
  select * into v_s from public.daily_sets where user_id = v_p.id and day = public.baku_today();
  if not found then
    insert into public.daily_sets (user_id, day, questions) values (v_p.id, public.baku_today(), public.daily_make())
    on conflict do nothing;
    select * into v_s from public.daily_sets where user_id = v_p.id and day = public.baku_today();
  end if;
  if jsonb_array_length(v_s.questions) = 0 then
    -- müəllim söz/sual əlavə edəndən sonra yenidən cəhd olunsun
    delete from public.daily_sets where user_id = v_p.id and day = v_s.day and done_at is null;
    return json_build_object('empty', true, 'streak', public.daily_streak(v_p.id));
  end if;
  return public.daily_view(v_s);
end;
$$;

create or replace function public.daily_submit(p_answers jsonb)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets; q jsonb; i int := 0; v_my text; v_ok boolean; v_res jsonb := '[]'::jsonb; v_c int := 0; alt text;
begin
  select * into v_s from public.daily_sets where user_id = auth.uid() and day = public.baku_today() for update;
  if not found then raise exception 'Bugünkü məşq tapılmadı — səhifəni yenilə'; end if;
  if v_s.done_at is not null then return public.daily_view(v_s); end if;
  if jsonb_typeof(p_answers) <> 'array' then raise exception 'Cavablar düzgün deyil'; end if;
  for q in select value from jsonb_array_elements(v_s.questions) loop
    v_my := left(trim(coalesce(p_answers->>i, '')), 120);
    v_ok := false;
    if q->'opts' is null or jsonb_typeof(q->'opts') = 'null' then
      foreach alt in array string_to_array(q->>'ans', '/') loop
        if public.practice_norm(alt) <> '' and public.practice_norm(alt) = public.practice_norm(v_my) then v_ok := true; end if;
      end loop;
    else
      v_ok := v_my <> '' and v_my = q->>'ans';
    end if;
    v_res := v_res || to_jsonb(v_ok);
    if v_ok then v_c := v_c + 1; end if;
    i := i + 1;
  end loop;
  update public.daily_sets
     set answers = (select coalesce(jsonb_agg(left(trim(coalesce(p_answers->>(g - 1), '')), 120) order by g), '[]'::jsonb)
                      from generate_series(1, jsonb_array_length(v_s.questions)) g),
         results = v_res, correct = v_c, total = jsonb_array_length(v_s.questions), done_at = now()
   where user_id = v_s.user_id and day = v_s.day
  returning * into v_s;
  return public.daily_view(v_s);
end;
$$;
revoke execute on function public.daily_status()        from public, anon;
revoke execute on function public.daily_get()           from public, anon;
revoke execute on function public.daily_submit(jsonb)   from public, anon;
grant  execute on function public.daily_status()        to authenticated;
grant  execute on function public.daily_get()           to authenticated;
grant  execute on function public.daily_submit(jsonb)   to authenticated;

-- =====================================================================
-- 2) SƏHVLƏRİM DƏFTƏRİ
-- =====================================================================
create table if not exists public.mistake_fixed (
  user_id  uuid not null references public.profiles(id) on delete cascade,
  src      text not null check (src in ('test', 'daily')),
  ref      text not null,
  qn       int  not null,
  fixed_at timestamptz not null default now(),
  primary key (user_id, src, ref, qn)
);
alter table public.mistake_fixed enable row level security;
drop policy if exists "mfix_admin" on public.mistake_fixed;
create policy "mfix_admin" on public.mistake_fixed for select to authenticated using (public.is_admin());
revoke all on public.mistake_fixed from anon;

create or replace function public.my_mistakes()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_out jsonb := '[]'::jsonb; r record; q jsonb; o jsonb; v_key jsonb; v_on public.test_online;
        n text; v_pass jsonb; v_found boolean; d record; i int; L text := 'ABCDE';
begin
  if v_uid is null then return '[]'::json; end if;
  -- sınaqlar (yalnız nəticəsi açılmışlar)
  for r in
    select t.id, t.title, t.questions, t.pdf_path, x.answers, x.details, x.variant, x.at_
      from (select test_id, answers, details, variant, coalesce(submitted_at, started_at) as at_
              from public.attempts where user_id = v_uid and status <> 'in_progress'
            union all
            select test_id, answers, details, variant, created_at from public.paper_entries where user_id = v_uid) x
      join public.tests t on t.id = x.test_id
     where t.results_released and x.details is not null
     order by x.at_ desc limit 40
  loop
    v_key := public.variant_key(r.id, r.variant);
    select * into v_on from public.test_online where test_id = r.id;
    v_found := found;
    for q in select value from jsonb_array_elements(r.questions) loop
      continue when q->>'type' = 'essay';
      n := q->>'n';
      continue when coalesce((r.details->n->>'frac')::numeric, 0) >= 1;
      continue when exists (select 1 from public.mistake_fixed f where f.user_id = v_uid and f.src = 'test' and f.ref = r.id::text and f.qn = n::int);
      o := null; v_pass := null;
      if v_found then
        select e into o from jsonb_array_elements(v_on.questions) e where e->>'n' = n limit 1;
        if o ? 'pid' then
          select jsonb_build_object('title', p->>'title', 'text', left(p->>'text', 4000)) into v_pass
            from jsonb_array_elements(v_on.passages) p where p->>'id' = o->>'pid' limit 1;
        end if;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'src', 'test', 'ref', r.id, 'title', r.title, 'at', r.at_, 'n', n::int,
        'type', q->>'type', 'options', coalesce(q->>'options', 'ABCDE'), 'parts', q->'parts',
        'my', r.answers->>n, 'key', v_key->>n,
        'text', o->>'text', 'opts', o->'opts', 'passage', v_pass));
      exit when jsonb_array_length(v_out) >= 200;
    end loop;
    exit when jsonb_array_length(v_out) >= 200;
  end loop;
  -- gündəlik məşq
  for d in select day, questions, answers, results from public.daily_sets
            where user_id = v_uid and done_at is not null order by day desc limit 60 loop
    i := 0;
    for q in select value from jsonb_array_elements(d.questions) loop
      if coalesce((d.results->>i)::boolean, true) = false
         and not exists (select 1 from public.mistake_fixed f where f.user_id = v_uid and f.src = 'daily' and f.ref = d.day::text and f.qn = i) then
        v_out := v_out || jsonb_build_array(jsonb_build_object(
          'src', 'daily', 'ref', d.day::text, 'title', 'Gündəlik məşq', 'at', d.day, 'n', i,
          'type', case when q->'opts' is null or jsonb_typeof(q->'opts') = 'null' then 'open' else 'choice' end,
          'options', substr(L, 1, greatest(2, coalesce(jsonb_array_length(case when jsonb_typeof(q->'opts') = 'array' then q->'opts' end), 0))),
          'my', case when jsonb_typeof(q->'opts') = 'array' and coalesce(d.answers->>i, '') ~ '^\d$'
                     then substr(L, (d.answers->>i)::int + 1, 1) else d.answers->>i end,
          'key', case when jsonb_typeof(q->'opts') = 'array' then substr(L, (q->>'ans')::int + 1, 1) else q->>'ans' end,
          'text', q->>'text', 'opts', case when jsonb_typeof(q->'opts') = 'array' then q->'opts' end, 'topic', q->>'topic'));
      end if;
      i := i + 1;
    end loop;
    exit when jsonb_array_length(v_out) >= 260;
  end loop;
  return v_out;
end;
$$;

create or replace function public.mistake_fix(p_src text, p_ref text, p_n int)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Daxil ol'; end if;
  insert into public.mistake_fixed (user_id, src, ref, qn) values (auth.uid(), p_src, left(p_ref, 60), p_n)
  on conflict do nothing;
end;
$$;
revoke execute on function public.my_mistakes()                 from public, anon;
revoke execute on function public.mistake_fix(text, text, int)  from public, anon;
grant  execute on function public.my_mistakes()                 to authenticated;
grant  execute on function public.mistake_fix(text, text, int)  to authenticated;

-- =====================================================================
-- 3) MÖVZULAR ÜZRƏ NƏTİCƏ
--    Sınaqda "Mövzular" (məs. "Present Perfect: 1-5; Passive: 6-10") yazılıbsa — onlar,
--    yoxdursa "Bölmələr" götürülür. Gündəlik məşq də əlavə olunur.
-- =====================================================================
create or replace function public.topic_facts(p_user uuid, p_from timestamptz default null, p_to timestamptz default null)
returns table (user_id uuid, topic text, frac numeric)
language sql stable security definer set search_path = ''
as $$
  with res as (
    select a.user_id, a.test_id, a.details, coalesce(a.submitted_at, a.started_at) as at_
      from public.attempts a where a.status <> 'in_progress' and a.details is not null
    union all
    select p.user_id, p.test_id, p.details, p.created_at
      from public.paper_entries p where p.user_id is not null and p.details is not null
  ), t as (
    select id, questions,
           case when jsonb_typeof(content->'topics') = 'array' and jsonb_array_length(content->'topics') > 0 then content->'topics'
                when jsonb_typeof(content->'sections') = 'array' then content->'sections' else '[]'::jsonb end as tp
      from public.tests where results_released or results_mode = 'instant'
  )
  select r.user_id, trim(tpc->>'name'), least(1, greatest(0, coalesce((r.details -> (q->>'n') ->> 'frac')::numeric, 0)))
    from res r join t on t.id = r.test_id
    cross join jsonb_array_elements(t.tp) tpc
    cross join jsonb_array_elements(t.questions) q
   where (q->>'n')::int between (tpc->>'from')::int and (tpc->>'to')::int
     and q->>'type' <> 'essay' and r.details ? (q->>'n')
     and (p_user is null or r.user_id = p_user)
     and (p_from is null or r.at_ >= p_from) and (p_to is null or r.at_ < p_to)
  union all
  select d.user_id, coalesce(q->>'topic', 'Sözlər'), case when (d.results->>((i - 1)::int))::boolean then 1 else 0 end
    from public.daily_sets d
    cross join jsonb_array_elements(d.questions) with ordinality as x(q, i)
   where d.done_at is not null
     and (p_user is null or d.user_id = p_user)
     and (p_from is null or d.done_at >= p_from) and (p_to is null or d.done_at < p_to);
$$;
revoke execute on function public.topic_facts(uuid, timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.topics_of(p_user uuid)
returns json
language sql stable security definer set search_path = ''
as $$
  select coalesce(json_agg(json_build_object('topic', topic, 'pct', pct, 'n', n) order by pct, n desc), '[]'::json)
    from (select min(topic) as topic, round(avg(frac) * 100)::int as pct, count(*) as n
            from public.topic_facts(p_user) where topic <> '' and lower(topic) not in ('essay', 'esse', 'writing (essay)')
           group by lower(topic) having count(*) >= 2) x;
$$;
revoke execute on function public.topics_of(uuid) from public, anon, authenticated;

create or replace function public.my_topics()
returns json language plpgsql stable security definer set search_path = ''
as $$ begin if auth.uid() is null then return '[]'::json; end if; return public.topics_of(auth.uid()); end; $$;

create or replace function public.admin_student_topics(p_user uuid)
returns json language plpgsql stable security definer set search_path = ''
as $$ begin if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if; return public.topics_of(p_user); end; $$;

-- Bütün sinif üzrə (aylıq hesabat üçün)
create or replace function public.admin_topics(p_from timestamptz default null, p_to timestamptz default null)
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return (with f as (
      select f.user_id, f.topic, f.frac, coalesce(p.class_name, '?') as cls
        from public.topic_facts(null, p_from, p_to) f join public.profiles p on p.id = f.user_id and p.role = 'student'
       where f.topic <> '' and lower(f.topic) not in ('essay', 'esse')
    ), g as (
      select lower(topic) as k, min(topic) as topic, round(avg(frac) * 100)::int as pct, count(*) as n, count(distinct user_id) as s
        from f group by 1 having count(*) >= 3
    ), c as (
      select lower(topic) as k, cls, round(avg(frac) * 100)::int as cp from f group by 1, 2
    )
    select coalesce(json_agg(json_build_object('topic', g.topic, 'pct', g.pct, 'n', g.n, 'students', g.s,
                                               'classes', (select json_object_agg(c.cls, c.cp) from c where c.k = g.k)) order by g.pct), '[]'::json)
      from g);
end;
$$;
revoke execute on function public.my_topics()                                   from public, anon;
revoke execute on function public.admin_student_topics(uuid)                    from public, anon;
revoke execute on function public.admin_topics(timestamptz, timestamptz)        from public, anon;
grant  execute on function public.my_topics()                                   to authenticated;
grant  execute on function public.admin_student_topics(uuid)                    to authenticated;
grant  execute on function public.admin_topics(timestamptz, timestamptz)        to authenticated;

-- =====================================================================
-- 5) VALİDEYN ÜÇÜN AYLIQ HESABAT
-- =====================================================================
create or replace function public.parent_month(p_code text, p_month date default null)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_p public.profiles; v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
        v_m date := date_trunc('month', coalesce(p_month, public.baku_today()))::date;
        v_from timestamptz; v_to timestamptz; v_pfrom timestamptz;
begin
  if length(v_code) <> 10 then raise exception 'Kod düzgün deyil'; end if;
  select * into v_p from public.profiles
   where replace(parent_code, '-', '') = v_code and role = 'student' and status in ('approved', 'blocked');
  if not found then raise exception 'Kod tapılmadı'; end if;
  v_from  := v_m::timestamp at time zone 'Asia/Baku';
  v_to    := (v_m + interval '1 month')::timestamp at time zone 'Asia/Baku';
  v_pfrom := (v_m - interval '1 month')::timestamp at time zone 'Asia/Baku';

  return (with res as (
      select a.user_id, a.test_id, a.score, coalesce(a.submitted_at, a.started_at) as at_, a.status
        from public.attempts a where a.status <> 'in_progress'
      union all
      select p.user_id, p.test_id, p.score, p.created_at, p.status from public.paper_entries p where p.user_id is not null
    ), scored as (
      select r.*, t.title, public.test_total(t.questions) as total, pr.class_name
        from res r join public.tests t on t.id = r.test_id join public.profiles pr on pr.id = r.user_id
       where (t.results_released or t.results_mode = 'instant') and r.score is not null and public.test_total(t.questions) > 0
    )
    select json_build_object(
      'name', v_p.full_name, 'class', v_p.class_name, 'month', v_m,
      'tests', (select coalesce(json_agg(json_build_object('title', title, 'date', at_, 'pct', round(score / total * 100)) order by at_), '[]'::json)
                  from scored where user_id = v_p.id and at_ >= v_from and at_ < v_to),
      'avg', (select round(avg(score / total * 100)) from scored where user_id = v_p.id and at_ >= v_from and at_ < v_to),
      'prev_avg', (select round(avg(score / total * 100)) from scored where user_id = v_p.id and at_ >= v_pfrom and at_ < v_from),
      'class_avg', (select round(avg(score / total * 100)) from scored where class_name = v_p.class_name and at_ >= v_from and at_ < v_to),
      'attendance', (select json_build_object('present', count(*) filter (where status = 'present'), 'late', count(*) filter (where status = 'late'),
                                              'absent', count(*) filter (where status = 'absent'), 'excused', count(*) filter (where status = 'excused'))
                       from public.attendance where user_id = v_p.id and att_date >= v_m and att_date < (v_m + interval '1 month')::date),
      'homework', (select json_build_object('given', count(*), 'done', count(s.id), 'avg', round(avg(s.grade / nullif(h.max_points, 0) * 100)))
                     from public.homework h left join public.hw_submissions s on s.homework_id = h.id and s.user_id = v_p.id
                    where h.is_published and h.created_at >= v_from and h.created_at < v_to and public.target_ok(h.target_classes, v_p.class_name)),
      'live', (select json_build_object('games', count(*), 'points', coalesce(sum(score), 0))
                 from public.live_players where user_id = v_p.id and joined_at >= v_from and joined_at < v_to),
      'daily', (select json_build_object('days', count(*), 'correct', coalesce(sum(correct), 0), 'total', coalesce(sum(total), 0))
                  from public.daily_sets where user_id = v_p.id and done_at is not null and day >= v_m and day < (v_m + interval '1 month')::date),
      'streak', public.daily_streak(v_p.id),
      'topics', public.topics_of(v_p.id)));
end;
$$;
grant execute on function public.parent_month(text, date) to anon, authenticated;

-- =====================================================================
-- 7) BİLDİRİŞLƏR (Web Push)
--    Göndərməni GitHub Actions edir (.github/workflows/push.yml, hər 5 dəqiqə).
--    O, BACKUP_SECRET ilə daxil olur — əlavə heç nə qurmaq lazım deyil.
--    VAPID açarlarını ilk işə düşəndə özü yaradıb Vault-da saxlayır.
-- =====================================================================
create table if not exists public.push_subs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  endpoint   text not null unique check (char_length(endpoint) <= 1000),
  p256dh     text not null check (char_length(p256dh) <= 200),
  auth       text not null check (char_length(auth) <= 100),
  created_at timestamptz not null default now()
);
create index if not exists push_subs_user_idx on public.push_subs (user_id);
alter table public.push_subs enable row level security;
drop policy if exists "psubs_admin" on public.push_subs;
create policy "psubs_admin" on public.push_subs for select to authenticated using (public.is_admin());
revoke all on public.push_subs from anon;

create table if not exists public.push_queue (
  id         bigint generated always as identity primary key,
  kind       text not null,                 -- test | result | hw | ann | daily
  mode       text not null default 'class', -- class (target_ok) | test (test_target_ok) | users
  title      text not null,
  body       text not null default '',
  url        text not null default 'portal.html',
  classes    text[],
  groups     uuid[],
  users      uuid[],
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  sent_n     int
);
alter table public.push_queue enable row level security;
drop policy if exists "pq_admin" on public.push_queue;
create policy "pq_admin" on public.push_queue for select to authenticated using (public.is_admin());
revoke all on public.push_queue from anon;

create or replace function public.push_public_key()
returns text language sql stable security definer set search_path = ''
as $$ select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'; $$;
grant execute on function public.push_public_key() to anon, authenticated;

create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Daxil ol'; end if;
  if coalesce(p_endpoint, '') !~ '^https://' then raise exception 'Yanlış ünvan'; end if;
  insert into public.push_subs (user_id, endpoint, p256dh, auth) values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth;
  -- bir şagirdin ən çox 5 cihazı
  delete from public.push_subs where id in (select id from public.push_subs where user_id = auth.uid() order by created_at desc offset 5);
end;
$$;
create or replace function public.push_unsubscribe(p_endpoint text)
returns void language sql security definer set search_path = ''
as $$ delete from public.push_subs where endpoint = p_endpoint and user_id = auth.uid(); $$;
revoke execute on function public.push_subscribe(text, text, text) from public, anon;
revoke execute on function public.push_unsubscribe(text)           from public, anon;
grant  execute on function public.push_subscribe(text, text, text) to authenticated;
grant  execute on function public.push_unsubscribe(text)           to authenticated;

-- Avtomatik növbəyə yazma
create or replace function public.push_on_test()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_published and not coalesce(new.is_paper, false)
     and (tg_op = 'INSERT' or not coalesce(old.is_published, false)) then
    insert into public.push_queue (kind, mode, title, body, url, classes, groups)
    values ('test', 'test', '📝 Yeni sınaq: ' || left(new.title, 80),
            case when new.starts_at is not null and new.starts_at > now()
                 then 'Başlayır: ' || to_char(new.starts_at at time zone 'Asia/Baku', 'DD.MM HH24:MI')
                 else 'Sınaq açıqdır — portala gir' end,
            'portal.html#tests', new.target_classes, new.target_groups);
  end if;
  if tg_op = 'UPDATE' and new.results_released and not coalesce(old.results_released, false) then
    insert into public.push_queue (kind, mode, title, body, url, users)
    values ('result', 'users', '📊 Nəticələr açıldı: ' || left(new.title, 80), 'Balına və səhvlərinə bax', 'portal.html#results',
            array(select user_id from public.attempts where test_id = new.id and status <> 'in_progress'
                  union select user_id from public.paper_entries where test_id = new.id and user_id is not null));
  end if;
  return new;
end;
$$;
drop trigger if exists push_on_test on public.tests;
create trigger push_on_test after insert or update of is_published, results_released on public.tests
  for each row execute function public.push_on_test();

create or replace function public.push_on_hw()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.is_published and (tg_op = 'INSERT' or not coalesce(old.is_published, false)) then
    insert into public.push_queue (kind, mode, title, body, url, classes)
    values ('hw', 'class', '📚 Yeni ev tapşırığı: ' || left(new.title, 80),
            case when new.due_at is not null then 'Son tarix: ' || to_char(new.due_at at time zone 'Asia/Baku', 'DD.MM HH24:MI') else 'Portala gir və bax' end,
            'homework.html', new.target_classes);
  end if;
  return new;
end;
$$;
drop trigger if exists push_on_hw on public.homework;
create trigger push_on_hw after insert or update of is_published on public.homework
  for each row execute function public.push_on_hw();

create or replace function public.push_on_ann()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.push_queue (kind, mode, title, body, url, classes)
  values ('ann', 'class', '📢 ' || left(new.title, 90), left(regexp_replace(new.body, '\s+', ' ', 'g'), 140), 'portal.html',
          case when new.target_class is null then null else array[new.target_class] end);
  return new;
end;
$$;
drop trigger if exists push_on_ann on public.announcements;
create trigger push_on_ann after insert on public.announcements
  for each row execute function public.push_on_ann();

-- GitHub Actions üçün: göndəriləcəklər (BACKUP_SECRET ilə)
create or replace function public.push_secret_ok(p_secret text)
returns boolean language sql stable security definer set search_path = ''
as $$ select p_secret is not null and p_secret = (select decrypted_secret from vault.decrypted_secrets where name = 'backup_secret'); $$;
revoke execute on function public.push_secret_ok(text) from public, anon, authenticated;

create or replace function public.push_set_vapid(p_secret text, p_public text, p_private text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.push_secret_ok(p_secret) then raise exception 'İcazə yoxdur'; end if;
  if exists (select 1 from vault.secrets where name = 'vapid_public') then return; end if;   -- bir dəfə
  perform vault.create_secret(p_public, 'vapid_public');
  perform vault.create_secret(p_private, 'vapid_private');
end;
$$;

create or replace function public.push_pending(p_secret text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_users uuid[];
begin
  if not public.push_secret_ok(p_secret) then raise exception 'İcazə yoxdur'; end if;

  -- Axşam 19:00-dan sonra: bugünkü məşqi etməyənlərə xatırlatma (gündə bir dəfə)
  if extract(hour from now() at time zone 'Asia/Baku') >= 19
     and not exists (select 1 from public.push_queue where kind = 'daily' and (created_at at time zone 'Asia/Baku')::date = public.baku_today()) then
    select coalesce(array_agg(distinct s.user_id), '{}') into v_users
      from public.push_subs s join public.profiles p on p.id = s.user_id and p.status = 'approved'
     where not exists (select 1 from public.daily_sets d where d.user_id = s.user_id and d.day = public.baku_today() and d.done_at is not null);
    insert into public.push_queue (kind, mode, title, body, url, users)
    values ('daily', 'users', '🔥 Gündəlik məşqi unutma!', 'Bugünkü 5 sual səni gözləyir — seriyanı itirmə', 'practice.html', v_users);
  end if;

  -- 2 gündən köhnə göndərilməmişləri at
  update public.push_queue set sent_at = now(), sent_n = 0 where sent_at is null and created_at < now() - interval '2 days';

  return json_build_object(
    'vapid', (select json_build_object('public', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'),
                                       'private', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private'))
               where exists (select 1 from vault.secrets where name = 'vapid_public')),
    'items', (select coalesce(json_agg(json_build_object('id', q.id, 'title', q.title, 'body', q.body, 'url', q.url, 'tag', q.kind || q.id,
               'subs', (select coalesce(json_agg(json_build_object('id', s.id, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)), '[]'::json)
                          from public.push_subs s join public.profiles p on p.id = s.user_id
                         where p.status = 'approved' and p.role = 'student'
                           and case q.mode
                                 when 'users' then s.user_id = any (coalesce(q.users, '{}'))
                                 when 'test'  then public.test_target_ok(q.classes, q.groups, p.id, p.class_name)
                                 else public.target_ok(q.classes, p.class_name) end)) order by q.id), '[]'::json)
                from (select * from public.push_queue where sent_at is null order by id limit 20) q));
end;
$$;

create or replace function public.push_done(p_secret text, p_ids bigint[], p_sent int[], p_dead bigint[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare i int;
begin
  if not public.push_secret_ok(p_secret) then raise exception 'İcazə yoxdur'; end if;
  for i in 1 .. coalesce(cardinality(p_ids), 0) loop
    update public.push_queue set sent_at = now(), sent_n = coalesce(p_sent[i], 0) where id = p_ids[i];
  end loop;
  delete from public.push_subs where id = any (coalesce(p_dead, '{}'));
end;
$$;
revoke execute on function public.push_set_vapid(text, text, text)            from public, authenticated;
revoke execute on function public.push_pending(text)                          from public, authenticated;
revoke execute on function public.push_done(text, bigint[], int[], bigint[])  from public, authenticated;
grant  execute on function public.push_set_vapid(text, text, text)            to anon;
grant  execute on function public.push_pending(text)                          to anon;
grant  execute on function public.push_done(text, bigint[], int[], bigint[])  to anon;

-- Admin: neçə şagird bildirişləri açıb
create or replace function public.admin_push_stats()
returns json language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return json_build_object('users', (select count(distinct user_id) from public.push_subs),
                           'ready', exists (select 1 from vault.secrets where name = 'vapid_public'),
                           'last', (select max(sent_at) from public.push_queue where sent_n > 0));
end;
$$;
grant execute on function public.admin_push_stats() to authenticated;
