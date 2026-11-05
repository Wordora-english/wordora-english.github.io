-- =====================================================================
--  WORDORA — 6-cı mərhələ (2-ci hissə)
--  A) Yeni tədris ili keçidi (siniflər +1, 11-ci sinif → məzun arxivi)
--  B) Söz bazası: günün sözü, söz kartları
--  C) Reytinq
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- =====================================================================
-- A) YENİ TƏDRİS İLİ
-- =====================================================================
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check
  check (status in ('pending', 'approved', 'rejected', 'blocked', 'archived'));

-- Öncədən baxış: neçə şagird hansı sinfə keçəcək
create or replace function public.admin_year_preview()
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return (
    select coalesce(json_agg(json_build_object('from', class_name, 'n', n) order by class_name), '[]'::json)
      from (select class_name, count(*) n from public.profiles
             where role = 'student' and status in ('approved', 'pending', 'blocked')
             group by class_name) x);
end;
$$;

create or replace function public.admin_promote_year()
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_grad int; v_up int; v_year text := extract(year from now())::text;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;

  -- 11-ci sinif → məzun (arxiv; giriş bağlanır, nəticələr saxlanır)
  update public.profiles
     set status = 'archived', status_note = 'Məzun — ' || v_year, status_changed_at = now()
   where role = 'student' and class_name = '11' and status in ('approved', 'pending', 'blocked');
  get diagnostics v_grad = row_count;

  -- 1–10 → bir sinif yuxarı
  update public.profiles
     set class_name = (class_name::int + 1)::text
   where role = 'student' and class_name ~ '^([1-9]|10)$' and status <> 'archived';
  get diagnostics v_up = row_count;

  return json_build_object('promoted', v_up, 'graduated', v_grad);
end;
$$;

-- admin_set_status arxivdən qaytarmağa da icazə versin (məs. səhvən arxivlənibsə)
revoke execute on function public.admin_year_preview()  from public, anon;
revoke execute on function public.admin_promote_year()  from public, anon;
grant  execute on function public.admin_year_preview()  to authenticated;
grant  execute on function public.admin_promote_year()  to authenticated;

-- =====================================================================
-- B) SÖZ BAZASI
-- =====================================================================
create table if not exists public.words (
  id         bigint generated always as identity primary key,
  deck       text not null default 'Ümumi' check (char_length(deck) between 1 and 60),
  word       text not null check (char_length(word) between 1 and 80),
  meaning    text not null check (char_length(meaning) between 1 and 200),   -- azərbaycanca
  example    text check (char_length(example) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists words_deck_idx on public.words (deck);

alter table public.words enable row level security;
drop policy if exists "words_read" on public.words;
create policy "words_read" on public.words for select to authenticated using (public.is_admin() or public.is_active_user());
drop policy if exists "words_admin_write" on public.words;
create policy "words_admin_write" on public.words for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.words from anon;

-- =====================================================================
-- C) REYTİNQ
-- =====================================================================
insert into public.app_settings (key, value) values ('leaderboard', 'on') on conflict (key) do nothing;

create or replace function public.admin_set_leaderboard(p_on boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  insert into public.app_settings (key, value) values ('leaderboard', case when p_on then 'on' else 'off' end)
  on conflict (key) do update set value = excluded.value;
end;
$$;

-- p_kind: 'tests' (orta faiz) və ya 'live' (viktorina balı)
-- p_scope: 'class' (öz sinfim) və ya 'all'
-- p_days: son neçə gün (0 = hamısı)
-- Yalnız şagirdlərə görünən ballar sayılır (nəticəsi açılmış və ya dərhal göstərilən sınaqlar)
create or replace function public.get_leaderboard(p_kind text, p_scope text, p_days int default 30)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_me public.profiles; v_from timestamptz; v_rows json; v_on boolean;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if not found or (v_me.status <> 'approved') then raise exception 'Hesabın aktiv deyil'; end if;
  v_on := public.get_setting('leaderboard', 'on') = 'on';
  if not v_on and v_me.role <> 'admin' then return json_build_object('enabled', false); end if;
  v_from := case when coalesce(p_days, 0) > 0 then now() - make_interval(days => p_days) else '-infinity'::timestamptz end;

  if p_kind = 'live' then
    with s as (
      select p.id, p.full_name, p.class_name, sum(lp.score)::numeric as val, count(*) as n
        from public.live_players lp join public.profiles p on p.id = lp.user_id
       where lp.joined_at >= v_from and p.role = 'student' and p.status = 'approved'
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

revoke execute on function public.admin_set_leaderboard(boolean)     from public, anon;
revoke execute on function public.get_leaderboard(text, text, int)   from public, anon;
grant  execute on function public.admin_set_leaderboard(boolean)     to authenticated;
grant  execute on function public.get_leaderboard(text, text, int)   to authenticated;

-- admin_get_settings: reytinq ayarını da qaytarsın
create or replace function public.admin_get_settings()
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return json_build_object(
    'max_warnings', public.get_setting('max_warnings', '2')::int,
    'tor_block',    public.get_setting('tor_block', 'on'),
    'leaderboard',  public.get_setting('leaderboard', 'on'),
    'tor_count',    (select count(*) from public.tor_exits),
    'telegram',     exists (select 1 from vault.decrypted_secrets where name = 'telegram_bot_token')
  );
end;
$$;
