-- =====================================================================
--  WORDORA — Dərs qrupları (davamiyyət üçün)
--  Cədvəllər: 1-ci və 3-cü gün, 3-cü və 5-ci gün, 2-ci və 4-cü gün, 6-cı və 7-ci gün.
--  Hər cədvəlin içində istədiyin qədər qrup; hər qrupa istədiyin şagirdlər.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create table if not exists public.study_groups (
  id         uuid primary key default gen_random_uuid(),
  schedule   text not null check (schedule ~ '^[1-7]{1,7}$'),       -- məs. '24' = 2-ci və 4-cü gün
  name       text not null check (char_length(name) between 1 and 60),
  sort       int  not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists study_groups_sched_idx on public.study_groups (schedule, sort, created_at);

create table if not exists public.study_group_members (
  group_id uuid not null references public.study_groups(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists study_group_members_user_idx on public.study_group_members (user_id);

alter table public.study_groups        enable row level security;
alter table public.study_group_members enable row level security;

drop policy if exists "sg_admin" on public.study_groups;
create policy "sg_admin" on public.study_groups for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "sgm_admin" on public.study_group_members;
create policy "sgm_admin" on public.study_group_members for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.study_groups, public.study_group_members from anon;

-- Ehtiyat nüsxəyə qruplar da daxil olsun (19-backup-errors.sql işə salınıbsa)
do $$ begin if to_regprocedure('public.backup_bundle(text)') is null then raise notice '19 hələ işə salınmayıb'; end if; end $$;
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
grant  execute on function public.backup_bundle(text) to anon, authenticated;
