-- =====================================================================
--  WORDORA — Görüntülü dərs saytın öz içində (Wordora sinif otağı)
--  39-video.sql-dən SONRA işə sal.
--  * Görüntü birbaşa iştirakçılar arasında gedir (WebRTC), sayt yalnız əlaqəni qurur
--  * video_join indi dərsin adını və başlama vaxtını da qaytarır
--  * video_ice — bağlantı serverləri (lazım olsa sonradan TURN əlavə etmək üçün)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create or replace function public.video_join(p_id uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v public.video_lessons; p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found or p.status <> 'approved' then raise exception 'Hesabın aktiv deyil'; end if;
  select * into v from public.video_lessons where id = p_id;
  if not found or not (p.role = 'admin' or public.test_target_ok(v.target_classes, v.target_groups, p.id, p.class_name)) then
    raise exception 'Bu dərs sənin üçün deyil';
  end if;
  if v.ended_at is not null then raise exception 'Dərs artıq bitib'; end if;
  if not public.video_is_live(v) then raise exception 'Dərs hələ başlamayıb — başlamasına 15 dəqiqə qalmış qoşula bilərsən'; end if;

  if p.role = 'student' then
    insert into public.video_joins (lesson_id, user_id) values (v.id, p.id)
    on conflict (lesson_id, user_id) do update set last_at = now(), n = public.video_joins.n + 1;
    insert into public.attendance (user_id, att_date, status, note)
    values (p.id, (now() at time zone 'Asia/Baku')::date, 'present', 'Onlayn dərsə qoşulub')
    on conflict (user_id, att_date) do nothing;
  end if;
  return json_build_object('id', v.id, 'room', v.room, 'url', v.ext_url, 'title', v.title, 'starts_at', v.starts_at,
                           'uid', p.id, 'name', p.full_name, 'teacher', p.role = 'admin');
end;
$$;
revoke execute on function public.video_join(uuid) from public, anon;
grant  execute on function public.video_join(uuid) to authenticated;

-- Dərs hələ davam edirmi? (şagirdin səhifəsi vaxtaşırı yoxlayır)
create or replace function public.video_alive(p_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.video_lessons v where v.id = p_id and public.video_is_live(v)); $$;
revoke execute on function public.video_alive(uuid) from public, anon;
grant  execute on function public.video_alive(uuid) to authenticated;

-- Bağlantı serverləri. Standart: pulsuz STUN (əksər hallarda kifayətdir).
-- Bəzi şagirdlər qoşula bilməsə, TURN serveri belə əlavə olunur (Claude-dan soruş):
--   select vault.create_secret('[{"urls":"turn:...","username":"...","credential":"..."}]', 'video_ice');
create or replace function public.video_ice()
returns json
language sql stable security definer set search_path = ''
as $$ select (select decrypted_secret from vault.decrypted_secrets where name = 'video_ice')::json; $$;
revoke execute on function public.video_ice() from public, anon;
grant  execute on function public.video_ice() to authenticated;

notify pgrst, 'reload schema';
