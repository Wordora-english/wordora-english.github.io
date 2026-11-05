-- =====================================================================
--  WORDORA — Telegram bildirişləri bir neçə nəfərə
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--
--  Sonra yeni şəxsi əlavə etmək üçün (o, əvvəlcə bota Start basmalıdır):
--      select public.add_telegram_chat('ID');
--  Siyahıya baxmaq:
--      select public.list_telegram_chats();
--  Silmək:
--      select public.remove_telegram_chat('ID');
-- =====================================================================

-- Bildirişi siyahıdakı hər kəsə göndər (Id-lər vergüllə saxlanır)
create or replace function public.notify_telegram(p_text text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_token text;
  v_chats text;
  v_chat  text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_bot_token' limit 1;
  select decrypted_secret into v_chats from vault.decrypted_secrets where name = 'telegram_chat_id'   limit 1;
  if v_token is null or v_chats is null then return; end if;
  foreach v_chat in array string_to_array(v_chats, ',') loop
    v_chat := trim(v_chat);
    continue when v_chat = '';
    perform net.http_post(
      url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
      body    := jsonb_build_object('chat_id', v_chat, 'text', p_text, 'parse_mode', 'HTML',
                                    'disable_web_page_preview', true),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  end loop;
exception when others then
  return;
end;
$$;
revoke execute on function public.notify_telegram(text) from public, anon, authenticated;

create or replace function public.add_telegram_chat(p_chat text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_list text; v_new text := regexp_replace(coalesce(p_chat, ''), '[^0-9-]', '', 'g');
begin
  if v_new = '' then raise exception 'Id yalnız rəqəmlərdən ibarət olmalıdır'; end if;
  select id, decrypted_secret into v_id, v_list from vault.decrypted_secrets where name = 'telegram_chat_id';
  if v_id is null then raise exception 'Əvvəlcə set_telegram ilə botu qoş'; end if;
  if v_new = any (string_to_array(replace(v_list, ' ', ''), ',')) then return 'Bu Id artıq siyahıdadır'; end if;
  perform vault.update_secret(v_id, v_list || ',' || v_new);
  -- yalnız yeni şəxsə test mesajı
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || (select decrypted_secret from vault.decrypted_secrets where name = 'telegram_bot_token') || '/sendMessage',
    body    := jsonb_build_object('chat_id', v_new, 'text', '✅ Wordora bildirişləri bu hesaba da qoşuldu.'),
    headers := '{"Content-Type": "application/json"}'::jsonb);
  return 'Əlavə edildi. Yeni şəxsin telefonuna test mesajı getdi.';
end;
$$;

create or replace function public.remove_telegram_chat(p_chat text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_id uuid; v_list text; v_rm text := regexp_replace(coalesce(p_chat, ''), '[^0-9-]', '', 'g');
begin
  select id, decrypted_secret into v_id, v_list from vault.decrypted_secrets where name = 'telegram_chat_id';
  if v_id is null then return 'Siyahı boşdur'; end if;
  perform vault.update_secret(v_id, coalesce(array_to_string(array_remove(string_to_array(replace(v_list, ' ', ''), ','), v_rm), ','), ''));
  return 'Silindi';
end;
$$;

create or replace function public.list_telegram_chats()
returns text
language sql security definer set search_path = ''
as $$ select coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'telegram_chat_id'), 'boş'); $$;

revoke execute on function public.add_telegram_chat(text)    from public, anon, authenticated;
revoke execute on function public.remove_telegram_chat(text) from public, anon, authenticated;
revoke execute on function public.list_telegram_chats()      from public, anon, authenticated;
