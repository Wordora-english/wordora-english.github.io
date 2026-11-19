-- =====================================================================
--  WORDORA — Canlı viktorina 3.0
--   • 👥 komanda yarışı (2–4 komanda, avtomatik bərabər bölünür)
--   • ⭐ ikiqat bal sualı
--   • 🖼 şəkilli sual (şəkillər "live" qovluğunda saxlanır)
--   • ✍️ yazmalı sual (variant yox — şagird cavabı özü yazır)
--   • 📊 oyundan sonra hesabat
--   • 🏅 portalda viktorina xalları və nişanlar
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
--  Əvvəlcə 30-live-fun.sql işə salınmış olmalıdır.
-- =====================================================================

alter table public.live_sessions add column if not exists teams       int not null default 0;
alter table public.live_sessions add column if not exists questions   jsonb;          -- oyun başlayanda sualların surəti
alter table public.live_sessions add column if not exists finished_at timestamptz;
alter table public.live_players  add column if not exists team        int;
alter table public.live_players  add column if not exists best_streak int not null default 0;
alter table public.live_answers  add column if not exists text_answer text;

-- Köhnə bitmiş oyunlar üçün də bitmə vaxtı olsun
update public.live_sessions set finished_at = created_at where status = 'finished' and finished_at is null;

-- ---------------------------------------------------------------------
-- Şəkillər: açıq "live" qovluğu (oxumaq hamıya, yükləmək yalnız müəllimə)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('live', 'live', true, 3145728, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "live_files_admin" on storage.objects;
create policy "live_files_admin" on storage.objects for all to authenticated
  using (bucket_id = 'live' and public.is_admin()) with check (bucket_id = 'live' and public.is_admin());

-- ---------------------------------------------------------------------
-- Köməkçilər
-- ---------------------------------------------------------------------
-- Oyunun sualları (başlayanda götürülən surət; köhnə oyunlarda — viktorinanın özü)
create or replace function public.live_qs(p_session uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(s.questions, q.questions, '[]'::jsonb)
    from public.live_sessions s left join public.live_quizzes q on q.id = s.quiz_id
   where s.id = p_session;
$$;
revoke execute on function public.live_qs(uuid) from public, anon, authenticated;

-- Yazılan cavabı müqayisə üçün sadələşdir: kiçik hərf, artıq boşluq və sondakı nöqtə-vergül yox
create or replace function public.live_norm(p text)
returns text
language sql immutable set search_path = ''
as $$
  select regexp_replace(regexp_replace(regexp_replace(
           lower(translate(trim(coalesce(p, '')), '’‘`´“”', '''''''''""')),
           '\s+', ' ', 'g'),
         '^[\s.,!?;:"]+', ''),
       '[\s.,!?;:"]+$', '');
$$;

-- Bal: sürətə görə 500–1000 + seriya bonusu; ikiqat sualda ×2
create or replace function public.live_points(p_ms int, p_time int, p_streak int, p_double boolean)
returns int
language sql immutable set search_path = ''
as $$
  select ((greatest(500, round(1000 - 500.0 * least(p_ms, p_time * 1000) / (p_time * 1000)))::int
          + least(greatest(coalesce(p_streak, 0) + 1 - 2, 0), 5) * 50)
          * case when coalesce(p_double, false) then 2 else 1 end);
$$;

-- Komandaların balı (orta bal — komandalar fərqli sayda olsa da ədalətli)
create or replace function public.live_team_scores(p_session uuid)
returns json
language sql stable security definer set search_path = ''
as $$
  select coalesce(json_agg(json_build_object('team', team, 'avg', avg_score, 'n', n, 'total', total) order by avg_score desc, team), '[]'::json)
    from (select team, round(avg(score))::int as avg_score, count(*) as n, sum(score)::int as total
            from public.live_players where session_id = p_session and team is not null group by team) t
   where exists (select 1 from public.live_sessions where id = p_session and teams > 0);
$$;
revoke execute on function public.live_team_scores(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Oyunu başlat: sualların surəti saxlanır (oyun vaxtı redaktə oyunu pozmasın)
-- ---------------------------------------------------------------------
create or replace function public.live_start(p_quiz uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_code text; v_id uuid; i int := 0; v_qs jsonb;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select questions into v_qs from public.live_quizzes where id = p_quiz;
  if v_qs is null or jsonb_array_length(v_qs) = 0 then raise exception 'Viktorinada sual yoxdur'; end if;
  update public.live_sessions set status = 'finished', finished_at = coalesce(finished_at, now())
   where quiz_id = p_quiz and status <> 'finished';
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from public.live_sessions where code = v_code and status <> 'finished');
    i := i + 1; if i > 50 then raise exception 'Kod yaradılmadı'; end if;
  end loop;
  insert into public.live_sessions (quiz_id, code, questions) values (p_quiz, v_code, v_qs) returning id into v_id;
  return json_build_object('session_id', v_id, 'code', v_code);
end;
$$;

-- Komandalar (yalnız gözləmə otağında): 0 = komandasız, 2–4 komanda; p_shuffle — yenidən qarışdır
create or replace function public.live_settings(p_session uuid, p_teams int, p_shuffle boolean default false)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_teams not in (0, 2, 3, 4) then raise exception 'Komanda sayı 2, 3 və ya 4 ola bilər'; end if;
  select * into v_s from public.live_sessions where id = p_session for update;
  if not found then raise exception 'Oyun tapılmadı'; end if;
  if v_s.status <> 'lobby' then raise exception 'Komandaları yalnız oyun başlamamış dəyişmək olar'; end if;
  update public.live_sessions set teams = p_teams where id = p_session;
  if p_teams = 0 then
    update public.live_players set team = null where session_id = p_session;
  else
    update public.live_players lp set team = x.t
      from (select user_id, ((row_number() over (order by case when p_shuffle then random() end, joined_at)) - 1) % p_teams as t
              from public.live_players where session_id = p_session) x
     where lp.session_id = p_session and lp.user_id = x.user_id;
  end if;
end;
$$;

-- Qoşulma: təsadüfi personaj + (komanda varsa) ən az adamı olan komanda
create or replace function public.live_join(p_code text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_team int;
        v_av text[] := array['🦊','🐼','🐯','🦁','🐸','🐵','🐨','🐰','🐧','🦉','🐙','🦄','🐲','🐢','🐬','🦋','🐝','🐞','🦖','🐺','🐱','🐶','🐮','🦔'];
        v_cl text[] := array['#e5484d','#2f7ce0','#f5a400','#12925c','#7b4fe0','#e0529c','#0ea5a5','#f97316'];
begin
  if not public.is_active_user() then raise exception 'Hesabın aktiv deyil'; end if;
  select * into v_s from public.live_sessions where code = trim(p_code) and status <> 'finished' order by created_at desc limit 1;
  if not found then raise exception 'Bu kodla aktiv viktorina tapılmadı'; end if;
  if v_s.teams > 0 then
    select g.t into v_team
      from generate_series(0, v_s.teams - 1) g(t)
      left join public.live_players lp on lp.session_id = v_s.id and lp.team = g.t
     group by g.t order by count(lp.user_id), random() limit 1;
  end if;
  insert into public.live_players (session_id, user_id, avatar, color, team)
  values (v_s.id, auth.uid(), v_av[1 + floor(random() * 24)::int], v_cl[1 + floor(random() * 8)::int], v_team)
  on conflict do nothing;
  return json_build_object('session_id', v_s.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Şagird ekranı
-- ---------------------------------------------------------------------
create or replace function public.live_state(p_session uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_s public.live_sessions; v_qz public.live_quizzes; v_qs jsonb; v_q jsonb; v_left int; v_text boolean;
  v_my public.live_answers; v_me public.live_players; v_rank int; v_players int; v_open boolean;
begin
  select * into v_me from public.live_players where session_id = p_session and user_id = auth.uid();
  if not found then raise exception 'Sən bu viktorinada deyilsən'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  select * into v_qz from public.live_quizzes where id = v_s.quiz_id;
  v_qs := public.live_qs(p_session);
  v_q := case when v_s.q_index >= 0 then v_qs -> v_s.q_index end;
  v_text := coalesce(v_q->>'type', '') = 'text';
  v_open := v_s.status in ('reveal', 'finished');
  v_left := case when v_s.status = 'question'
                 then greatest(0, ceil(public.live_q_time(v_q) * 1000 - extract(epoch from (now() - v_s.q_started_at)) * 1000))::int
                 end;
  select * into v_my from public.live_answers where session_id = p_session and user_id = auth.uid() and q_index = v_s.q_index;
  select count(*) + 1 into v_rank from public.live_players where session_id = p_session and score > v_me.score;
  select count(*) into v_players from public.live_players where session_id = p_session;

  return json_build_object(
    'title', coalesce(v_qz.title, 'Viktorina'), 'status', v_s.status, 'q_index', v_s.q_index,
    'total', jsonb_array_length(v_qs), 'left_ms', v_left,
    'time', case when v_q is not null then public.live_q_time(v_q) end,
    -- düzgün cavab yalnız "reveal" mərhələsində göndərilir; səsli sualın gizli mətni şagirdə getmir
    'question', case when v_q is null then null
                     else json_build_object(
                       'text', case when v_text or v_open then v_q->>'text' end,
                       'type', case when v_text then 'text' else 'choice' end,
                       'double', coalesce((v_q->>'double')::boolean, false),
                       'options', case when v_text then '[]'::jsonb else v_q->'options' end,
                       'correct', case when v_s.status = 'reveal' and not v_text then (v_q->>'correct')::int end,
                       'answer', case when v_open and v_text then v_q->'answers'->>0 end) end,
    'my_choice', case when v_my.user_id is null then null when v_text then 0 else v_my.choice end,
    'my_text', v_my.text_answer,
    'my_correct', case when v_open then v_my.correct end,
    'my_points', case when v_open then v_my.points end,
    'score', v_me.score, 'rank', v_rank, 'players', v_players,
    'avatar', v_me.avatar, 'color', v_me.color, 'streak', v_me.streak,
    'teams', v_s.teams, 'team', v_me.team,
    'team_scores', case when v_s.teams > 0 and v_s.status in ('reveal', 'finished') then public.live_team_scores(p_session) end,
    'room', case when v_s.status = 'lobby' then (
      select coalesce(json_agg(json_build_object('name', split_part(p.full_name, ' ', 1), 'avatar', lp.avatar, 'color', lp.color, 'team', lp.team) order by lp.joined_at), '[]'::json)
        from public.live_players lp join public.profiles p on p.id = lp.user_id where lp.session_id = p_session) end);
end;
$$;

-- ---------------------------------------------------------------------
-- Cavablar
-- ---------------------------------------------------------------------
create or replace function public.live_answer(p_session uuid, p_choice int)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_q jsonb; v_t int; v_ms int; v_ok boolean; v_pts int; v_streak int;
begin
  select streak into v_streak from public.live_players where session_id = p_session and user_id = auth.uid();
  if not found then raise exception 'Sən bu viktorinada deyilsən'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  if v_s.status <> 'question' then return json_build_object('accepted', false); end if;
  v_q := public.live_qs(p_session) -> v_s.q_index;
  if coalesce(v_q->>'type', '') = 'text' then raise exception 'Bu sualda cavabı yazmaq lazımdır'; end if;
  v_t  := public.live_q_time(v_q);
  v_ms := (extract(epoch from (now() - v_s.q_started_at)) * 1000)::int;
  if v_ms > v_t * 1000 + 1500 then return json_build_object('accepted', false); end if;
  if p_choice < 0 or p_choice >= jsonb_array_length(v_q->'options') then raise exception 'Yanlış variant'; end if;

  v_ok  := p_choice = (v_q->>'correct')::int;
  v_pts := case when v_ok then public.live_points(v_ms, v_t, v_streak, (v_q->>'double')::boolean) else 0 end;

  insert into public.live_answers (session_id, user_id, q_index, choice, ms, correct, points)
  values (p_session, auth.uid(), v_s.q_index, p_choice, v_ms, v_ok, v_pts)
  on conflict do nothing;
  if found then
    update public.live_players
       set score = score + v_pts,
           streak = case when v_ok then streak + 1 else 0 end,
           best_streak = greatest(best_streak, case when v_ok then streak + 1 else 0 end)
     where session_id = p_session and user_id = auth.uid();
  end if;
  return json_build_object('accepted', true);
end;
$$;

-- Yazmalı sual
create or replace function public.live_answer_text(p_session uuid, p_text text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_q jsonb; v_t int; v_ms int; v_ok boolean; v_pts int; v_streak int; v_txt text;
begin
  select streak into v_streak from public.live_players where session_id = p_session and user_id = auth.uid();
  if not found then raise exception 'Sən bu viktorinada deyilsən'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  if v_s.status <> 'question' then return json_build_object('accepted', false); end if;
  v_q := public.live_qs(p_session) -> v_s.q_index;
  if coalesce(v_q->>'type', '') <> 'text' then raise exception 'Bu sualda variant seçmək lazımdır'; end if;
  v_txt := left(trim(coalesce(p_text, '')), 120);
  if v_txt = '' then raise exception 'Cavabı yaz'; end if;
  v_t  := public.live_q_time(v_q);
  v_ms := (extract(epoch from (now() - v_s.q_started_at)) * 1000)::int;
  if v_ms > v_t * 1000 + 1500 then return json_build_object('accepted', false); end if;

  v_ok := exists (select 1 from jsonb_array_elements_text(coalesce(v_q->'answers', '[]'::jsonb)) a
                   where public.live_norm(a) = public.live_norm(v_txt));
  v_pts := case when v_ok then public.live_points(v_ms, v_t, v_streak, (v_q->>'double')::boolean) else 0 end;

  insert into public.live_answers (session_id, user_id, q_index, choice, ms, correct, points, text_answer)
  values (p_session, auth.uid(), v_s.q_index, case when v_ok then 1 else 0 end, v_ms, v_ok, v_pts, v_txt)
  on conflict do nothing;
  if found then
    update public.live_players
       set score = score + v_pts,
           streak = case when v_ok then streak + 1 else 0 end,
           best_streak = greatest(best_streak, case when v_ok then streak + 1 else 0 end)
     where session_id = p_session and user_id = auth.uid();
  end if;
  return json_build_object('accepted', true);
end;
$$;

-- ---------------------------------------------------------------------
-- Müəllimin idarəsi
-- ---------------------------------------------------------------------
create or replace function public.live_control(p_session uuid, p_action text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_n int;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_s from public.live_sessions where id = p_session for update;
  if not found then raise exception 'Oyun tapılmadı'; end if;
  v_n := jsonb_array_length(public.live_qs(p_session));

  if p_action = 'next' then
    if v_s.status = 'finished' then return; end if;
    if v_s.q_index + 1 >= v_n then
      update public.live_sessions set status = 'finished', finished_at = now() where id = p_session;
    else
      update public.live_sessions
         set status = 'question', q_index = v_s.q_index + 1, q_started_at = now()
       where id = p_session;
    end if;
  elsif p_action = 'reveal' then
    if v_s.status = 'question' then
      update public.live_sessions set status = 'reveal' where id = p_session;
      update public.live_players lp set streak = 0
       where lp.session_id = p_session
         and not exists (select 1 from public.live_answers a where a.session_id = p_session and a.user_id = lp.user_id and a.q_index = v_s.q_index);
    end if;
  elsif p_action = 'end' then
    update public.live_sessions set status = 'finished', finished_at = coalesce(finished_at, now()) where id = p_session;
  else
    raise exception 'Yanlış əməliyyat';
  end if;
end;
$$;

-- Proyektor ekranı
create or replace function public.live_host_state(p_session uuid, p_after bigint default 0)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_qz public.live_quizzes; v_qs jsonb; v_q jsonb; v_left int;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  if not found then raise exception 'Oyun tapılmadı'; end if;
  select * into v_qz from public.live_quizzes where id = v_s.quiz_id;
  v_qs := public.live_qs(p_session);
  v_q := case when v_s.q_index >= 0 then v_qs -> v_s.q_index end;
  v_left := case when v_s.status = 'question'
                 then greatest(0, ceil(public.live_q_time(v_q) * 1000 - extract(epoch from (now() - v_s.q_started_at)) * 1000))::int
                 end;
  return json_build_object(
    'title', coalesce(v_qz.title, 'Viktorina'), 'code', v_s.code, 'status', v_s.status,
    'q_index', v_s.q_index, 'total', jsonb_array_length(v_qs), 'teams', v_s.teams,
    'question', v_q, 'left_ms', v_left, 'time', case when v_q is not null then public.live_q_time(v_q) end,
    'players', (select coalesce(json_agg(json_build_object('uid', lp.user_id, 'name', p.full_name, 'class', p.class_name, 'avatar', lp.avatar, 'color', lp.color, 'team', lp.team) order by lp.joined_at), '[]'::json)
                  from public.live_players lp join public.profiles p on p.id = lp.user_id where lp.session_id = p_session),
    'answered', (select count(*) from public.live_answers where session_id = p_session and q_index = v_s.q_index),
    'dist', (select coalesce(json_object_agg(choice, n), '{}'::json)
               from (select choice, count(*) n from public.live_answers
                      where session_id = p_session and q_index = v_s.q_index group by choice) d),
    -- yazmalı sualda: ən çox yazılan səhv cavablar (adsız)
    'wrong', case when v_s.status in ('reveal', 'finished') and coalesce(v_q->>'type', '') = 'text' then (
               select coalesce(json_agg(json_build_object('a', a, 'n', n) order by n desc, a), '[]'::json) from (
                 select min(text_answer) a, count(*) n from public.live_answers
                  where session_id = p_session and q_index = v_s.q_index and not correct and text_answer is not null
                  group by public.live_norm(text_answer) order by count(*) desc limit 6) w) end,
    'fastest', case when v_s.status in ('reveal', 'finished') then (
                 select json_build_object('name', p.full_name, 'avatar', lp.avatar, 'color', lp.color, 'ms', a.ms)
                   from public.live_answers a join public.live_players lp on lp.session_id = a.session_id and lp.user_id = a.user_id
                   join public.profiles p on p.id = a.user_id
                  where a.session_id = p_session and a.q_index = v_s.q_index and a.correct
                  order by a.ms limit 1) end,
    'top', (select coalesce(json_agg(t), '[]'::json) from (
              select p.full_name as name, p.class_name as class, lp.score, lp.avatar, lp.color, lp.streak, lp.team
                from public.live_players lp join public.profiles p on p.id = lp.user_id
               where lp.session_id = p_session order by lp.score desc, lp.joined_at limit 50) t),
    'team_scores', public.live_team_scores(p_session),
    'reactions', (select coalesce(json_agg(json_build_object('id', id, 'emoji', emoji) order by id), '[]'::json)
                    from (select id, emoji from public.live_reactions
                           where session_id = p_session and id > coalesce(p_after, 0) and created_at > now() - interval '6 seconds'
                           order by id desc limit 30) r)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 🏅 Şagirdin viktorina xalları və nişanları
-- ---------------------------------------------------------------------
create or replace function public.my_live_stats()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid();
        v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
        v json;
begin
  if v_uid is null then return null; end if;
  with my as (
    select lp.session_id, lp.score, lp.best_streak, s.created_at
      from public.live_players lp join public.live_sessions s on s.id = lp.session_id
     where lp.user_id = v_uid and s.status = 'finished'
  ), ranked as (
    select m.session_id, m.score,
           (select count(*) from public.live_players x where x.session_id = m.session_id and x.score > m.score) + 1 as rnk,
           (select count(*) from public.live_players x where x.session_id = m.session_id) as players
      from my m
  ), months as (
    select date_trunc('month', s.created_at at time zone 'Asia/Baku') as m, lp.user_id, sum(lp.score) as pts
      from public.live_players lp join public.live_sessions s on s.id = lp.session_id
      join public.profiles p on p.id = lp.user_id and p.role = 'student'
     where s.status = 'finished'
     group by 1, 2
  ), leaders as (
    select m, user_id, pts, rank() over (partition by m order by pts desc) as r from months where pts > 0
  )
  select json_build_object(
    'games',        (select count(*) from my),
    'total_points', (select coalesce(sum(score), 0) from my),
    'month_points', (select coalesce(sum(score), 0) from my where created_at >= v_month),
    'month_games',  (select count(*) from my where created_at >= v_month),
    'month_rank',   (select r from leaders where user_id = v_uid and m = date_trunc('month', now() at time zone 'Asia/Baku')),
    'wins',         (select count(*) from ranked where rnk = 1 and players >= 2 and score > 0),
    'podiums',      (select count(*) from ranked where rnk <= 3 and players >= 4 and score > 0),
    'best_streak',  (select coalesce(max(best_streak), 0) from my),
    'fastest',      (select count(*) from (
                       select distinct on (a.session_id, a.q_index) a.user_id from public.live_answers a
                        where a.correct and a.session_id in (select session_id from my)
                        order by a.session_id, a.q_index, a.ms) f where f.user_id = v_uid),
    'perfect',      (select count(*) from (
                       select a.session_id from public.live_answers a
                        where a.user_id = v_uid and a.correct and a.session_id in (select session_id from my)
                        group by a.session_id
                       having count(*) >= 5 and count(*) >= jsonb_array_length(public.live_qs(a.session_id))) p),
    'champion_months', (select count(*) from leaders
                         where user_id = v_uid and r = 1 and m < date_trunc('month', now() at time zone 'Asia/Baku')),
    'champion',     (select json_build_object('name', p.full_name, 'class', p.class_name, 'points', l.pts, 'me', l.user_id = v_uid)
                       from leaders l join public.profiles p on p.id = l.user_id
                      where l.m = date_trunc('month', now() at time zone 'Asia/Baku') and l.r = 1
                      order by p.full_name limit 1)
  ) into v;
  return v;
end;
$$;
revoke execute on function public.my_live_stats() from public, anon;
grant  execute on function public.my_live_stats() to authenticated;

-- ---------------------------------------------------------------------
-- İcazələr
-- ---------------------------------------------------------------------
revoke execute on function public.live_settings(uuid, int, boolean)  from public, anon;
revoke execute on function public.live_answer_text(uuid, text)       from public, anon;
grant  execute on function public.live_settings(uuid, int, boolean)  to authenticated;
grant  execute on function public.live_answer_text(uuid, text)       to authenticated;
revoke execute on function public.live_points(int, int, int, boolean) from public, anon;
