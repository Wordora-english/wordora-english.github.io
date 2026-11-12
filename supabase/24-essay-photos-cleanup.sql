-- =====================================================================
--  WORDORA — A) Esse dəftərdə: şagird SINAQ ZAMANI şəklini çəkib göndərir
--               (kamera saytın içində açılır — qalereya və başqa proqram yox)
--            B) Nəticələr açılandan sonra şagird sınağı (PDF) yükləyə bilir
--            C) Sınağın faylları (PDF, dinləmə, esse şəkilləri) silinir — yer
--               tutmasın; ballar, cavablar, şərhlər QALIR
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.tests add column if not exists essay_photo         boolean not null default false;
alter table public.tests add column if not exists essay_photo_min     int     not null default 5;
alter table public.tests add column if not exists allow_download      boolean not null default false;
alter table public.tests add column if not exists auto_clean_days     int;          -- köhnə sınaqlar: avtomatik silinmir
alter table public.tests alter column auto_clean_days set default 7;               -- yeni sınaqlar: 7 gün
alter table public.tests add column if not exists results_released_at timestamptz;
alter table public.tests add column if not exists files_cleaned_at    timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tests_essay_photo_min_chk') then
    alter table public.tests add constraint tests_essay_photo_min_chk check (essay_photo_min between 1 and 30);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tests_auto_clean_days_chk') then
    alter table public.tests add constraint tests_auto_clean_days_chk check (auto_clean_days is null or auto_clean_days between 1 and 365);
  end if;
end;
$$;

-- Nəticələr nə vaxt açılıb (avtomatik silmə bu tarixdən sayılır)
create or replace function public.tests_release_stamp()
returns trigger
language plpgsql
as $$
begin
  if new.results_released and (tg_op = 'INSERT' or not old.results_released) then
    new.results_released_at := now();
  elsif not new.results_released then
    new.results_released_at := null;
  end if;
  return new;
end;
$$;
drop trigger if exists tests_release_stamp on public.tests;
create trigger tests_release_stamp before insert or update of results_released on public.tests
  for each row execute function public.tests_release_stamp();

-- =====================================================================
-- B) Sınaq faylını oxumaq: sınaq zamanı (əvvəlki kimi) + nəticələr açılandan
--    sonra, müəllim "yükləməyə icazə" veribsə (yalnız sınağı yazanlar)
-- =====================================================================
create or replace function public.can_read_test_file(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin()
  or exists (
    select 1 from public.tests t
      join public.attempts a on a.test_id = t.id
     where a.user_id = auth.uid()
       and p_name in (public.variant_file(t, a.variant, 'pdf_path'), public.variant_file(t, a.variant, 'audio_path'))
       and ((a.status = 'in_progress' and now() <= a.deadline + interval '30 seconds')
            or (a.status <> 'in_progress' and t.results_released and t.allow_download and t.files_cleaned_at is null)))
  or exists (
    select 1 from public.tests t
      join public.paper_entries p on p.test_id = t.id
     where p.user_id = auth.uid() and t.results_released and t.allow_download and t.files_cleaned_at is null
       and p_name in (public.variant_file(t, p.variant, 'pdf_path'), public.variant_file(t, p.variant, 'audio_path')));
$$;
revoke execute on function public.can_read_test_file(text) from public, anon;
grant  execute on function public.can_read_test_file(text) to authenticated;

-- =====================================================================
-- A) ESSE ŞƏKİLLƏRİ — gizli "essays" bucket
--    Yol: <sınaq id>/<şagird id>/<cəhd id>/<fayl>.jpg
--    Şagird yalnız SINAQ GEDƏRKƏN (təhvil verənə qədər) göndərə bilir —
--    təhvildən sonra şəkil göndərmək olmur (süni intellektdən köçürməsin deyə).
-- =====================================================================
create or replace function public.essay_photo_window(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.attempts a join public.tests t on t.id = a.test_id
     where a.id::text = split_part(p_name, '/', 3)
       and a.test_id::text = split_part(p_name, '/', 1)
       and split_part(p_name, '/', 2) = auth.uid()::text
       and a.user_id = auth.uid()
       and t.essay_photo and t.files_cleaned_at is null
       and a.status = 'in_progress' and now() <= a.deadline + interval '30 seconds');
$$;

