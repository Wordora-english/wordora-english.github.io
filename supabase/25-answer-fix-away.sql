-- =====================================================================
--  WORDORA — A) Rəqəmli cavablarda boşluq/vergül səhv sayılmasın
--               (düzgün "24", şagird "2 4", "2,4", "2-4" yazıb → düzgün)
--            B) Müəllim şagirdin cavabını əl ilə düzəldə bilsin (bal yenidən hesablanır)
--            C) Pozuntuda: şagird neçə saniyə sınaqdan kənarda olub
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  Sonda: köhnə nəticələr yenidən hesablanır və balı DƏYİŞƏN şagirdlərin
--  siyahısı göstərilir. (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

-- A) Açar yalnız rəqəmlərdən ibarətdirsə (məs. "24", "135"), şagirdin cavabındakı
--    boşluq, vergül, nöqtə, tire, kəsr xətti nəzərə alınmır.
create or replace function public.digits_key(p text)
returns text language sql immutable set search_path = ''
as $$ select regexp_replace(coalesce(p, ''), '[\s,;\-]+', '', 'g'); $$;

create or replace function public.digits_answer(p text)
returns text language sql immutable set search_path = ''
as $$ select regexp_replace(coalesce(p, ''), '[\s,.;:/\-_|]+', '', 'g'); $$;

create or replace function public.grade_answers(p_questions jsonb, p_key jsonb, p_answers jsonb)
returns jsonb
language plpgsql immutable set search_path = ''
as $$
declare
  q jsonb; n text; t text; pts numeric; k text; a text;
  i int; ok int; frac numeric; alt text; words int;
  v_score numeric := 0; v_det jsonb := '{}'::jsonb; v_essay boolean := false;
begin
  for q in select value from jsonb_array_elements(p_questions) loop
    n   := q->>'n';
    t   := q->>'type';
    pts := coalesce((q->>'points')::numeric, 0);
    a   := trim(coalesce(p_answers->>n, ''));
    frac := 0;

    if t = 'essay' then
      v_essay := true;
      words := case when a = '' then 0 else coalesce(array_length(regexp_split_to_array(a, '\s+'), 1), 0) end;
      v_det := v_det || jsonb_build_object(n, jsonb_build_object('essay', true, 'words', words));
      continue;
    elsif t = 'choice' then
      k := upper(trim(coalesce(p_key->>n, '')));
      if a <> '' and upper(a) = k then frac := 1; end if;
    elsif t = 'multi' then
      k := upper(trim(coalesce(p_key->>n, '')));
      a := regexp_replace(a, '[\s,.;:/\-]+', '', 'g');          -- "A B C" → "ABC"
      ok := 0;
      for i in 1 .. length(k) loop
        if upper(substr(a, i, 1)) = substr(k, i, 1) then ok := ok + 1; end if;
      end loop;
      frac := case when length(k) > 0 then ok::numeric / length(k) else 0 end;
    elsif t = 'open' then
      foreach alt in array string_to_array(coalesce(p_key->>n, ''), '/') loop
        if public.norm_answer(alt) <> '' and public.norm_answer(alt) = public.norm_answer(a) then frac := 1; end if;
        -- rəqəmli açar: "24" = "2 4" = "2,4" = "2-4"
        if frac < 1 and public.digits_key(alt) ~ '^[0-9]+$' and public.digits_answer(a) = public.digits_key(alt) then frac := 1; end if;
      end loop;
    end if;

    v_score := v_score + round(pts * frac, 2);
    v_det := v_det || jsonb_build_object(n, jsonb_build_object('frac', round(frac, 3), 'points', round(pts * frac, 2)));
  end loop;
  return jsonb_build_object('score', v_score, 'details', v_det, 'has_essay', v_essay);
end;
$$;

-- B) Müəllim cavabı düzəldir. Şagirdin ilk yazdığı cavab "answers_orig"-də saxlanır.
alter table public.attempts add column if not exists answers_orig jsonb;

