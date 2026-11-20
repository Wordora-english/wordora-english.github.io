-- =====================================================================
--  WORDORA — Sual bankı (WORDORA-BANK-38) (fənn → bölmə → mövzu, asan/orta/çətin)
--   • Suallar daily_questions cədvəlindədir (gündəlik alov da buradan seçir)
--   • Şagird istədiyi qədər həll edir: cavab dərhal yoxlanır (yaşıl / qırmızı)
--   • Hər şagirdin hər sual üzrə nəticəsi bank_progress-də saxlanır
--   • Gündəlik məşq üçün fənn seçimi (profiles.daily_subject)
--  Əvvəlcə 36-daily-grow.sql işə salınmış olmalıdır.
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.daily_questions add column if not exists subject text;
alter table public.daily_questions add column if not exists section text;
alter table public.daily_questions add column if not exists sort    int not null default 0;
alter table public.daily_questions drop constraint if exists daily_questions_text_check;
alter table public.daily_questions add  constraint daily_questions_text_check check (char_length(text) <= 1500);
alter table public.daily_questions drop constraint if exists daily_questions_subject_check;
alter table public.daily_questions add  constraint daily_questions_subject_check check (subject is null or subject ~ '^[a-z]{1,12}$');
create index if not exists daily_questions_bank_idx on public.daily_questions (subject, section, topic, level) where active;

alter table public.profiles add column if not exists daily_subject text;

create table if not exists public.bank_progress (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  qid         int  not null references public.daily_questions (id) on delete cascade,
  tries       int  not null default 1,
  last_ok     boolean not null,
  ever_ok     boolean not null,
  last_choice int,
  updated_at  timestamptz not null default now(),
  primary key (user_id, qid)
);
create index if not exists bank_progress_qid_idx on public.bank_progress (qid);
alter table public.bank_progress enable row level security;
drop policy if exists "bp_read" on public.bank_progress;
create policy "bp_read" on public.bank_progress for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke all on public.bank_progress from anon;
revoke insert, update, delete on public.bank_progress from authenticated;

-- Təsdiqlənmiş şagird (və ya admin) yoxlaması
create or replace function public.bank_me()
returns uuid
language plpgsql stable security definer set search_path = ''
as $$
declare v uuid;
begin
  select id into v from public.profiles where id = auth.uid() and (status = 'approved' or role = 'admin');
  if v is null then raise exception 'Hesabın aktiv deyil'; end if;
  return v;
end;
$$;
revoke execute on function public.bank_me() from public, anon;

-- Fənlər: sual sayı və şagirdin irəliləyişi
create or replace function public.bank_subjects()
returns json
language sql stable security definer set search_path = ''
as $$
  with me as materialized (select public.bank_me() as id)
  select coalesce(json_agg(x order by x.total desc), '[]'::json) from (
    select q.subject, count(*) as total,
           count(p.qid) as done, count(p.qid) filter (where p.last_ok) as ok
      from me cross join public.daily_questions q
      left join public.bank_progress p on p.qid = q.id and p.user_id = me.id
     where q.active and q.subject is not null
     group by q.subject) x;
$$;
revoke execute on function public.bank_subjects() from public, anon;
grant  execute on function public.bank_subjects() to authenticated;

-- Fənnin bölmə və mövzuları
create or replace function public.bank_tree(p_subject text)
returns json
language sql stable security definer set search_path = ''
as $$
  with me as materialized (select public.bank_me() as id)
  select coalesce(json_agg(x order by x.ord), '[]'::json) from (
    select q.section, q.topic, min(q.sort) as ord, count(*) as total,
           count(*) filter (where q.level = 'easy') as easy,
           count(*) filter (where q.level = 'medium') as medium,
           count(*) filter (where q.level = 'hard') as hard,
           count(p.qid) as done, count(p.qid) filter (where p.last_ok) as ok,
           count(p.qid) filter (where not p.last_ok) as wrong
      from me cross join public.daily_questions q
      left join public.bank_progress p on p.qid = q.id and p.user_id = me.id
     where q.active and q.subject = p_subject
     group by q.section, q.topic) x;
