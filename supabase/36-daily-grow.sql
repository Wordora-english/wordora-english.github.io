-- =====================================================================
--  WORDORA — Gündəlik məşq: seriya uzandıqca suallar artır
--   Seriyanın 1-ci günü 5 sual → 2-ci gün 7 → 3-cü gün 8 → 4-cü gün 9 → 5–7-ci gün 10
--   2-ci həftə (8–14-cü gün) 20 sual (2 qat) → 15–29-cu gün 25 → 30-cu gündən 30 sual
--   Seriya qırılsa — yenidən 5 sualdan başlayır.
--   Vaxt: 10 suala qədər hər suala 72 saniyə, daha çoxda hər suala 60 saniyə.
--   Səviyyə qarışığı: ~20% asan, ~45% orta, ~35% çətin (5 sualda: 1 asan + 2 orta + 2 çətin).
--  Əvvəlcə 33-daily-bank.sql işə salınmış olmalıdır.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.daily_sets add column if not exists limit_sec int;

-- Seriyanın neçənci günüdür → neçə sual
create or replace function public.daily_count(p_day int)
returns int language sql immutable set search_path = ''
as $$
  select case when coalesce(p_day, 1) <= 1 then 5
              when p_day = 2 then 7
              when p_day = 3 then 8
              when p_day = 4 then 9
              when p_day <= 7 then 10
              when p_day <= 14 then 20
              when p_day <= 29 then 25
              else 30 end;
$$;

-- Sual sayına görə vaxt (saniyə)
create or replace function public.daily_seconds(p_n int)
returns int language sql immutable set search_path = ''
as $$ select case when p_n <= 10 then p_n * 72 else p_n * 60 end; $$;

create or replace function public.daily_make2(p_user uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_out jsonb := '[]'::jsonb; v_ids int[] := '{}'; lv record; q record; v_order int[]; v_new jsonb; k int; v_n int;
        v_total int := public.daily_count((public.daily_streak(p_user)->>'current')::int + 1);
        v_easy int; v_hard int;
begin
  if (select count(*) from public.daily_questions where active) < 5 then   -- baza boşdursa
    return jsonb_build_object('questions', public.daily_make(), 'qids', null);   -- baza boşdursa — köhnə üsul (sözlər + sual bankı)
  end if;
  v_easy := greatest(1, round(v_total * 0.2)::int);
  v_hard := round(v_total * 0.35)::int;
  for lv in select * from (values ('easy', v_easy, 1), ('medium', v_total - v_easy - v_hard, 2), ('hard', v_hard, 3), ('any', v_total, 4)) v(l, n, o) order by o loop
    for q in
      select dq.* from public.daily_questions dq
        left join (select x.qid, count(*) as n from public.daily_sets d, unnest(d.qids) as x(qid)
                    where d.user_id = p_user group by x.qid) s on s.qid = dq.id
       where dq.active and (lv.l = 'any' or dq.level = lv.l) and not (dq.id = any (v_ids))
       order by coalesce(s.n, 0), random()
       limit greatest(0, case when lv.l = 'any' then v_total - cardinality(v_ids) else lv.n end)
    loop
      v_n := jsonb_array_length(q.opts);
      select array_agg(g order by random()) into v_order from generate_series(1, v_n) g;
      v_new := '[]'::jsonb;
      for k in 1 .. v_n loop v_new := v_new || jsonb_build_array(q.opts -> (v_order[k] - 1)); end loop;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'k', 'q', 'id', q.id, 'topic', q.topic, 'level', q.level, 'text', q.text, 'opts', v_new,
        'ans', (array_position(v_order, q.ans + 1) - 1)::text, 'expl', q.expl));
      v_ids := v_ids || q.id;
    end loop;
  end loop;
  return jsonb_build_object('questions', v_out, 'qids', to_jsonb(v_ids));
end;
$$;
revoke execute on function public.daily_make2(uuid) from public, anon, authenticated;

create or replace function public.daily_view(p_set public.daily_sets)
returns json
language sql stable security definer set search_path = ''
as $$
  select json_build_object(
    'day', p_set.day, 'done', p_set.done_at is not null,
    'started_at', p_set.started_at, 'limit', coalesce(p_set.limit_sec, public.daily_limit_sec()),
    'left_ms', case when p_set.started_at is not null and p_set.done_at is null
                    then greatest(0, (extract(epoch from (p_set.started_at + make_interval(secs => coalesce(p_set.limit_sec, public.daily_limit_sec())) - now())) * 1000)::bigint) end,
    'voided', p_set.voided, 'void_reason', p_set.void_reason,
    'questions', case when p_set.started_at is null and p_set.done_at is null then null   -- başlamamış — suallar görünmür
                      else (select coalesce(jsonb_agg(
                    (q - 'ans' - 'expl') || case when p_set.done_at is not null and not p_set.voided
                                        then jsonb_build_object('ans', q->'ans', 'expl', q->'expl', 'my', p_set.answers->((i - 1)::int), 'ok', p_set.results->((i - 1)::int))
                                        else '{}'::jsonb end order by i), '[]'::jsonb)
                    from jsonb_array_elements(p_set.questions) with ordinality as x(q, i)) end,
    'count', jsonb_array_length(p_set.questions),
    'levels', (select jsonb_agg(coalesce(q->>'level', 'medium') order by i) from jsonb_array_elements(p_set.questions) with ordinality as x(q, i)),
    'correct', p_set.correct, 'total', p_set.total,
    'streak_day', (public.daily_streak(p_set.user_id)->>'current')::int + case when p_set.done_at is null then 1 else 0 end,
    'next_count', case when p_set.voided then 5 else public.daily_count((public.daily_streak(p_set.user_id)->>'current')::int + case when p_set.done_at is not null then 1 else 2 end) end,
    'streak', public.daily_streak(p_set.user_id));
