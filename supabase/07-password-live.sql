-- =====================================================================
--  WORDORA — 5-ci mərhələ
--  A) Şifrə sıfırlama (admin paneldən)
--  B) Canlı viktorina — proyektor rejimi (Kahoot kimi)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- A) ŞİFRƏ SIFIRLAMA
-- =====================================================================
create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if p_password is null or length(p_password) < 8 or p_password !~ '[A-Za-z]' or p_password !~ '[0-9]' then
    raise exception 'Şifrə ən azı 8 simvol olmalı, hərf və rəqəm daxil etməlidir';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and role = 'student') then
    raise exception 'Şagird tapılmadı';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_user;

  -- köhnə cihazlardakı girişləri bağla
  begin
    delete from auth.sessions where user_id = p_user;
  exception when others then null;
  end;
  update public.profiles set session_token = null where id = p_user;
end;
$$;
revoke execute on function public.admin_set_password(uuid, text) from public, anon;
grant  execute on function public.admin_set_password(uuid, text) to authenticated;

-- =====================================================================
-- B) CANLI VİKTORİNA
-- =====================================================================
create table if not exists public.live_quizzes (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 1 and 150),
  -- [{"text":"She ___ to school.","options":["goes","go","going"],"correct":0,"time":20}]
  questions  jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.live_sessions (
  id           uuid primary key default gen_random_uuid(),
  quiz_id      uuid not null references public.live_quizzes(id) on delete cascade,
  code         text not null,
  status       text not null default 'lobby' check (status in ('lobby', 'question', 'reveal', 'finished')),
  q_index      int not null default -1,
  q_started_at timestamptz,
  created_at   timestamptz not null default now()
);
create unique index if not exists live_sessions_code_active on public.live_sessions (code) where status <> 'finished';

