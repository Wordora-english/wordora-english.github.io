-- =====================================================================
--  WORDORA — "İnterneti söndürüb sınaqdan çıxmaq" açığının bağlanması
--  1) İnternet yoxdursa, pozuntu telefonda saxlanır və internet qayıdan kimi
--     göndərilir (vaxtı ilə birlikdə, "internet söndürülmüşdü" qeydi ilə).
--  2) Server özü yoxlayır: sınaq gedərkən sayt hər 15 saniyədə serverə
--     "buradayam" deyir. 40 saniyədən çox səs gəlmirsə, bu boşluq qeyd olunur
--     (telefondan bunu gizlətmək mümkün deyil).
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.violations add column if not exists happened_at timestamptz;   -- telefonda baş verdiyi vaxt
alter table public.violations add column if not exists offline     boolean not null default false;

-- Pozuntu: indi "nə vaxt baş verdi" və "internet var idimi" də qəbul edir
drop function if exists public.report_violation(text, text, text);
create or replace function public.report_violation(p_kind text, p_details text default null, p_page text default null,
                                                   p_happened_at timestamptz default null, p_offline boolean default false)
returns json
language plpgsql security definer set search_path = ''
as $$
declare
  v_p       public.profiles;
  v_max     int := coalesce(public.get_setting('max_warnings', '2')::int, 2);
  v_counted boolean := true;
  v_blocked boolean := false;
  v_warn    int;
  v_at      timestamptz := least(greatest(coalesce(p_happened_at, now()), now() - interval '12 hours'), now());
  v_off     boolean := coalesce(p_offline, false);
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
                   and abs(extract(epoch from (coalesce(happened_at, created_at) - v_at))) < 15) then
    v_counted := false;
  end if;

  insert into public.violations (user_id, kind, details, page, ip, counted, happened_at, offline)
  values (auth.uid(), p_kind,
          left(case when v_off then '📵 İnternet söndürülmüşdü. ' else '' end || coalesce(p_details, ''), 300),
          left(p_page, 120), public.client_ip(), v_counted, v_at, v_off);

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
      (case when v_off then '📵 <b>İnterneti söndürüb çıxıb</b> (' || to_char(v_at at time zone 'Asia/Baku', 'HH24:MI:SS') || ')' || chr(10) else '' end) ||
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
revoke execute on function public.report_violation(text, text, text, timestamptz, boolean) from public, anon;
grant  execute on function public.report_violation(text, text, text, timestamptz, boolean) to authenticated;

-- =====================================================================
-- Server tərəfi: "buradayam" siqnalı və əlaqə boşluqları
-- =====================================================================
alter table public.attempts add column if not exists last_ping timestamptz;

create table if not exists public.attempt_gaps (
  id         bigint generated always as identity primary key,
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  gap_from   timestamptz not null,
  gap_to     timestamptz not null,
  seconds    int not null
);
create index if not exists attempt_gaps_attempt_idx on public.attempt_gaps (attempt_id);
alter table public.attempt_gaps enable row level security;
drop policy if exists "gaps_admin" on public.attempt_gaps;
create policy "gaps_admin" on public.attempt_gaps for select to authenticated using (public.is_admin());
revoke all on public.attempt_gaps from anon;

create or replace function public.exam_ping(p_attempt uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts;
begin
  select * into v_a from public.attempts
   where id = p_attempt and user_id = auth.uid() and status = 'in_progress' for update;
  if not found then return; end if;
  if v_a.last_ping is not null and now() - v_a.last_ping > interval '40 seconds' then
    insert into public.attempt_gaps (attempt_id, user_id, gap_from, gap_to, seconds)
    values (v_a.id, v_a.user_id, v_a.last_ping, now(), extract(epoch from now() - v_a.last_ping)::int);
  end if;
  update public.attempts set last_ping = now() where id = v_a.id;
end;
$$;
revoke execute on function public.exam_ping(uuid) from public, anon;
grant  execute on function public.exam_ping(uuid) to authenticated;

-- Təhvil anında da yoxla: son siqnaldan təhvilə qədər uzun boşluq olubsa, yaz
create or replace function public.attempt_final_gap()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v_end timestamptz;
begin
  if old.status = 'in_progress' and new.status <> 'in_progress' and old.last_ping is not null then
    v_end := least(coalesce(new.submitted_at, now()), now());
    if v_end - old.last_ping > interval '40 seconds' then
      insert into public.attempt_gaps (attempt_id, user_id, gap_from, gap_to, seconds)
      values (new.id, new.user_id, old.last_ping, v_end, extract(epoch from v_end - old.last_ping)::int);
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists attempt_final_gap on public.attempts;
create trigger attempt_final_gap after update of status on public.attempts
  for each row execute function public.attempt_final_gap();
