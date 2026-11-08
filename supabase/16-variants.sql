-- =====================================================================
--  WORDORA — Sınaq variantları (A, B, C ...)
--  Hər variantın öz PDF-i, cavab açarı və (istəyə görə) audiosu var (yoxdursa, A-nın audiosu).
--  Sual quruluşu (sual sayı, tipləri, ballar) bütün variantlarda eynidir.
--  Şagird "Başla" basanda variant avtomatik verilir (az yazılan variant,
--  yenidən yazanda əvvəlkindən fərqli); müəllim əvvəlcədən özü də təyin edə bilər.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.tests            add column if not exists variants jsonb not null default '[]'::jsonb;   -- [{"code":"B","pdf_path":"...","audio_path":null}]
alter table public.test_keys        add column if not exists variants jsonb not null default '{}'::jsonb;   -- {"B": {"1":"C", ...}}
alter table public.attempts         add column if not exists variant  text  not null default 'A';
alter table public.attempts_archive add column if not exists variant  text;

-- Müəllimin əvvəlcədən təyin etdiyi variantlar (yalnız admin)
create table if not exists public.test_variant_assign (
  test_id uuid not null references public.tests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  variant text not null check (variant ~ '^[A-Z]$'),
  primary key (test_id, user_id)
);
alter table public.test_variant_assign enable row level security;
drop policy if exists "tva_admin" on public.test_variant_assign;
create policy "tva_admin" on public.test_variant_assign for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.test_variant_assign from anon;

-- Variantın faylı (A = əsas)
create or replace function public.variant_file(p_t public.tests, p_code text, p_field text)
returns text
language sql stable
as $$
  select case when coalesce(p_code, 'A') = 'A' then
           case p_field when 'pdf_path' then p_t.pdf_path when 'audio_path' then p_t.audio_path end
         when p_field = 'audio_path' then   -- variantın öz audiosu yoxdursa, A-nın audiosu
           coalesce((select nullif(v->>'audio_path', '') from jsonb_array_elements(p_t.variants) v where v->>'code' = p_code limit 1), p_t.audio_path)
         else (select nullif(v->>p_field, '') from jsonb_array_elements(p_t.variants) v where v->>'code' = p_code limit 1)
         end;
$$;

