-- =====================================================================
--  WORDORA — Davamiyyət yazılandan sonra Telegram-a qısa xülasə
--  "Saat 15:00 (2-ci və 4-cü gün) — gəlməyənlər: ..."
--  + şagird portalda öz dərs qrupunu görür
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create or replace function public.tg_esc(p text)
returns text
language sql immutable
as $$ select replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'); $$;

create or replace function public.admin_attendance_notify(p_title text, p_date date, p_users uuid[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_total int; v_present int; v_absent text; v_late text; v_exc text; v_msg text;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if cardinality(coalesce(p_users, '{}')) = 0 then return; end if;

  select count(*),
         count(*) filter (where a.status in ('present', 'late')),
         string_agg(public.tg_esc(p.full_name), ', ' order by p.full_name) filter (where a.status = 'absent'),
         string_agg(public.tg_esc(p.full_name), ', ' order by p.full_name) filter (where a.status = 'late'),
         string_agg(public.tg_esc(p.full_name), ', ' order by p.full_name) filter (where a.status = 'excused')
    into v_total, v_present, v_absent, v_late, v_exc
    from public.attendance a join public.profiles p on p.id = a.user_id
   where a.att_date = p_date and a.user_id = any (p_users);
  if v_total = 0 then return; end if;

  v_msg := format(E'✅ <b>Davamiyyət — %s</b>\n📅 %s · gəlib: <b>%s / %s</b>',
                  public.tg_esc(left(p_title, 120)), to_char(p_date, 'DD.MM.YYYY'), v_present, v_total);
  if v_absent is not null then v_msg := v_msg || E'\n✕ <b>Gəlməyənlər:</b> ' || v_absent; end if;
  if v_late   is not null then v_msg := v_msg || E'\n⏰ Gecikənlər: ' || v_late; end if;
  if v_exc    is not null then v_msg := v_msg || E'\n📄 Üzrlü: ' || v_exc; end if;
  if v_absent is null and v_late is null and v_exc is null then v_msg := v_msg || E'\n👏 Hamı gəlib!'; end if;
  perform public.notify_telegram(left(v_msg, 3900));
end;
$$;
revoke execute on function public.admin_attendance_notify(text, date, uuid[]) from public, anon;
grant  execute on function public.admin_attendance_notify(text, date, uuid[]) to authenticated;

-- =====================================================================
--  Şagird portalda öz dərs qrupunu görsün
-- =====================================================================
create or replace function public.get_my_groups()
returns table (schedule text, name text)
language sql stable security definer set search_path = ''
as $$
  select g.schedule, g.name
    from public.study_group_members m join public.study_groups g on g.id = m.group_id
   where m.user_id = auth.uid()
   order by g.schedule, g.sort, g.created_at;
$$;
revoke execute on function public.get_my_groups() from public, anon;
grant  execute on function public.get_my_groups() to authenticated;
