-- =====================================================================
--  WORDORA — Şagirdi silmək və sınağı yenidən yazdırmaq
--  A) Şagirdi saytdan tamamilə silmək (hesab, nəticələr, hər şey)
--  B) "Yenidən yazsın": köhnə nəticə arxivdə qalır, şagird sınağı
--     son tarix keçsə belə müəyyən gün ərzində yenidən yaza bilir
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- =====================================================================
-- A) ŞAGİRDİ SİLMƏK
-- =====================================================================
create or replace function public.admin_delete_student(p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.profiles;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_p from public.profiles where id = p_user;
  if not found then raise exception 'Şagird tapılmadı'; end if;
  if v_p.role = 'admin' or p_user = auth.uid() then raise exception 'Admin hesabı silinə bilməz'; end if;
  delete from public.attempts_archive where user_id = p_user;
  delete from auth.users where id = p_user;            -- profil və bütün nəticələr avtomatik silinir
  delete from public.profiles where id = p_user;       -- ehtiyat üçün
end;
$$;
revoke execute on function public.admin_delete_student(uuid) from public, anon;
grant  execute on function public.admin_delete_student(uuid) to authenticated;

-- =====================================================================
-- B) YENİDƏN YAZMAQ
-- =====================================================================
-- Köhnə cəhdlər (yalnız admin görür)
create table if not exists public.attempts_archive (
  id           uuid primary key,
  test_id      uuid not null references public.tests(id) on delete cascade,
  user_id      uuid not null,
  started_at   timestamptz,
  submitted_at timestamptz,
  score        numeric,
  auto_score   numeric,
  essay_score  numeric,
  answers      jsonb,
  details      jsonb,
  essay_review jsonb,
  status       text,
  archived_at  timestamptz not null default now()
);
alter table public.attempts_archive enable row level security;
drop policy if exists "aarch_admin" on public.attempts_archive;
create policy "aarch_admin" on public.attempts_archive for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.attempts_archive from anon;

-- İcazələr: şagird yalnız özününkünü görür
create table if not exists public.test_retakes (
  test_id    uuid not null references public.tests(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (test_id, user_id)
);
alter table public.test_retakes enable row level security;
drop policy if exists "retake_select" on public.test_retakes;
create policy "retake_select" on public.test_retakes for select to authenticated using (public.is_admin() or user_id = auth.uid());
revoke insert, update, delete on public.test_retakes from anon, authenticated;
revoke all on public.test_retakes from anon;

create or replace function public.admin_allow_retake(p_test uuid, p_user uuid, p_days int default 3)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_a from public.attempts where test_id = p_test and user_id = p_user;
  if found then
    insert into public.attempts_archive (id, test_id, user_id, started_at, submitted_at, score, auto_score, essay_score, answers, details, essay_review, status)
    values (v_a.id, v_a.test_id, v_a.user_id, v_a.started_at, v_a.submitted_at, v_a.score, v_a.auto_score, v_a.essay_score, v_a.answers, v_a.details, v_a.essay_review, v_a.status)
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

create or replace function public.admin_cancel_retake(p_test uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  delete from public.test_retakes where test_id = p_test and user_id = p_user;
end;
$$;
revoke execute on function public.admin_cancel_retake(uuid, uuid) from public, anon;
grant  execute on function public.admin_cancel_retake(uuid, uuid) to authenticated;

-- start_attempt: icazə varsa, vaxt məhdudiyyəti tətbiq olunmur
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz; v_o public.test_online; v_q jsonb; v_retake boolean;
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
    insert into public.attempts (test_id, user_id, deadline)
    values (p_test, auth.uid(), v_deadline) returning * into v_a;
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
    'pdf_path', v_t.pdf_path,
    'has_audio', v_t.audio_path is not null,
    'audio_max', v_t.audio_max_plays,
    'audio_plays', v_a.audio_plays);
end;
$$;
revoke execute on function public.start_attempt(uuid) from public, anon;
grant  execute on function public.start_attempt(uuid) to authenticated;
