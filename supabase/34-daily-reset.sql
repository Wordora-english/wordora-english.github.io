-- =====================================================================
--  WORDORA — Gündəlik məşq: müəllim şagirdin bir günlük nəticəsini silə bilir
--  (məs. sınaq üçün yazılıbsa və ya səhvən 0 bal alınıbsa). Şagird həmin gün
--  yenidən yaza bilər — yeni suallarla.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================
create or replace function public.admin_daily_reset(p_user uuid, p_day date)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  delete from public.daily_sets where user_id = p_user and day = p_day;
  delete from public.mistake_fixed where user_id = p_user and src = 'daily' and ref = p_day::text;
end;
$$;
revoke execute on function public.admin_daily_reset(uuid, date) from public, anon;
grant  execute on function public.admin_daily_reset(uuid, date) to authenticated;
