-- =====================================================================
--  WORDORA — Gündəlik məşq 2.0
--   • 100 suallıq baza (qrammatika kitabının mövzuları üzrə): hər gün 5 sual —
--     1 asan + 2 orta + 2 çətin; hər şagirdə ayrı, əvvəl görmədikləri suallar
--   • Sınaq kimi: 6 dəqiqə vaxt, səhifədən çıxmaq / köçürmə → BUGÜNKÜ məşq 0 bal
--     (hesab bloklanmır, sabah yenə iştirak edə bilər); müəllimə Telegram xəbəri
--  Əvvəlcə 32-practice-push.sql işə salınmış olmalıdır.
--  Supabase → SQL Editor → New query → hamısını yapışdır → Run
--  (Faylı ikinci dəfə işə salmaq təhlükəsizdir.)
-- =====================================================================

create table if not exists public.daily_questions (
  id         serial primary key,
  code       text unique,
  topic      text not null,
  level      text not null check (level in ('easy', 'medium', 'hard')),
  text       text not null check (char_length(text) <= 400),
  opts       jsonb not null,
  ans        int  not null,
  expl       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.daily_questions enable row level security;
drop policy if exists "dq_admin" on public.daily_questions;
create policy "dq_admin" on public.daily_questions for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.daily_questions from anon;

-- 100 hazır sual (təkrar işə salınsa, təkrarlanmır)
insert into public.daily_questions (code, topic, level, text, opts, ans, expl) values
  ('N01', 'Nouns', 'easy', 'Two ___ were playing in the yard.', '["children", "childs", "childrens", "childes", "child"]'::jsonb, 0, '"child" sözünün cəmi qeyri-qaydalıdır: children.'),
  ('N02', 'Nouns', 'easy', 'My father bought two new ___ for the kitchen.', '["knives", "knifes", "knive", "knifs", "knifies"]'::jsonb, 0, '-f / -fe ilə bitən bir çox isimlərdə cəm -ves olur: knife → knives.'),
  ('N03', 'Nouns', 'medium', 'Choose the correct plural of "passer-by".', '["passers-by", "passer-bys", "passers-bys", "passer-by''s", "passer-bies"]'::jsonb, 0, 'Mürəkkəb isimlərdə cəm şəkilçisi əsas sözə artırılır: passer-by → passers-by.'),
  ('N04', 'Nouns', 'medium', 'Choose the uncountable noun.', '["advice", "suggestion", "idea", "tip", "opinion"]'::jsonb, 0, '"advice" sayılmayan isimdir: an advice yox, a piece of advice deyilir.'),
  ('N05', 'Nouns', 'medium', 'The news ___ very surprising yesterday.', '["was", "were", "are", "have been", "is"]'::jsonb, 0, '"news" -s ilə bitsə də, təkdir: The news was ... "yesterday" keçmiş zaman tələb edir.'),
  ('N06', 'Nouns', 'hard', 'This is ___ car.', '["my brother-in-law''s", "my brother''s-in-law", "my brothers-in-law", "my brother-in-laws''", "my brothers''-in-law"]'::jsonb, 0, 'Mürəkkəb isimlərdə yiyəlik -''s sözün sonuna artırılır: my brother-in-law''s car.'),
  ('N07', 'Nouns', 'hard', 'Mary and Ann own a shop together. We visited ___.', '["Mary and Ann''s shop", "Mary''s and Ann''s shop", "Mary and Ann shop", "Mary''s and Ann shop", "Marys and Anns shop"]'::jsonb, 0, 'Bir şey iki nəfərin birlikdə malıdırsa, -''s yalnız sonuncu ada artırılır: Mary and Ann''s shop.'),
  ('N08', 'Nouns', 'medium', 'We had a ___ walk after dinner.', '["ten-minute", "ten-minutes", "ten minute''s", "ten-minutes''", "tens-minute"]'::jsonb, 0, 'Defislə yazılan sifət kimi işlənən birləşmələrdə isim tək olur: a ten-minute walk.'),
  ('A01', 'Articles', 'easy', 'She is ___ honest girl.', '["an", "a", "the", "—", "one"]'::jsonb, 0, '"honest" sözündə h oxunmur, söz sait səslə başlayır: an honest girl.'),
  ('A02', 'Articles', 'easy', '___ sun rises in the east.', '["The", "A", "An", "—", "Some"]'::jsonb, 0, 'Təbiətdə yeganə olan əşyalar the ilə işlənir: the sun, the moon.'),
  ('A03', 'Articles', 'medium', 'He plays ___ guitar very well, but he doesn''t like ___ football.', '["the / —", "a / the", "— / the", "the / the", "a / —"]'::jsonb, 0, 'Musiqi alətləri the ilə (play the guitar), idman oyunları artiklsız işlənir (play football).'),
  ('A04', 'Articles', 'medium', 'We went to ___ Caspian Sea last summer.', '["the", "a", "—", "an", "one"]'::jsonb, 0, 'Dəniz, okean, çay adları the ilə işlənir: the Caspian Sea.'),
  ('A05', 'Articles', 'medium', '___ Mount Everest is the highest mountain in ___ world.', '["— / the", "The / the", "The / —", "A / the", "— / a"]'::jsonb, 0, 'Ayrıca dağ adları artiklsız (Mount Everest), "the world" isə həmişə the ilə işlənir.'),
  ('A06', 'Articles', 'hard', 'My mother went to ___ school to talk to my teacher.', '["the", "—", "a", "an", "some"]'::jsonb, 0, 'Məktəbə oxumaq üçün deyil, başqa məqsədlə gedəndə the işlənir: went to the school (to talk).'),
  ('A07', 'Articles', 'hard', '___ rich should help ___ poor.', '["The / the", "— / —", "A / a", "The / —", "— / the"]'::jsonb, 0, 'Sifət insanlar qrupunu bildirəndə the ilə işlənir: the rich, the poor.'),
  ('A08', 'Articles', 'hard', 'What ___ beautiful weather!', '["—", "a", "the", "an", "one"]'::jsonb, 0, '"weather" sayılmayan isimdir, ona görə What beautiful weather! — a işlənmir.'),
  ('P01', 'Pronouns', 'easy', 'This book is not mine. It is ___.', '["hers", "her", "she", "her''s", "herself"]'::jsonb, 0, 'İsimsiz yiyəlik əvəzliyi: mine, yours, his, hers, ours, theirs. "her''s" yazılışı yoxdur.'),
  ('P02', 'Pronouns', 'easy', '___ is my brother over there.', '["That", "This", "These", "Those", "Them"]'::jsonb, 0, 'Uzaqdakı (over there) tək şəxs/əşya üçün that işlənir.'),
  ('P03', 'Pronouns', 'medium', 'They enjoyed ___ at the party.', '["themselves", "themself", "theirselves", "them", "their"]'::jsonb, 0, '"enjoy oneself" — qayıdış əvəzliyi: they → themselves.'),
  ('P04', 'Pronouns', 'medium', 'There isn''t ___ milk in the fridge.', '["any", "some", "no", "none", "nothing"]'::jsonb, 0, 'İnkar cümlədə any işlənir: There isn''t any milk (= There is no milk).'),
  ('P05', 'Pronouns', 'medium', '___ of the two answers is correct — both are wrong.', '["Neither", "None", "Either", "Both", "No"]'::jsonb, 0, 'İki şeydən heç biri — neither. None üçdən çox üçün işlənir.'),
  ('P06', 'Pronouns', 'medium', 'I have two sisters. ___ of them are married.', '["Both", "Each", "Every", "Either", "Every one"]'::jsonb, 0, 'İki nəfərin ikisi də — both, fel cəmdə: Both of them are ...'),
  ('P07', 'Pronouns', 'medium', 'I can''t find my keys. I''ve looked ___.', '["everywhere", "anywhere", "somewhere", "nowhere", "everything"]'::jsonb, 0, '"hər yerə baxmışam" — everywhere. nowhere inkar mənası verir, cümlə isə təsdiqdir.'),
  ('P08', 'Pronouns', 'hard', 'Help ___ to some cake, children!', '["yourselves", "yourself", "you", "your", "yours"]'::jsonb, 0, '"help oneself to" — özünə götürmək. Uşaqlara (cəm) müraciət: yourselves.'),
  ('P09', 'Pronouns', 'hard', '___ of my friends has a car, so we always walk.', '["None", "No one of", "Nothing", "Any", "Some"]'::jsonb, 0, '"of" ilə: None of my friends ... No one of / Nothing of işlənmir.'),
  ('P10', 'Pronouns', 'hard', 'You can take ___ book you like — they are all free.', '["any", "some", "no", "none", "each"]'::jsonb, 0, '"istənilən, hansını istəsən" mənasında təsdiq cümlədə any işlənir.'),
  ('J01', 'Adjectives & Adverbs', 'easy', 'Ann is ___ than her sister.', '["taller", "more tall", "tallest", "the tallest", "most tall"]'::jsonb, 0, 'Qısa sifətlərdə müqayisə dərəcəsi -er + than: taller than.'),
  ('J02', 'Adjectives & Adverbs', 'easy', 'This is the ___ day of my life!', '["happiest", "happier", "most happy", "more happier", "happyest"]'::jsonb, 0, '-y ilə bitən sifət: y → i + est: the happiest.'),
  ('J03', 'Adjectives & Adverbs', 'medium', 'My brother drives very ___.', '["carefully", "careful", "care", "carefuly", "more careful"]'::jsonb, 0, 'Feli (drives) təsvir edən zərflik lazımdır: careful + ly = carefully.'),
  ('J04', 'Adjectives & Adverbs', 'medium', 'The film was ___ than I expected.', '["worse", "bad", "worst", "badder", "more bad"]'::jsonb, 0, 'bad – worse – the worst (qeyri-qaydalı). than ilə müqayisə dərəcəsi: worse.'),
  ('J05', 'Adjectives & Adverbs', 'medium', 'She bought a ___ table.', '["beautiful old wooden", "wooden old beautiful", "old beautiful wooden", "beautiful wooden old", "wooden beautiful old"]'::jsonb, 0, 'Sifətlərin sırası: fikir (beautiful) → yaş (old) → material (wooden).'),
  ('J06', 'Adjectives & Adverbs', 'hard', 'The ___ you study, the ___ results you get.', '["more / better", "most / best", "more / good", "much / better", "many / best"]'::jsonb, 0, '"Nə qədər çox..., o qədər yaxşı": The more ..., the better ...'),
  ('J07', 'Adjectives & Adverbs', 'hard', 'He works ___ and rarely takes a break.', '["hard", "hardly", "hardy", "harder than", "hardest"]'::jsonb, 0, 'hard — həm sifət, həm zərf ("çox, ciddi"). hardly = "demək olar ki, heç".'),
  ('J08', 'Adjectives & Adverbs', 'medium', 'This box is ___ heavy for me to carry.', '["too", "enough", "very much", "so much", "such"]'::jsonb, 0, 'too + sifət + for/to: "həddindən artıq" — too heavy to carry.'),
  ('J09', 'Adjectives & Adverbs', 'hard', 'She is not old ___ to drive a car.', '["enough", "too", "so", "such", "very"]'::jsonb, 0, 'enough sifətdən SONRA gəlir: old enough to drive.'),
  ('Q01', 'Quantifiers', 'easy', 'How ___ apples do you want?', '["many", "much", "a lot", "lot", "few"]'::jsonb, 0, 'Sayılan isimlərlə (apples) how many işlənir.'),
  ('Q02', 'Quantifiers', 'easy', 'There is ___ water in the glass.', '["a little", "a few", "many", "few", "several"]'::jsonb, 0, 'Sayılmayan isimlə (water) a little işlənir; a few / many / several sayılanlar üçündür.'),
  ('Q03', 'Quantifiers', 'medium', 'He has ___ friends, so he often feels lonely.', '["few", "a few", "little", "a little", "much"]'::jsonb, 0, 'few = "az, demək olar ki, yox" (mənfi məna). a few = "bir neçə" (müsbət). Tənhalıq mənfi mənadır.'),
  ('Q04', 'Quantifiers', 'medium', 'We have ___ time left, so let''s hurry.', '["little", "few", "a few", "many", "much"]'::jsonb, 0, 'time sayılmayan isimdir; "az vaxt qalıb, tələsək" — little.'),
  ('Q05', 'Quantifiers', 'hard', '___ students in our class passed the exam; only two failed.', '["Most", "Most of", "The most", "Almost", "Mostly"]'::jsonb, 0, 'Most + isim (artiklsız): Most students. "Most of" isə the/my/these ilə işlənir: most of the students.'),
  ('Q06', 'Quantifiers', 'hard', 'There were ___ people at the concert that we couldn''t find seats.', '["so many", "so much", "such many", "such a lot", "too many"]'::jsonb, 0, 'so many + sayılan isim + that ... (nəticə). such a lot OF people olardı.'),
  ('Q07', 'Quantifiers', 'medium', 'I have ___ money than you.', '["less", "fewer", "little", "few", "least"]'::jsonb, 0, 'Sayılmayan isimlə (money) müqayisədə less than; fewer sayılanlar üçündür.'),
  ('S01', 'So do I / Neither do I', 'easy', '— I like ice cream. — ___', '["So do I.", "So am I.", "Neither do I.", "So I do.", "Neither am I."]'::jsonb, 0, 'Təsdiq cümləyə razılıq: So + köməkçi fel + mən. like → do: So do I.'),
  ('S02', 'So do I / Neither do I', 'medium', '— I can''t swim. — ___', '["Neither can I.", "So can I.", "Neither can''t I.", "So can''t I.", "Either can I."]'::jsonb, 0, 'İnkar cümləyə razılıq: Neither + köməkçi fel (təsdiq formada) + I: Neither can I.'),
  ('S03', 'So do I / Neither do I', 'medium', '— She has been to London. — ___', '["So have I.", "So did I.", "So has I.", "So I have.", "Neither have I."]'::jsonb, 0, 'Köməkçi fel təkrar olunur: has been → So have I (I ilə have).'),
  ('S04', 'So do I / Neither do I', 'hard', '— Tom didn''t go to the party. — ___', '["Neither did I.", "So didn''t I.", "Neither didn''t I.", "So did I.", "I didn''t too."]'::jsonb, 0, 'Keçmişdə inkar: Neither did I (ikiqat inkar olmaz). "I didn''t either" də düzdür.'),
  ('S05', 'So do I / Neither do I', 'hard', '— I was tired yesterday. — ___', '["So was I.", "So did I.", "So were I.", "Neither was I.", "So had I."]'::jsonb, 0, 'to be fel olanda o təkrar olunur: was → So was I.'),
  ('T01', 'Tense Forms', 'easy', 'Look! The children ___ in the garden.', '["are playing", "play", "plays", "played", "have played"]'::jsonb, 0, '"Look!" — hərəkət indi baş verir: Present Continuous.'),
  ('T02', 'Tense Forms', 'easy', 'She usually ___ to school by bus.', '["goes", "go", "is going", "going", "have gone"]'::jsonb, 0, 'usually — adət: Present Simple, she ilə -es: goes.'),
  ('T03', 'Tense Forms', 'easy', 'I ___ my homework yesterday evening.', '["did", "do", "have done", "was do", "does"]'::jsonb, 0, 'yesterday — Past Simple: did.'),
  ('T04', 'Tense Forms', 'medium', 'When I came home, my mother ___ dinner, so I helped her.', '["was cooking", "is cooking", "has cooked", "cooks", "has been cooking"]'::jsonb, 0, 'Keçmişdə müəyyən anda davam edən hərəkət: Past Continuous — was cooking.'),
  ('T05', 'Tense Forms', 'medium', 'I ___ in Baku since 2015.', '["have lived", "live", "lived", "am living", "was living"]'::jsonb, 0, 'since + başlanğıc vaxt, indiyə qədər davam edir: Present Perfect — have lived.'),
  ('T06', 'Tense Forms', 'medium', 'By the time we arrived, the film ___.', '["had already started", "already started", "has already started", "was already starting", "already starts"]'::jsonb, 0, 'Keçmişdəki başqa hərəkətdən (arrived) əvvəl bitmiş hərəkət: Past Perfect.'),
  ('T07', 'Tense Forms', 'medium', 'This time tomorrow I ___ on the beach.', '["will be lying", "will lie", "am lying", "lie", "will have lain"]'::jsonb, 0, 'Gələcəkdə müəyyən anda davam edən hərəkət: Future Continuous — will be lying.'),
  ('T08', 'Tense Forms', 'hard', 'She ___ for two hours when the rain started.', '["had been walking", "has been walking", "is walking", "walked", "has walked"]'::jsonb, 0, 'Keçmişdəki andan (rain started) əvvəl başlayıb müddətcə davam edən: Past Perfect Continuous.'),
  ('T09', 'Tense Forms', 'hard', 'By next June, I ___ at this school for ten years.', '["will have worked", "will work", "have worked", "will be working", "work"]'::jsonb, 0, 'By + gələcək vaxt + müddət: Future Perfect — will have worked.'),
  ('T10', 'Tense Forms', 'hard', 'He said that he ___ the book the day before.', '["had read", "has read", "reads", "will read", "is reading"]'::jsonb, 0, 'Zamanların uzlaşması: said + keçmişdən əvvəlki hərəkət (the day before) → Past Perfect.'),
  ('T11', 'Tense Forms', 'medium', 'I ___ this film three times already.', '["have seen", "saw", "see", "had seen", "am seeing"]'::jsonb, 0, 'Nəticə indiyə aiddir, vaxt göstərilmir (three times already): Present Perfect.'),
  ('T12', 'Tense Forms', 'medium', 'According to the timetable, the lesson ___ at 9 a.m. every Monday.', '["starts", "is starting", "has started", "started", "will be starting"]'::jsonb, 0, 'Cədvəl və adət (every Monday): Present Simple — starts.'),
  ('T13', 'Tense Forms', 'hard', 'I ___ for you for an hour! Where have you been?', '["have been waiting", "am waiting", "waited", "was waiting", "had waited"]'::jsonb, 0, 'İndiyə qədər müddətcə davam edən hərəkət (for an hour): Present Perfect Continuous.'),
  ('T14', 'Tense Forms', 'hard', 'She told me that she ___ to Paris the next week.', '["would go", "will go", "goes", "has gone", "had gone"]'::jsonb, 0, 'Zamanların uzlaşması: told + gələcək → Future in the Past: would go (the next week).'),
  ('C01', 'Conditional sentences', 'easy', 'If it rains tomorrow, we ___ at home.', '["will stay", "would stay", "stayed", "would have stayed", "staying"]'::jsonb, 0, 'Real şərt (1-ci növ): If + Present Simple, will + fel.'),
  ('C02', 'Conditional sentences', 'medium', 'If I ___ rich, I would travel around the world.', '["were", "am", "will be", "had been", "be"]'::jsonb, 0, 'Qeyri-real indiki şərt (2-ci növ): If + Past Simple (to be → were), would + fel.'),
  ('C03', 'Conditional sentences', 'medium', 'If you heat ice, it ___.', '["melts", "melted", "would melt", "had melted", "melting"]'::jsonb, 0, 'Ümumi həqiqət (0-cı növ): If + Present Simple, Present Simple.'),
  ('C04', 'Conditional sentences', 'hard', 'If he ___ harder, he would have passed the exam.', '["had studied", "studied", "has studied", "would study", "studies"]'::jsonb, 0, 'Keçmişə aid qeyri-real şərt (3-cü növ): If + Past Perfect, would have + V3.'),
  ('C05', 'Conditional sentences', 'hard', 'I wish I ___ the answer now.', '["knew", "know", "had known", "will know", "would know"]'::jsonb, 0, 'I wish + indiki arzu (now): Past Simple — knew.'),
  ('C06', 'Conditional sentences', 'hard', 'If I had taken the medicine yesterday, I ___ better now.', '["would feel", "would have felt", "will feel", "felt", "had felt"]'::jsonb, 0, 'Qarışıq şərt: keçmiş şərt (had taken), indiki nəticə (now) → would feel.'),
  ('C07', 'Conditional sentences', 'medium', 'Unless you hurry, you ___ the bus.', '["will miss", "miss", "would miss", "missed", "won''t miss"]'::jsonb, 0, 'unless = if not. Real şərt: Unless + Present Simple, will + fel.'),
  ('C08', 'Conditional sentences', 'hard', 'I wish I ___ so much money last weekend.', '["hadn''t spent", "didn''t spend", "haven''t spent", "wouldn''t spend", "don''t spend"]'::jsonb, 0, 'Keçmişə təəssüf (last weekend): I wish + Past Perfect — hadn''t spent.'),
  ('V01', 'Passive Voice', 'easy', 'English ___ all over the world.', '["is spoken", "speaks", "is speaking", "spoken", "speak"]'::jsonb, 0, 'Passiv: be + V3. İngilis dili özü danışmır, onu danışırlar: is spoken.'),
  ('V02', 'Passive Voice', 'easy', 'This house ___ in 1990.', '["was built", "built", "is built", "has built", "was build"]'::jsonb, 0, 'Keçmişdə passiv: was/were + V3 — was built.'),
  ('V03', 'Passive Voice', 'medium', 'The letter ___ yet.', '["hasn''t been sent", "hasn''t sent", "wasn''t sent", "isn''t sending", "didn''t send"]'::jsonb, 0, 'yet — Present Perfect; passivdə: have/has been + V3.'),
  ('V04', 'Passive Voice', 'medium', 'A new bridge ___ in our city now.', '["is being built", "is built", "is building", "has been building", "builds"]'::jsonb, 0, 'İndi davam edən passiv: am/is/are being + V3.'),
  ('V05', 'Passive Voice', 'medium', 'Change into the passive: "They will finish the work tomorrow."', '["The work will be finished tomorrow.", "The work will finished tomorrow.", "The work will be finish tomorrow.", "The work is finished tomorrow.", "The work would be finished tomorrow."]'::jsonb, 0, 'Gələcək zamanda passiv: will be + V3.'),
  ('V06', 'Passive Voice', 'hard', 'Change into the passive: "Who wrote this poem?"', '["By whom was this poem written?", "Whom was this poem written?", "By whom this poem was written?", "Who this poem was written by?", "By whom was written this poem?"]'::jsonb, 0, 'Who sualı passivdə: By whom + was + mübtəda + V3? (sual sırası saxlanılır).'),
  ('V07', 'Passive Voice', 'hard', 'Change into the passive: "They gave her a present."', '["She was given a present.", "She was gave a present.", "She has given a present.", "She is given a present.", "A present was given to she."]'::jsonb, 0, 'İki tamamlıqlı fel: şəxs mübtəda olur — She was given a present (V3: given).'),
  ('V08', 'Passive Voice', 'medium', 'The room must ___ before the guests arrive.', '["be cleaned", "clean", "be cleaning", "cleaned", "have cleaning"]'::jsonb, 0, 'Modal fel ilə passiv: must + be + V3.'),
  ('V09', 'Passive Voice', 'hard', 'Which sentence can NOT be changed into the passive?', '["She arrived late.", "They built a school.", "He opened the door.", "We will invite Tom.", "People speak French here."]'::jsonb, 0, 'Təsirsiz fellər (arrive, come, sleep) tamamlıq qəbul etmir, passivə çevrilmir.'),
  ('V10', 'Passive Voice', 'hard', 'Change into the passive: "Did they invite you to the party?"', '["Were you invited to the party?", "Did you invited to the party?", "Were you invite to the party?", "Was you invited to the party?", "Did you be invited to the party?"]'::jsonb, 0, 'Past Simple sualı passivdə: Was/Were + mübtəda + V3? — Were you invited ...?'),
  ('M01', 'Modal Verbs', 'easy', 'You ___ smoke here. It''s forbidden.', '["mustn''t", "don''t have to", "needn''t", "can", "should"]'::jsonb, 0, 'Qadağa: mustn''t. don''t have to / needn''t = "lazım deyil".'),
  ('M02', 'Modal Verbs', 'easy', '___ I open the window? It''s very hot.', '["May", "Must", "Did", "Ought", "Have"]'::jsonb, 0, 'İcazə istəmək: May I ...? (Can I ...? də olar).'),
  ('M03', 'Modal Verbs', 'medium', 'You ___ wear a uniform; it''s optional.', '["don''t have to", "mustn''t", "can''t", "must", "have to"]'::jsonb, 0, 'Məcburi deyil (optional): don''t have to. mustn''t qadağa bildirir.'),
  ('M04', 'Modal Verbs', 'medium', 'He ___ be at home — the lights are on.', '["must", "can''t", "mustn''t", "needn''t", "has"]'::jsonb, 0, 'Güclü ehtimal (yəqin ki): must be.'),
  ('M05', 'Modal Verbs', 'hard', 'She ___ have gone to school today — it''s Sunday!', '["can''t", "must", "should", "has to", "ought"]'::jsonb, 0, 'Keçmişə aid mümkünsüzlük: can''t have + V3 ("getmiş ola bilməz").'),
  ('M06', 'Modal Verbs', 'hard', 'You ___ have told me earlier! Now it''s too late.', '["should", "must", "can", "need", "may"]'::jsonb, 0, 'Keçmişə irad (etməli idin, amma etmədin): should have + V3.'),
  ('M07', 'Modal Verbs', 'medium', 'When I was five, I ___ swim.', '["could", "can", "must", "may", "should"]'::jsonb, 0, 'Keçmişdə bacarıq: could.'),
  ('M08', 'Modal Verbs', 'hard', 'You ___ have bought milk — we already had two bottles.', '["needn''t", "mustn''t", "couldn''t", "had to", "don''t need"]'::jsonb, 0, 'Lazım olmayan, amma edilmiş iş: needn''t have + V3.'),
  ('K01', 'Conjunctions', 'easy', 'I was very tired, ___ I went to bed early.', '["so", "but", "because", "although", "or"]'::jsonb, 0, 'Nəticə bildirən bağlayıcı: so (ona görə də).'),
  ('K02', 'Conjunctions', 'medium', '___ it was raining, we went for a walk.', '["Although", "Because", "Despite", "So", "In spite"]'::jsonb, 0, 'Qarşılaşdırma + tam cümlə: Although + mübtəda + xəbər. Despite yalnız isimlə işlənir.'),
  ('K03', 'Conjunctions', 'medium', 'This is the girl ___ father is a famous doctor.', '["whose", "who", "whom", "which", "that"]'::jsonb, 0, 'Yiyəlik bildirən nisbi əvəzlik: whose (atası kim olan qız).'),
  ('K04', 'Conjunctions', 'hard', 'I don''t know ___ he will come or not.', '["whether", "that", "what", "unless", "which"]'::jsonb, 0, '"...-ib-məyəcəyini" (or not): whether.'),
  ('K05', 'Conjunctions', 'hard', '___ the bad weather, the plane landed safely.', '["In spite of", "Although", "Even though", "Despite of", "However"]'::jsonb, 0, 'İsimdən (the bad weather) əvvəl: In spite of / Despite. "Despite of" yanlışdır.'),
  ('K06', 'Conjunctions', 'medium', 'She can speak ___ English ___ French.', '["both / and", "either / nor", "neither / or", "not only / and", "both / or"]'::jsonb, 0, 'Cüt bağlayıcılar: both ... and, either ... or, neither ... nor.'),
  ('K07', 'Conjunctions', 'hard', 'The town ___ I grew up is very small.', '["where", "which", "that", "what", "whose"]'::jsonb, 0, 'Yer bildirən nisbi zərf: where (= in which). which/that olsa, sonda "in" lazım olardı.'),
  ('G01', 'Subject–Verb Agreement', 'easy', 'My brother and I ___ students.', '["are", "is", "am", "be", "was"]'::jsonb, 0, 'İki mübtəda (and ilə) — cəm: are.'),
  ('G02', 'Subject–Verb Agreement', 'medium', 'Everybody ___ here.', '["is", "are", "were", "have", "be"]'::jsonb, 0, 'everybody, someone, nobody — tək fel ilə işlənir: is.'),
  ('G03', 'Subject–Verb Agreement', 'medium', 'The police ___ looking for the thief.', '["are", "is", "was", "has", "does"]'::jsonb, 0, '"police" həmişə cəm fel ilə işlənir: The police are ...'),
  ('G04', 'Subject–Verb Agreement', 'hard', 'Neither the teacher nor the students ___ ready.', '["were", "was", "is", "has", "has been"]'::jsonb, 0, 'neither ... nor — fel ən yaxın mübtədaya uyğunlaşır (the students → were).'),
  ('G05', 'Subject–Verb Agreement', 'medium', 'Mathematics ___ my favourite subject.', '["is", "are", "were", "have", "be"]'::jsonb, 0, 'Elm adları -s ilə bitsə də təkdir: Mathematics is, Physics is.'),
  ('G06', 'Subject–Verb Agreement', 'hard', 'A number of students ___ absent today.', '["are", "is", "was", "has", "has been"]'::jsonb, 0, 'a number of + cəm isim → cəm fel (are). "The number of" isə tək fellə işlənir.')
on conflict (code) do nothing;

alter table public.daily_sets add column if not exists started_at  timestamptz;
alter table public.daily_sets add column if not exists voided      boolean not null default false;
alter table public.daily_sets add column if not exists void_reason text;
alter table public.daily_sets add column if not exists qids        int[];

-- Vaxt: 5 sual üçün 6 dəqiqə
create or replace function public.daily_limit_sec()
returns int language sql immutable set search_path = '' as $$ select 360; $$;

-- Bugünkü 5 sual: 1 asan + 2 orta + 2 çətin (şagirdin ən az gördüyü suallardan)
create or replace function public.daily_make2(p_user uuid)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_out jsonb := '[]'::jsonb; v_ids int[] := '{}'; lv record; q record; v_order int[]; v_new jsonb; k int; v_n int;
begin
  if (select count(*) from public.daily_questions where active) < 5 then
    return jsonb_build_object('questions', public.daily_make(), 'qids', null);   -- baza boşdursa — köhnə üsul (sözlər + sual bankı)
  end if;
  for lv in select * from (values ('easy', 1, 1), ('medium', 2, 2), ('hard', 2, 3), ('any', 5, 4)) v(l, n, o) order by o loop
    for q in
      select dq.* from public.daily_questions dq
        left join (select x.qid, count(*) as n from public.daily_sets d, unnest(d.qids) as x(qid)
                    where d.user_id = p_user group by x.qid) s on s.qid = dq.id
       where dq.active and (lv.l = 'any' or dq.level = lv.l) and not (dq.id = any (v_ids))
       order by coalesce(s.n, 0), random()
       limit greatest(0, case when lv.l = 'any' then 5 - cardinality(v_ids) else lv.n end)
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

create or replace function public.daily_streak(p_user uuid)
returns json
language sql stable security definer set search_path = ''
as $$
  with d as (select day from public.daily_sets where user_id = p_user and done_at is not null and not voided),
       g as (select day, day - (row_number() over (order by day))::int as grp from d),
       isl as (select max(day) as e, count(*) as n from g group by grp)
  select json_build_object(
    'current', coalesce((select n from isl where e >= public.baku_today() - 1 order by e desc limit 1), 0),
    'best',    coalesce((select max(n) from isl), 0),
    'total',   (select count(*) from d),
    'today',   exists (select 1 from d where day = public.baku_today()),
    'week',    (select json_agg(json_build_object('day', x::date, 'done', exists (select 1 from d where d.day = x::date)) order by x)
                  from generate_series(public.baku_today() - 6, public.baku_today(), interval '1 day') x));
$$;
revoke execute on function public.daily_streak(uuid) from public, anon, authenticated;

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
                                          'in_progress', v_s.started_at is not null and v_s.done_at is null))::json;