-- Variantın cavab açarı
create or replace function public.variant_key(p_test uuid, p_code text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when coalesce(p_code, 'A') = 'A' then k.answers
              else coalesce(k.variants -> p_code, k.answers) end
    from public.test_keys k where k.test_id = p_test;
$$;
revoke execute on function public.variant_key(uuid, text) from public, anon, authenticated;

-- Variant seçimi: təyin edilibsə — o; yoxsa ən az yazılan (əvvəl yazdığı variantdan qaçaraq)
create or replace function public.pick_variant(p_test uuid, p_user uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_codes text[]; v_pick text;
begin
  select * into v_t from public.tests where id = p_test;
  if jsonb_array_length(coalesce(v_t.variants, '[]'::jsonb)) = 0 then return 'A'; end if;
  v_codes := array['A'] || array(select v->>'code' from jsonb_array_elements(v_t.variants) v where coalesce(v->>'pdf_path', '') <> '' order by v->>'code');
  select variant into v_pick from public.test_variant_assign where test_id = p_test and user_id = p_user;
  if v_pick = any (v_codes) then return v_pick; end if;
  perform pg_advisory_xact_lock(hashtext('variant:' || p_test::text));   -- eyni anda başlayanlar fərqli variant alsın
  select c into v_pick
    from unnest(v_codes) with ordinality as x(c, ord)
   order by exists (select 1 from public.attempts_archive ar where ar.test_id = p_test and ar.user_id = p_user and ar.variant = c),
            (select count(*) from public.attempts a where a.test_id = p_test and a.variant = c),
            ord
   limit 1;
  return coalesce(v_pick, 'A');
end;
$$;
revoke execute on function public.pick_variant(uuid, uuid) from public, anon, authenticated;

-- Yoxlama: hər cəhd öz variantının açarı ilə
create or replace function public.finalize_attempt(p_attempt uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_key jsonb; v_g jsonb;
begin
  select * into v_a from public.attempts where id = p_attempt;
  if not found then return; end if;
  select * into v_t from public.tests where id = v_a.test_id;
  v_key := public.variant_key(v_a.test_id, v_a.variant);
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

-- PDF və audio: şagird yalnız öz variantının faylını, yalnız sınaq gedərkən açır
create or replace function public.can_read_test_file(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.tests t
      join public.attempts a on a.test_id = t.id
     where a.user_id = auth.uid()
       and a.status = 'in_progress'
       and now() <= a.deadline + interval '30 seconds'
       and p_name in (public.variant_file(t, a.variant, 'pdf_path'), public.variant_file(t, a.variant, 'audio_path'))
  );
$$;

create or replace function public.test_audio_play(p_attempt uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_path text;
begin
  select * into v_a from public.attempts
   where id = p_attempt and user_id = auth.uid() and status = 'in_progress'
     and now() <= deadline + interval '30 seconds'
   for update;
  if not found then raise exception 'Sınaq aktiv deyil'; end if;
  select * into v_t from public.tests where id = v_a.test_id;
  v_path := public.variant_file(v_t, v_a.variant, 'audio_path');
  if v_path is null then raise exception 'Bu sınaqda dinləmə yoxdur'; end if;
  if v_t.audio_max_plays > 0 and v_a.audio_plays >= v_t.audio_max_plays then
    return json_build_object('allowed', false, 'plays', v_a.audio_plays, 'max', v_t.audio_max_plays);
  end if;
  update public.attempts set audio_plays = audio_plays + 1 where id = p_attempt;
  return json_build_object('allowed', true, 'plays', v_a.audio_plays + 1, 'max', v_t.audio_max_plays, 'path', v_path);
end;
$$;
revoke execute on function public.test_audio_play(uuid) from public, anon;
grant  execute on function public.test_audio_play(uuid) to authenticated;

-- Şagirdin nəticə səhifəsi: öz variantının açarı
create or replace function public.get_my_review(p_test uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests; v_key jsonb; v_q jsonb; v_o public.test_online;
begin
  select * into v_t from public.tests where id = p_test;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();
  if not found or v_a.status = 'in_progress' then raise exception 'Nəticə yoxdur'; end if;
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

-- "Yenidən yazsın": köhnə cəhdin variantı da arxivə düşür
create or replace function public.admin_allow_retake(p_test uuid, p_user uuid, p_days int default 3)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_a from public.attempts where test_id = p_test and user_id = p_user;
  if found then
    insert into public.attempts_archive (id, test_id, user_id, started_at, submitted_at, score, auto_score, essay_score, answers, details, essay_review, status, variant)
    values (v_a.id, v_a.test_id, v_a.user_id, v_a.started_at, v_a.submitted_at, v_a.score, v_a.auto_score, v_a.essay_score, v_a.answers, v_a.details, v_a.essay_review, v_a.status, v_a.variant)
    on conflict (id) do nothing;
    delete from public.attempts where id = v_a.id;
  end if;
  insert into public.test_retakes (test_id, user_id, expires_at)
  values (p_test, p_user, now() + make_interval(days => greatest(coalesce(p_days, 3), 1)))
  on conflict (test_id, user_id) do update set granted_at = now(), expires_at = excluded.expires_at;
end;
$$;
revoke execute on function public.admin_allow_retake(uuid, uuid, int) from public, anon;
grant  execute on function public.admin_allow_retake(uuid, uuid, int) to authenticated;

-- Başla: variant seçilir, şagirdə öz variantının faylları verilir
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz; v_o public.test_online; v_q jsonb; v_retake boolean; v_var text;
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
