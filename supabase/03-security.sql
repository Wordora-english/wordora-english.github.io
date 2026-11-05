-- =====================================================================
--  WORDORA — 3-cü mərhələ: qoruma sistemi
--  • Pozuntular (F12, PrintScreen, başqa tab, ikinci cihaz)
--  • 2 xəbərdarlıq → avtomatik blok (limit ayarlarda dəyişir)
--  • Telegram bildirişləri (yeni qeydiyyat, pozuntu, blok)
--  • Tor Browser bloku (Tor çıxış IP siyahısı 3 saatdan bir yenilənir)
--  • Bir hesab = eyni anda bir cihaz
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create extension if not exists pg_net  with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------------
-- 1. Ayarlar
-- ---------------------------------------------------------------------
create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);
alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon, authenticated;

insert into public.app_settings (key, value) values
  ('max_warnings', '2'),
  ('tor_block',    'on')
on conflict (key) do nothing;

create or replace function public.get_setting(p_key text, p_default text default null)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce((select value from public.app_settings where key = p_key), p_default);
$$;
revoke execute on function public.get_setting(text, text) from public, anon, authenticated;

-- Admin üçün ayarları oxu / dəyiş
create or replace function public.admin_get_settings()
returns json
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return json_build_object(
    'max_warnings', public.get_setting('max_warnings', '2')::int,
    'tor_block',    public.get_setting('tor_block', 'on'),
    'tor_count',    (select count(*) from public.tor_exits),
    'telegram',     exists (select 1 from vault.decrypted_secrets where name = 'telegram_bot_token')
  );
end;
$$;