end;
$$;

-- Şagirdə göstərilən hal (cavablar yalnız bitəndən sonra; 0 bal alınıbsa — heç vaxt)
create or replace function public.daily_view(p_set public.daily_sets)
returns json
language sql stable security definer set search_path = ''
as $$
  select json_build_object(
    'day', p_set.day, 'done', p_set.done_at is not null,
    'started_at', p_set.started_at, 'limit', public.daily_limit_sec(),
    'left_ms', case when p_set.started_at is not null and p_set.done_at is null
                    then greatest(0, (extract(epoch from (p_set.started_at + make_interval(secs => public.daily_limit_sec()) - now())) * 1000)::bigint) end,
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
    'streak', public.daily_streak(p_set.user_id));
$$;
revoke execute on function public.daily_view(public.daily_sets) from public, anon, authenticated;

-- Vaxtı keçmiş, bitirilməmiş məşqi bağla (0 bal, amma "köçürmə" sayılmır)
create or replace function public.daily_close_late(p_user uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.daily_sets
     set done_at = now(), correct = 0, total = jsonb_array_length(questions), answers = '[]'::jsonb,
         results = (select coalesce(jsonb_agg(false), '[]'::jsonb) from jsonb_array_elements(questions)),
         void_reason = 'Vaxt bitdi — cavablar göndərilmədi'
   where user_id = p_user and done_at is null and started_at is not null
     and now() > started_at + make_interval(secs => public.daily_limit_sec() + 60);
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
    insert into public.daily_sets (user_id, day, questions, qids)
    values (v_p.id, public.baku_today(), v_m->'questions',
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

-- "Başla" düyməsi — vaxt buradan sayılır
create or replace function public.daily_start()
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets;
begin
  update public.daily_sets set started_at = now()
   where user_id = auth.uid() and day = public.baku_today() and started_at is null and done_at is null;
  select * into v_s from public.daily_sets where user_id = auth.uid() and day = public.baku_today();
  if not found then raise exception 'Bugünkü məşq tapılmadı — səhifəni yenilə'; end if;
  return public.daily_view(v_s);
end;
$$;

-- Qayda pozuntusu: bugünkü məşq 0 bal ilə bağlanır (hesab BLOKLANMIR)
create or replace function public.daily_void(p_reason text)
returns json
language plpgsql security definer set search_path = ''
as $$
declare v_s public.daily_sets; v_p public.profiles;
begin
  select * into v_s from public.daily_sets where user_id = auth.uid() and day = public.baku_today() for update;
  if not found then return null; end if;
  if v_s.done_at is not null or v_s.started_at is null then return public.daily_view(v_s); end if;
  update public.daily_sets
     set done_at = now(), voided = true, void_reason = left(coalesce(nullif(trim(p_reason), ''), 'Qayda pozuntusu'), 200),
         correct = 0, total = jsonb_array_length(questions), answers = '[]'::jsonb,
         results = (select coalesce(jsonb_agg(false), '[]'::jsonb) from jsonb_array_elements(questions))
   where user_id = v_s.user_id and day = v_s.day
  returning * into v_s;
  select * into v_p from public.profiles where id = auth.uid();
  perform public.notify_telegram(format(E'🔥 <b>Gündəlik məşq — 0 bal</b>\n%s (%s)\n%s',
    public.tg_esc(v_p.full_name), public.tg_esc(coalesce(v_p.class_name, '')), public.tg_esc(v_s.void_reason)));
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
  if now() > v_s.started_at + make_interval(secs => public.daily_limit_sec() + 45) then
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
revoke execute on function public.daily_start()          from public, anon;
revoke execute on function public.daily_void(text)       from public, anon;
grant  execute on function public.daily_start()          to authenticated;
grant  execute on function public.daily_void(text)       to authenticated;

-- Səhvlər dəftəri, mövzular, valideyn hesabatı: 0 bal alınmış (pozuntulu) günlər sayılmır
create or replace function public.my_mistakes()
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_out jsonb := '[]'::jsonb; r record; q jsonb; o jsonb; v_key jsonb; v_on public.test_online;
        n text; v_pass jsonb; v_found boolean; d record; i int; L text := 'ABCDE';
begin
  if v_uid is null then return '[]'::json; end if;
  -- sınaqlar (yalnız nəticəsi açılmışlar)
  for r in
    select t.id, t.title, t.questions, t.pdf_path, x.answers, x.details, x.variant, x.at_
      from (select test_id, answers, details, variant, coalesce(submitted_at, started_at) as at_
              from public.attempts where user_id = v_uid and status <> 'in_progress'
            union all
            select test_id, answers, details, variant, created_at from public.paper_entries where user_id = v_uid) x
      join public.tests t on t.id = x.test_id
     where t.results_released and x.details is not null
     order by x.at_ desc limit 40
  loop
    v_key := public.variant_key(r.id, r.variant);
    select * into v_on from public.test_online where test_id = r.id;
    v_found := found;
    for q in select value from jsonb_array_elements(r.questions) loop
      continue when q->>'type' = 'essay';
      n := q->>'n';
      continue when coalesce((r.details->n->>'frac')::numeric, 0) >= 1;
      continue when exists (select 1 from public.mistake_fixed f where f.user_id = v_uid and f.src = 'test' and f.ref = r.id::text and f.qn = n::int);
      o := null; v_pass := null;
      if v_found then
        select e into o from jsonb_array_elements(v_on.questions) e where e->>'n' = n limit 1;
        if o ? 'pid' then
          select jsonb_build_object('title', p->>'title', 'text', left(p->>'text', 4000)) into v_pass
            from jsonb_array_elements(v_on.passages) p where p->>'id' = o->>'pid' limit 1;
        end if;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'src', 'test', 'ref', r.id, 'title', r.title, 'at', r.at_, 'n', n::int,
        'type', q->>'type', 'options', coalesce(q->>'options', 'ABCDE'), 'parts', q->'parts',
        'my', r.answers->>n, 'key', v_key->>n,
        'text', o->>'text', 'opts', o->'opts', 'passage', v_pass));
      exit when jsonb_array_length(v_out) >= 200;
    end loop;
    exit when jsonb_array_length(v_out) >= 200;
  end loop;
  -- gündəlik məşq
  for d in select day, questions, answers, results from public.daily_sets
            where user_id = v_uid and done_at is not null and not voided order by day desc limit 60 loop
    i := 0;
    for q in select value from jsonb_array_elements(d.questions) loop
      if coalesce((d.results->>i)::boolean, true) = false
         and not exists (select 1 from public.mistake_fixed f where f.user_id = v_uid and f.src = 'daily' and f.ref = d.day::text and f.qn = i) then
        v_out := v_out || jsonb_build_array(jsonb_build_object(
          'src', 'daily', 'ref', d.day::text, 'title', 'Gündəlik məşq', 'at', d.day, 'n', i,
          'type', case when q->'opts' is null or jsonb_typeof(q->'opts') = 'null' then 'open' else 'choice' end,
          'options', substr(L, 1, greatest(2, coalesce(jsonb_array_length(case when jsonb_typeof(q->'opts') = 'array' then q->'opts' end), 0))),
          'my', case when jsonb_typeof(q->'opts') = 'array' and coalesce(d.answers->>i, '') ~ '^\d$'
                     then substr(L, (d.answers->>i)::int + 1, 1) else d.answers->>i end,
          'key', case when jsonb_typeof(q->'opts') = 'array' then substr(L, (q->>'ans')::int + 1, 1) else q->>'ans' end,
          'text', q->>'text', 'opts', case when jsonb_typeof(q->'opts') = 'array' then q->'opts' end, 'topic', q->>'topic', 'expl', q->>'expl'));
      end if;
      i := i + 1;
    end loop;
    exit when jsonb_array_length(v_out) >= 260;
  end loop;
  return v_out;
