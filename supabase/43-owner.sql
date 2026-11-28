-- =====================================================================
--  WORDORA — Baş admin (gizli)
--  * Baş admin istədiyi şagirdi admin edə və adminlikdən çıxara bilər
--  * Baş adminlərin siyahısı ayrıca, heç kimin oxuya bilmədiyi cədvəldədir —
--    digər adminlər kimin baş admin olduğunu görmür və onu dəyişə bilmir
--  * Adi admin başqa admini nə bloklaya, nə silə, nə də parolunu dəyişə bilər
--    (bu, əvvəlki fayllarda artıq belədir)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create table if not exists public.owners (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.owners enable row level security;   -- heç bir qayda yoxdur → saytdan heç kim oxuya/yaza bilməz
revoke all on public.owners from anon, authenticated;

-- İlk baş admin: hazırkı (ən köhnə) admin — Gülnar Salayeva
insert into public.owners (user_id)
select id from public.profiles where role = 'admin' and status = 'approved' order by created_at limit 1
on conflict do nothing;

create or replace function public.is_owner()
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.owners o join public.profiles p on p.id = o.user_id
                      where o.user_id = auth.uid() and p.role = 'admin' and p.status = 'approved'); $$;

-- Baş admin: adminlər və hesablar siyahısı
create or replace function public.owner_admins()
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'Bu əməliyyat yalnız baş admin üçündür'; end if;
  return (select coalesce(json_agg(json_build_object('id', p.id, 'full_name', p.full_name, 'username', p.username,
                                                     'class_name', p.class_name, 'owner', o.user_id is not null,
                                                     'me', p.id = auth.uid()) order by o.user_id is null, p.full_name), '[]'::json)
            from public.profiles p left join public.owners o on o.user_id = p.id
           where p.role = 'admin');
end;
$$;

-- Baş admin: şagirdi admin et / adminlikdən çıxar
create or replace function public.owner_set_admin(p_user uuid, p_admin boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.profiles;
begin
  if not public.is_owner() then raise exception 'Bu əməliyyat yalnız baş admin üçündür'; end if;
  if p_user = auth.uid() then raise exception 'Öz adminliyinizi dəyişə bilməzsiniz'; end if;
  if exists (select 1 from public.owners where user_id = p_user) then raise exception 'Baş admini dəyişmək olmaz'; end if;
  select * into v from public.profiles where id = p_user;
  if not found then raise exception 'İstifadəçi tapılmadı'; end if;

  if p_admin then
    update public.profiles set role = 'admin', status = 'approved', status_note = null, status_changed_at = now(), warnings = 0
     where id = p_user;
  else
    update public.profiles set role = 'student', status = 'approved', status_changed_at = now() where id = p_user;
    delete from auth.sessions where user_id = p_user;   -- açıq admin səhifələri bağlansın
  end if;
end;
$$;

revoke execute on function public.is_owner()                   from public, anon;
revoke execute on function public.owner_admins()               from public, anon;
revoke execute on function public.owner_set_admin(uuid, boolean) from public, anon;
grant  execute on function public.is_owner()                   to authenticated;
grant  execute on function public.owner_admins()               to authenticated;
grant  execute on function public.owner_set_admin(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
