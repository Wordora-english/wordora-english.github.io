-- =====================================================================
--  WORDORA — 4-cü mərhələ: sınaq platforması (PDF + onlayn cavab kartı)
--  • Cavab açarı ayrıca, yalnız admin üçün cədvəldə — şagird heç vaxt görmür
--  • Taymer serverdə: vaxt serverin saatı ilə hesablanır
--  • Yoxlama serverdə aparılır
--  • PDF-ə yalnız sınaq gedən müddətdə baxmaq olar, yükləmək olmur
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cədvəllər
-- ---------------------------------------------------------------------
create table if not exists public.tests (
  id               uuid primary key default gen_random_uuid(),
  title            text not null check (char_length(title) between 1 and 150),
  description      text check (char_length(description) <= 2000),
  pdf_path         text,                                  -- gizli "tests" bucket-də
  -- Sualların quruluşu (cavabsız):
  -- [{"n":1,"type":"choice","options":"ABCDE","points":4},
  --  {"n":4,"type":"multi","parts":4,"options":"ABCDE","points":4},
  --  {"n":10,"type":"open","points":2},
  --  {"n":26,"type":"essay","points":16.6,"min_words":70}]
  questions        jsonb not null default '[]'::jsonb,
  duration_min     int not null default 45 check (duration_min between 1 and 600),
  starts_at        timestamptz,
  ends_at          timestamptz,
  target_classes   text[],
  is_published     boolean not null default false,
  results_mode     text not null default 'manual' check (results_mode in ('instant', 'manual')),
  results_released boolean not null default false,
  created_at       timestamptz not null default now()
);

