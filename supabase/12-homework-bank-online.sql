-- =====================================================================
--  WORDORA — 6-cı mərhələ (4-cü hissə)
--  A) Tam onlayn sınaq (suallar saytın özündə, mətnlərlə; başlamadan görünmür)
--  B) Sual bankı
--  C) Ev tapşırığı (yazılı cavab + şəkil/PDF, qiymət və şərh)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- =====================================================================
-- A) ONLAYN SINAQ
--    tests.questions-da yalnız quruluş qalır (nömrə, tip, bal).
--    Sualların mətni, variantlar və oxu mətnləri ayrıca, yalnız adminin
--    görə bildiyi test_online cədvəlindədir. Şagird onları yalnız sınağa
--    başlayanda start_attempt vasitəsilə alır — əvvəlcədən görə bilməz.
-- =====================================================================
alter table public.tests add column if not exists content jsonb not null default '{}'::jsonb;   -- yalnız {"mode":"online"}

create table if not exists public.test_online (
  test_id    uuid primary key references public.tests(id) on delete cascade,
  questions  jsonb not null default '[]'::jsonb,   -- [{n, text, opts, pid}]
  passages   jsonb not null default '[]'::jsonb,   -- [{id, title, text}]
  source     text  not null default '',
  updated_at timestamptz not null default now()
);
alter table public.test_online enable row level security;
drop policy if exists "tonline_admin" on public.test_online;
create policy "tonline_admin" on public.test_online for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.test_online from anon;

-- start_attempt: onlayn sınaqda sual mətnlərini də qaytarır
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz; v_o public.test_online; v_q jsonb;
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

-- =====================================================================
-- B) SUAL BANKI (yalnız admin)
-- =====================================================================
create table if not exists public.question_bank (
  id         bigint generated always as identity primary key,
  topic      text not null default 'Ümumi' check (char_length(topic) between 1 and 80),
  body       text not null check (char_length(body) between 1 and 6000),
  created_at timestamptz not null default now()
);
create index if not exists qbank_topic_idx on public.question_bank (topic);
alter table public.question_bank enable row level security;
drop policy if exists "qbank_admin" on public.question_bank;
create policy "qbank_admin" on public.question_bank for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.question_bank from anon;

-- =====================================================================
-- C) EV TAPŞIRIĞI
-- =====================================================================
create table if not exists public.homework (
  id             uuid primary key default gen_random_uuid(),
  title          text not null check (char_length(title) between 1 and 150),
  description    text check (char_length(description) <= 5000),
  target_classes text[],
  due_at         timestamptz,
  max_points     numeric not null default 10 check (max_points > 0),
  allow_files    boolean not null default true,
  is_published   boolean not null default true,
  created_at     timestamptz not null default now()
);

create table if not exists public.hw_submissions (
  id           uuid primary key default gen_random_uuid(),
  homework_id  uuid not null references public.homework(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  body         text check (char_length(body) <= 8000),
  files        text[] not null default '{}',
  submitted_at timestamptz not null default now(),
  grade        numeric,
  feedback     text check (char_length(feedback) <= 2000),
  graded_at    timestamptz,
  unique (homework_id, user_id)
);

alter table public.homework       enable row level security;
alter table public.hw_submissions enable row level security;

create or replace function public.hw_visible(p_hw uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.homework h join public.profiles p on p.id = auth.uid()
     where h.id = p_hw and h.is_published and p.status = 'approved'
       and (h.target_classes is null or cardinality(h.target_classes) = 0 or p.class_name = any (h.target_classes)));
$$;

drop policy if exists "hw_select" on public.homework;
create policy "hw_select" on public.homework for select to authenticated using (public.hw_visible(id));
drop policy if exists "hw_admin_write" on public.homework;
create policy "hw_admin_write" on public.homework for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "hws_select" on public.hw_submissions;
create policy "hws_select" on public.hw_submissions for select to authenticated using (public.is_admin() or user_id = auth.uid());
revoke insert, update, delete on public.hw_submissions from anon, authenticated;
revoke all on public.homework, public.hw_submissions from anon;

-- Şagird tapşırığı göndərir / yeniləyir (qiymət qoyulana qədər)
create or replace function public.submit_homework(p_hw uuid, p_body text, p_files text[])
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_h public.homework; v_s public.hw_submissions; f text; v_files text[] := coalesce(p_files, '{}');
begin
  if not public.hw_visible(p_hw) or public.is_admin() then raise exception 'Bu tapşırıq sənin üçün deyil'; end if;
  select * into v_h from public.homework where id = p_hw;
  if coalesce(trim(p_body), '') = '' and cardinality(v_files) = 0 then raise exception 'Cavab yaz və ya fayl əlavə et'; end if;
  if cardinality(v_files) > 5 then raise exception 'Ən çoxu 5 fayl'; end if;
  if cardinality(v_files) > 0 and not v_h.allow_files then raise exception 'Bu tapşırığa fayl əlavə etmək olmaz'; end if;
  foreach f in array v_files loop
    if f not like auth.uid()::text || '/' || p_hw::text || '/%' then raise exception 'Yanlış fayl'; end if;
  end loop;
  select * into v_s from public.hw_submissions where homework_id = p_hw and user_id = auth.uid();
  if found and v_s.grade is not null then raise exception 'Tapşırıq artıq qiymətləndirilib, dəyişmək olmaz'; end if;

  insert into public.hw_submissions (homework_id, user_id, body, files, submitted_at)
  values (p_hw, auth.uid(), left(p_body, 8000), v_files, now())
  on conflict (homework_id, user_id) do update set body = excluded.body, files = excluded.files, submitted_at = now();
  return json_build_object('ok', true, 'late', v_h.due_at is not null and now() > v_h.due_at);
end;
$$;

create or replace function public.admin_grade_homework(p_sub uuid, p_grade numeric, p_feedback text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  update public.hw_submissions
     set grade = p_grade, feedback = nullif(trim(p_feedback), ''), graded_at = case when p_grade is null then null else now() end
   where id = p_sub;
end;
$$;

revoke execute on function public.submit_homework(uuid, text, text[])            from public, anon;
revoke execute on function public.admin_grade_homework(uuid, numeric, text)      from public, anon;
grant  execute on function public.submit_homework(uuid, text, text[])            to authenticated;
grant  execute on function public.admin_grade_homework(uuid, numeric, text)      to authenticated;

-- Fayllar: gizli "homework" bucket, şagird yalnız öz qovluğuna yazır
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('homework', 'homework', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "hw_files_admin" on storage.objects;
create policy "hw_files_admin" on storage.objects for all to authenticated
  using (bucket_id = 'homework' and public.is_admin()) with check (bucket_id = 'homework' and public.is_admin());

drop policy if exists "hw_files_own_insert" on storage.objects;
create policy "hw_files_own_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'homework' and split_part(name, '/', 1) = auth.uid()::text and public.is_active_user());

drop policy if exists "hw_files_own_read" on storage.objects;
create policy "hw_files_own_read" on storage.objects for select to authenticated
  using (bucket_id = 'homework' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists "hw_files_own_delete" on storage.objects;
create policy "hw_files_own_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'homework' and split_part(name, '/', 1) = auth.uid()::text);
