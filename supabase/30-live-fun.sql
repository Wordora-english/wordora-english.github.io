-- =====================================================================
--  WORDORA — Canlı viktorina 2.0
--   • hər şagird personaj (heyvan emojisi) və rəng seçir
--   • gözləmə otağında hamı bir-birini görür
--   • 🔥 seriya: ardıcıl düzgün cavablara bonus bal
--   • ⚡ ən sürətli düzgün cavab verən göstərilir
--   • emoji reaksiyaları proyektorda uçur
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.live_players add column if not exists avatar text;
alter table public.live_players add column if not exists color  text;
alter table public.live_players add column if not exists streak int not null default 0;

create or replace function public.live_avatar_ok(p text)
returns boolean language sql immutable set search_path = ''
as $$ select p = any (array['🦊','🐼','🐯','🦁','🐸','🐵','🐨','🐰','🐧','🦉','🐙','🦄','🐲','🐢','🐬','🦋','🐝','🐞','🦖','🐺','🐱','🐶','🐮','🦔']); $$;
create or replace function public.live_color_ok(p text)
returns boolean language sql immutable set search_path = ''
as $$ select p ~ '^#[0-9a-fA-F]{6}$'; $$;

-- Qoşulanda təsadüfi personaj; sonra gözləmə otağında dəyişmək olar
create or replace function public.live_join(p_code text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.live_sessions;
        v_av text[] := array['🦊','🐼','🐯','🦁','🐸','🐵','🐨','🐰','🐧','🦉','🐙','🦄','🐲','🐢','🐬','🦋','🐝','🐞','🦖','🐺','🐱','🐶','🐮','🦔'];
        v_cl text[] := array['#e5484d','#2f7ce0','#f5a400','#12925c','#7b4fe0','#e0529c','#0ea5a5','#f97316'];
begin
  if not public.is_active_user() then raise exception 'Hesabın aktiv deyil'; end if;
  select * into v_s from public.live_sessions where code = trim(p_code) and status <> 'finished' order by created_at desc limit 1;
  if not found then raise exception 'Bu kodla aktiv viktorina tapılmadı'; end if;
  insert into public.live_players (session_id, user_id, avatar, color)
  values (v_s.id, auth.uid(), v_av[1 + floor(random() * 24)::int], v_cl[1 + floor(random() * 8)::int])
  on conflict do nothing;
  return json_build_object('session_id', v_s.id);
end;
$$;

create or replace function public.live_set_avatar(p_session uuid, p_avatar text, p_color text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.live_avatar_ok(p_avatar) or not public.live_color_ok(p_color) then raise exception 'Yanlış personaj'; end if;
  update public.live_players set avatar = p_avatar, color = lower(p_color)
   where session_id = p_session and user_id = auth.uid();
end;
$$;

-- Emoji reaksiyaları (proyektorda uçur)
create table if not exists public.live_reactions (
  id         bigint generated always as identity primary key,
  session_id uuid not null references public.live_sessions(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now()
);
create index if not exists live_reactions_sess_idx on public.live_reactions (session_id, id);
alter table public.live_reactions enable row level security;
drop policy if exists "lr_admin" on public.live_reactions;
create policy "lr_admin" on public.live_reactions for select to authenticated using (public.is_admin());
revoke all on public.live_reactions from anon;

create or replace function public.live_react(p_session uuid, p_emoji text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_emoji is null or not (p_emoji = any (array['👏','😂','😮','🔥','❤️','👍','😱','🎉'])) then return; end if;
  if not exists (select 1 from public.live_players where session_id = p_session and user_id = auth.uid()) then return; end if;
  -- spam olmasın: saniyədə ən çox bir
  if exists (select 1 from public.live_reactions where session_id = p_session and user_id = auth.uid()
                                                   and created_at > now() - interval '900 milliseconds') then return; end if;
  insert into public.live_reactions (session_id, user_id, emoji) values (p_session, auth.uid(), p_emoji);
  delete from public.live_reactions where session_id = p_session and created_at < now() - interval '2 minutes';
end;
$$;

-- Şagird ekranı
create or replace function public.live_state(p_session uuid)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_s public.live_sessions; v_qz public.live_quizzes; v_q jsonb; v_left int;
  v_my public.live_answers; v_me public.live_players; v_rank int; v_players int;
begin
  select * into v_me from public.live_players where session_id = p_session and user_id = auth.uid();
  if not found then raise exception 'Sən bu viktorinada deyilsən'; end if;
  select * into v_s from public.live_sessions where id = p_session;
  select * into v_qz from public.live_quizzes where id = v_s.quiz_id;
  v_q := case when v_s.q_index >= 0 then v_qz.questions -> v_s.q_index end;
  v_left := case when v_s.status = 'question'
                 then greatest(0, ceil(public.live_q_time(v_q) * 1000 - extract(epoch from (now() - v_s.q_started_at)) * 1000))::int
                 end;
  select * into v_my from public.live_answers where session_id = p_session and user_id = auth.uid() and q_index = v_s.q_index;
  select count(*) + 1 into v_rank from public.live_players where session_id = p_session and score > v_me.score;
  select count(*) into v_players from public.live_players where session_id = p_session;

  return json_build_object(
    'title', v_qz.title, 'status', v_s.status, 'q_index', v_s.q_index,
    'total', jsonb_array_length(v_qz.questions), 'left_ms', v_left,
    'time', case when v_q is not null then public.live_q_time(v_q) end,
    -- düzgün cavab yalnız "reveal" mərhələsində göndərilir
    'question', case when v_q is null then null
                     else json_build_object('text', v_q->>'text', 'options', v_q->'options',
                                            'correct', case when v_s.status = 'reveal' then (v_q->>'correct')::int end) end,
    'my_choice', v_my.choice,
    'my_correct', case when v_s.status in ('reveal', 'finished') then v_my.correct end,
    'my_points', case when v_s.status in ('reveal', 'finished') then v_my.points end,
    'score', v_me.score, 'rank', v_rank, 'players', v_players,
    'avatar', v_me.avatar, 'color', v_me.color, 'streak', v_me.streak,
    -- gözləmə otağı: kim qoşulub (yalnız ad və personaj)
    'room', case when v_s.status = 'lobby' then (
      select coalesce(json_agg(json_build_object('name', split_part(p.full_name, ' ', 1), 'avatar', lp.avatar, 'color', lp.color) order by lp.joined_at), '[]'::json)
        from public.live_players lp join public.profiles p on p.id = lp.user_id where lp.session_id = p_session) end);
end;
$$;

-- Cavab: sürətə görə 500–1000 bal + 🔥 seriya bonusu (3-cü ardıcıl düzgündən +50, +100 … ən çox +250)
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
  select questions -> v_s.q_index into v_q from public.live_quizzes where id = v_s.quiz_id;
  v_t  := public.live_q_time(v_q);
  v_ms := (extract(epoch from (now() - v_s.q_started_at)) * 1000)::int;
  if v_ms > v_t * 1000 + 1500 then return json_build_object('accepted', false); end if;
  if p_choice < 0 or p_choice >= jsonb_array_length(v_q->'options') then raise exception 'Yanlış variant'; end if;

  v_ok  := p_choice = (v_q->>'correct')::int;
  v_pts := case when v_ok then greatest(500, round(1000 - 500.0 * least(v_ms, v_t * 1000) / (v_t * 1000)))::int
                               + least(greatest(coalesce(v_streak, 0) + 1 - 2, 0), 5) * 50
                else 0 end;

  insert into public.live_answers (session_id, user_id, q_index, choice, ms, correct, points)
  values (p_session, auth.uid(), v_s.q_index, p_choice, v_ms, v_ok, v_pts)
  on conflict do nothing;
  if found then
    update public.live_players
       set score = score + v_pts, streak = case when v_ok then streak + 1 else 0 end
     where session_id = p_session and user_id = auth.uid();
  end if;
  return json_build_object('accepted', true);
end;
$$;

-- Cavab verməyənlərin seriyası sıfırlansın (sual bağlananda)
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
      update public.live_players lp set streak = 0
       where lp.session_id = p_session
         and not exists (select 1 from public.live_answers a where a.session_id = p_session and a.user_id = lp.user_id and a.q_index = v_s.q_index);
    end if;
  elsif p_action = 'end' then
    update public.live_sessions set status = 'finished' where id = p_session;
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
    'question', v_q, 'left_ms', v_left, 'time', case when v_q is not null then public.live_q_time(v_q) end,
    'players', (select coalesce(json_agg(json_build_object('name', p.full_name, 'class', p.class_name, 'avatar', lp.avatar, 'color', lp.color) order by lp.joined_at), '[]'::json)
                  from public.live_players lp join public.profiles p on p.id = lp.user_id where lp.session_id = p_session),
    'answered', (select count(*) from public.live_answers where session_id = p_session and q_index = v_s.q_index),
    'dist', (select coalesce(json_object_agg(choice, n), '{}'::json)
               from (select choice, count(*) n from public.live_answers
                      where session_id = p_session and q_index = v_s.q_index group by choice) d),
    'fastest', case when v_s.status in ('reveal', 'finished') then (
                 select json_build_object('name', p.full_name, 'avatar', lp.avatar, 'ms', a.ms)
                   from public.live_answers a join public.live_players lp on lp.session_id = a.session_id and lp.user_id = a.user_id
                   join public.profiles p on p.id = a.user_id
                  where a.session_id = p_session and a.q_index = v_s.q_index and a.correct
                  order by a.ms limit 1) end,
    'top', (select coalesce(json_agg(t), '[]'::json) from (
              select p.full_name as name, p.class_name as class, lp.score, lp.avatar, lp.color, lp.streak
                from public.live_players lp join public.profiles p on p.id = lp.user_id
               where lp.session_id = p_session order by lp.score desc, lp.joined_at limit 50) t),
    'reactions', (select coalesce(json_agg(json_build_object('id', id, 'emoji', emoji) order by id), '[]'::json)
                    from (select id, emoji from public.live_reactions
                           where session_id = p_session and id > coalesce(p_after, 0) and created_at > now() - interval '6 seconds'
                           order by id desc limit 30) r)
  );
end;
$$;
drop function if exists public.live_host_state(uuid);

revoke execute on function public.live_set_avatar(uuid, text, text)   from public, anon;
revoke execute on function public.live_react(uuid, text)              from public, anon;
revoke execute on function public.live_host_state(uuid, bigint)       from public, anon;
grant  execute on function public.live_set_avatar(uuid, text, text)   to authenticated;
grant  execute on function public.live_react(uuid, text)              to authenticated;
grant  execute on function public.live_host_state(uuid, bigint)       to authenticated;
