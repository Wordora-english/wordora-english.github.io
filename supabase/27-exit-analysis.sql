-- =====================================================================
--  WORDORA — Sınaqdan çıxışların təhlili: təsadüf, yoxsa qəsdən?
--  Hər çıxış üçün yazılır:
--   • necə çıxıb (başqa proqram/tab, üzən pəncərə, bölünmüş ekran, tam ekrandan çıxma)
--   • neçə saniyə kənarda qalıb
--   • qayıdandan sonra 60 saniyədə neçə cavab yazıb/dəyişib
--   • şagirdin özünün dediyi səbəb (bildiriş, zəng, səhvən toxundum...)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.violations add column if not exists away_seconds  int;
alter table public.violations add column if not exists away_kind     text;
alter table public.violations add column if not exists answers_after int;
alter table public.violations add column if not exists student_reason text;

-- Qayıdanda: müddət və çıxış növü
create or replace function public.report_away(p_seconds int, p_kind text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint; v_s int := least(greatest(coalesce(p_seconds, 0), 0), 7200);
begin
  select id into v_id from public.violations
   where user_id = auth.uid() and kind = 'tab_switch' and away_seconds is null
     and created_at > now() - make_interval(secs => v_s + 60)
   order by created_at desc limit 1;
  if v_id is not null then
    update public.violations
       set away_seconds = v_s,
           away_kind = case when p_kind in ('hidden', 'focus', 'split', 'fullscreen') then p_kind else away_kind end
     where id = v_id;
  end if;
end;
$$;
-- köhnə (bir parametrli) versiya da işləsin
drop function if exists public.report_away(int);
revoke execute on function public.report_away(int, text) from public, anon;
grant  execute on function public.report_away(int, text) to authenticated;

-- Bir az sonra: şagirdin səbəbi və qayıdandan sonrakı 60 saniyədə yazdığı cavab sayı
create or replace function public.report_away_more(p_reason text default null, p_answers int default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint;
begin
  select id into v_id from public.violations
   where user_id = auth.uid() and kind = 'tab_switch' and away_seconds is not null
     and created_at > now() - interval '15 minutes'
   order by created_at desc limit 1;
  if v_id is null then return; end if;
  update public.violations
     set student_reason = coalesce(left(nullif(trim(p_reason), ''), 120), student_reason),
         answers_after  = coalesce(least(greatest(p_answers, 0), 500), answers_after)
   where id = v_id;
end;
$$;
revoke execute on function public.report_away_more(text, int) from public, anon;
grant  execute on function public.report_away_more(text, int) to authenticated;
