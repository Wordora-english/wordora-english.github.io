-- =====================================================================
--  WORDORA — A) Şagird öz dərs qrupuna özü qoşulur
--               (yalnız heç bir qrupda olmayan şagirdlərə təklif çıxır;
--                qrupu sonra yalnız müəllim dəyişə bilər)
--            B) Müəllim şagirdin ad-soyadını dəyişə bilir
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- A) Şagird üçün: qoşula biləcəyi qruplar (artıq qrupdadırsa — boş)
create or replace function public.my_join_options()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_p public.profiles;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.role <> 'student' or v_p.status <> 'approved' then return json_build_object('show', false); end if;
  if public.get_setting('group_join', 'on') <> 'on' then return json_build_object('show', false); end if;
  if exists (select 1 from public.study_group_members where user_id = v_p.id) then return json_build_object('show', false); end if;
  return json_build_object('show', true, 'groups', coalesce((
    select json_agg(json_build_object('id', g.id, 'schedule', g.schedule, 'name', g.name,
                                      'count', (select count(*) from public.study_group_members m where m.group_id = g.id))
                    order by g.schedule, g.sort, g.created_at)
      from public.study_groups g), '[]'::json));
end;
$$;
revoke execute on function public.my_join_options() from public, anon;
grant  execute on function public.my_join_options() to authenticated;

create or replace function public.join_study_group(p_group uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_p public.profiles; v_g public.study_groups;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.role <> 'student' or v_p.status <> 'approved' then raise exception 'Hesabın təsdiqlənməyib'; end if;
  if public.get_setting('group_join', 'on') <> 'on' then raise exception 'Qrupa qoşulma bağlıdır — müəllimə yaz'; end if;
  if exists (select 1 from public.study_group_members where user_id = v_p.id) then
    raise exception 'Sən artıq qrupdasan. Qrupu dəyişmək üçün müəllimə yaz';
  end if;
  select * into v_g from public.study_groups where id = p_group;
  if not found then raise exception 'Qrup tapılmadı'; end if;
  insert into public.study_group_members (group_id, user_id) values (v_g.id, v_p.id) on conflict do nothing;
  perform public.notify_telegram(format(E'👥 <b>Qrupa qoşuldu</b>\n%s (%s) → %s · %s',
    public.tg_esc(v_p.full_name), public.tg_esc(coalesce(v_p.class_name, '')), v_g.schedule, public.tg_esc(v_g.name)));
  return json_build_object('schedule', v_g.schedule, 'name', v_g.name);
end;
$$;
revoke execute on function public.join_study_group(uuid) from public, anon;
grant  execute on function public.join_study_group(uuid) to authenticated;

-- Admin: özü qoşulmanı aç/bağla
create or replace function public.admin_set_group_join(p_on boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  insert into public.app_settings (key, value) values ('group_join', case when p_on then 'on' else 'off' end)
  on conflict (key) do update set value = excluded.value;
end;
$$;
create or replace function public.admin_get_group_join()
returns boolean
language sql stable security definer set search_path = ''
as $$ select public.is_admin() and public.get_setting('group_join', 'on') = 'on'; $$;
revoke execute on function public.admin_set_group_join(boolean) from public, anon;
revoke execute on function public.admin_get_group_join()        from public, anon;
grant  execute on function public.admin_set_group_join(boolean) to authenticated;
grant  execute on function public.admin_get_group_join()        to authenticated;

-- B) Ad-soyadı dəyişmək
create or replace function public.admin_set_name(p_user uuid, p_name text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_name text := regexp_replace(trim(coalesce(p_name, '')), '\s+', ' ', 'g');
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if char_length(v_name) < 3 or char_length(v_name) > 60 then raise exception 'Ad-soyad 3–60 hərf olmalıdır'; end if;
  update public.profiles set full_name = v_name where id = p_user and role = 'student';
  if not found then raise exception 'Şagird tapılmadı'; end if;
end;
$$;
revoke execute on function public.admin_set_name(uuid, text) from public, anon;
grant  execute on function public.admin_set_name(uuid, text) to authenticated;

-- C) Avtomatik fayl silmə yalnız BAĞLANMIŞ sınaqlarda (bitmə vaxtı keçib və ya gizlədilib)
create or replace function public.admin_tests_due_clean()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select t.id from public.tests t
   where public.is_admin()
     and t.files_cleaned_at is null and t.auto_clean_days is not null
     and t.results_released and t.results_released_at is not null
     and t.results_released_at + make_interval(days => t.auto_clean_days) <= now()
     and (not t.is_published or (t.ends_at is not null and t.ends_at <= now()))
     and not exists (select 1 from public.attempts a where a.test_id = t.id and a.status = 'in_progress');
$$;
revoke execute on function public.admin_tests_due_clean() from public, anon;
grant  execute on function public.admin_tests_due_clean() to authenticated;