create table if not exists public.test_keys (
  test_id uuid primary key references public.tests(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb              -- {"1":"A","4":"BBAA","10":"went/has gone"}
);

create table if not exists public.attempts (
  id           uuid primary key default gen_random_uuid(),
  test_id      uuid not null references public.tests(id)    on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  started_at   timestamptz not null default now(),
  deadline     timestamptz not null,
  submitted_at timestamptz,
  answers      jsonb not null default '{}'::jsonb,
  details      jsonb,
  auto_score   numeric,
  essay_score  numeric,
  score        numeric,
  status       text not null default 'in_progress' check (status in ('in_progress', 'submitted', 'graded')),
  unique (test_id, user_id)
);
create index if not exists attempts_test_idx on public.attempts (test_id);

alter table public.tests     enable row level security;
alter table public.test_keys enable row level security;
alter table public.attempts  enable row level security;

-- ---------------------------------------------------------------------
-- 2. Köməkçi funksiyalar
-- ---------------------------------------------------------------------
create or replace function public.test_visible(p_test uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.tests t join public.profiles p on p.id = auth.uid()
     where t.id = p_test and t.is_published and p.status = 'approved'
       and (t.target_classes is null or cardinality(t.target_classes) = 0
            or p.class_name = any (t.target_classes))
  );
$$;

create or replace function public.test_total(p_questions jsonb)
returns numeric language sql immutable set search_path = ''
as $$ select coalesce(sum((q->>'points')::numeric), 0) from jsonb_array_elements(p_questions) q; $$;

create or replace function public.norm_answer(p text)
returns text language sql immutable set search_path = ''
as $$
  select regexp_replace(
           regexp_replace(lower(trim(replace(replace(coalesce(p, ''), '’', ''''), '`', ''''))), '\s+', ' ', 'g'),
           '[.!?,;:"]+$', '');
$$;

-- Cavabları açarla yoxla
create or replace function public.grade_answers(p_questions jsonb, p_key jsonb, p_answers jsonb)
returns jsonb
language plpgsql immutable set search_path = ''
as $$
declare
  q jsonb; n text; t text; pts numeric; k text; a text;
  i int; ok int; frac numeric; alt text; words int;
  v_score numeric := 0; v_det jsonb := '{}'::jsonb; v_essay boolean := false;
begin
  for q in select value from jsonb_array_elements(p_questions) loop
    n   := q->>'n';
    t   := q->>'type';
    pts := coalesce((q->>'points')::numeric, 0);
    a   := trim(coalesce(p_answers->>n, ''));
    frac := 0;

    if t = 'essay' then
      v_essay := true;
      words := case when a = '' then 0 else coalesce(array_length(regexp_split_to_array(a, '\s+'), 1), 0) end;
      v_det := v_det || jsonb_build_object(n, jsonb_build_object('essay', true, 'words', words));
      continue;
    elsif t = 'choice' then
      k := upper(trim(coalesce(p_key->>n, '')));
      if a <> '' and upper(a) = k then frac := 1; end if;
    elsif t = 'multi' then
      k := upper(trim(coalesce(p_key->>n, '')));
      ok := 0;
      for i in 1 .. length(k) loop
        if upper(substr(a, i, 1)) = substr(k, i, 1) then ok := ok + 1; end if;
      end loop;
      frac := case when length(k) > 0 then ok::numeric / length(k) else 0 end;
    elsif t = 'open' then
      foreach alt in array string_to_array(coalesce(p_key->>n, ''), '/') loop
        if public.norm_answer(alt) <> '' and public.norm_answer(alt) = public.norm_answer(a) then frac := 1; end if;
      end loop;
    end if;

    v_score := v_score + round(pts * frac, 2);
    v_det := v_det || jsonb_build_object(n, jsonb_build_object('frac', round(frac, 3), 'points', round(pts * frac, 2)));
  end loop;
  return jsonb_build_object('score', v_score, 'details', v_det, 'has_essay', v_essay);
end;
$$;

-- Cəhdi bitir və yoxla
create or replace function public.finalize_attempt(p_attempt uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_key jsonb; v_g jsonb;
begin
  select * into v_a from public.attempts where id = p_attempt;
  if not found then return; end if;
  select * into v_t from public.tests where id = v_a.test_id;
  select answers into v_key from public.test_keys where test_id = v_a.test_id;
  v_g := public.grade_answers(v_t.questions, coalesce(v_key, '{}'::jsonb), v_a.answers);
  update public.attempts
     set submitted_at = coalesce(submitted_at, least(now(), deadline + interval '60 seconds')),
         details      = v_g->'details',
         auto_score   = (v_g->>'score')::numeric,
         score        = (v_g->>'score')::numeric + coalesce(essay_score, 0),
         status       = case when (v_g->>'has_essay')::boolean and essay_score is null
                             then 'submitted' else 'graded' end
   where id = p_attempt;
end;
$$;
revoke execute on function public.finalize_attempt(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Qaydalar (RLS)
-- ---------------------------------------------------------------------
drop policy if exists "tests_select" on public.tests;
create policy "tests_select" on public.tests for select to authenticated using (public.test_visible(id));
drop policy if exists "tests_admin_insert" on public.tests;
create policy "tests_admin_insert" on public.tests for insert to authenticated with check (public.is_admin());
drop policy if exists "tests_admin_update" on public.tests;
create policy "tests_admin_update" on public.tests for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "tests_admin_delete" on public.tests;
create policy "tests_admin_delete" on public.tests for delete to authenticated using (public.is_admin());

-- Cavab açarı: yalnız admin
drop policy if exists "keys_admin_all" on public.test_keys;
create policy "keys_admin_all" on public.test_keys for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Cəhdlər: yalnız admin birbaşa oxuyur; şagird öz nəticəsini funksiya ilə alır
-- (bal "müəllim açanda" rejimində vaxtından əvvəl görünməsin deyə)
drop policy if exists "attempts_admin_select" on public.attempts;
create policy "attempts_admin_select" on public.attempts for select to authenticated using (public.is_admin());

revoke all on public.tests, public.test_keys, public.attempts from anon;
revoke insert, update, delete on public.attempts from authenticated;

-- ---------------------------------------------------------------------
-- 4. Şagird funksiyaları
-- ---------------------------------------------------------------------
-- Sınağa başla (və ya yarımçıq qalanı davam etdir)
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz;
begin
  if not public.test_visible(p_test) then raise exception 'Bu sınaq sənin üçün açıq deyil'; end if;
  select * into v_t from public.tests where id = p_test;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();

  if found then
    if v_a.status = 'in_progress' and now() > v_a.deadline + interval '30 seconds' then
      perform public.finalize_attempt(v_a.id);
      return json_build_object('status', 'done');
    end if;
    if v_a.status <> 'in_progress' then return json_build_object('status', 'done'); end if;
  else
    if v_t.starts_at is not null and now() < v_t.starts_at then raise exception 'Sınaq hələ başlamayıb'; end if;
    if v_t.ends_at   is not null and now() >= v_t.ends_at  then raise exception 'Sınağın vaxtı bitib'; end if;
    v_deadline := now() + make_interval(mins => v_t.duration_min);
    if v_t.ends_at is not null and v_t.ends_at < v_deadline then v_deadline := v_t.ends_at; end if;
    insert into public.attempts (test_id, user_id, deadline)
    values (p_test, auth.uid(), v_deadline) returning * into v_a;
  end if;

  return json_build_object(
    'status', 'in_progress',
    'attempt_id', v_a.id,
    'deadline', v_a.deadline,
    'server_now', now(),
    'answers', v_a.answers,
    'title', v_t.title,
    'questions', v_t.questions,
    'total', public.test_total(v_t.questions),
    'pdf_path', v_t.pdf_path);
end;
$$;

-- Avtomatik yadda saxlama
create or replace function public.save_answers(p_attempt uuid, p_answers jsonb)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  if octet_length(p_answers::text) > 200000 then raise exception 'Cavablar çox böyükdür'; end if;
  update public.attempts set answers = p_answers
   where id = p_attempt and user_id = auth.uid() and status = 'in_progress'
     and now() <= deadline + interval '30 seconds';
  return found;
end;
$$;

-- Təhvil ver
create or replace function public.submit_attempt(p_attempt uuid, p_answers jsonb)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests;
begin
  select * into v_a from public.attempts where id = p_attempt and user_id = auth.uid();
  if not found then raise exception 'Cəhd tapılmadı'; end if;
  if v_a.status = 'in_progress' then
    if now() <= v_a.deadline + interval '60 seconds' and octet_length(p_answers::text) <= 200000 then
      update public.attempts set answers = p_answers where id = p_attempt;
    end if;
    update public.attempts set submitted_at = least(now(), deadline + interval '60 seconds') where id = p_attempt;
    perform public.finalize_attempt(p_attempt);
  end if;
  select * into v_a from public.attempts where id = p_attempt;
  select * into v_t from public.tests where id = v_a.test_id;
  if v_t.results_mode = 'instant' or v_t.results_released then
    return json_build_object('submitted', true, 'show', true, 'score', v_a.score,
                             'total', public.test_total(v_t.questions), 'pending_essay', v_a.status = 'submitted');
  end if;
  return json_build_object('submitted', true, 'show', false);
end;
$$;

-- Portal üçün: mənim cəhdlərim (bal yalnız icazə varsa)
create or replace function public.get_my_attempts()
returns table (test_id uuid, status text, deadline timestamptz, submitted_at timestamptz,
               score numeric, total numeric, show_score boolean, released boolean)
language sql stable security definer set search_path = ''
as $$
  select a.test_id,
         case when a.status = 'in_progress' and now() > a.deadline + interval '30 seconds' then 'expired' else a.status end,
         a.deadline, a.submitted_at,
         case when t.results_mode = 'instant' or t.results_released then a.score end,
         public.test_total(t.questions),
         (t.results_mode = 'instant' or t.results_released),
         t.results_released
    from public.attempts a join public.tests t on t.id = a.test_id
   where a.user_id = auth.uid();
$$;

-- Nəticələr açılandan sonra: öz cavablarım + düzgün cavablar
create or replace function public.get_my_review(p_test uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_key jsonb;
begin
  select * into v_t from public.tests where id = p_test;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();
  if not found or v_a.status = 'in_progress' then raise exception 'Nəticə yoxdur'; end if;
  if not v_t.results_released then raise exception 'Nəticələr hələ açılmayıb'; end if;
  select answers into v_key from public.test_keys where test_id = p_test;
  return json_build_object('title', v_t.title, 'questions', v_t.questions, 'answers', v_a.answers,
                           'key', v_key, 'details', v_a.details, 'score', v_a.score,
                           'essay_score', v_a.essay_score, 'total', public.test_total(v_t.questions));
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Admin funksiyaları
-- ---------------------------------------------------------------------
create or replace function public.admin_finalize_expired(p_test uuid)
returns int
language plpgsql security definer set search_path = ''
as $$
declare r record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  for r in select id from public.attempts
            where test_id = p_test and status = 'in_progress' and now() > deadline + interval '30 seconds' loop
    perform public.finalize_attempt(r.id); n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.admin_regrade(p_test uuid)
returns int
language plpgsql security definer set search_path = ''
as $$
declare r record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  for r in select id from public.attempts where test_id = p_test and status <> 'in_progress' loop
    perform public.finalize_attempt(r.id); n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.admin_grade_essay(p_attempt uuid, p_points numeric)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_points is not null and p_points < 0 then raise exception 'Bal mənfi ola bilməz'; end if;
  update public.attempts
     set essay_score = p_points,
         score  = coalesce(auto_score, 0) + coalesce(p_points, 0),
         status = case when p_points is null then 'submitted' else 'graded' end
   where id = p_attempt and status <> 'in_progress';
end;
$$;

-- Şagirdə yenidən yazmaq imkanı ver (cəhdi sil)
create or replace function public.admin_reset_attempt(p_attempt uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  delete from public.attempts where id = p_attempt;
end;
$$;

revoke execute on function public.start_attempt(uuid)              from public, anon;
revoke execute on function public.save_answers(uuid, jsonb)        from public, anon;
revoke execute on function public.submit_attempt(uuid, jsonb)      from public, anon;
revoke execute on function public.get_my_attempts()                from public, anon;
revoke execute on function public.get_my_review(uuid)              from public, anon;
revoke execute on function public.admin_finalize_expired(uuid)     from public, anon;
revoke execute on function public.admin_regrade(uuid)              from public, anon;
revoke execute on function public.admin_grade_essay(uuid, numeric) from public, anon;
revoke execute on function public.admin_reset_attempt(uuid)        from public, anon;
grant  execute on function public.start_attempt(uuid)              to authenticated;
grant  execute on function public.save_answers(uuid, jsonb)        to authenticated;
grant  execute on function public.submit_attempt(uuid, jsonb)      to authenticated;
grant  execute on function public.get_my_attempts()                to authenticated;
grant  execute on function public.get_my_review(uuid)              to authenticated;
grant  execute on function public.admin_finalize_expired(uuid)     to authenticated;
grant  execute on function public.admin_regrade(uuid)              to authenticated;
grant  execute on function public.admin_grade_essay(uuid, numeric) to authenticated;
grant  execute on function public.admin_reset_attempt(uuid)        to authenticated;

-- ---------------------------------------------------------------------
-- 6. Gizli "tests" bucket — PDF-ə yalnız sınaq gedən müddətdə baxmaq olar
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tests', 'tests', false, 52428800, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "tests_files_admin_all" on storage.objects;
create policy "tests_files_admin_all" on storage.objects
  for all to authenticated
  using (bucket_id = 'tests' and public.is_admin())
  with check (bucket_id = 'tests' and public.is_admin());

create or replace function public.can_read_test_file(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.tests t
      join public.attempts a on a.test_id = t.id
     where t.pdf_path = p_name
       and a.user_id = auth.uid()
       and a.status = 'in_progress'
       and now() <= a.deadline + interval '30 seconds'
  );
$$;
revoke execute on function public.can_read_test_file(text) from public, anon;
grant  execute on function public.can_read_test_file(text) to authenticated;

drop policy if exists "tests_files_student_read" on storage.objects;
create policy "tests_files_student_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'tests' and public.can_read_test_file(name));
