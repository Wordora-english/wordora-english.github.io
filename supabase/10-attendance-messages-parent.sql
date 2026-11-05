-- =====================================================================
--  WORDORA — 6-cı mərhələ (3-cü hissə)
--  A) Davamiyyət jurnalı
--  B) Müəllimə sual (mesajlar)
--  C) Valideyn görünüşü (kodla, girişsiz, yalnız oxumaq)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- =====================================================================
-- A) DAVAMİYYƏT
-- =====================================================================
create table if not exists public.attendance (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  att_date   date not null,
  status     text not null check (status in ('present', 'absent', 'late', 'excused')),
  note       text check (char_length(note) <= 200),
  updated_at timestamptz not null default now(),
  primary key (user_id, att_date)
);
create index if not exists attendance_date_idx on public.attendance (att_date);

alter table public.attendance enable row level security;
drop policy if exists "att_admin_all" on public.attendance;
create policy "att_admin_all" on public.attendance for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "att_own_read" on public.attendance;
create policy "att_own_read" on public.attendance for select to authenticated using (user_id = auth.uid());
revoke all on public.attendance from anon;

-- =====================================================================
-- B) MESAJLAR (hər şagirdin müəllimlə bir söhbəti var)
-- =====================================================================
create table if not exists public.messages (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references public.profiles(id) on delete cascade,   -- söhbətin sahibi (şagird)
  sender          text not null check (sender in ('student', 'teacher')),
  body            text not null check (char_length(body) between 1 and 1000),
  read_by_teacher boolean not null default false,
  read_by_student boolean not null default false,
  created_at      timestamptz not null default now()
);
create index if not exists messages_user_idx on public.messages (user_id, created_at);

alter table public.messages enable row level security;
drop policy if exists "msg_read" on public.messages;
create policy "msg_read" on public.messages for select to authenticated
  using (public.is_admin() or user_id = auth.uid());
revoke insert, update, delete on public.messages from anon, authenticated;

