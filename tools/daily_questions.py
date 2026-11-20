# Gündəlik məşq üçün 100 sual (qrammatika kitabının mövzuları üzrə).
# Hər sual: (kod, mövzu, səviyyə, sual, [variantlar], düzgün variantın indeksi, izah)
# Səviyyə: easy (asan) | medium (orta) | hard (çətin). Hər gün: 1 asan + 2 orta + 2 çətin.
# Bu fayldan supabase/33-daily-bank.sql yaradılır:  python3 tools/daily_questions.py

Q = [
# ---------------- Nouns ----------------
("N01", "Nouns", "easy", "Two ___ were playing in the yard.", ["children", "childs", "childrens", "childes", "child"], 0,
 "\"child\" sözünün cəmi qeyri-qaydalıdır: children."),
("N02", "Nouns", "easy", "My father bought two new ___ for the kitchen.", ["knives", "knifes", "knive", "knifs", "knifies"], 0,
 "-f / -fe ilə bitən bir çox isimlərdə cəm -ves olur: knife → knives."),
("N03", "Nouns", "medium", "Choose the correct plural of \"passer-by\".", ["passers-by", "passer-bys", "passers-bys", "passer-by's", "passer-bies"], 0,
 "Mürəkkəb isimlərdə cəm şəkilçisi əsas sözə artırılır: passer-by → passers-by."),
("N04", "Nouns", "medium", "Choose the uncountable noun.", ["advice", "suggestion", "idea", "tip", "opinion"], 0,
 "\"advice\" sayılmayan isimdir: an advice yox, a piece of advice deyilir."),
("N05", "Nouns", "medium", "The news ___ very surprising yesterday.", ["was", "were", "are", "have been", "is"], 0,
 "\"news\" -s ilə bitsə də, təkdir: The news was ... \"yesterday\" keçmiş zaman tələb edir."),
("N06", "Nouns", "hard", "This is ___ car.", ["my brother-in-law's", "my brother's-in-law", "my brothers-in-law", "my brother-in-laws'", "my brothers'-in-law"], 0,
 "Mürəkkəb isimlərdə yiyəlik -'s sözün sonuna artırılır: my brother-in-law's car."),
("N07", "Nouns", "hard", "Mary and Ann own a shop together. We visited ___.", ["Mary and Ann's shop", "Mary's and Ann's shop", "Mary and Ann shop", "Mary's and Ann shop", "Marys and Anns shop"], 0,
 "Bir şey iki nəfərin birlikdə malıdırsa, -'s yalnız sonuncu ada artırılır: Mary and Ann's shop."),
("N08", "Nouns", "medium", "We had a ___ walk after dinner.", ["ten-minute", "ten-minutes", "ten minute's", "ten-minutes'", "tens-minute"], 0,
 "Defislə yazılan sifət kimi işlənən birləşmələrdə isim tək olur: a ten-minute walk."),

# ---------------- Articles ----------------
("A01", "Articles", "easy", "She is ___ honest girl.", ["an", "a", "the", "—", "one"], 0,
 "\"honest\" sözündə h oxunmur, söz sait səslə başlayır: an honest girl."),
("A02", "Articles", "easy", "___ sun rises in the east.", ["The", "A", "An", "—", "Some"], 0,
 "Təbiətdə yeganə olan əşyalar the ilə işlənir: the sun, the moon."),
("A03", "Articles", "medium", "He plays ___ guitar very well, but he doesn't like ___ football.", ["the / —", "a / the", "— / the", "the / the", "a / —"], 0,
 "Musiqi alətləri the ilə (play the guitar), idman oyunları artiklsız işlənir (play football)."),
("A04", "Articles", "medium", "We went to ___ Caspian Sea last summer.", ["the", "a", "—", "an", "one"], 0,
 "Dəniz, okean, çay adları the ilə işlənir: the Caspian Sea."),
("A05", "Articles", "medium", "___ Mount Everest is the highest mountain in ___ world.", ["— / the", "The / the", "The / —", "A / the", "— / a"], 0,
 "Ayrıca dağ adları artiklsız (Mount Everest), \"the world\" isə həmişə the ilə işlənir."),
("A06", "Articles", "hard", "My mother went to ___ school to talk to my teacher.", ["the", "—", "a", "an", "some"], 0,
 "Məktəbə oxumaq üçün deyil, başqa məqsədlə gedəndə the işlənir: went to the school (to talk)."),
("A07", "Articles", "hard", "___ rich should help ___ poor.", ["The / the", "— / —", "A / a", "The / —", "— / the"], 0,
 "Sifət insanlar qrupunu bildirəndə the ilə işlənir: the rich, the poor."),
("A08", "Articles", "hard", "What ___ beautiful weather!", ["—", "a", "the", "an", "one"], 0,
 "\"weather\" sayılmayan isimdir, ona görə What beautiful weather! — a işlənmir."),

# ---------------- Pronouns ----------------
("P01", "Pronouns", "easy", "This book is not mine. It is ___.", ["hers", "her", "she", "her's", "herself"], 0,
 "İsimsiz yiyəlik əvəzliyi: mine, yours, his, hers, ours, theirs. \"her's\" yazılışı yoxdur."),
("P02", "Pronouns", "easy", "___ is my brother over there.", ["That", "This", "These", "Those", "Them"], 0,
 "Uzaqdakı (over there) tək şəxs/əşya üçün that işlənir."),
("P03", "Pronouns", "medium", "They enjoyed ___ at the party.", ["themselves", "themself", "theirselves", "them", "their"], 0,
 "\"enjoy oneself\" — qayıdış əvəzliyi: they → themselves."),
("P04", "Pronouns", "medium", "There isn't ___ milk in the fridge.", ["any", "some", "no", "none", "nothing"], 0,
 "İnkar cümlədə any işlənir: There isn't any milk (= There is no milk)."),
("P05", "Pronouns", "medium", "___ of the two answers is correct — both are wrong.", ["Neither", "None", "Either", "Both", "No"], 0,
 "İki şeydən heç biri — neither. None üçdən çox üçün işlənir."),
("P06", "Pronouns", "medium", "I have two sisters. ___ of them are married.", ["Both", "Each", "Every", "Either", "Every one"], 0,
 "İki nəfərin ikisi də — both, fel cəmdə: Both of them are ..."),
("P07", "Pronouns", "medium", "I can't find my keys. I've looked ___.", ["everywhere", "anywhere", "somewhere", "nowhere", "everything"], 0,
 "\"hər yerə baxmışam\" — everywhere. nowhere inkar mənası verir, cümlə isə təsdiqdir."),
("P08", "Pronouns", "hard", "Help ___ to some cake, children!", ["yourselves", "yourself", "you", "your", "yours"], 0,
 "\"help oneself to\" — özünə götürmək. Uşaqlara (cəm) müraciət: yourselves."),
("P09", "Pronouns", "hard", "___ of my friends has a car, so we always walk.", ["None", "No one of", "Nothing", "Any", "Some"], 0,
 "\"of\" ilə: None of my friends ... No one of / Nothing of işlənmir."),
("P10", "Pronouns", "hard", "You can take ___ book you like — they are all free.", ["any", "some", "no", "none", "each"], 0,
 "\"istənilən, hansını istəsən\" mənasında təsdiq cümlədə any işlənir."),

# ---------------- Adjectives & Adverbs ----------------
("J01", "Adjectives & Adverbs", "easy", "Ann is ___ than her sister.", ["taller", "more tall", "tallest", "the tallest", "most tall"], 0,
 "Qısa sifətlərdə müqayisə dərəcəsi -er + than: taller than."),
("J02", "Adjectives & Adverbs", "easy", "This is the ___ day of my life!", ["happiest", "happier", "most happy", "more happier", "happyest"], 0,
 "-y ilə bitən sifət: y → i + est: the happiest."),
("J03", "Adjectives & Adverbs", "medium", "My brother drives very ___.", ["carefully", "careful", "care", "carefuly", "more careful"], 0,
 "Feli (drives) təsvir edən zərflik lazımdır: careful + ly = carefully."),
("J04", "Adjectives & Adverbs", "medium", "The film was ___ than I expected.", ["worse", "bad", "worst", "badder", "more bad"], 0,
 "bad – worse – the worst (qeyri-qaydalı). than ilə müqayisə dərəcəsi: worse."),
("J05", "Adjectives & Adverbs", "medium", "She bought a ___ table.", ["beautiful old wooden", "wooden old beautiful", "old beautiful wooden", "beautiful wooden old", "wooden beautiful old"], 0,
 "Sifətlərin sırası: fikir (beautiful) → yaş (old) → material (wooden)."),
("J06", "Adjectives & Adverbs", "hard", "The ___ you study, the ___ results you get.", ["more / better", "most / best", "more / good", "much / better", "many / best"], 0,
 "\"Nə qədər çox..., o qədər yaxşı\": The more ..., the better ..."),
("J07", "Adjectives & Adverbs", "hard", "He works ___ and rarely takes a break.", ["hard", "hardly", "hardy", "harder than", "hardest"], 0,
 "hard — həm sifət, həm zərf (\"çox, ciddi\"). hardly = \"demək olar ki, heç\"."),
("J08", "Adjectives & Adverbs", "medium", "This box is ___ heavy for me to carry.", ["too", "enough", "very much", "so much", "such"], 0,
 "too + sifət + for/to: \"həddindən artıq\" — too heavy to carry."),
("J09", "Adjectives & Adverbs", "hard", "She is not old ___ to drive a car.", ["enough", "too", "so", "such", "very"], 0,
 "enough sifətdən SONRA gəlir: old enough to drive."),

# ---------------- Quantifiers ----------------
("Q01", "Quantifiers", "easy", "How ___ apples do you want?", ["many", "much", "a lot", "lot", "few"], 0,
 "Sayılan isimlərlə (apples) how many işlənir."),
("Q02", "Quantifiers", "easy", "There is ___ water in the glass.", ["a little", "a few", "many", "few", "several"], 0,
 "Sayılmayan isimlə (water) a little işlənir; a few / many / several sayılanlar üçündür."),
("Q03", "Quantifiers", "medium", "He has ___ friends, so he often feels lonely.", ["few", "a few", "little", "a little", "much"], 0,
 "few = \"az, demək olar ki, yox\" (mənfi məna). a few = \"bir neçə\" (müsbət). Tənhalıq mənfi mənadır."),
("Q04", "Quantifiers", "medium", "We have ___ time left, so let's hurry.", ["little", "few", "a few", "many", "much"], 0,
 "time sayılmayan isimdir; \"az vaxt qalıb, tələsək\" — little."),
("Q05", "Quantifiers", "hard", "___ students in our class passed the exam; only two failed.", ["Most", "Most of", "The most", "Almost", "Mostly"], 0,
 "Most + isim (artiklsız): Most students. \"Most of\" isə the/my/these ilə işlənir: most of the students."),
("Q06", "Quantifiers", "hard", "There were ___ people at the concert that we couldn't find seats.", ["so many", "so much", "such many", "such a lot", "too many"], 0,
 "so many + sayılan isim + that ... (nəticə). such a lot OF people olardı."),
("Q07", "Quantifiers", "medium", "I have ___ money than you.", ["less", "fewer", "little", "few", "least"], 0,
 "Sayılmayan isimlə (money) müqayisədə less than; fewer sayılanlar üçündür."),

# ---------------- So do I / Neither do I ----------------
("S01", "So do I / Neither do I", "easy", "— I like ice cream. — ___", ["So do I.", "So am I.", "Neither do I.", "So I do.", "Neither am I."], 0,
 "Təsdiq cümləyə razılıq: So + köməkçi fel + mən. like → do: So do I."),
("S02", "So do I / Neither do I", "medium", "— I can't swim. — ___", ["Neither can I.", "So can I.", "Neither can't I.", "So can't I.", "Either can I."], 0,
 "İnkar cümləyə razılıq: Neither + köməkçi fel (təsdiq formada) + I: Neither can I."),
("S03", "So do I / Neither do I", "medium", "— She has been to London. — ___", ["So have I.", "So did I.", "So has I.", "So I have.", "Neither have I."], 0,
 "Köməkçi fel təkrar olunur: has been → So have I (I ilə have)."),
("S04", "So do I / Neither do I", "hard", "— Tom didn't go to the party. — ___", ["Neither did I.", "So didn't I.", "Neither didn't I.", "So did I.", "I didn't too."], 0,
 "Keçmişdə inkar: Neither did I (ikiqat inkar olmaz). \"I didn't either\" də düzdür."),
("S05", "So do I / Neither do I", "hard", "— I was tired yesterday. — ___", ["So was I.", "So did I.", "So were I.", "Neither was I.", "So had I."], 0,
 "to be fel olanda o təkrar olunur: was → So was I."),

# ---------------- Tense Forms ----------------
("T01", "Tense Forms", "easy", "Look! The children ___ in the garden.", ["are playing", "play", "plays", "played", "have played"], 0,
 "\"Look!\" — hərəkət indi baş verir: Present Continuous."),
("T02", "Tense Forms", "easy", "She usually ___ to school by bus.", ["goes", "go", "is going", "going", "have gone"], 0,
 "usually — adət: Present Simple, she ilə -es: goes."),
("T03", "Tense Forms", "easy", "I ___ my homework yesterday evening.", ["did", "do", "have done", "was do", "does"], 0,
 "yesterday — Past Simple: did."),
("T04", "Tense Forms", "medium", "When I came home, my mother ___ dinner, so I helped her.", ["was cooking", "is cooking", "has cooked", "cooks", "has been cooking"], 0,
 "Keçmişdə müəyyən anda davam edən hərəkət: Past Continuous — was cooking."),
("T05", "Tense Forms", "medium", "I ___ in Baku since 2015.", ["have lived", "live", "lived", "am living", "was living"], 0,
 "since + başlanğıc vaxt, indiyə qədər davam edir: Present Perfect — have lived."),
("T06", "Tense Forms", "medium", "By the time we arrived, the film ___.", ["had already started", "already started", "has already started", "was already starting", "already starts"], 0,
 "Keçmişdəki başqa hərəkətdən (arrived) əvvəl bitmiş hərəkət: Past Perfect."),
("T07", "Tense Forms", "medium", "This time tomorrow I ___ on the beach.", ["will be lying", "will lie", "am lying", "lie", "will have lain"], 0,
 "Gələcəkdə müəyyən anda davam edən hərəkət: Future Continuous — will be lying."),
("T08", "Tense Forms", "hard", "She ___ for two hours when the rain started.", ["had been walking", "has been walking", "is walking", "walked", "has walked"], 0,
 "Keçmişdəki andan (rain started) əvvəl başlayıb müddətcə davam edən: Past Perfect Continuous."),
("T09", "Tense Forms", "hard", "By next June, I ___ at this school for ten years.", ["will have worked", "will work", "have worked", "will be working", "work"], 0,
 "By + gələcək vaxt + müddət: Future Perfect — will have worked."),
("T10", "Tense Forms", "hard", "He said that he ___ the book the day before.", ["had read", "has read", "reads", "will read", "is reading"], 0,
 "Zamanların uzlaşması: said + keçmişdən əvvəlki hərəkət (the day before) → Past Perfect."),
("T11", "Tense Forms", "medium", "I ___ this film three times already.", ["have seen", "saw", "see", "had seen", "am seeing"], 0,
 "Nəticə indiyə aiddir, vaxt göstərilmir (three times already): Present Perfect."),
("T12", "Tense Forms", "medium", "According to the timetable, the lesson ___ at 9 a.m. every Monday.", ["starts", "is starting", "has started", "started", "will be starting"], 0,
 "Cədvəl və adət (every Monday): Present Simple — starts."),
("T13", "Tense Forms", "hard", "I ___ for you for an hour! Where have you been?", ["have been waiting", "am waiting", "waited", "was waiting", "had waited"], 0,
 "İndiyə qədər müddətcə davam edən hərəkət (for an hour): Present Perfect Continuous."),
("T14", "Tense Forms", "hard", "She told me that she ___ to Paris the next week.", ["would go", "will go", "goes", "has gone", "had gone"], 0,
 "Zamanların uzlaşması: told + gələcək → Future in the Past: would go (the next week)."),

# ---------------- Conditionals ----------------
("C01", "Conditional sentences", "easy", "If it rains tomorrow, we ___ at home.", ["will stay", "would stay", "stayed", "would have stayed", "staying"], 0,
 "Real şərt (1-ci növ): If + Present Simple, will + fel."),
("C02", "Conditional sentences", "medium", "If I ___ rich, I would travel around the world.", ["were", "am", "will be", "had been", "be"], 0,
 "Qeyri-real indiki şərt (2-ci növ): If + Past Simple (to be → were), would + fel."),
("C03", "Conditional sentences", "medium", "If you heat ice, it ___.", ["melts", "melted", "would melt", "had melted", "melting"], 0,
 "Ümumi həqiqət (0-cı növ): If + Present Simple, Present Simple."),
("C04", "Conditional sentences", "hard", "If he ___ harder, he would have passed the exam.", ["had studied", "studied", "has studied", "would study", "studies"], 0,
 "Keçmişə aid qeyri-real şərt (3-cü növ): If + Past Perfect, would have + V3."),
("C05", "Conditional sentences", "hard", "I wish I ___ the answer now.", ["knew", "know", "had known", "will know", "would know"], 0,
 "I wish + indiki arzu (now): Past Simple — knew."),
("C06", "Conditional sentences", "hard", "If I had taken the medicine yesterday, I ___ better now.", ["would feel", "would have felt", "will feel", "felt", "had felt"], 0,
 "Qarışıq şərt: keçmiş şərt (had taken), indiki nəticə (now) → would feel."),
("C07", "Conditional sentences", "medium", "Unless you hurry, you ___ the bus.", ["will miss", "miss", "would miss", "missed", "won't miss"], 0,
 "unless = if not. Real şərt: Unless + Present Simple, will + fel."),
("C08", "Conditional sentences", "hard", "I wish I ___ so much money last weekend.", ["hadn't spent", "didn't spend", "haven't spent", "wouldn't spend", "don't spend"], 0,
 "Keçmişə təəssüf (last weekend): I wish + Past Perfect — hadn't spent."),

# ---------------- Passive Voice ----------------
("V01", "Passive Voice", "easy", "English ___ all over the world.", ["is spoken", "speaks", "is speaking", "spoken", "speak"], 0,
 "Passiv: be + V3. İngilis dili özü danışmır, onu danışırlar: is spoken."),
("V02", "Passive Voice", "easy", "This house ___ in 1990.", ["was built", "built", "is built", "has built", "was build"], 0,
 "Keçmişdə passiv: was/were + V3 — was built."),
("V03", "Passive Voice", "medium", "The letter ___ yet.", ["hasn't been sent", "hasn't sent", "wasn't sent", "isn't sending", "didn't send"], 0,
 "yet — Present Perfect; passivdə: have/has been + V3."),
("V04", "Passive Voice", "medium", "A new bridge ___ in our city now.", ["is being built", "is built", "is building", "has been building", "builds"], 0,
 "İndi davam edən passiv: am/is/are being + V3."),
("V05", "Passive Voice", "medium", "Change into the passive: \"They will finish the work tomorrow.\"", ["The work will be finished tomorrow.", "The work will finished tomorrow.", "The work will be finish tomorrow.", "The work is finished tomorrow.", "The work would be finished tomorrow."], 0,
 "Gələcək zamanda passiv: will be + V3."),
("V06", "Passive Voice", "hard", "Change into the passive: \"Who wrote this poem?\"", ["By whom was this poem written?", "Whom was this poem written?", "By whom this poem was written?", "Who this poem was written by?", "By whom was written this poem?"], 0,
 "Who sualı passivdə: By whom + was + mübtəda + V3? (sual sırası saxlanılır)."),
("V07", "Passive Voice", "hard", "Change into the passive: \"They gave her a present.\"", ["She was given a present.", "She was gave a present.", "She has given a present.", "She is given a present.", "A present was given to she."], 0,
 "İki tamamlıqlı fel: şəxs mübtəda olur — She was given a present (V3: given)."),
("V08", "Passive Voice", "medium", "The room must ___ before the guests arrive.", ["be cleaned", "clean", "be cleaning", "cleaned", "have cleaning"], 0,
 "Modal fel ilə passiv: must + be + V3."),
("V09", "Passive Voice", "hard", "Which sentence can NOT be changed into the passive?", ["She arrived late.", "They built a school.", "He opened the door.", "We will invite Tom.", "People speak French here."], 0,
 "Təsirsiz fellər (arrive, come, sleep) tamamlıq qəbul etmir, passivə çevrilmir."),
("V10", "Passive Voice", "hard", "Change into the passive: \"Did they invite you to the party?\"", ["Were you invited to the party?", "Did you invited to the party?", "Were you invite to the party?", "Was you invited to the party?", "Did you be invited to the party?"], 0,
 "Past Simple sualı passivdə: Was/Were + mübtəda + V3? — Were you invited ...?"),

# ---------------- Modal Verbs ----------------
("M01", "Modal Verbs", "easy", "You ___ smoke here. It's forbidden.", ["mustn't", "don't have to", "needn't", "can", "should"], 0,
 "Qadağa: mustn't. don't have to / needn't = \"lazım deyil\"."),
("M02", "Modal Verbs", "easy", "___ I open the window? It's very hot.", ["May", "Must", "Did", "Ought", "Have"], 0,
 "İcazə istəmək: May I ...? (Can I ...? də olar)."),
("M03", "Modal Verbs", "medium", "You ___ wear a uniform; it's optional.", ["don't have to", "mustn't", "can't", "must", "have to"], 0,
 "Məcburi deyil (optional): don't have to. mustn't qadağa bildirir."),
("M04", "Modal Verbs", "medium", "He ___ be at home — the lights are on.", ["must", "can't", "mustn't", "needn't", "has"], 0,
 "Güclü ehtimal (yəqin ki): must be."),
("M05", "Modal Verbs", "hard", "She ___ have gone to school today — it's Sunday!", ["can't", "must", "should", "has to", "ought"], 0,
 "Keçmişə aid mümkünsüzlük: can't have + V3 (\"getmiş ola bilməz\")."),
("M06", "Modal Verbs", "hard", "You ___ have told me earlier! Now it's too late.", ["should", "must", "can", "need", "may"], 0,
 "Keçmişə irad (etməli idin, amma etmədin): should have + V3."),
("M07", "Modal Verbs", "medium", "When I was five, I ___ swim.", ["could", "can", "must", "may", "should"], 0,
 "Keçmişdə bacarıq: could."),
("M08", "Modal Verbs", "hard", "You ___ have bought milk — we already had two bottles.", ["needn't", "mustn't", "couldn't", "had to", "don't need"], 0,
 "Lazım olmayan, amma edilmiş iş: needn't have + V3."),

# ---------------- Conjunctions & Conjunctive Words ----------------
("K01", "Conjunctions", "easy", "I was very tired, ___ I went to bed early.", ["so", "but", "because", "although", "or"], 0,
 "Nəticə bildirən bağlayıcı: so (ona görə də)."),
("K02", "Conjunctions", "medium", "___ it was raining, we went for a walk.", ["Although", "Because", "Despite", "So", "In spite"], 0,
 "Qarşılaşdırma + tam cümlə: Although + mübtəda + xəbər. Despite yalnız isimlə işlənir."),
("K03", "Conjunctions", "medium", "This is the girl ___ father is a famous doctor.", ["whose", "who", "whom", "which", "that"], 0,
 "Yiyəlik bildirən nisbi əvəzlik: whose (atası kim olan qız)."),
("K04", "Conjunctions", "hard", "I don't know ___ he will come or not.", ["whether", "that", "what", "unless", "which"], 0,
 "\"...-ib-məyəcəyini\" (or not): whether."),
("K05", "Conjunctions", "hard", "___ the bad weather, the plane landed safely.", ["In spite of", "Although", "Even though", "Despite of", "However"], 0,
 "İsimdən (the bad weather) əvvəl: In spite of / Despite. \"Despite of\" yanlışdır."),
("K06", "Conjunctions", "medium", "She can speak ___ English ___ French.", ["both / and", "either / nor", "neither / or", "not only / and", "both / or"], 0,
 "Cüt bağlayıcılar: both ... and, either ... or, neither ... nor."),
("K07", "Conjunctions", "hard", "The town ___ I grew up is very small.", ["where", "which", "that", "what", "whose"], 0,
 "Yer bildirən nisbi zərf: where (= in which). which/that olsa, sonda \"in\" lazım olardı."),

# ---------------- Subject–Verb Agreement ----------------
("G01", "Subject–Verb Agreement", "easy", "My brother and I ___ students.", ["are", "is", "am", "be", "was"], 0,
 "İki mübtəda (and ilə) — cəm: are."),
("G02", "Subject–Verb Agreement", "medium", "Everybody ___ here.", ["is", "are", "were", "have", "be"], 0,
 "everybody, someone, nobody — tək fel ilə işlənir: is."),
("G03", "Subject–Verb Agreement", "medium", "The police ___ looking for the thief.", ["are", "is", "was", "has", "does"], 0,
 "\"police\" həmişə cəm fel ilə işlənir: The police are ..."),
("G04", "Subject–Verb Agreement", "hard", "Neither the teacher nor the students ___ ready.", ["were", "was", "is", "has", "has been"], 0,
 "neither ... nor — fel ən yaxın mübtədaya uyğunlaşır (the students → were)."),
("G05", "Subject–Verb Agreement", "medium", "Mathematics ___ my favourite subject.", ["is", "are", "were", "have", "be"], 0,
 "Elm adları -s ilə bitsə də təkdir: Mathematics is, Physics is."),
("G06", "Subject–Verb Agreement", "hard", "A number of students ___ absent today.", ["are", "is", "was", "has", "has been"], 0,
 "a number of + cəm isim → cəm fel (are). \"The number of\" isə tək fellə işlənir."),
]

assert len(Q) == 100, len(Q)
assert len({q[0] for q in Q}) == 100
for q in Q:
    assert q[2] in ("easy", "medium", "hard"), q
    assert len(q[4]) == 5 and len(set(q[4])) == 5, q
    assert 0 <= q[5] < 5

if __name__ == "__main__":
    import json, collections
    print(collections.Counter(q[2] for q in Q))
    def lit(s): return "'" + s.replace("'", "''") + "'"
    rows = []
    for code, topic, lvl, text, opts, ans, expl in Q:
        rows.append(f"  ({lit(code)}, {lit(topic)}, {lit(lvl)}, {lit(text)}, {lit(json.dumps(opts, ensure_ascii=False))}::jsonb, {ans}, {lit(expl)})")
    open("/tmp/daily_seed.sql", "w").write(
        "insert into public.daily_questions (code, topic, level, text, opts, ans, expl) values\n" + ",\n".join(rows) +
        "\non conflict (code) do nothing;\n")
    print("ok")
