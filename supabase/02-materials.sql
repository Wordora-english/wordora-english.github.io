-- =====================================================================
--  WORDORA — 2-ci mərhələ: materiallar (su nişanlı PDF-lər)
--  Supabase → SQL Editor → New query → bu faylın hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Materiallar
-- ---------------------------------------------------------------------
create table if not exists public.materials (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(title) between 1 and 150),
  description     text check (char_length(description) <= 1000),
  category        text not null default 'Digər' check (char_length(category) between 1 and 60),
  file_path       text not null unique,          -- gizli bucket-dəki fayl adı
  file_size       bigint,
  target_classes  text[],                        -- boş / null = bütün siniflər
  is_published    boolean not null default true,
  available_until timestamptz,                   -- null = müddətsiz
  allow_download  boolean not null default true, -- şagird su nişanlı PDF yükləyə bilər
  created_at      timestamptz not null default now()
);

-- Fayl əvvəllər işə salınıbsa, yeni sütunu əlavə et
alter table public.materials add column if not exists allow_download boolean not null default true;

alter table public.materials enable row level security;

-- Bu şagird bu materialı görə bilərmi?
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
       and (m.target_classes is null
            or cardinality(m.target_classes) = 0
            or p.class_name = any (m.target_classes))
  );
$$;

drop policy if exists "materials_select" on public.materials;
create policy "materials_select" on public.materials
  for select to authenticated
  using (public.can_view_material(id));

drop policy if exists "materials_admin_insert" on public.materials;
create policy "materials_admin_insert" on public.materials
  for insert to authenticated with check (public.is_admin());

drop policy if exists "materials_admin_update" on public.materials;
create policy "materials_admin_update" on public.materials
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "materials_admin_delete" on public.materials;
create policy "materials_admin_delete" on public.materials
  for delete to authenticated using (public.is_admin());

revoke all on public.materials from anon;

-- ---------------------------------------------------------------------
-- 2. Kim nə vaxt baxıb
-- ---------------------------------------------------------------------
create table if not exists public.material_views (
  id          bigint generated always as identity primary key,
  material_id uuid not null references public.materials(id) on delete cascade,
  user_id     uuid not null references public.profiles(id)  on delete cascade,
  kind        text not null default 'view' check (kind in ('view', 'download')),
  viewed_at   timestamptz not null default now()
);

alter table public.material_views
  add column if not exists kind text not null default 'view' check (kind in ('view', 'download'));

create index if not exists material_views_material_idx on public.material_views (material_id, viewed_at desc);

alter table public.material_views enable row level security;

drop policy if exists "views_admin_select" on public.material_views;
create policy "views_admin_select" on public.material_views
  for select to authenticated using (public.is_admin());

drop policy if exists "views_admin_delete" on public.material_views;
create policy "views_admin_delete" on public.material_views
  for delete to authenticated using (public.is_admin());

revoke insert, update on public.material_views from anon, authenticated;

-- Material açılanda / yüklənəndə çağırılır: baxışı və ya yükləməni qeyd
-- edir və su nişanı məlumatını serverdən qaytarır (ad, şəxsi kod, vaxt).
drop function if exists public.open_material(uuid);
drop function if exists public.open_material(uuid, text);
create function public.open_material(p_material uuid, p_kind text default 'view')
returns table (
  title          text,
  file_path      text,
  allow_download boolean,
  full_name      text,
  username       text,
  class_name     text,
  student_code   text,
  opened_at      timestamptz
)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_kind not in ('view', 'download') then
    raise exception 'Yanlış əməliyyat';
  end if;
  if not public.can_view_material(p_material) then
    raise exception 'Bu materiala giriş icazən yoxdur';
  end if;
  if p_kind = 'download' and not public.is_admin() and not exists (
       select 1 from public.materials m where m.id = p_material and m.allow_download) then
    raise exception 'Bu materialı yükləmək olmaz, yalnız baxmaq olar';
  end if;

  insert into public.material_views (material_id, user_id, kind)
  values (p_material, auth.uid(), p_kind);

  return query
    select m.title, m.file_path, m.allow_download,
           p.full_name, p.username, p.class_name, p.student_code, now()
      from public.materials m, public.profiles p
     where m.id = p_material and p.id = auth.uid();
end;
$$;

revoke execute on function public.open_material(uuid, text) from public, anon;
revoke execute on function public.can_view_material(uuid)   from public, anon;
grant  execute on function public.open_material(uuid, text) to authenticated;
grant  execute on function public.can_view_material(uuid)   to authenticated;

-- ---------------------------------------------------------------------
-- 3. Gizli fayl anbarı (bucket) — yalnız PDF, maksimum 50 MB
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('materials', 'materials', false, 52428800, array['application/pdf'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "materials_files_admin_all" on storage.objects;
create policy "materials_files_admin_all" on storage.objects
  for all to authenticated
  using (bucket_id = 'materials' and public.is_admin())
  with check (bucket_id = 'materials' and public.is_admin());

-- Şagird faylı yalnız icazəsi olan material üçün oxuya bilər
drop policy if exists "materials_files_student_read" on storage.objects;
create policy "materials_files_student_read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'materials'
    and exists (
      select 1 from public.materials m
       where m.file_path = storage.objects.name
         and public.can_view_material(m.id)
    )
  );