end;
$$;

create or replace function public.topic_facts(p_user uuid, p_from timestamptz default null, p_to timestamptz default null)
returns table (user_id uuid, topic text, frac numeric)
language sql stable security definer set search_path = ''
as $$
  with res as (
    select a.user_id, a.test_id, a.details, coalesce(a.submitted_at, a.started_at) as at_
      from public.attempts a where a.status <> 'in_progress' and a.details is not null
    union all
    select p.user_id, p.test_id, p.details, p.created_at
      from public.paper_entries p where p.user_id is not null and p.details is not null
  ), t as (
    select id, questions,
           case when jsonb_typeof(content->'topics') = 'array' and jsonb_array_length(content->'topics') > 0 then content->'topics'
                when jsonb_typeof(content->'sections') = 'array' then content->'sections' else '[]'::jsonb end as tp
      from public.tests where results_released or results_mode = 'instant'
  )
  select r.user_id, trim(tpc->>'name'), least(1, greatest(0, coalesce((r.details -> (q->>'n') ->> 'frac')::numeric, 0)))
    from res r join t on t.id = r.test_id
    cross join jsonb_array_elements(t.tp) tpc
    cross join jsonb_array_elements(t.questions) q
   where (q->>'n')::int between (tpc->>'from')::int and (tpc->>'to')::int
     and q->>'type' <> 'essay' and r.details ? (q->>'n')
     and (p_user is null or r.user_id = p_user)
     and (p_from is null or r.at_ >= p_from) and (p_to is null or r.at_ < p_to)
  union all
  select d.user_id, coalesce(q->>'topic', 'Sözlər'), case when (d.results->>((i - 1)::int))::boolean then 1 else 0 end
    from public.daily_sets d
    cross join jsonb_array_elements(d.questions) with ordinality as x(q, i)
   where d.done_at is not null and not d.voided
     and (p_user is null or d.user_id = p_user)
     and (p_from is null or d.done_at >= p_from) and (p_to is null or d.done_at < p_to);