create or replace function public.essay_photo_can_add(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.essay_photo_window(p_name)
     and (select count(*) from storage.objects o
           where o.bucket_id = 'essays'
             and o.name like split_part(p_name, '/', 1) || '/' || split_part(p_name, '/', 2) || '/' || split_part(p_name, '/', 3) || '/%') < 6;
$$;
revoke execute on function public.essay_photo_window(text)  from public, anon;
revoke execute on function public.essay_photo_can_add(text) from public, anon;
grant  execute on function public.essay_photo_window(text)  to authenticated;
grant  execute on function public.essay_photo_can_add(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('essays', 'essays', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "essays_insert" on storage.objects;
create policy "essays_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'essays' and public.essay_photo_can_add(name));
drop policy if exists "essays_read" on storage.objects;
create policy "essays_read" on storage.objects for select to authenticated
  using (bucket_id = 'essays' and (public.is_admin() or split_part(name, '/', 2) = auth.uid()::text));
drop policy if exists "essays_delete_own" on storage.objects;
create policy "essays_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'essays' and public.essay_photo_window(name));
drop policy if exists "essays_admin" on storage.objects;
create policy "essays_admin" on storage.objects for all to authenticated
  using (bucket_id = 'essays' and public.is_admin()) with check (bucket_id = 'essays' and public.is_admin());

-- Şagird: öz cəhdi və şəkil göndərmək olarmı (yalnız sınaq gedərkən)
create or replace function public.my_essay_upload(p_test uuid)
returns json
language sql stable security definer set search_path = ''
as $$
  select json_build_object(
    'attempt_id', a.id, 'user_id', a.user_id,
    'open', t.essay_photo and t.files_cleaned_at is null and a.status = 'in_progress' and now() <= a.deadline + interval '30 seconds',
    'cleaned', t.files_cleaned_at is not null)
    from public.attempts a join public.tests t on t.id = a.test_id
   where a.test_id = p_test and a.user_id = auth.uid();
$$;
revoke execute on function public.my_essay_upload(uuid) from public, anon;
grant  execute on function public.my_essay_upload(uuid) to authenticated;

-- =====================================================================
-- C) FAYLLARI SİLMƏK (ballar qalır)
--    Supabase faylları birbaşa SQL ilə silməyə icazə vermir — ona görə
--    admin paneli açılanda sayt özü silir (bu funksiyalar siyahını verir).
-- =====================================================================
create or replace function public.admin_test_files(p_test uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_t public.tests; v_paths text[];
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_t from public.tests where id = p_test;
  if not found then raise exception 'Sınaq tapılmadı'; end if;
  -- bu sınağın faylları (başqa sınaq — məs. kopya — istifadə etmirsə)
  select coalesce(array_agg(distinct p), '{}') into v_paths
    from (select v_t.pdf_path as p union all select v_t.audio_path
          union all select nullif(v->>'pdf_path', '') from jsonb_array_elements(coalesce(v_t.variants, '[]'::jsonb)) v
          union all select nullif(v->>'audio_path', '') from jsonb_array_elements(coalesce(v_t.variants, '[]'::jsonb)) v) x
   where p is not null
     and not exists (select 1 from public.tests o where o.id <> p_test and o.files_cleaned_at is null
                       and (o.pdf_path = x.p or o.audio_path = x.p
                            or exists (select 1 from jsonb_array_elements(coalesce(o.variants, '[]'::jsonb)) w
                                        where w->>'pdf_path' = x.p or w->>'audio_path' = x.p)));
  return json_build_object(
    'tests', v_paths,
    'essays', (select coalesce(json_agg(json_build_object('name', o.name, 'size', (o.metadata->>'size')::bigint, 'created_at', o.created_at) order by o.created_at), '[]'::json)
                 from storage.objects o where o.bucket_id = 'essays' and o.name like p_test::text || '/%'),
    'bytes', (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o
               where (o.bucket_id = 'tests' and o.name = any (v_paths)) or (o.bucket_id = 'essays' and o.name like p_test::text || '/%')),
    'cleaned_at', v_t.files_cleaned_at);
end;
$$;

create or replace function public.admin_mark_files_cleaned(p_test uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  update public.tests
     set files_cleaned_at = now(), pdf_path = null, audio_path = null,
         variants = coalesce((select jsonb_agg(v || '{"pdf_path": null, "audio_path": null}'::jsonb)
                                from jsonb_array_elements(coalesce(variants, '[]'::jsonb)) v), '[]'::jsonb)
   where id = p_test;
end;
$$;

-- Vaxtı çatmış sınaqlar (nəticələr açılandan N gün sonra, sınaq bitibsə)
create or replace function public.admin_tests_due_clean()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select t.id from public.tests t
   where public.is_admin()
     and t.files_cleaned_at is null and t.auto_clean_days is not null
     and t.results_released and t.results_released_at is not null
     and t.results_released_at + make_interval(days => t.auto_clean_days) <= now()
     and (t.ends_at is null or t.ends_at <= now());
$$;

revoke execute on function public.admin_test_files(uuid)          from public, anon;
revoke execute on function public.admin_mark_files_cleaned(uuid)  from public, anon;
revoke execute on function public.admin_tests_due_clean()         from public, anon;
grant  execute on function public.admin_test_files(uuid)          to authenticated;
grant  execute on function public.admin_mark_files_cleaned(uuid)  to authenticated;
grant  execute on function public.admin_tests_due_clean()         to authenticated;
