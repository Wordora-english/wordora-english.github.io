-- =====================================================================
--  WORDORA — Kağız sınaqlar
--  Sınaq kağızda yazılır; müəllim hər şagirdin cavablarını sayta yazır,
--  sayt yoxlayır, analiz edir və hər şagird üçün PDF hesabat hazırlayır.
--  Saytda qeydiyyatı olmayan şagirdləri də (yalnız adı ilə) daxil etmək olar.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.tests add column if not exists is_paper boolean not null default false;

create table if not exists public.paper_entries (
  id           uuid primary key default gen_random_uuid(),
  test_id      uuid not null references public.tests(id) on delete cascade,
  user_id      uuid references public.profiles(id) on delete set null,   -- qeydiyyatı yoxdursa boş
  student_name text not null check (char_length(student_name) between 1 and 120),
  class_name   text check (char_length(class_name) <= 40),
  variant      text not null default 'A',
  answers      jsonb not null default '{}'::jsonb,
  details      jsonb,
  auto_score   numeric,
  essay_score  numeric,
  essay_review jsonb,
  score        numeric,
  status       text not null default 'graded' check (status in ('submitted', 'graded')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists paper_entries_user_uq on public.paper_entries (test_id, user_id) where user_id is not null;
create index if not exists paper_entries_test_idx on public.paper_entries (test_id);

alter table public.paper_entries enable row level security;
drop policy if exists "paper_admin" on public.paper_entries;
create policy "paper_admin" on public.paper_entries for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.paper_entries from anon;

-- Müəllim cavabları yazır / düzəldir → server yoxlayır (öz variantının açarı ilə)
create or replace function public.admin_paper_save(p_test uuid, p_entry uuid, p_user uuid, p_name text, p_class text, p_variant text, p_answers jsonb)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_g jsonb; v_e public.paper_entries; v_var text := upper(coalesce(nullif(trim(p_variant), ''), 'A'));
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_t from public.tests where id = p_test;
  if not found then raise exception 'Sınaq tapılmadı'; end if;
  if coalesce(trim(p_name), '') = '' and p_user is null then raise exception 'Şagirdin adını yaz'; end if;
  if v_var <> 'A' and not exists (select 1 from jsonb_array_elements(v_t.variants) v where v->>'code' = v_var) then
    raise exception '% variantı bu sınaqda yoxdur', v_var;
  end if;
  v_g := public.grade_answers(v_t.questions, coalesce(public.variant_key(p_test, v_var), '{}'::jsonb), coalesce(p_answers, '{}'::jsonb));

  if p_entry is not null then
    select * into v_e from public.paper_entries where id = p_entry and test_id = p_test for update;
    if not found then raise exception 'Qeyd tapılmadı'; end if;
  elsif p_user is not null then
    select * into v_e from public.paper_entries where test_id = p_test and user_id = p_user for update;
  end if;

  if v_e.id is null then
    insert into public.paper_entries (test_id, user_id, student_name, class_name, variant, answers)
    values (p_test, p_user, coalesce(nullif(trim(p_name), ''), (select full_name from public.profiles where id = p_user)),
            coalesce(nullif(trim(p_class), ''), (select class_name from public.profiles where id = p_user)), v_var, coalesce(p_answers, '{}'::jsonb))
    returning * into v_e;
  end if;

  update public.paper_entries
     set user_id = p_user,
         student_name = coalesce(nullif(trim(p_name), ''), (select full_name from public.profiles where id = p_user), student_name),
         class_name = coalesce(nullif(trim(p_class), ''), (select class_name from public.profiles where id = p_user), class_name),
         variant = v_var,
         answers = coalesce(p_answers, '{}'::jsonb),
         details = v_g->'details',
         auto_score = (v_g->>'score')::numeric,
         score = (v_g->>'score')::numeric + coalesce(essay_score, 0),
         status = case when (v_g->>'has_essay')::boolean and essay_score is null then 'submitted' else 'graded' end,
         updated_at = now()
   where id = v_e.id
   returning * into v_e;
  return row_to_json(v_e);
end;
$$;

create or replace function public.admin_paper_essay(p_entry uuid, p_points numeric, p_review jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_points is not null and p_points < 0 then raise exception 'Bal mənfi ola bilməz'; end if;
  update public.paper_entries
     set essay_score = p_points, essay_review = nullif(p_review, '{}'::jsonb),
         score = coalesce(auto_score, 0) + coalesce(p_points, 0),
         status = case when p_points is null and exists (select 1 from jsonb_each(coalesce(details, '{}'::jsonb)) d where (d.value->>'essay')::boolean) then 'submitted' else 'graded' end,
         updated_at = now()
   where id = p_entry;
end;
$$;

revoke execute on function public.admin_paper_save(uuid, uuid, uuid, text, text, text, jsonb) from public, anon;
revoke execute on function public.admin_paper_essay(uuid, numeric, jsonb)                      from public, anon;
grant  execute on function public.admin_paper_save(uuid, uuid, uuid, text, text, text, jsonb) to authenticated;
grant  execute on function public.admin_paper_essay(uuid, numeric, jsonb)                      to authenticated;

-- Açar dəyişəndə kağız nəticələr də yenidən hesablanır
create or replace function public.admin_regrade(p_test uuid)
returns int
language plpgsql security definer set search_path = ''
as $$
declare r record; n int := 0; v_t public.tests; v_g jsonb;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  for r in select id from public.attempts where test_id = p_test and status <> 'in_progress' loop
    perform public.finalize_attempt(r.id); n := n + 1;
  end loop;
  select * into v_t from public.tests where id = p_test;
  for r in select * from public.paper_entries where test_id = p_test loop
    v_g := public.grade_answers(v_t.questions, coalesce(public.variant_key(p_test, r.variant), '{}'::jsonb), r.answers);
    update public.paper_entries
       set details = v_g->'details', auto_score = (v_g->>'score')::numeric,
           score = (v_g->>'score')::numeric + coalesce(essay_score, 0),
           status = case when (v_g->>'has_essay')::boolean and essay_score is null then 'submitted' else 'graded' end
     where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function public.admin_regrade(uuid) from public, anon;
grant  execute on function public.admin_regrade(uuid) to authenticated;

-- Portal: kağız nəticələr də "Nəticələrim"-də görünsün (nəticələr açılandan sonra)
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
   where a.user_id = auth.uid()
  union all
  select p.test_id, p.status, null, p.created_at,
         case when t.results_released then p.score end,
         public.test_total(t.questions), t.results_released, t.results_released
    from public.paper_entries p join public.tests t on t.id = p.test_id
   where p.user_id = auth.uid() and t.is_published;
$$;
revoke execute on function public.get_my_attempts() from public, anon;
grant  execute on function public.get_my_attempts() to authenticated;

create or replace function public.get_my_review(p_test uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_key jsonb; v_q jsonb; v_o public.test_online; v_p public.paper_entries;
begin
  select * into v_t from public.tests where id = p_test;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();
  if not found then
    -- kağız sınaq: nəticə müəllimin daxil etdiyi cədvəldən
    select * into v_p from public.paper_entries where test_id = p_test and user_id = auth.uid();
    if not found then raise exception 'Nəticə yoxdur'; end if;
    v_a.answers := v_p.answers; v_a.details := v_p.details; v_a.score := v_p.score; v_a.essay_score := v_p.essay_score;
    v_a.essay_review := v_p.essay_review; v_a.variant := v_p.variant; v_a.status := v_p.status;
  end if;
  if v_a.status = 'in_progress' then raise exception 'Nəticə yoxdur'; end if;
  if not v_t.results_released then raise exception 'Nəticələr hələ açılmayıb'; end if;
  v_key := public.variant_key(p_test, v_a.variant);

  v_q := v_t.questions;
  select * into v_o from public.test_online where test_id = p_test;
  if found then
    select coalesce(jsonb_agg(q || coalesce((select o - 'n' - 'pid' from jsonb_array_elements(v_o.questions) o where o->>'n' = q->>'n' limit 1), '{}'::jsonb)
                              order by ord), '[]'::jsonb)
      into v_q
      from jsonb_array_elements(v_t.questions) with ordinality as x(q, ord);
  end if;

  return json_build_object('title', v_t.title, 'questions', v_q, 'answers', v_a.answers,
                           'key', v_key, 'details', v_a.details, 'score', v_a.score,
                           'essay_score', v_a.essay_score, 'essay_review', v_a.essay_review,
                           'variant', case when jsonb_array_length(v_t.variants) > 0 then v_a.variant end,
                           'sections', coalesce(v_t.content->'sections', '[]'::jsonb),
                           'total', public.test_total(v_t.questions));
end;
$$;
revoke execute on function public.get_my_review(uuid) from public, anon;
grant  execute on function public.get_my_review(uuid) to authenticated;

-- Kağız sınağa saytda başlamaq olmaz
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz; v_o public.test_online; v_q jsonb; v_retake boolean; v_var text;
begin
  if not public.test_visible(p_test) then raise exception 'Bu sınaq sənin üçün açıq deyil'; end if;
  select * into v_t from public.tests where id = p_test;
  if v_t.is_paper then raise exception 'Bu sınaq kağız üzərində yazılır — saytda yazmaq olmur'; end if;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();

  if found then
    if v_a.status = 'in_progress' and now() > v_a.deadline + interval '30 seconds' then
      perform public.finalize_attempt(v_a.id);
      return json_build_object('status', 'done');
    end if;
    if v_a.status <> 'in_progress' then return json_build_object('status', 'done'); end if;
  else
    -- müəllim "yenidən yazsın" icazəsi veribsə, başlama/bitmə vaxtı yoxlanmır
    delete from public.test_retakes where test_id = p_test and user_id = auth.uid() and expires_at > now()
    returning true into v_retake;
    if not coalesce(v_retake, false) then
      if v_t.starts_at is not null and now() < v_t.starts_at then raise exception 'Sınaq hələ başlamayıb'; end if;
      if v_t.ends_at   is not null and now() >= v_t.ends_at  then raise exception 'Sınağın vaxtı bitib'; end if;
    end if;
    v_deadline := now() + make_interval(mins => v_t.duration_min);
    if not coalesce(v_retake, false) and v_t.ends_at is not null and v_t.ends_at < v_deadline then v_deadline := v_t.ends_at; end if;
    v_var := public.pick_variant(p_test, auth.uid());
    insert into public.attempts (test_id, user_id, deadline, variant)
    values (p_test, auth.uid(), v_deadline, v_var) returning * into v_a;
  end if;

  -- quruluşu mətnlərlə birləşdir (n-ə görə)
  v_q := v_t.questions;
  select * into v_o from public.test_online where test_id = p_test;
  if found then
    select coalesce(jsonb_agg(q || coalesce((select o - 'n' from jsonb_array_elements(v_o.questions) o where o->>'n' = q->>'n' limit 1), '{}'::jsonb)
                              order by ord), '[]'::jsonb)
      into v_q
      from jsonb_array_elements(v_t.questions) with ordinality as x(q, ord);
  end if;

  return json_build_object(
    'status', 'in_progress',
    'attempt_id', v_a.id,
    'deadline', v_a.deadline,
    'server_now', now(),
    'answers', v_a.answers,
    'title', v_t.title,
    'questions', v_q,
    'passages', coalesce(v_o.passages, '[]'::jsonb),
    'total', public.test_total(v_t.questions),
    'variant', v_a.variant,
    'has_variants', jsonb_array_length(v_t.variants) > 0,
    'pdf_path', public.variant_file(v_t, v_a.variant, 'pdf_path'),
    'has_audio', public.variant_file(v_t, v_a.variant, 'audio_path') is not null,
    'audio_max', v_t.audio_max_plays,
    'audio_plays', v_a.audio_plays);
end;
$$;
revoke execute on function public.start_attempt(uuid) from public, anon;
grant  execute on function public.start_attempt(uuid) to authenticated;
