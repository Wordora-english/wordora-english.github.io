-- =====================================================================
--  WORDORA — 1-ci mərhələ: baza sxemi və təhlükəsizlik qaydaları
--  Supabase → SQL Editor → New query → bu faylın hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir — mövcud olanları yeniləyir.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Profillər (hər istifadəçi üçün bir sətir)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  username      text not null unique check (username ~ '^[a-z0-9._]{3,20}$'),
  full_name     text not null check (char_length(full_name) between 3 and 80),
  class_name    text not null check (char_length(class_name) between 1 and 30),
  student_code  text not null unique,           -- şəxsi gizli kod (PDF su nişanı üçün)
  role          text not null default 'student' check (role in ('student', 'admin')),
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected', 'blocked')),
  warnings      int  not null default 0 check (warnings >= 0),
  status_note   text,
  created_at    timestamptz not null default now(),
  approved_at   timestamptz,
  status_changed_at timestamptz
);

create index if not exists profiles_status_idx on public.profiles (status);
create index if not exists profiles_class_idx  on public.profiles (class_name);

alter table public.profiles enable row level security;

-- ---------------------------------------------------------------------
-- 2. Köməkçi funksiyalar (rol və status yoxlaması)
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'approved'
  );
$$;

-- Təsdiqlənmiş və bloklanmamış istifadəçi
create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and status = 'approved'
  );
$$;

create or replace function public.my_class()
returns text
language sql stable security definer set search_path = ''
as $$
  select class_name from public.profiles where id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 3. Yeni qeydiyyat → avtomatik "gözləmədə" profil
--    Rol HƏMİŞƏ 'student', status HƏMİŞƏ 'pending' olur —
--    qeydiyyat formundan gələn heç nə bunu dəyişə bilməz.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_code text;
begin
  loop
    v_code := 'WD-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.profiles where student_code = v_code);
  end loop;

  insert into public.profiles (id, username, full_name, class_name, student_code)
  values (
    new.id,
    lower(trim(new.raw_user_meta_data ->> 'username')),
    trim(new.raw_user_meta_data ->> 'full_name'),
    trim(new.raw_user_meta_data ->> 'class_name'),
    v_code
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 4. Profil qaydaları: hər kəs yalnız özünü görür, admin hamını görür.
--    Heç kim (admin də daxil) cədvəli birbaşa dəyişə bilməz —
--    dəyişikliklər yalnız aşağıdakı admin funksiyaları ilə olur.
-- ---------------------------------------------------------------------
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

revoke insert, update, delete on public.profiles from anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Admin funksiyaları
-- ---------------------------------------------------------------------
-- Statusu dəyiş: approved (təsdiqlə / blokdan çıxar), rejected, blocked
create or replace function public.admin_set_status(
  p_user   uuid,
  p_status text,
  p_note   text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Bu əməliyyat yalnız admin üçündür';
  end if;
  if p_status not in ('approved', 'rejected', 'blocked') then
    raise exception 'Yanlış status: %', p_status;
  end if;
  if p_user = auth.uid() then
    raise exception 'Öz statusunu dəyişə bilməzsən';
  end if;

  update public.profiles
     set status            = p_status,
         status_note       = p_note,
         status_changed_at = now(),
         approved_at       = case when p_status = 'approved' and approved_at is null
                                  then now() else approved_at end,
         -- blokdan çıxanda xəbərdarlıqlar sıfırlanır
         warnings          = case when p_status = 'approved' then 0 else warnings end
   where id = p_user and role = 'student';

  if not found then
    raise exception 'Şagird tapılmadı';
  end if;
end;
$$;

-- Şagirdin sinfini dəyiş (məs. yeni tədris ilində)
create or replace function public.admin_set_class(p_user uuid, p_class text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Bu əməliyyat yalnız admin üçündür';
  end if;
  update public.profiles set class_name = trim(p_class)
   where id = p_user and role = 'student';
end;
$$;

revoke execute on function public.admin_set_status(uuid, text, text) from public, anon;
revoke execute on function public.admin_set_class(uuid, text)        from public, anon;
grant  execute on function public.admin_set_status(uuid, text, text) to authenticated;
grant  execute on function public.admin_set_class(uuid, text)        to authenticated;

-- ---------------------------------------------------------------------
-- 6. Elanlar (portalda görünür)
-- ---------------------------------------------------------------------
create table if not exists public.announcements (
  id           bigint generated always as identity primary key,
  title        text not null check (char_length(title) between 1 and 150),
  body         text not null check (char_length(body) between 1 and 5000),
  target_class text,                 -- null = bütün siniflər
  created_at   timestamptz not null default now()
);

alter table public.announcements enable row level security;

drop policy if exists "ann_select" on public.announcements;
create policy "ann_select" on public.announcements
  for select to authenticated
  using (
    public.is_admin()
    or (public.is_active_user()
        and (target_class is null or target_class = public.my_class()))
  );

drop policy if exists "ann_admin_insert" on public.announcements;
create policy "ann_admin_insert" on public.announcements
  for insert to authenticated with check (public.is_admin());

drop policy if exists "ann_admin_delete" on public.announcements;
create policy "ann_admin_delete" on public.announcements
  for delete to authenticated using (public.is_admin());

revoke all on public.announcements from anon;

-- ---------------------------------------------------------------------
-- 7. Saytın "yatmaması" üçün həftəlik yoxlama (GitHub Actions çağırır)
-- ---------------------------------------------------------------------
create or replace function public.ping()
returns text
language sql stable security definer set search_path = ''
as $$
  select 'ok:' || count(*)::text from public.profiles;
$$;
grant execute on function public.ping() to anon, authenticated;

-- =====================================================================
--  İLK ADMİN: saytda öz hesabınla qeydiyyatdan keçəndən sonra aşağıdakı
--  sətirdə 'gulnar' yerinə öz istifadəçi adını yaz və yalnız onu işə sal:
--
--  update public.profiles set role = 'admin', status = 'approved',
--         approved_at = now() where username = 'gulnar';
-- =====================================================================
