-- =====================================================================
--  WORDORA — A) Həftəlik avtomatik ehtiyat nüsxə (Telegram-a)
--            B) Xəta bildirişi (şagirddə sayt xəta verəndə)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  Sonda AÇAR (uzun kod) göstəriləcək — onu GitHub-a "BACKUP_SECRET" kimi yaz.
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir — açar dəyişmir.)
-- =====================================================================

-- =====================================================================
-- A) EHTİYAT NÜSXƏ
--    GitHub hər bazar bu funksiyanı gizli açarla çağırır, bütün bazanı
--    alır və fayl kimi Telegram-a göndərir.
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from vault.decrypted_secrets where name = 'backup_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'backup_secret');
  end if;
end;
$$;

create or replace function public.backup_bundle(p_secret text)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_secret text; v_data jsonb := '{}'::jsonb; v_rows jsonb; t text;
  v_tables text[] := array['profiles', 'announcements', 'materials', 'material_views', 'violations', 'tests', 'test_keys',
    'test_online', 'attempts', 'attempts_archive', 'test_retakes', 'test_variant_assign', 'paper_entries',
    'live_quizzes', 'live_sessions', 'live_players', 'live_answers', 'words', 'attendance', 'messages',
    'question_bank', 'homework', 'hw_submissions', 'quick_comments', 'app_settings', 'client_errors',
    'study_groups', 'study_group_members'];
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'backup_secret';
  if v_secret is null or p_secret is distinct from v_secret then
    perform pg_sleep(1);   -- açarı təxmin etməyi çətinləşdirir
    raise exception 'Yanlış açar';
  end if;
  foreach t in array v_tables loop
    if to_regclass('public.' || t) is not null then
      execute format('select coalesce(jsonb_agg(x), ''[]''::jsonb) from public.%I x', t) into v_rows;
      v_data := v_data || jsonb_build_object(t, v_rows);
    end if;
  end loop;
  return json_build_object(
    'created_at', now(),
    'telegram', json_build_object(
      'token', (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_bot_token'),
      'chats', (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_chat_id')),
    'counts', (select jsonb_object_agg(k, jsonb_array_length(v)) from jsonb_each(v_data) as e(k, v)),
    'data', v_data);
end;
$$;
revoke execute on function public.backup_bundle(text) from public;
grant  execute on function public.backup_bundle(text) to anon, authenticated;   -- açarsız heç nə qaytarmır

-- Açarı göstər (yalnız SQL Editor-da işləyir)
create or replace function public.backup_secret_show()
returns text
language sql security definer set search_path = ''
as $$ select decrypted_secret from vault.decrypted_secrets where name = 'backup_secret'; $$;
revoke execute on function public.backup_secret_show() from public, anon, authenticated;

-- =====================================================================
-- B) XƏTA BİLDİRİŞİ
-- =====================================================================
create or replace function public.tg_esc(p text)
returns text
language sql immutable
as $$ select replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'); $$;

create table if not exists public.client_errors (
  id         bigint generated always as identity primary key,
  user_id    uuid references public.profiles(id) on delete cascade,
  page       text check (char_length(page) <= 200),
  message    text not null check (char_length(message) <= 500),
  details    text check (char_length(details) <= 2000),
  user_agent text check (char_length(user_agent) <= 300),
  notified   boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists client_errors_created_idx on public.client_errors (created_at desc);
alter table public.client_errors enable row level security;
drop policy if exists "cerr_admin" on public.client_errors;
create policy "cerr_admin" on public.client_errors for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.client_errors from anon;

create or replace function public.report_client_error(p_page text, p_message text, p_details text default null, p_ua text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.profiles; v_notify boolean;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.role = 'admin' then return; end if;
  -- spam olmasın: bir şagirddən saatda ən çox 10 qeyd
  if (select count(*) from public.client_errors where user_id = v_p.id and created_at > now() - interval '1 hour') >= 10 then return; end if;
  -- Telegram: eyni xəta 30 dəqiqədə bir dəfə, gündə ən çox 20 bildiriş
  v_notify := not exists (select 1 from public.client_errors
                           where notified and message = left(p_message, 500) and coalesce(page, '') = coalesce(left(p_page, 200), '')
                             and created_at > now() - interval '30 minutes')
              and (select count(*) from public.client_errors where notified and created_at > now() - interval '1 day') < 20;
  insert into public.client_errors (user_id, page, message, details, user_agent, notified)
  values (v_p.id, left(p_page, 200), left(coalesce(nullif(p_message, ''), 'Naməlum xəta'), 500), left(p_details, 2000), left(p_ua, 300), v_notify);
  if v_notify then
    perform public.notify_telegram(format(E'🚨 <b>Saytda xəta</b>\n👤 %s (%s)\n📄 %s\n❗ %s%s',
      public.tg_esc(v_p.full_name), public.tg_esc(coalesce(v_p.class_name, '')), public.tg_esc(coalesce(p_page, '')),
      public.tg_esc(left(p_message, 300)), case when coalesce(p_details, '') <> '' then E'\n<i>' || public.tg_esc(left(p_details, 300)) || '</i>' else '' end));
  end if;
end;
$$;
revoke execute on function public.report_client_error(text, text, text, text) from public, anon;
grant  execute on function public.report_client_error(text, text, text, text) to authenticated;

-- Köhnə xəta qeydləri 60 gündən sonra silinsin
do $$
begin
  if exists (select 1 from cron.job where jobname = 'wordora-errors-cleanup') then
    perform cron.unschedule('wordora-errors-cleanup');
  end if;
  perform cron.schedule('wordora-errors-cleanup', '40 3 * * *', $c$delete from public.client_errors where created_at < now() - interval '60 days'$c$);
end;
$$;

-- ⬇⬇⬇ BU AÇARI KOPYALA → GitHub → Settings → Secrets and variables → Actions → New repository secret → Name: BACKUP_SECRET
select public.backup_secret_show() as "BACKUP_SECRET (GitHub-a yaz)";