$$;

create or replace function public.parent_month(p_code text, p_month date default null)
returns json
language plpgsql stable security definer set search_path = ''
as $$
declare v_p public.profiles; v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
        v_m date := date_trunc('month', coalesce(p_month, public.baku_today()))::date;
        v_from timestamptz; v_to timestamptz; v_pfrom timestamptz;
begin
  if length(v_code) <> 10 then raise exception 'Kod düzgün deyil'; end if;
  select * into v_p from public.profiles
   where replace(parent_code, '-', '') = v_code and role = 'student' and status in ('approved', 'blocked');
  if not found then raise exception 'Kod tapılmadı'; end if;
  v_from  := v_m::timestamp at time zone 'Asia/Baku';
  v_to    := (v_m + interval '1 month')::timestamp at time zone 'Asia/Baku';
  v_pfrom := (v_m - interval '1 month')::timestamp at time zone 'Asia/Baku';

  return (with res as (
      select a.user_id, a.test_id, a.score, coalesce(a.submitted_at, a.started_at) as at_, a.status
        from public.attempts a where a.status <> 'in_progress'
      union all
      select p.user_id, p.test_id, p.score, p.created_at, p.status from public.paper_entries p where p.user_id is not null
    ), scored as (
      select r.*, t.title, public.test_total(t.questions) as total, pr.class_name
        from res r join public.tests t on t.id = r.test_id join public.profiles pr on pr.id = r.user_id
       where (t.results_released or t.results_mode = 'instant') and r.score is not null and public.test_total(t.questions) > 0
    )
    select json_build_object(
      'name', v_p.full_name, 'class', v_p.class_name, 'month', v_m,
      'tests', (select coalesce(json_agg(json_build_object('title', title, 'date', at_, 'pct', round(score / total * 100)) order by at_), '[]'::json)
                  from scored where user_id = v_p.id and at_ >= v_from and at_ < v_to),
      'avg', (select round(avg(score / total * 100)) from scored where user_id = v_p.id and at_ >= v_from and at_ < v_to),
      'prev_avg', (select round(avg(score / total * 100)) from scored where user_id = v_p.id and at_ >= v_pfrom and at_ < v_from),
      'class_avg', (select round(avg(score / total * 100)) from scored where class_name = v_p.class_name and at_ >= v_from and at_ < v_to),
      'attendance', (select json_build_object('present', count(*) filter (where status = 'present'), 'late', count(*) filter (where status = 'late'),
                                              'absent', count(*) filter (where status = 'absent'), 'excused', count(*) filter (where status = 'excused'))
                       from public.attendance where user_id = v_p.id and att_date >= v_m and att_date < (v_m + interval '1 month')::date),
      'homework', (select json_build_object('given', count(*), 'done', count(s.id), 'avg', round(avg(s.grade / nullif(h.max_points, 0) * 100)))
                     from public.homework h left join public.hw_submissions s on s.homework_id = h.id and s.user_id = v_p.id
                    where h.is_published and h.created_at >= v_from and h.created_at < v_to and public.target_ok(h.target_classes, v_p.class_name)),
      'live', (select json_build_object('games', count(*), 'points', coalesce(sum(score), 0))
                 from public.live_players where user_id = v_p.id and joined_at >= v_from and joined_at < v_to),
      'daily', (select json_build_object('days', count(*), 'correct', coalesce(sum(correct), 0), 'total', coalesce(sum(total), 0),
                                        'voided', (select count(*) from public.daily_sets x where x.user_id = v_p.id and x.voided and x.day >= v_m and x.day < (v_m + interval '1 month')::date))
                  from public.daily_sets where user_id = v_p.id and done_at is not null and not voided and day >= v_m and day < (v_m + interval '1 month')::date),
      'streak', public.daily_streak(v_p.id),
      'topics', public.topics_of(v_p.id)));
end;
$$;