$$;
revoke execute on function public.bank_tree(text) from public, anon;
grant  execute on function public.bank_tree(text) to authenticated;

-- Növbəti suallar (cavabsız). p_mode: 'new' — həll etmədiklərim, 'wrong' — səhvlərim, 'all' — hamısı
create or replace function public.bank_next(p_subject text, p_section text default null, p_topic text default null,
                                            p_level text default null, p_mode text default 'new', p_limit int default 20)
returns json
language plpgsql volatile security definer set search_path = ''
as $$
declare v_me uuid := public.bank_me();
begin
  return (select coalesce(json_agg(json_build_object('id', x.id, 'text', x.text, 'opts', x.opts, 'level', x.level,
                                                     'topic', x.topic, 'section', x.section, 'seen', x.seen)), '[]'::json)
    from (select q.id, q.text, q.opts, q.level, q.topic, q.section, p.qid is not null as seen
            from public.daily_questions q
            left join public.bank_progress p on p.qid = q.id and p.user_id = v_me
           where q.active and q.subject = p_subject
             and (p_section is null or q.section = p_section)
             and (p_topic is null or q.topic = p_topic)
             and (p_level is null or q.level = p_level)
             and case coalesce(p_mode, 'new') when 'new' then p.qid is null
                                              when 'wrong' then p.qid is not null and not p.last_ok
                                              else true end
           order by case when coalesce(p_mode, 'new') = 'all' then (p.qid is not null)::int else 0 end, random()
           limit least(greatest(coalesce(p_limit, 20), 1), 50)) x);
end;
$$;
revoke execute on function public.bank_next(text, text, text, text, text, int) from public, anon;
grant  execute on function public.bank_next(text, text, text, text, text, int) to authenticated;

-- Cavabı yoxla: düzgündürmü + düzgün variant + izah
create or replace function public.bank_check(p_qid int, p_choice int)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_me uuid := public.bank_me(); q public.daily_questions; v_ok boolean;
begin
  select * into q from public.daily_questions where id = p_qid and active;
  if not found then raise exception 'Sual tapılmadı'; end if;
  -- bugünkü (bitməmiş) gündəlik məşqin suallarının cavabı burada göstərilmir
  if exists (select 1 from public.daily_sets d where d.user_id = v_me and d.day = public.baku_today()
                and d.done_at is null and p_qid = any (coalesce(d.qids, '{}'))) then
    raise exception 'Bu sual bugünkü gündəlik məşqdədir — əvvəlcə məşqi bitir';
  end if;
  v_ok := p_choice is not null and p_choice = q.ans;
  insert into public.bank_progress as b (user_id, qid, tries, last_ok, ever_ok, last_choice)
  values (v_me, p_qid, 1, v_ok, v_ok, p_choice)
  on conflict (user_id, qid) do update
     set tries = b.tries + 1, last_ok = excluded.last_ok, ever_ok = b.ever_ok or excluded.last_ok,
         last_choice = excluded.last_choice, updated_at = now();
  return json_build_object('ok', v_ok, 'ans', q.ans, 'expl', q.expl);
end;
$$;
revoke execute on function public.bank_check(int, int) from public, anon;
grant  execute on function public.bank_check(int, int) to authenticated;

-- Şagirdin ümumi statistikası (bugün, bu həftə, cəmi)
create or replace function public.bank_stats()
returns json
language sql stable security definer set search_path = ''
as $$
  select json_build_object(
    'total', count(*), 'ok', count(*) filter (where last_ok),
    'today', count(*) filter (where (updated_at at time zone 'Asia/Baku')::date = public.baku_today()),
    'today_ok', count(*) filter (where last_ok and (updated_at at time zone 'Asia/Baku')::date = public.baku_today()))
  from public.bank_progress where user_id = (select public.bank_me());