$$;
revoke execute on function public.daily_view(public.daily_sets) from public, anon, authenticated;

create or replace function public.daily_close_late(p_user uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.daily_sets
     set done_at = now(), correct = 0, total = jsonb_array_length(questions), answers = '[]'::jsonb,
         results = (select coalesce(jsonb_agg(false), '[]'::jsonb) from jsonb_array_elements(questions)),
         void_reason = 'Vaxt bitdi — cavablar göndərilmədi'
   where user_id = p_user and done_at is null and started_at is not null
     and now() > started_at + make_interval(secs => coalesce(limit_sec, public.daily_limit_sec()) + 60);
$$;
revoke execute on function public.daily_close_late(uuid) from public, anon, authenticated;

create or replace function public.daily_get()
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets; v_p public.profiles; v_m jsonb;
begin
  select * into v_p from public.profiles where id = auth.uid();
  if not found or v_p.status <> 'approved' then raise exception 'Hesabın aktiv deyil'; end if;
  perform public.daily_close_late(v_p.id);
  select * into v_s from public.daily_sets where user_id = v_p.id and day = public.baku_today();
  if not found then
    v_m := public.daily_make2(v_p.id);
    insert into public.daily_sets (user_id, day, limit_sec, questions, qids)
    values (v_p.id, public.baku_today(), public.daily_seconds(jsonb_array_length(v_m->'questions')), v_m->'questions',
            case when jsonb_typeof(v_m->'qids') = 'array' then array(select jsonb_array_elements_text(v_m->'qids')::int) end)
    on conflict do nothing;
    select * into v_s from public.daily_sets where user_id = v_p.id and day = public.baku_today();
  end if;
  if jsonb_array_length(v_s.questions) = 0 then
    delete from public.daily_sets where user_id = v_p.id and day = v_s.day and done_at is null;
    return json_build_object('empty', true, 'streak', public.daily_streak(v_p.id));
  end if;
  return public.daily_view(v_s);
end;
$$;

create or replace function public.daily_submit(p_answers jsonb)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets; q jsonb; i int := 0; v_my text; v_ok boolean; v_res jsonb := '[]'::jsonb; v_c int := 0; alt text;
begin
  select * into v_s from public.daily_sets where user_id = auth.uid() and day = public.baku_today() for update;
  if not found then raise exception 'Bugünkü məşq tapılmadı — səhifəni yenilə'; end if;
  if v_s.done_at is not null then return public.daily_view(v_s); end if;
  if v_s.started_at is null then
    update public.daily_sets set started_at = now() where user_id = v_s.user_id and day = v_s.day returning * into v_s;
  end if;
  if now() > v_s.started_at + make_interval(secs => coalesce(v_s.limit_sec, public.daily_limit_sec()) + 45) then
    perform public.daily_close_late(v_s.user_id);
    update public.daily_sets set void_reason = 'Vaxt bitdi — cavablar gec göndərildi', done_at = coalesce(done_at, now()),
           correct = 0, total = jsonb_array_length(questions), answers = '[]'::jsonb,
           results = (select coalesce(jsonb_agg(false), '[]'::jsonb) from jsonb_array_elements(questions))
     where user_id = v_s.user_id and day = v_s.day returning * into v_s;
    return public.daily_view(v_s);
  end if;
  if jsonb_typeof(p_answers) <> 'array' then raise exception 'Cavablar düzgün deyil'; end if;
  for q in select value from jsonb_array_elements(v_s.questions) loop
    v_my := left(trim(coalesce(p_answers->>i, '')), 120);
    v_ok := false;
    if q->'opts' is null or jsonb_typeof(q->'opts') = 'null' then
      foreach alt in array string_to_array(q->>'ans', '/') loop
        if public.practice_norm(alt) <> '' and public.practice_norm(alt) = public.practice_norm(v_my) then v_ok := true; end if;
      end loop;
    else
      v_ok := v_my <> '' and v_my = q->>'ans';
    end if;
    v_res := v_res || to_jsonb(v_ok);
    if v_ok then v_c := v_c + 1; end if;
    i := i + 1;
  end loop;
  update public.daily_sets
     set answers = (select coalesce(jsonb_agg(left(trim(coalesce(p_answers->>(g - 1), '')), 120) order by g), '[]'::jsonb)
                      from generate_series(1, jsonb_array_length(v_s.questions)) g),
         results = v_res, correct = v_c, total = jsonb_array_length(v_s.questions), done_at = now()
   where user_id = v_s.user_id and day = v_s.day
  returning * into v_s;
  return public.daily_view(v_s);
end;
$$;

create or replace function public.daily_status()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_s public.daily_sets; v json;
begin
  if auth.uid() is null then return null; end if;
  select * into v_s from public.daily_sets where user_id = auth.uid() and day = public.baku_today();
  v := public.daily_streak(auth.uid());
  return (v::jsonb || jsonb_build_object('today_voided', coalesce(v_s.voided, false), 'void_reason', v_s.void_reason,
                                          'in_progress', v_s.started_at is not null and v_s.done_at is null,
                                          'count_today', coalesce(jsonb_array_length(v_s.questions), public.daily_count((v->>'current')::int + 1)),
                                          'count_next', case when coalesce(v_s.voided, false) then 5 else public.daily_count((v->>'current')::int + case when v_s.done_at is not null then 1 else 2 end) end))::json;
end;
$$;
