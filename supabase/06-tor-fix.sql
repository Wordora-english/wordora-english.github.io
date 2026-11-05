-- =====================================================================
--  WORDORA — Tor bloku: siyahını dərhal doldur və 30 dəqiqədən bir yenilə
--  Supabase → SQL Editor → New query → yapışdır → Run
--  Nəticədə "Yeniləndi: 1000+ IP" görünməlidir. 0 görünsə, 10 saniyə
--  gözlə və yalnız sonuncu sətri (select public.tor_refresh();) yenidən işə sal.
-- =====================================================================

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wordora-tor') then
    perform cron.unschedule('wordora-tor');
  end if;
  perform cron.schedule('wordora-tor', '*/30 * * * *', 'select public.tor_refresh()');
end;
$$;

select public.tor_refresh();
