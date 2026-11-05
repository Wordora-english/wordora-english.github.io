-- =====================================================================
--  WORDORA — 7-ci mərhələ
--  A) Bölmələr üzrə nəticə (Reading / Listening / Grammar / Essay)
--  B) Esse meyar cədvəli (rubrika) + şərh + hazır şərhlər
--  C) Yaddaş göstəricisi və köhnə ev tapşırığı fayllarının silinməsi
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
--  Bölmələr və qarışdırma ayarı tests.content-də saxlanır — ayrıca cədvəl lazım deyil.
-- =====================================================================

-- =====================================================================
-- B) ESSE: meyarlar və şərh
-- =====================================================================
alter table public.attempts add column if not exists essay_review jsonb;   -- {"c": {"Məzmun": 4, ...}, "comment": "..."}

create or replace function public.admin_save_essay(p_attempt uuid, p_points numeric, p_review jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_points is not null and p_points < 0 then raise exception 'Bal mənfi ola bilməz'; end if;
  if p_review is not null and length(p_review::text) > 4000 then raise exception 'Şərh çox uzundur'; end if;
  update public.attempts
     set essay_score  = p_points,
         essay_review = nullif(p_review, '{}'::jsonb),
         score  = coalesce(auto_score, 0) + coalesce(p_points, 0),
         status = case when p_points is null then 'submitted' else 'graded' end
   where id = p_attempt and status <> 'in_progress';
end;
$$;
revoke execute on function public.admin_save_essay(uuid, numeric, jsonb) from public, anon;
grant  execute on function public.admin_save_essay(uuid, numeric, jsonb) to authenticated;

-- Hazır şərhlər (esse və ev tapşırığı üçün) — yalnız admin
create table if not exists public.quick_comments (
  id         bigint generated always as identity primary key,
  body       text not null check (char_length(body) between 1 and 300),
  created_at timestamptz not null default now()
);
alter table public.quick_comments enable row level security;
drop policy if exists "qc_admin" on public.quick_comments;
create policy "qc_admin" on public.quick_comments for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.quick_comments from anon;

insert into public.quick_comments (body)
select x from unnest(array[
  'Çox yaxşı! Fikirlərin aydın və ardıcıldır.',
  'Past Simple formalarına diqqət et.',
  'Daha çox bağlayıcı söz işlət: however, moreover, therefore.',
  'Giriş və nəticə hissəsini ayrıca abzas kimi yaz.',
  'Söz sayı tələb olunandan azdır.',
  'Artikllara (a / an / the) diqqət et.'
]) x
where not exists (select 1 from public.quick_comments);

-- =====================================================================
-- A) Şagirdin nəticə səhifəsi: sual mətnləri, bölmələr və esse şərhi
-- =====================================================================
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
  select answers into v_key from public.test_keys where test_id = p_test;

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
                           'sections', coalesce(v_t.content->'sections', '[]'::jsonb),
                           'total', public.test_total(v_t.questions));
end;
$$;
revoke execute on function public.get_my_review(uuid) from public, anon;
grant  execute on function public.get_my_review(uuid) to authenticated;

-- =====================================================================
-- C) YADDAŞ (pulsuz plan: fayllar 1 GB, baza 500 MB)
-- =====================================================================
create or replace function public.admin_storage_usage()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v json;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select json_build_object(
    'buckets', coalesce((select json_agg(json_build_object('bucket', bucket_id, 'files', n, 'bytes', b) order by b desc)
                           from (select bucket_id, count(*) n, coalesce(sum((metadata->>'size')::bigint), 0) b
                                   from storage.objects group by bucket_id) s), '[]'::json),
    'db_bytes', pg_database_size(current_database()),
    'hw_old', (select json_agg(json_build_object('months', m, 'files', f, 'bytes', b) order by m)
                 from (select m,
                              count(o.name) f,
                              coalesce(sum((o.metadata->>'size')::bigint), 0) b
                         from unnest(array[1, 3, 6, 12]) m
                         left join public.hw_submissions s on s.submitted_at < now() - make_interval(months => m)
                         left join lateral unnest(s.files) p on true
                         left join storage.objects o on o.bucket_id = 'homework' and o.name = p
                        group by m) z)
  ) into v;
  return v;
end;
$$;

-- Köhnə ev tapşırığı fayllarının siyahısı (sayt bunları Storage-dan silir)
create or replace function public.admin_old_hw_files(p_months int)
returns text[]
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return coalesce((select array_agg(p) from public.hw_submissions s, unnest(s.files) p
                    where s.submitted_at < now() - make_interval(months => greatest(p_months, 1))), '{}');
end;
$$;

-- Silinmiş faylları cavablardan çıxar (yazılı cavab, bal və şərh qalır)
create or replace function public.admin_forget_hw_files(p_paths text[])
returns int
language plpgsql security definer set search_path = ''
as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  update public.hw_submissions
     set files = array(select f from unnest(files) f where f <> all (p_paths))
   where files && p_paths;
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.admin_storage_usage()            from public, anon;
revoke execute on function public.admin_old_hw_files(int)          from public, anon;
revoke execute on function public.admin_forget_hw_files(text[])    from public, anon;
grant  execute on function public.admin_storage_usage()            to authenticated;
grant  execute on function public.admin_old_hw_files(int)          to authenticated;
grant  execute on function public.admin_forget_hw_files(text[])    to authenticated;
