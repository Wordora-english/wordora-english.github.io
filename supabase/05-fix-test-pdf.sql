-- =====================================================================
--  WORDORA — düzəliş: sınaq PDF-i şagirdə "Object not found" göstərirdi
--  Səbəb: fayl icazəsi yoxlananda şagird öz cəhdini görə bilmirdi
--  (cəhdlər cədvəli yalnız admin üçün açıqdır). İndi yoxlama
--  xüsusi funksiya ilə aparılır.
--  Supabase → SQL Editor → New query → yapışdır → Run
-- =====================================================================

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
