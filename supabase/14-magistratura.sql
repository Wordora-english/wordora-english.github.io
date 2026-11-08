-- =====================================================================
--  WORDORA — Magistratura ayrıca bölmə
--  Məktəb şagirdləri (5–11) və magistrantlar bir-birinin materiallarını,
--  elanlarını və ev tapşırıqlarını görmür.
--  "Bütün siniflər" (heç bir sinif seçilməyib) = yalnız məktəb sinifləri.
--  Magistrantlar yalnız "Magistratura" üçün paylaşılanları görür.
--  Sınaq sistemi dəyişmir.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- Hədəf siyahısı bu sinfə uyğundurmu?
create or replace function public.target_ok(p_targets text[], p_class text)
returns boolean
language sql immutable
as $$
  select case
    when p_targets is null or cardinality(p_targets) = 0 then coalesce(p_class, '') <> 'Magistratura'
    else p_class = any (p_targets)
  end;
$$;

-- Materiallar
create or replace function public.can_view_material(p_material uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1
      from public.materials m
      join public.profiles  p on p.id = auth.uid()
     where m.id = p_material
       and p.status = 'approved'
       and m.is_published
       and (m.available_until is null or m.available_until > now())
       and public.target_ok(m.target_classes, p.class_name)
  );
$$;

-- Elanlar
drop policy if exists "ann_select" on public.announcements;
create policy "ann_select" on public.announcements
  for select to authenticated
  using (
    public.is_admin()
    or (public.is_active_user()
        and public.target_ok(case when target_class is null then null else array[target_class] end, public.my_class()))
  );

-- Ev tapşırıqları
create or replace function public.hw_visible(p_hw uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.homework h join public.profiles p on p.id = auth.uid()
     where h.id = p_hw and h.is_published and p.status = 'approved'
       and public.target_ok(h.target_classes, p.class_name));
$$;

-- Reytinq: magistrantlar yalnız bir-biri ilə, məktəblilər bir-biri ilə
create or replace function public.get_leaderboard(p_kind text, p_scope text, p_days int default 30)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_me public.profiles; v_from timestamptz; v_rows json; v_on boolean; v_mag boolean;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if not found or (v_me.status <> 'approved') then raise exception 'Hesabın aktiv deyil'; end if;
  v_on := public.get_setting('leaderboard', 'on') = 'on';
  if not v_on and v_me.role <> 'admin' then return json_build_object('enabled', false); end if;
  v_from := case when coalesce(p_days, 0) > 0 then now() - make_interval(days => p_days) else '-infinity'::timestamptz end;
  v_mag := coalesce(v_me.class_name, '') = 'Magistratura';

  if p_kind = 'live' then
    with s as (
      select p.id, p.full_name, p.class_name, sum(lp.score)::numeric as val, count(*) as n
        from public.live_players lp join public.profiles p on p.id = lp.user_id
       where lp.joined_at >= v_from and p.role = 'student' and p.status = 'approved'
         and (coalesce(p.class_name, '') = 'Magistratura') = v_mag
         and (p_scope <> 'class' or p.class_name = v_me.class_name)
       group by p.id)
    select json_agg(json_build_object('id', id, 'name', full_name, 'class', class_name, 'value', val, 'n', n, 'rank', rk) order by rk)
      into v_rows
      from (select *, rank() over (order by val desc) rk from s) r
     where rk <= 20 or id = v_me.id;
  else
    with s as (
      select p.id, p.full_name, p.class_name,
             round(avg(a.score / nullif(public.test_total(t.questions), 0) * 100), 1) as val, count(*) as n
        from public.attempts a
        join public.tests t on t.id = a.test_id
        join public.profiles p on p.id = a.user_id
       where a.status <> 'in_progress' and a.submitted_at >= v_from
         and (t.results_mode = 'instant' or t.results_released)
         and public.test_total(t.questions) > 0
         and p.role = 'student' and p.status = 'approved'
         and (coalesce(p.class_name, '') = 'Magistratura') = v_mag
         and (p_scope <> 'class' or p.class_name = v_me.class_name)
       group by p.id)
    select json_agg(json_build_object('id', id, 'name', full_name, 'class', class_name, 'value', val, 'n', n, 'rank', rk) order by rk)
      into v_rows
      from (select *, rank() over (order by val desc) rk from s) r
     where rk <= 20 or id = v_me.id;
  end if;

  return json_build_object('enabled', v_on, 'me', v_me.id, 'rows', coalesce(v_rows, '[]'::json));
end;
$$;
revoke execute on function public.get_leaderboard(text, text, int) from public, anon;
grant  execute on function public.get_leaderboard(text, text, int) to authenticated;
