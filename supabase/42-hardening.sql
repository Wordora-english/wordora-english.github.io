-- =====================================================================
--  WORDORA — əlavə təhlükəsizlik (2026-11-24 yoxlamasından sonra)
--  Saytdakı açıq açar (publishable key) ilə daxil olmamış adam (anon)
--  artıq heç bir cədvələ birbaşa toxuna bilməsin — hətta boş oxumaq da yox.
--  Bütün məlumat yenə də RLS qaydaları və yoxlamalı funksiyalarla qorunur;
--  bu fayl sadəcə qalan köhnə icazələri təmizləyir ("ikinci qıfıl").
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- 1) Daxil olmamış adam (anon) cədvəllərə birbaşa heç nə edə bilməz
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
-- gələcəkdə yaranacaq cədvəllərə də avtomatik icazə verilməsin
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;

-- 2) Yalnız sayta daxil olmuş istifadəçilər üçün olan köməkçi funksiyalar
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('admin_push_stats', 'chat_can', 'chat_expired_files', 'hw_visible', 'test_visible',
                         'my_class', 'is_active_user', 'video_is_live', 'variant_file', 'test_total')
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