-- Şagird yazır (gündə ən çoxu 20 mesaj)
create or replace function public.send_message(p_body text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.profiles; v_body text := trim(p_body);
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.status <> 'approved' or v_p.role <> 'student' then raise exception 'Hesabın aktiv deyil'; end if;
  if v_body = '' or char_length(v_body) > 1000 then raise exception 'Mesaj 1–1000 simvol olmalıdır'; end if;
  if (select count(*) from public.messages where user_id = auth.uid() and sender = 'student'
        and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Bu gün çox mesaj göndərmisən. Sabah yenidən yaz.';
  end if;
  insert into public.messages (user_id, sender, body, read_by_student) values (auth.uid(), 'student', v_body, true);
  perform public.notify_telegram('💬 <b>Yeni sual</b>' || chr(10) ||
    public.tg_esc(v_p.full_name) || ' · ' || public.tg_esc(v_p.class_name) || chr(10) || public.tg_esc(left(v_body, 500)));
end;
$$;

-- Müəllim cavab verir
create or replace function public.admin_reply(p_user uuid, p_body text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_body text := trim(p_body);
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if v_body = '' or char_length(v_body) > 1000 then raise exception 'Mesaj 1–1000 simvol olmalıdır'; end if;
  insert into public.messages (user_id, sender, body, read_by_teacher) values (p_user, 'teacher', v_body, true);
  update public.messages set read_by_teacher = true where user_id = p_user and sender = 'student';
end;
$$;

-- Oxundu işarəsi
create or replace function public.mark_messages_read(p_user uuid default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if public.is_admin() and p_user is not null then
    update public.messages set read_by_teacher = true where user_id = p_user and not read_by_teacher;
  else
    update public.messages set read_by_student = true where user_id = auth.uid() and not read_by_student;
  end if;
end;
$$;

revoke execute on function public.send_message(text)             from public, anon;
revoke execute on function public.admin_reply(uuid, text)        from public, anon;
revoke execute on function public.mark_messages_read(uuid)       from public, anon;
grant  execute on function public.send_message(text)             to authenticated;
grant  execute on function public.admin_reply(uuid, text)        to authenticated;
grant  execute on function public.mark_messages_read(uuid)       to authenticated;

-- =====================================================================
-- C) VALİDEYN GÖRÜNÜŞÜ
-- =====================================================================
alter table public.profiles add column if not exists parent_code text;
create unique index if not exists profiles_parent_code_idx on public.profiles (parent_code) where parent_code is not null;

create or replace function public.gen_parent_code()
returns text language plpgsql volatile set search_path = ''
as $$
declare abc text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v text := ''; i int;
begin
  for i in 1 .. 10 loop v := v || substr(abc, 1 + floor(random() * 32)::int, 1); end loop;
  return substr(v, 1, 5) || '-' || substr(v, 6, 5);
end;
$$;

-- Şagird öz valideyn kodunu görür (yoxdursa yaradılır)
create or replace function public.get_parent_code()
returns text
language plpgsql security definer set search_path = ''
as $$
declare v text;
begin
  select parent_code into v from public.profiles where id = auth.uid() and status = 'approved';
  if not found then raise exception 'Hesabın aktiv deyil'; end if;
  if v is null then
    loop
      v := public.gen_parent_code();
      exit when not exists (select 1 from public.profiles where parent_code = v);
    end loop;
    update public.profiles set parent_code = v where id = auth.uid();
  end if;
  return v;
end;
$$;

-- Admin kodu yeniləyə bilər (köhnə kod işləməz)
create or replace function public.admin_reset_parent_code(p_user uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v text;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  loop
    v := public.gen_parent_code();
    exit when not exists (select 1 from public.profiles where parent_code = v);
  end loop;
  update public.profiles set parent_code = v where id = p_user and role = 'student';
  return v;
end;
$$;

-- Valideyn: kodla, girişsiz. Yalnız şagirdə görünən ballar qaytarılır.
create or replace function public.parent_view(p_code text)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_p public.profiles; v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if length(v_code) <> 10 then raise exception 'Kod düzgün deyil'; end if;
  select * into v_p from public.profiles
   where replace(parent_code, '-', '') = v_code and role = 'student' and status in ('approved', 'blocked');
  if not found then raise exception 'Kod tapılmadı'; end if;

  return json_build_object(
    'name', v_p.full_name,
    'class', v_p.class_name,
    'status', v_p.status,
    'warnings', v_p.warnings,
    'tests', (select coalesce(json_agg(json_build_object(
                 'title', t.title, 'date', a.submitted_at, 'score', a.score,
                 'total', public.test_total(t.questions), 'pending', a.status = 'submitted') order by a.submitted_at desc), '[]'::json)
                from public.attempts a join public.tests t on t.id = a.test_id
               where a.user_id = v_p.id and a.status <> 'in_progress'
                 and (t.results_mode = 'instant' or t.results_released)),
    'attendance', (select json_build_object(
                      'present', count(*) filter (where status = 'present'),
                      'late',    count(*) filter (where status = 'late'),
                      'absent',  count(*) filter (where status = 'absent'),
                      'excused', count(*) filter (where status = 'excused'),
                      'recent',  coalesce((select json_agg(json_build_object('date', att_date, 'status', status) order by att_date desc)
                                             from (select att_date, status from public.attendance
                                                    where user_id = v_p.id and status <> 'present'
                                                    order by att_date desc limit 10) r), '[]'::json))
                     from public.attendance where user_id = v_p.id and att_date > current_date - 90),
    'live', (select coalesce(sum(score), 0) from public.live_players where user_id = v_p.id)
  );
end;
$$;

revoke execute on function public.gen_parent_code()              from public, anon, authenticated;
revoke execute on function public.get_parent_code()              from public, anon;
revoke execute on function public.admin_reset_parent_code(uuid)  from public, anon;
grant  execute on function public.get_parent_code()              to authenticated;
grant  execute on function public.admin_reset_parent_code(uuid)  to authenticated;
grant  execute on function public.parent_view(text)              to anon, authenticated;
