-- =====================================================================
--  WORDORA — Görüntülü dərsdə "dərsdən çıxdı" qeydi
--  Şagird dərs vaxtı başqa proqrama/sayta keçəndə neçə dəfə və nə qədər
--  kənarda olduğu yadda saxlanır (müəllim "🎥 Canlı dərs" siyahısında görür).
--  40-video-room.sql-dən SONRA işə sal.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.video_joins add column if not exists away_n   int not null default 0;
alter table public.video_joins add column if not exists away_sec int not null default 0;

create or replace function public.video_away(p_id uuid, p_sec int)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.video_joins
     set away_n = away_n + 1, away_sec = away_sec + least(greatest(coalesce(p_sec, 0), 0), 6 * 3600)
   where lesson_id = p_id and user_id = auth.uid();
end;
$$;
revoke execute on function public.video_away(uuid, int) from public, anon;
grant  execute on function public.video_away(uuid, int) to authenticated;

notify pgrst, 'reload schema';
