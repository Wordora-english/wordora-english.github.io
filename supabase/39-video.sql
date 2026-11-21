-- =====================================================================
--  WORDORA — Görüntülü canlı dərs (Jitsi Meet və ya öz Zoom/Meet linkin)
--  * Müəllim sinif/qrup seçib dərsi başladır və ya vaxtını planlaşdırır
--  * Həmin uşaqlara telefon bildirişi gedir, portalda "Dərsə qoşul" görünür
--  * Qoşulan uşaq həmin gün avtomatik "iştirak etdi" kimi davamiyyətə düşür
--    (müəllim artıq qeyd edibsə, onun qeydinə toxunulmur)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create table if not exists public.video_lessons (
  id             uuid primary key default gen_random_uuid(),
  title          text not null check (char_length(title) between 1 and 100),
  room           text not null unique,
  ext_url        text check (ext_url is null or (ext_url ~ '^https://' and char_length(ext_url) <= 500)),
  target_classes text[],
  target_groups  uuid[],
  starts_at      timestamptz not null default now(),
  ended_at       timestamptz,
  notified       boolean not null default false,
  created_at     timestamptz not null default now()
);
create index if not exists video_lessons_start_idx on public.video_lessons (starts_at desc);

create table if not exists public.video_joins (
  lesson_id uuid not null references public.video_lessons(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  first_at  timestamptz not null default now(),
  last_at   timestamptz not null default now(),
  n         int not null default 1,
  primary key (lesson_id, user_id)
);

alter table public.video_lessons enable row level security;
alter table public.video_joins   enable row level security;
drop policy if exists "vl_admin" on public.video_lessons;
create policy "vl_admin" on public.video_lessons for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "vj_admin" on public.video_joins;
create policy "vj_admin" on public.video_joins for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.video_lessons, public.video_joins from anon;

-- Dərs "canlıdır": başlamasına 15 dəqiqə qalıb və ya başlayıb, bitməyib, 4 saatdan köhnə deyil
create or replace function public.video_is_live(v public.video_lessons)
returns boolean language sql stable set search_path = ''
as $$ select v.ended_at is null and v.starts_at <= now() + interval '15 minutes' and v.starts_at > now() - interval '4 hours'; $$;

-- Bildirişi növbəyə yaz
create or replace function public.video_notify(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.video_lessons;
begin
  select * into v from public.video_lessons where id = p_id;
  if not found or v.notified then return; end if;
  if to_regclass('public.push_queue') is not null then
    insert into public.push_queue (kind, mode, title, body, url, classes, groups)
    values ('video', 'test', '🎥 Canlı dərs başlayır: ' || left(v.title, 70),
            'Dərsə qoşulmaq üçün toxun', 'portal.html#video', v.target_classes, v.target_groups);
  end if;
  update public.video_lessons set notified = true where id = p_id;
end;
$$;
revoke execute on function public.video_notify(uuid) from public, anon, authenticated;

-- Müəllim: dərs yarat (p_starts_at boşdursa — indi)
create or replace function public.admin_video_start(p_title text, p_classes text[], p_groups uuid[],
                                                    p_starts_at timestamptz default null, p_url text default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_title text := trim(coalesce(p_title, '')); v_url text := nullif(trim(coalesce(p_url, '')), '');
begin
  if not public.is_admin() then raise exception 'İcazə yoxdur'; end if;
  if v_title = '' then v_title := 'İngilis dili dərsi'; end if;
  if v_url is not null and v_url !~ '^https://' then raise exception 'Link https:// ilə başlamalıdır'; end if;
  insert into public.video_lessons (title, room, ext_url, target_classes, target_groups, starts_at)
  values (left(v_title, 100), 'Wordora-' || left(replace(gen_random_uuid()::text, '-', ''), 20), v_url,
          nullif(p_classes, '{}'), nullif(p_groups, '{}'), coalesce(p_starts_at, now()))
  returning id into v_id;
  if coalesce(p_starts_at, now()) <= now() + interval '15 minutes' then perform public.video_notify(v_id); end if;
  return v_id;
end;
$$;

create or replace function public.admin_video_end(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'İcazə yoxdur'; end if;
  update public.video_lessons set ended_at = now() where id = p_id and ended_at is null;
end;
$$;

-- Şagird: mənə aid canlı və planlaşdırılmış dərslər (otaq adı burada verilmir)
create or replace function public.my_video_lessons()
returns json
language sql stable security definer set search_path = ''
as $$
  select coalesce(json_agg(json_build_object('id', v.id, 'title', v.title, 'starts_at', v.starts_at,
                                             'live', public.video_is_live(v)) order by v.starts_at), '[]'::json)
    from public.video_lessons v join public.profiles p on p.id = auth.uid()
   where p.status = 'approved' and v.ended_at is null
     and v.starts_at > now() - interval '4 hours' and v.starts_at < now() + interval '7 days'
     and (p.role = 'admin' or public.test_target_ok(v.target_classes, v.target_groups, p.id, p.class_name));
$$;

-- Şagird: dərsə qoşul — iştirak yazılır, otağın linki qaytarılır
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
  return json_build_object('room', v.room, 'url', v.ext_url, 'name', p.full_name, 'teacher', p.role = 'admin');
end;
$$;

revoke execute on function public.admin_video_start(text, text[], uuid[], timestamptz, text) from public, anon;
revoke execute on function public.admin_video_end(uuid)    from public, anon;
revoke execute on function public.my_video_lessons()       from public, anon;
revoke execute on function public.video_join(uuid)         from public, anon;
grant  execute on function public.admin_video_start(text, text[], uuid[], timestamptz, text) to authenticated;
grant  execute on function public.admin_video_end(uuid)    to authenticated;
grant  execute on function public.my_video_lessons()       to authenticated;
grant  execute on function public.video_join(uuid)         to authenticated;

-- Planlaşdırılmış dərslər: başlamasına 15 dəqiqə qalanda bildiriş göndərilsin
-- (push_pending hər 5 dəqiqədən bir işləyir — onu yeniləyirik, köhnə hissəsi eynidir)
create or replace function public.push_pending(p_secret text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_users uuid[]; v_id uuid;
begin
  if not public.push_secret_ok(p_secret) then raise exception 'İcazə yoxdur'; end if;

  -- Canlı dərs xatırlatması
  for v_id in select id from public.video_lessons
               where not notified and ended_at is null
                 and starts_at <= now() + interval '15 minutes' and starts_at > now() - interval '1 hour' loop
    perform public.video_notify(v_id);
  end loop;

  -- Axşam 19:00-dan sonra: bugünkü məşqi etməyənlərə xatırlatma (gündə bir dəfə)
  if extract(hour from now() at time zone 'Asia/Baku') >= 19
     and not exists (select 1 from public.push_queue where kind = 'daily' and (created_at at time zone 'Asia/Baku')::date = public.baku_today()) then
    select coalesce(array_agg(distinct s.user_id), '{}') into v_users
      from public.push_subs s join public.profiles p on p.id = s.user_id and p.status = 'approved'
     where not exists (select 1 from public.daily_sets d where d.user_id = s.user_id and d.day = public.baku_today() and d.done_at is not null);
    insert into public.push_queue (kind, mode, title, body, url, users)
    values ('daily', 'users', '🔥 Gündəlik məşqi unutma!', 'Bugünkü suallar səni gözləyir — seriyanı itirmə', 'practice.html', v_users);
  end if;

  -- 2 gündən köhnə göndərilməmişləri at
  update public.push_queue set sent_at = now(), sent_n = 0 where sent_at is null and created_at < now() - interval '2 days';

  return json_build_object(
    'vapid', (select json_build_object('public', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'),
                                       'private', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private'))
               where exists (select 1 from vault.secrets where name = 'vapid_public')),
    'items', (select coalesce(json_agg(json_build_object('id', q.id, 'title', q.title, 'body', q.body, 'url', q.url, 'tag', q.kind || q.id,
               'subs', (select coalesce(json_agg(json_build_object('id', s.id, 'endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)), '[]'::json)
                          from public.push_subs s join public.profiles p on p.id = s.user_id
                         where p.status = 'approved' and p.role = 'student'
                           and case q.mode
                                 when 'users' then s.user_id = any (coalesce(q.users, '{}'))
                                 when 'test'  then public.test_target_ok(q.classes, q.groups, p.id, p.class_name)
                                 else public.target_ok(q.classes, p.class_name) end)) order by q.id), '[]'::json)
                from (select * from public.push_queue where sent_at is null order by id limit 20) q));
end;
$$;

-- Ehtiyat nüsxəyə görüntülü dərslər də daxil olsun
do $$
declare v_src text;
begin
  select pg_get_functiondef('public.backup_bundle(text)'::regprocedure) into v_src;
  if v_src is not null and v_src not like '%video_lessons%' then
    v_src := replace(v_src, '''study_groups'', ''study_group_members''', '''study_groups'', ''study_group_members'', ''video_lessons'', ''video_joins''');
    execute v_src;
  end if;
exception when others then raise notice 'backup_bundle yenilənmədi: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