create table if not exists public.live_players (
  session_id uuid not null references public.live_sessions(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  score      int not null default 0,
  joined_at  timestamptz not null default now(),
  primary key (session_id, user_id)
);

create table if not exists public.live_answers (
  session_id uuid not null references public.live_sessions(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  q_index    int not null,
  choice     int not null,
  ms         int not null,
  correct    boolean not null,
  points     int not null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id, q_index)
);

alter table public.live_quizzes  enable row level security;
alter table public.live_sessions enable row level security;
alter table public.live_players  enable row level security;
alter table public.live_answers  enable row level security;

-- Yalnız admin birbaşa oxuyur/yazır; şagirdlər funksiyalarla işləyir
drop policy if exists "lq_admin" on public.live_quizzes;
create policy "lq_admin" on public.live_quizzes for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "ls_admin" on public.live_sessions;
create policy "ls_admin" on public.live_sessions for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "lp_admin" on public.live_players;
create policy "lp_admin" on public.live_players for select to authenticated using (public.is_admin());
drop policy if exists "la_admin" on public.live_answers;
create policy "la_admin" on public.live_answers for select to authenticated using (public.is_admin());
revoke all on public.live_quizzes, public.live_sessions, public.live_players, public.live_answers from anon;

-- Sualın vaxtı (saniyə)
create or replace function public.live_q_time(p_q jsonb)
returns int language sql immutable set search_path = ''
as $$ select greatest(5, least(coalesce((p_q->>'time')::int, 20), 120)); $$;

-- ---------- Admin ----------
create or replace function public.live_start(p_quiz uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_code text; v_id uuid; i int := 0;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  if not exists (select 1 from public.live_quizzes where id = p_quiz and jsonb_array_length(questions) > 0) then
    raise exception 'Viktorinada sual yoxdur';
  end if;
  -- köhnə yarımçıq oyunları bağla
  update public.live_sessions set status = 'finished' where quiz_id = p_quiz and status <> 'finished';
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from public.live_sessions where code = v_code and status <> 'finished');
    i := i + 1; if i > 50 then raise exception 'Kod yaradılmadı'; end if;
  end loop;
  insert into public.live_sessions (quiz_id, code) values (p_quiz, v_code) returning id into v_id;
  return json_build_object('session_id', v_id, 'code', v_code);
end;
$$;

create or replace function public.live_control(p_session uuid, p_action text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_n int;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_s from public.live_sessions where id = p_session for update;
  if not found then raise exception 'Oyun tapılmadı'; end if;
  select jsonb_array_length(questions) into v_n from public.live_quizzes where id = v_s.quiz_id;

  if p_action = 'next' then
    if v_s.q_index + 1 >= v_n then
      update public.live_sessions set status = 'finished' where id = p_session;
    else
      update public.live_sessions
         set status = 'question', q_index = v_s.q_index + 1, q_started_at = now()
       where id = p_session;
    end if;
  elsif p_action = 'reveal' then
    if v_s.status = 'question' then
      update public.live_sessions set status = 'reveal' where id = p_session;
    end if;
  elsif p_action = 'end' then
    update public.live_sessions set status = 'finished' where id = p_session;
  else
    raise exception 'Yanlış əməliyyat';
  end if;
end;
$$;

create or replace function public.live_host_state(p_session uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_qz public.live_quizzes; v_q jsonb; v_left int;
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  if not found then raise exception 'Oyun tapılmadı'; end if;
  select * into v_qz from public.live_quizzes where id = v_s.quiz_id;
  v_q := case when v_s.q_index >= 0 then v_qz.questions -> v_s.q_index end;
  v_left := case when v_s.status = 'question'
                 then greatest(0, ceil(public.live_q_time(v_q) * 1000 - extract(epoch from (now() - v_s.q_started_at)) * 1000))::int
                 end;
  return json_build_object(
    'title', v_qz.title, 'code', v_s.code, 'status', v_s.status,
    'q_index', v_s.q_index, 'total', jsonb_array_length(v_qz.questions),
    'question', v_q, 'left_ms', v_left,
    'players', (select coalesce(json_agg(json_build_object('name', p.full_name, 'class', p.class_name) order by lp.joined_at), '[]'::json)
                  from public.live_players lp join public.profiles p on p.id = lp.user_id where lp.session_id = p_session),
    'answered', (select count(*) from public.live_answers where session_id = p_session and q_index = v_s.q_index),
    'dist', (select coalesce(json_object_agg(choice, n), '{}'::json)
               from (select choice, count(*) n from public.live_answers
                      where session_id = p_session and q_index = v_s.q_index group by choice) d),
    'top', (select coalesce(json_agg(t), '[]'::json) from (
              select p.full_name as name, p.class_name as class, lp.score
                from public.live_players lp join public.profiles p on p.id = lp.user_id
               where lp.session_id = p_session order by lp.score desc, lp.joined_at limit 50) t)
  );
end;
$$;

-- ---------- Şagird ----------
create or replace function public.live_join(p_code text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions;
begin
  if not public.is_active_user() then raise exception 'Hesabın aktiv deyil'; end if;
  select * into v_s from public.live_sessions where code = trim(p_code) and status <> 'finished' order by created_at desc limit 1;
  if not found then raise exception 'Bu kodla aktiv viktorina tapılmadı'; end if;
  insert into public.live_players (session_id, user_id) values (v_s.id, auth.uid())
  on conflict do nothing;
  return json_build_object('session_id', v_s.id);
end;
$$;

create or replace function public.live_state(p_session uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_s public.live_sessions; v_qz public.live_quizzes; v_q jsonb; v_left int;
  v_my public.live_answers; v_score int; v_rank int; v_players int;
begin
  if not exists (select 1 from public.live_players where session_id = p_session and user_id = auth.uid()) then
    raise exception 'Sən bu viktorinada deyilsən';
  end if;
  select * into v_s from public.live_sessions where id = p_session;
  select * into v_qz from public.live_quizzes where id = v_s.quiz_id;
  v_q := case when v_s.q_index >= 0 then v_qz.questions -> v_s.q_index end;
  v_left := case when v_s.status = 'question'
                 then greatest(0, ceil(public.live_q_time(v_q) * 1000 - extract(epoch from (now() - v_s.q_started_at)) * 1000))::int
                 end;
  select * into v_my from public.live_answers where session_id = p_session and user_id = auth.uid() and q_index = v_s.q_index;
  select score into v_score from public.live_players where session_id = p_session and user_id = auth.uid();
  select count(*) + 1 into v_rank from public.live_players where session_id = p_session and score > v_score;
  select count(*) into v_players from public.live_players where session_id = p_session;

  return json_build_object(
    'title', v_qz.title, 'status', v_s.status, 'q_index', v_s.q_index,
    'total', jsonb_array_length(v_qz.questions), 'left_ms', v_left,
    -- düzgün cavab yalnız "reveal" mərhələsində göndərilir
    'question', case when v_q is null then null
                     else json_build_object('text', v_q->>'text', 'options', v_q->'options',
                                            'correct', case when v_s.status = 'reveal' then (v_q->>'correct')::int end) end,
    'my_choice', v_my.choice,
    'my_correct', case when v_s.status in ('reveal', 'finished') then v_my.correct end,
    'my_points', case when v_s.status in ('reveal', 'finished') then v_my.points end,
    'score', v_score, 'rank', v_rank, 'players', v_players);
end;
$$;

create or replace function public.live_answer(p_session uuid, p_choice int)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions; v_q jsonb; v_t int; v_ms int; v_ok boolean; v_pts int;
begin
  if not exists (select 1 from public.live_players where session_id = p_session and user_id = auth.uid()) then
    raise exception 'Sən bu viktorinada deyilsən';
  end if;
  select * into v_s from public.live_sessions where id = p_session;
  if v_s.status <> 'question' then return json_build_object('accepted', false); end if;
  select questions -> v_s.q_index into v_q from public.live_quizzes where id = v_s.quiz_id;
  v_t  := public.live_q_time(v_q);
  v_ms := (extract(epoch from (now() - v_s.q_started_at)) * 1000)::int;
  if v_ms > v_t * 1000 + 1500 then return json_build_object('accepted', false); end if;
  if p_choice < 0 or p_choice >= jsonb_array_length(v_q->'options') then raise exception 'Yanlış variant'; end if;

  v_ok  := p_choice = (v_q->>'correct')::int;
  -- düzgün cavab: 500–1000 bal (nə qədər tez, o qədər çox)
  v_pts := case when v_ok then greatest(500, round(1000 - 500.0 * least(v_ms, v_t * 1000) / (v_t * 1000)))::int else 0 end;

  insert into public.live_answers (session_id, user_id, q_index, choice, ms, correct, points)
  values (p_session, auth.uid(), v_s.q_index, p_choice, v_ms, v_ok, v_pts)
  on conflict do nothing;
  if found then
    update public.live_players set score = score + v_pts where session_id = p_session and user_id = auth.uid();
  end if;
  return json_build_object('accepted', true);
end;
$$;

revoke execute on function public.live_start(uuid)              from public, anon;
revoke execute on function public.live_control(uuid, text)      from public, anon;
revoke execute on function public.live_host_state(uuid)         from public, anon;
revoke execute on function public.live_join(text)               from public, anon;
revoke execute on function public.live_state(uuid)              from public, anon;
revoke execute on function public.live_answer(uuid, int)        from public, anon;
grant  execute on function public.live_start(uuid)              to authenticated;
grant  execute on function public.live_control(uuid, text)      to authenticated;
grant  execute on function public.live_host_state(uuid)         to authenticated;
grant  execute on function public.live_join(text)               to authenticated;
grant  execute on function public.live_state(uuid)              to authenticated;
grant  execute on function public.live_answer(uuid, int)        to authenticated;
