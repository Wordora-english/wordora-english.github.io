-- =====================================================================
--  WORDORA — 6-cı mərhələ (1-ci hissə): sınaqda dinləmə (audio)
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

alter table public.tests    add column if not exists audio_path      text;
alter table public.tests    add column if not exists audio_max_plays int not null default 2;   -- 0 = limitsiz
alter table public.attempts add column if not exists audio_plays     int not null default 0;

-- "tests" bucket-ə audio faylları da icazə ver (maks. 50 MB)
update storage.buckets
   set allowed_mime_types = array['application/pdf', 'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a',
                                  'audio/aac', 'audio/wav', 'audio/x-wav', 'audio/ogg', 'audio/webm']
 where id = 'tests';

-- Şagird PDF-ə və audioya yalnız sınaq gedən müddətdə çata bilər
create or replace function public.can_read_test_file(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.tests t
      join public.attempts a on a.test_id = t.id
     where (t.pdf_path = p_name or t.audio_path = p_name)
       and a.user_id = auth.uid()
       and a.status = 'in_progress'
       and now() <= a.deadline + interval '30 seconds'
  );
$$;

-- Dinləmə: hər basış serverdə sayılır (səhifəni yeniləmək limiti sıfırlamır)
create or replace function public.test_audio_play(p_attempt uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_a public.attempts; v_t public.tests;
begin
  select * into v_a from public.attempts
   where id = p_attempt and user_id = auth.uid() and status = 'in_progress'
     and now() <= deadline + interval '30 seconds'
   for update;
  if not found then raise exception 'Sınaq aktiv deyil'; end if;
  select * into v_t from public.tests where id = v_a.test_id;
  if v_t.audio_path is null then raise exception 'Bu sınaqda dinləmə yoxdur'; end if;
  if v_t.audio_max_plays > 0 and v_a.audio_plays >= v_t.audio_max_plays then
    return json_build_object('allowed', false, 'plays', v_a.audio_plays, 'max', v_t.audio_max_plays);
  end if;
  update public.attempts set audio_plays = audio_plays + 1 where id = p_attempt;
  return json_build_object('allowed', true, 'plays', v_a.audio_plays + 1, 'max', v_t.audio_max_plays, 'path', v_t.audio_path);
end;
$$;
revoke execute on function public.test_audio_play(uuid) from public, anon;
grant  execute on function public.test_audio_play(uuid) to authenticated;

-- start_attempt: dinləmə məlumatını da qaytarır
create or replace function public.start_attempt(p_test uuid)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_t public.tests; v_a public.attempts; v_deadline timestamptz;
begin
  if not public.test_visible(p_test) then raise exception 'Bu sınaq sənin üçün açıq deyil'; end if;
  select * into v_t from public.tests where id = p_test;
  select * into v_a from public.attempts where test_id = p_test and user_id = auth.uid();

  if found then
    if v_a.status = 'in_progress' and now() > v_a.deadline + interval '30 seconds' then
      perform public.finalize_attempt(v_a.id);
      return json_build_object('status', 'done');
    end if;
    if v_a.status <> 'in_progress' then return json_build_object('status', 'done'); end if;
  else
    if v_t.starts_at is not null and now() < v_t.starts_at then raise exception 'Sınaq hələ başlamayıb'; end if;
    if v_t.ends_at   is not null and now() >= v_t.ends_at  then raise exception 'Sınağın vaxtı bitib'; end if;
    v_deadline := now() + make_interval(mins => v_t.duration_min);
    if v_t.ends_at is not null and v_t.ends_at < v_deadline then v_deadline := v_t.ends_at; end if;
    insert into public.attempts (test_id, user_id, deadline)
    values (p_test, auth.uid(), v_deadline) returning * into v_a;
  end if;

  return json_build_object(
    'status', 'in_progress',
    'attempt_id', v_a.id,
    'deadline', v_a.deadline,
    'server_now', now(),
    'answers', v_a.answers,
    'title', v_t.title,
    'questions', v_t.questions,
    'total', public.test_total(v_t.questions),
    'pdf_path', v_t.pdf_path,
    'has_audio', v_t.audio_path is not null,
    'audio_max', v_t.audio_max_plays,
    'audio_plays', v_a.audio_plays);
end;
$$;

