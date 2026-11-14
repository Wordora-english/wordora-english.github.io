-- =====================================================================
--  WORDORA — Esseləri bir düymə ilə Claude-a yoxlatmaq
--  Anthropic API açarı gizli Vault-da saxlanır; yalnız ADMIN (müəllim)
--  öz brauzerindən istifadə edə bilir. Şagirdlər açarı heç vaxt görmür.
--  Açarı SQL-ə YAZMA — sayt özü soruşacaq (nəticələr səhifəsində).
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create or replace function public.admin_set_ai_key(p_key text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_key text := trim(coalesce(p_key, ''));
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  select id into v_id from vault.secrets where name = 'anthropic_api_key';
  if v_key = '' then
    if v_id is not null then delete from vault.secrets where id = v_id; end if;   -- açarı sil
    return;
  end if;
  if v_key !~ '^sk-ant-[A-Za-z0-9_\-]{20,}$' then raise exception 'Açar düzgün deyil (sk-ant- ilə başlamalıdır)'; end if;
  if v_id is null then perform vault.create_secret(v_key, 'anthropic_api_key');
  else perform vault.update_secret(v_id, v_key); end if;
end;
$$;

create or replace function public.admin_ai_key()
returns text
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Bu əməliyyat yalnız admin üçündür'; end if;
  return (select decrypted_secret from vault.decrypted_secrets where name = 'anthropic_api_key');
end;
$$;

revoke execute on function public.admin_set_ai_key(text) from public, anon;
revoke execute on function public.admin_ai_key()         from public, anon;
grant  execute on function public.admin_set_ai_key(text) to authenticated;
grant  execute on function public.admin_ai_key()         to authenticated;