create or replace function public.admin_set_setting(p_key text, p_value text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_key = 'max_warnings' and (p_value !~ '^[0-9]$' or p_value::int < 0) then
    raise exception 'Xəbərdarlıq limiti 0–9 arası olmalıdır';
  elsif p_key = 'tor_block' and p_value not in ('on', 'off') then
    raise exception 'Yanlış dəyər';
  elsif p_key not in ('max_warnings', 'tor_block') then
    raise exception 'Belə ayar yoxdur';
  end if;
  insert into public.app_settings (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Telegram bildirişləri (token Vault-da gizli saxlanır, kodda yoxdur)
-- ---------------------------------------------------------------------
create or replace function public.notify_telegram(p_text text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_token text;
  v_chat  text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_bot_token' limit 1;
  select decrypted_secret into v_chat  from vault.decrypted_secrets where name = 'telegram_chat_id'   limit 1;
  if v_token is null or v_chat is null then return; end if;
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    body    := jsonb_build_object('chat_id', v_chat, 'text', p_text, 'parse_mode', 'HTML',
                                  'disable_web_page_preview', true),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
exception when others then
  -- bildiriş alınmasa da sayt işləməyə davam edir
  return;
end;
$$;
revoke execute on function public.notify_telegram(text) from public, anon, authenticated;

-- Telegram-ı qurmaq üçün (yalnız SQL Editor-dan): select public.set_telegram('TOKEN', 'CHAT_ID');
create or replace function public.set_telegram(p_token text, p_chat text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid;
begin
  select id into v_id from vault.secrets where name = 'telegram_bot_token';
  if v_id is null then perform vault.create_secret(p_token, 'telegram_bot_token');
  else perform vault.update_secret(v_id, p_token); end if;

  select id into v_id from vault.secrets where name = 'telegram_chat_id';
  if v_id is null then perform vault.create_secret(p_chat, 'telegram_chat_id');
  else perform vault.update_secret(v_id, p_chat); end if;

  perform public.notify_telegram('✅ <b>Wordora</b> bildirişləri qoşuldu. Yeni qeydiyyatlar və pozuntular buraya gələcək.');
  return 'Telegram qoşuldu — telefonuna test mesajı getdi';
end;
$$;
revoke execute on function public.set_telegram(text, text) from public, anon, authenticated;

-- HTML üçün mətni təmizlə
create or replace function public.tg_esc(p text)
returns text language sql immutable set search_path = ''
as $$ select replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'); $$;

-- Yeni qeydiyyat → Telegram
create or replace function public.on_profile_created()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.role = 'student' then
    perform public.notify_telegram(
      '🆕 <b>Yeni qeydiyyat</b>' || chr(10) ||
      public.tg_esc(new.full_name) || ' · ' || public.tg_esc(new.class_name) || chr(10) ||
      '@' || public.tg_esc(new.username) || ' · ' || new.student_code || chr(10) ||
      'Admin paneldə təsdiqlə və ya rədd et.');
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created
  after insert on public.profiles
  for each row execute function public.on_profile_created();

-- ---------------------------------------------------------------------
-- 3. IP və Tor
-- ---------------------------------------------------------------------
create table if not exists public.tor_exits (
  ip         inet primary key,
  updated_at timestamptz not null default now()
);
alter table public.tor_exits enable row level security;
revoke all on public.tor_exits from anon, authenticated;

create or replace function public.client_ip()
returns text
language plpgsql stable set search_path = ''
as $$
declare v text;
begin
  v := current_setting('request.headers', true)::json ->> 'x-forwarded-for';
  return nullif(trim(split_part(coalesce(v, ''), ',', 1)), '');
exception when others then
  return null;
end;
$$;

create or replace function public.is_tor()
returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare v_ip text := public.client_ip();
begin
  if v_ip is null or public.get_setting('tor_block', 'on') <> 'on' then return false; end if;
  return exists (select 1 from public.tor_exits where ip = v_ip::inet);
exception when others then
  return false;
end;
$$;

-- Hər API sorğusundan əvvəl işləyir: Tor-dan gələni dərhal dayandırır
create or replace function public.check_request()
returns void
language plpgsql stable security definer set search_path = ''
as $$
declare v_tor boolean := false;
begin
  begin
    v_tor := public.is_tor();
  exception when others then
    v_tor := false;
  end;
  if v_tor then
    raise exception 'TOR_BLOCKED' using errcode = '42501', hint = 'Tor ilə giriş qadağandır';
  end if;
end;
$$;
grant execute on function public.check_request() to anon, authenticated;

alter role authenticator set pgrst.db_pre_request = 'public.check_request';
notify pgrst, 'reload config';

-- Tor çıxış siyahısını yenilə (pg_cron 3 saatdan bir çağırır).
-- Əvvəlki sorğunun cavabını emal edir və yeni sorğu göndərir.
create or replace function public.tor_refresh()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_id    bigint;
  v_body  text;
  v_code  int;
  v_count int := 0;
begin
  v_id := nullif(public.get_setting('tor_request_id', ''), '')::bigint;
  if v_id is not null then
    select status_code, content into v_code, v_body from net._http_response where id = v_id;
    if v_code = 200 and length(v_body) > 1000 then
      begin
        delete from public.tor_exits;
        insert into public.tor_exits (ip)
        select distinct trim(l)::inet
          from regexp_split_to_table(v_body, E'\n') as l
         where trim(l) ~ '^[0-9a-fA-F:.]+$' and trim(l) ~ '[.:]'
        on conflict (ip) do nothing;
        get diagnostics v_count = row_count;
      exception when others then
        v_count := -1;
      end;
    end if;
  end if;

  v_id := net.http_get(url := 'https://check.torproject.org/torbulkexitlist', timeout_milliseconds := 20000);
  insert into public.app_settings (key, value) values ('tor_request_id', v_id::text)
  on conflict (key) do update set value = excluded.value;
  return 'Yeniləndi: ' || v_count || ' IP';
end;
$$;
revoke execute on function public.tor_refresh() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'wordora-tor') then
    perform cron.unschedule('wordora-tor');
  end if;
  perform cron.schedule('wordora-tor', '17 */3 * * *', 'select public.tor_refresh()');
end;
$$;

select public.tor_refresh();   -- ilk sorğu (siyahı ən geci 3 saata dolur)

-- ---------------------------------------------------------------------
-- 4. Pozuntular, xəbərdarlıq və avtomatik blok
-- ---------------------------------------------------------------------
create table if not exists public.violations (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null,
  details    text,
  page       text,
  ip         text,
  counted    boolean not null default true,    -- xəbərdarlıq sayına düşüb?
  cancelled  boolean not null default false,   -- admin ləğv edib?
  created_at timestamptz not null default now()
);
create index if not exists violations_user_idx on public.violations (user_id, created_at desc);
create index if not exists violations_time_idx on public.violations (created_at desc);

alter table public.violations enable row level security;
drop policy if exists "violations_admin_select" on public.violations;
create policy "violations_admin_select" on public.violations
  for select to authenticated using (public.is_admin());
revoke insert, update, delete on public.violations from anon, authenticated;

create or replace function public.violation_label(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case p_kind
    when 'devtools'      then 'Developer paneli (F12) açıldı'
    when 'devtools_key'  then 'F12 / developer düymələri basıldı'
    when 'printscreen'   then 'Ekran şəkli düyməsi (PrintScreen)'
    when 'tab_switch'    then 'Sınaq zamanı başqa tab/pəncərəyə keçid'
    when 'second_device' then 'Hesaba ikinci cihazdan giriş'
    else p_kind end;
$$;

create or replace function public.report_violation(p_kind text, p_details text default null, p_page text default null)
returns json
language plpgsql security definer set search_path = ''
as $$
declare
  v_p       public.profiles;
  v_max     int := coalesce(public.get_setting('max_warnings', '2')::int, 2);
  v_counted boolean := true;
  v_blocked boolean := false;
  v_warn    int;
begin
  if p_kind not in ('devtools', 'devtools_key', 'printscreen', 'tab_switch', 'second_device') then
    raise exception 'Yanlış pozuntu növü';
  end if;

  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.role = 'admin' then
    return json_build_object('ignored', true);
  end if;
  if v_p.status <> 'approved' then
    return json_build_object('blocked', v_p.status = 'blocked', 'warnings', v_p.warnings, 'max', v_max);
  end if;

  -- ikinci cihaz yalnız qeyd olunur; eyni 15 saniyədə ikinci siqnal təkrar sayılmır
  if p_kind = 'second_device' then
    v_counted := false;
  elsif exists (select 1 from public.violations
                 where user_id = auth.uid() and counted and not cancelled
                   and created_at > now() - interval '15 seconds') then
    v_counted := false;
  end if;

  insert into public.violations (user_id, kind, details, page, ip, counted)
  values (auth.uid(), p_kind, left(p_details, 300), left(p_page, 120), public.client_ip(), v_counted);

  v_warn := v_p.warnings;
  if v_counted then
    update public.profiles set warnings = warnings + 1 where id = auth.uid() returning warnings into v_warn;
    if v_warn > v_max then
      update public.profiles
         set status = 'blocked',
             status_note = 'Avtomatik blok: ' || public.violation_label(p_kind),
             status_changed_at = now()
       where id = auth.uid();
      v_blocked := true;
    end if;

    perform public.notify_telegram(
      (case when v_blocked then '🔒 <b>Avtomatik BLOK</b>' else '⚠️ <b>Pozuntu</b>' end) || chr(10) ||
      public.tg_esc(v_p.full_name) || ' · ' || public.tg_esc(v_p.class_name) || ' · ' || v_p.student_code || chr(10) ||
      public.violation_label(p_kind) || coalesce(' — ' || public.tg_esc(left(p_page, 60)), '') || chr(10) ||
      'Xəbərdarlıq: ' || least(v_warn, v_max) || '/' || v_max ||
      (case when v_blocked then chr(10) || 'Hesab bloklandı. Açmaq üçün: Admin panel → Bloklanan.' else '' end));
  elsif p_kind = 'second_device' then
    perform public.notify_telegram(
      '📱 <b>İkinci cihaz</b>' || chr(10) ||
      public.tg_esc(v_p.full_name) || ' · ' || public.tg_esc(v_p.class_name) || ' · ' || v_p.student_code || chr(10) ||
      'Hesaba başqa cihazdan daxil olundu, köhnə cihazdan çıxarıldı.');
  end if;

  return json_build_object('counted', v_counted, 'warnings', v_warn, 'max', v_max, 'blocked', v_blocked);
end;
$$;
revoke execute on function public.report_violation(text, text, text) from public, anon;
grant  execute on function public.report_violation(text, text, text) to authenticated;

-- Admin: səhv siqnalı ləğv et (xəbərdarlıq sayı bir azalır)
create or replace function public.admin_cancel_violation(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v public.violations;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  update public.violations set cancelled = true where id = p_id and not cancelled returning * into v;
  if found and v.counted then
    update public.profiles set warnings = greatest(warnings - 1, 0) where id = v.user_id;
  end if;
end;
$$;

-- Admin: şagirdin xəbərdarlıqlarını sıfırla
create or replace function public.admin_reset_warnings(p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  update public.profiles set warnings = 0 where id = p_user;
  update public.violations set cancelled = true where user_id = p_user and counted and not cancelled;
end;
$$;

revoke execute on function public.admin_get_settings()                from public, anon;
revoke execute on function public.admin_set_setting(text, text)       from public, anon;
revoke execute on function public.admin_cancel_violation(bigint)      from public, anon;
revoke execute on function public.admin_reset_warnings(uuid)          from public, anon;
grant  execute on function public.admin_get_settings()                to authenticated;
grant  execute on function public.admin_set_setting(text, text)       to authenticated;
grant  execute on function public.admin_cancel_violation(bigint)      to authenticated;
grant  execute on function public.admin_reset_warnings(uuid)          to authenticated;

-- ---------------------------------------------------------------------
-- 5. Bir hesab = eyni anda bir cihaz
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists session_token uuid;

-- Girişdə çağırılır: yeni cihaz "sahib" olur, köhnə cihaz çıxarılır
create or replace function public.claim_session()
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v uuid := gen_random_uuid();
begin
  update public.profiles set session_token = v where id = auth.uid();
  return v;
end;
$$;

create or replace function public.check_session(p_token uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((select session_token is null or session_token = p_token
                     from public.profiles where id = auth.uid()), true);
$$;

revoke execute on function public.claim_session()     from public, anon;
revoke execute on function public.check_session(uuid) from public, anon;
grant  execute on function public.claim_session()     to authenticated;
grant  execute on function public.check_session(uuid) to authenticated;
