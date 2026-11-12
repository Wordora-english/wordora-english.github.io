-- =====================================================================
--  WORDORA — Sınağı dərs qruplarına təyin etmək
--  Sınaq yaradanda siniflərdən əlavə (və ya əvəzinə) dərs qruplarını seçmək olar.
--  Görən: seçilən sinif(lər)in şagirdləri VƏ seçilən qrup(lar)ın şagirdləri.
--  Heç nə seçilməsə — əvvəlki kimi hamı görür.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.tests add column if not exists target_groups uuid[];

create or replace function public.test_target_ok(p_classes text[], p_groups uuid[], p_user uuid, p_class text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when coalesce(cardinality(p_classes), 0) = 0 and coalesce(cardinality(p_groups), 0) = 0 then true
    else coalesce(p_class = any (p_classes), false)
         or exists (select 1 from public.study_group_members m where m.user_id = p_user and m.group_id = any (coalesce(p_groups, '{}')))
  end;
$$;
revoke execute on function public.test_target_ok(text[], uuid[], uuid, text) from public, anon, authenticated;

create or replace function public.test_visible(p_test uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.tests t join public.profiles p on p.id = auth.uid()
     where t.id = p_test and t.is_published and p.status = 'approved'
       and public.test_target_ok(t.target_classes, t.target_groups, p.id, p.class_name)
  );
$$;

-- Həftəlik hesabatda "yazmayan" sayı qrupları da nəzərə alsın
create or replace function public.weekly_report_text()
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_from timestamptz := now() - interval '7 days';
  v_lines text[] := '{}';
  v_active int; v_new int; v_pending int; v_blocked int;
  v_ess int; v_hw_ungraded int; v_unread int; v_viol int; v_viol_users int; v_live int; v_att numeric;
  r record; v_tests text := ''; v_hws text := ''; n int := 0;
  v_best record;
begin
  v_lines := v_lines || format('📬 <b>Wordora — həftəlik hesabat</b>%s(%s – %s)',
    E'\n', to_char(v_from at time zone 'Asia/Baku', 'DD.MM'), to_char(now() at time zone 'Asia/Baku', 'DD.MM.YYYY'));

  -- şagirdlər
  select count(*) filter (where status = 'approved'), count(*) filter (where created_at >= v_from),
         count(*) filter (where status = 'pending'), count(*) filter (where status = 'blocked')
    into v_active, v_new, v_pending, v_blocked
    from public.profiles where role = 'student';
  v_lines := v_lines || format('👥 Aktiv şagird: <b>%s</b>%s%s%s', v_active,
    case when v_new > 0 then format(' · yeni qeydiyyat: %s', v_new) else '' end,
    case when v_pending > 0 then format(' · <b>təsdiq gözləyir: %s</b>', v_pending) else '' end,
    case when v_blocked > 0 then format(' · bloklanıb: %s', v_blocked) else '' end);

  -- sınaqlar (onlayn + kağız), bu həftə nəticəsi olanlar
  for r in
    with res as (
      select a.test_id, a.user_id, a.score from public.attempts a
       where a.status <> 'in_progress' and a.submitted_at >= v_from
      union all
      select p.test_id, p.user_id, p.score from public.paper_entries p where p.created_at >= v_from
    )
    select t.id, t.title, t.target_classes, t.target_groups, t.ends_at, t.is_paper, count(*) as n,
           round(avg(res.score / nullif(public.test_total(t.questions), 0) * 100)) as pct
      from res join public.tests t on t.id = res.test_id
     group by t.id order by max(t.created_at) desc limit 8
  loop
    n := n + 1;
    v_tests := v_tests || format(E'\n • %s%s — %s nəfər, orta <b>%s%%</b>', public.tg_esc(r.title), case when r.is_paper then ' 📝' else '' end, r.n, coalesce(r.pct, 0));
    if r.ends_at is not null and r.ends_at < now() and not r.is_paper then
      v_tests := v_tests || coalesce((
        select case when count(*) > 0 then format(' · yazmayan: %s', count(*)) else '' end
          from public.profiles s
         where s.role = 'student' and s.status = 'approved'
           and public.test_target_ok(r.target_classes, r.target_groups, s.id, s.class_name)
           and not exists (select 1 from public.attempts a where a.test_id = r.id and a.user_id = s.id)), '');
    end if;
  end loop;
  if n > 0 then v_lines := v_lines || ('📝 <b>Sınaqlar</b>' || v_tests); end if;

  -- həftənin ən yaxşısı (ən azı 1 sınaq)
  select p.full_name, round(avg(a.score / nullif(public.test_total(t.questions), 0) * 100)) as pct
    into v_best
    from public.attempts a join public.tests t on t.id = a.test_id join public.profiles p on p.id = a.user_id
   where a.status = 'graded' and a.submitted_at >= v_from and public.test_total(t.questions) > 0
   group by p.id order by 2 desc nulls last limit 1;
  if v_best.full_name is not null then
    v_lines := v_lines || format('🏆 Həftənin ən yaxşı nəticəsi: <b>%s</b> (%s%%)', public.tg_esc(v_best.full_name), v_best.pct);
  end if;

  -- ev tapşırıqları (son tarixi bu həftə olan və ya hələ açıq olanlar)
  n := 0;
  for r in
    select h.id, h.title, h.due_at, h.target_classes,
           (select count(*) from public.hw_submissions s where s.homework_id = h.id) as sent,
           (select count(*) from public.hw_submissions s where s.homework_id = h.id and h.due_at is not null and s.submitted_at > h.due_at) as late,
           (select count(*) from public.profiles p where p.role = 'student' and p.status = 'approved' and public.target_ok(h.target_classes, p.class_name)) as total
      from public.homework h
     where h.is_published and (h.created_at >= v_from or (h.due_at is not null and h.due_at >= v_from))
     order by h.created_at desc limit 6
  loop
    n := n + 1;
    v_hws := v_hws || format(E'\n • %s — %s/%s göndərib%s', public.tg_esc(r.title), r.sent, r.total,
      case when r.late > 0 then format(' · gecikən: %s', r.late) else '' end);
  end loop;
  if n > 0 then v_lines := v_lines || ('📚 <b>Ev tapşırıqları</b>' || v_hws); end if;

  -- yoxlanılmalı işlər
  select (select count(*) from public.attempts where status = 'submitted') + (select count(*) from public.paper_entries where status = 'submitted') into v_ess;
  select count(*) into v_hw_ungraded from public.hw_submissions where grade is null;
  select count(*) into v_unread from public.messages where sender = 'student' and not read_by_teacher;
  if v_ess + v_hw_ungraded + v_unread > 0 then
    v_lines := v_lines || format('✍️ <b>Səni gözləyir:</b>%s%s%s',
      case when v_ess > 0 then format(' %s esse', v_ess) else '' end,
      case when v_hw_ungraded > 0 then format('%s %s ev tapşırığı', case when v_ess > 0 then ' ·' else '' end, v_hw_ungraded) else '' end,
      case when v_unread > 0 then format('%s %s oxunmamış mesaj', case when v_ess + v_hw_ungraded > 0 then ' ·' else '' end, v_unread) else '' end);
  end if;

  -- pozuntular, viktorina, davamiyyət
  select count(*), count(distinct user_id) into v_viol, v_viol_users
    from public.violations where created_at >= v_from and counted and not cancelled;
  if v_viol > 0 then v_lines := v_lines || format('⚠️ Pozuntu: %s (%s şagird)', v_viol, v_viol_users); end if;
  select count(*) into v_live from public.live_sessions where created_at >= v_from;
  if v_live > 0 then v_lines := v_lines || format('🎮 Canlı viktorina: %s dəfə', v_live); end if;
  select round(avg(case when status in ('present', 'late') then 100 else 0 end)) into v_att
    from public.attendance where att_date >= (now() at time zone 'Asia/Baku')::date - 7;
  if v_att is not null then v_lines := v_lines || format('✅ Davamiyyət: orta %s%%', v_att); end if;

  if cardinality(v_lines) <= 2 then v_lines := v_lines || 'Bu həftə saytda aktivlik olmayıb.'::text; end if;
  return array_to_string(v_lines, E'\n\n');
end;
$$;
revoke execute on function public.weekly_report_text() from public, anon, authenticated;