create or replace function public.admin_set_answer(p_attempt uuid, p_n text, p_value text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_orig jsonb; v_val text := left(trim(coalesce(p_value, '')), 500);
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select * into v_a from public.attempts where id = p_attempt for update;
  if not found then raise exception 'Cəhd tapılmadı'; end if;
  if v_a.status = 'in_progress' then raise exception 'Şagird hələ sınağı yazır — bitirəndən sonra düzəlt'; end if;

  v_orig := coalesce(v_a.answers_orig, '{}'::jsonb);
  if not (v_orig ? p_n) then
    v_orig := v_orig || jsonb_build_object(p_n, coalesce(v_a.answers->>p_n, ''));
  end if;
  if coalesce(v_orig->>p_n, '') = v_val then v_orig := v_orig - p_n; end if;   -- əvvəlki cavaba qaytarıldı

  update public.attempts
     set answers = case when v_val = '' then answers - p_n else answers || jsonb_build_object(p_n, v_val) end,
         answers_orig = nullif(v_orig, '{}'::jsonb)
   where id = p_attempt;
  perform public.finalize_attempt(p_attempt);
  return (select json_build_object('score', score, 'auto_score', auto_score, 'details', details, 'answers', answers, 'answers_orig', answers_orig)
            from public.attempts where id = p_attempt);
end;
$$;
revoke execute on function public.admin_set_answer(uuid, text, text) from public, anon;
grant  execute on function public.admin_set_answer(uuid, text, text) to authenticated;

-- C) Kənarda keçən vaxt (saniyə) — şagird sınağa qayıdanda yazılır
alter table public.violations add column if not exists away_seconds int;

create or replace function public.report_away(p_seconds int)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_id bigint; v_s int := least(greatest(coalesce(p_seconds, 0), 0), 7200);
begin
  select id into v_id from public.violations
   where user_id = auth.uid() and kind = 'tab_switch' and away_seconds is null
     and created_at > now() - make_interval(secs => v_s + 60)
   order by created_at desc limit 1;
  if v_id is not null then
    update public.violations set away_seconds = v_s where id = v_id;
  end if;
end;
$$;
revoke execute on function public.report_away(int) from public, anon;
grant  execute on function public.report_away(int) to authenticated;

-- =====================================================================
-- Köhnə nəticələri yeni qayda ilə yenidən hesabla və dəyişənləri göstər
-- =====================================================================
drop table if exists _wordora_before;
create temp table _wordora_before as
  select 'online'::text as src, a.id, a.test_id, a.user_id, null::text as name, a.score from public.attempts a where a.status <> 'in_progress'
  union all
  select 'paper', p.id, p.test_id, p.user_id, p.student_name, p.score from public.paper_entries p;

do $$
declare r record; v_t public.tests; v_g jsonb;
begin
  for r in select id from public.attempts where status <> 'in_progress' loop
    perform public.finalize_attempt(r.id);
  end loop;
  for r in select * from public.paper_entries loop
    select * into v_t from public.tests where id = r.test_id;
    v_g := public.grade_answers(v_t.questions, coalesce(public.variant_key(r.test_id, r.variant), '{}'::jsonb), r.answers);
    update public.paper_entries
       set details = v_g->'details', auto_score = (v_g->>'score')::numeric,
           score = (v_g->>'score')::numeric + coalesce(essay_score, 0),
           status = case when (v_g->>'has_essay')::boolean and essay_score is null then 'submitted' else 'graded' end
     where id = r.id;
  end loop;
end;
$$;

select t.title as "Sınaq",
       coalesce(pr.full_name, b.name, '—') as "Şagird",
       b.score as "Əvvəlki bal",
       coalesce(a.score, p.score) as "Yeni bal"
  from _wordora_before b
  join public.tests t on t.id = b.test_id
  left join public.profiles pr on pr.id = b.user_id
  left join public.attempts a on b.src = 'online' and a.id = b.id
  left join public.paper_entries p on b.src = 'paper' and p.id = b.id
 where coalesce(a.score, p.score) is distinct from b.score
 order by t.title, 2;