$$;
revoke execute on function public.bank_stats() from public, anon;
grant  execute on function public.bank_stats() to authenticated;

-- Gündəlik məşqin fənni (null — bütün fənlər qarışıq). Bugünkü məşq hələ başlanmayıbsa, yenidən yaradılır.
create or replace function public.daily_set_subject(p_subject text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_me uuid := public.bank_me(); v text := nullif(trim(coalesce(p_subject, '')), '');
begin
  if v is not null and not exists (select 1 from public.daily_questions where active and subject = v) then
    raise exception 'Bu fənn üzrə sual yoxdur';
  end if;
  update public.profiles set daily_subject = v where id = v_me;
  delete from public.daily_sets where user_id = v_me and day = public.baku_today() and started_at is null and done_at is null;
end;
$$;
revoke execute on function public.daily_set_subject(text) from public, anon;
grant  execute on function public.daily_set_subject(text) to authenticated;

-- Gündəlik suallar: şagirdin seçdiyi fəndən (seçməyibsə — bütün fənlərdən)
create or replace function public.daily_make2(p_user uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_out jsonb := '[]'::jsonb; v_ids int[] := '{}'; lv record; q record; v_order int[]; v_new jsonb; k int; v_n int;
        v_total int := public.daily_count((public.daily_streak(p_user)->>'current')::int + 1);
        v_easy int; v_hard int;
        v_subj text := (select daily_subject from public.profiles where id = p_user);
begin
  if v_subj is not null and (select count(*) from public.daily_questions where active and subject = v_subj) < 5 then v_subj := null; end if;
  if (select count(*) from public.daily_questions where active) < 5 then
    return jsonb_build_object('questions', public.daily_make(), 'qids', null);
  end if;
  v_easy := greatest(1, round(v_total * 0.2)::int);
  v_hard := round(v_total * 0.35)::int;
  for lv in select * from (values ('easy', v_easy, 1), ('medium', v_total - v_easy - v_hard, 2), ('hard', v_hard, 3), ('any', v_total, 4)) v(l, n, o) order by o loop
    for q in
      select dq.* from public.daily_questions dq
        left join (select x.qid, count(*) as n from public.daily_sets d, unnest(d.qids) as x(qid)
                    where d.user_id = p_user group by x.qid) s on s.qid = dq.id
       where dq.active and (v_subj is null or dq.subject = v_subj)
         and (lv.l = 'any' or dq.level = lv.l) and not (dq.id = any (v_ids))
       order by coalesce(s.n, 0), random()
       limit greatest(0, case when lv.l = 'any' then v_total - cardinality(v_ids) else lv.n end)
    loop
      v_n := jsonb_array_length(q.opts);
      select array_agg(g order by random()) into v_order from generate_series(1, v_n) g;
      v_new := '[]'::jsonb;
      for k in 1 .. v_n loop v_new := v_new || jsonb_build_array(q.opts -> (v_order[k] - 1)); end loop;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'k', 'q', 'id', q.id, 'topic', q.topic, 'level', q.level, 'text', q.text, 'opts', v_new,
        'ans', (array_position(v_order, q.ans + 1) - 1)::text, 'expl', q.expl, 'subject', q.subject));
      v_ids := v_ids || q.id;
    end loop;
  end loop;
  return jsonb_build_object('questions', v_out, 'qids', to_jsonb(v_ids));
end;
$$;
revoke execute on function public.daily_make2(uuid) from public, anon, authenticated;

-- daily_status → şagirdin gündəlik fənni də qaytarılır
create or replace function public.daily_my_subject()
returns text
language sql stable security definer set search_path = ''
as $$ select daily_subject from public.profiles where id = auth.uid(); $$;
revoke execute on function public.daily_my_subject() from public, anon;
grant  execute on function public.daily_my_subject() to authenticated;

-- Wordora: bütün suallar ingilis dilidir
update public.daily_questions set subject = 'en' where subject is null;
