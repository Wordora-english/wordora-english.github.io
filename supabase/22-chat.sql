-- =====================================================================
--  WORDORA — Chat
--  Otaqlar: "Ümumi chat" (məktəb şagirdləri), "Magistratura chatı",
--  və hər dərs qrupunun öz chatı (yalnız qrupun şagirdləri + müəllim).
--  Mesajlar, şəkillər və PDF-lər 40 dəqiqədən sonra hamı üçün silinir.
--  Təhlükəsizlik üçün yalnız MÜƏLLİM 7 gün ərzində mətnlərin arxivini görür
--  (şikayət, təhqir və s. olanda yoxlamaq üçün); fayllar arxivlənmir.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- Otaq adı: 'school' | 'mag' | 'g-<qrup id>'
create or replace function public.chat_can(p_room text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or (
    public.get_setting('chat', 'on') = 'on'
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.status = 'approved' and p.role = 'student'
         and (
           (p_room = 'school' and coalesce(p.class_name, '') <> 'Magistratura')
           or (p_room = 'mag' and p.class_name = 'Magistratura')
           or (p_room like 'g-%' and exists (
                 select 1 from public.study_group_members m
                  where m.user_id = p.id and m.group_id::text = substr(p_room, 3)))
         )));
$$;

create table if not exists public.chat_mutes (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  until   timestamptz not null,
  reason  text check (char_length(reason) <= 200)
);
alter table public.chat_mutes enable row level security;
drop policy if exists "cmute_select" on public.chat_mutes;
create policy "cmute_select" on public.chat_mutes for select to authenticated using (public.is_admin() or user_id = auth.uid());
drop policy if exists "cmute_admin" on public.chat_mutes;
create policy "cmute_admin" on public.chat_mutes for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.chat_mutes from anon;

create table if not exists public.chat_messages (
  id         bigint generated always as identity primary key,
  room       text not null check (room ~ '^(school|mag|g-[0-9a-f-]{36})$'),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  body       text check (char_length(body) <= 1000),
  file_path  text check (char_length(file_path) <= 300),
  file_name  text check (char_length(file_name) <= 120),
  file_type  text check (file_type in ('image', 'pdf')),
  created_at timestamptz not null default now(),
  check (coalesce(trim(body), '') <> '' or file_path is not null)
);
create index if not exists chat_messages_room_idx on public.chat_messages (room, id);
create index if not exists chat_messages_created_idx on public.chat_messages (created_at);

alter table public.chat_messages enable row level security;
drop policy if exists "chat_select" on public.chat_messages;
create policy "chat_select" on public.chat_messages for select to authenticated
  using (public.chat_can(room) and created_at > now() - interval '40 minutes');
drop policy if exists "chat_insert" on public.chat_messages;
create policy "chat_insert" on public.chat_messages for insert to authenticated
  with check (
    user_id = auth.uid() and public.chat_can(room)
    and not exists (select 1 from public.chat_mutes m where m.user_id = auth.uid() and m.until > now())
    and (file_path is null or file_path like room || '/' || auth.uid()::text || '/%')
  );
drop policy if exists "chat_admin_delete" on public.chat_messages;
create policy "chat_admin_delete" on public.chat_messages for delete to authenticated using (public.is_admin() or user_id = auth.uid());
revoke update on public.chat_messages from anon, authenticated;
revoke all on public.chat_messages from anon;

-- Spam qarşısı: 10 saniyədə ən çox 5 mesaj
create or replace function public.chat_rate_limit()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() and (select count(*) from public.chat_messages
       where user_id = new.user_id and created_at > now() - interval '10 seconds') >= 5 then
    raise exception 'Çox sürətli yazırsan — bir az gözlə';
  end if;
  return new;
end;
$$;
drop trigger if exists chat_rate_limit on public.chat_messages;
create trigger chat_rate_limit before insert on public.chat_messages for each row execute function public.chat_rate_limit();

-- Müəllim üçün 7 günlük mətn arxivi (şagirdlər görmür)
create table if not exists public.chat_log (
  id         bigint primary key,
  room       text not null,
  user_id    uuid,
  user_name  text,
  body       text,
  file_name  text,
  created_at timestamptz not null
);
create index if not exists chat_log_created_idx on public.chat_log (created_at desc);
alter table public.chat_log enable row level security;
drop policy if exists "chatlog_admin" on public.chat_log;
create policy "chatlog_admin" on public.chat_log for select to authenticated using (public.is_admin());
revoke all on public.chat_log from anon;

create or replace function public.chat_to_log()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.chat_log (id, room, user_id, user_name, body, file_name, created_at)
  values (new.id, new.room, new.user_id, (select full_name from public.profiles where id = new.user_id), new.body, new.file_name, new.created_at)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists chat_to_log on public.chat_messages;
