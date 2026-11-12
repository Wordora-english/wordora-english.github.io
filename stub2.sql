create or replace function public.variant_file(p_t public.tests, p_code text, p_field text)
returns text
language sql stable
as $$
  select case when coalesce(p_code, 'A') = 'A' then
           case p_field when 'pdf_path' then p_t.pdf_path when 'audio_path' then p_t.audio_path end
         when p_field = 'audio_path' then   -- variantın öz audiosu yoxdursa, A-nın audiosu
           coalesce((select nullif(v->>'audio_path', '') from jsonb_array_elements(p_t.variants) v where v->>'code' = p_code limit 1), p_t.audio_path)
         else (select nullif(v->>p_field, '') from jsonb_array_elements(p_t.variants) v where v->>'code' = p_code limit 1)
         end;
$$;