create trigger chat_to_log after insert on public.chat_messages for each row execute function public.chat_to_log();

-- Ad və sinif (chatda göstərmək üçün) — yalnız eyni otaqda olanlar
create or replace function public.chat_people(p_room text)
returns table (id uuid, full_name text, class_name text, is_teacher boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.full_name, p.class_name, p.role = 'admin'
    from public.profiles p
   where public.chat_can(p_room)
     and p.id in (select user_id from public.chat_messages where room = p_room and created_at > now() - interval '40 minutes');
$$;
revoke execute on function public.chat_people(text) from public, anon;
grant  execute on function public.chat_people(text) to authenticated;

-- Şagirdin görə bildiyi otaqlar
create or replace function public.chat_my_rooms()
returns table (room text, title text, subtitle text)
language plpgsql stable security definer set search_path = ''
as $$
declare v_p public.profiles;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found then return; end if;
  if v_p.role = 'admin' then
    return query
      select 'school'::text, 'Ümumi chat'::text, 'Bütün məktəb şagirdləri'::text
      union all select 'mag', 'Magistratura chatı', 'Bütün magistrantlar'
      union all (select 'g-' || g.id::text, g.name, g.schedule from public.study_groups g order by g.schedule, g.sort, g.created_at);
    return;
  end if;
  if public.get_setting('chat', 'on') <> 'on' or v_p.status <> 'approved' then return; end if;
  if coalesce(v_p.class_name, '') = 'Magistratura' then
    return query select 'mag'::text, 'Magistratura chatı'::text, 'Bütün magistrantlar'::text;
  else
    return query select 'school'::text, 'Ümumi chat'::text, 'Bütün şagirdlər'::text;
  end if;
  return query
    select 'g-' || g.id::text, g.name, g.schedule
      from public.study_group_members m join public.study_groups g on g.id = m.group_id
     where m.user_id = v_p.id order by g.schedule, g.sort;
end;
$$;
revoke execute on function public.chat_my_rooms() from public, anon;
grant  execute on function public.chat_my_rooms() to authenticated;

-- Admin: chatı aç/bağla, şagirdi susdur
create or replace function public.admin_set_chat(p_on boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  insert into public.app_settings (key, value) values ('chat', case when p_on then 'on' else 'off' end)
  on conflict (key) do update set value = excluded.value;
end;
$$;
revoke execute on function public.admin_set_chat(boolean) from public, anon;
grant  execute on function public.admin_set_chat(boolean) to authenticated;

-- =====================================================================
--  Fayllar: gizli "chat" bucket (şəkil 3 MB-a qədər — sayt özü kiçildir; PDF 10 MB)
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat_files_insert" on storage.objects;
create policy "chat_files_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat' and split_part(name, '/', 2) = auth.uid()::text and public.chat_can(split_part(name, '/', 1))
              and not exists (select 1 from public.chat_mutes m where m.user_id = auth.uid() and m.until > now()));
drop policy if exists "chat_files_read" on storage.objects;
create policy "chat_files_read" on storage.objects for select to authenticated
  using (bucket_id = 'chat' and public.chat_can(split_part(name, '/', 1)) and created_at > now() - interval '40 minutes');
drop policy if exists "chat_files_admin" on storage.objects;
create policy "chat_files_admin" on storage.objects for all to authenticated
  using (bucket_id = 'chat' and public.is_admin()) with check (bucket_id = 'chat' and public.is_admin());
-- Vaxtı keçmiş faylları hər kəs silə bilər (sayt açılanda avtomatik təmizlənir)
drop policy if exists "chat_files_expired_delete" on storage.objects;
create policy "chat_files_expired_delete" on storage.objects for delete to anon, authenticated
  using (bucket_id = 'chat' and created_at < now() - interval '45 minutes');

-- Silinməli faylların siyahısı (yalnız ad — məzmun yox)
create or replace function public.chat_expired_files()
returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(name), '{}') from (
    select name from storage.objects where bucket_id = 'chat' and created_at < now() - interval '45 minutes' limit 500) x;
$$;
revoke execute on function public.chat_expired_files() from public;
grant  execute on function public.chat_expired_files() to anon, authenticated;

-- Hər 5 dəqiqədən bir: 40 dəqiqədən köhnə mesajlar silinir; arxiv 7 gün saxlanır
do $$
begin
  if exists (select 1 from cron.job where jobname = 'wordora-chat-cleanup') then
    perform cron.unschedule('wordora-chat-cleanup');
  end if;
  perform cron.schedule('wordora-chat-cleanup', '*/5 * * * *',
    $c$delete from public.chat_messages where created_at < now() - interval '40 minutes';
       delete from public.chat_log where created_at < now() - interval '7 days';
       delete from public.chat_mutes where until < now();$c$);
end;
$$;

-- Canlı yenilənmə (Realtime)
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages') then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end;
$$;
