# Wordora — quraşdırma bələdçisi

Bu addımları bir dəfə edirsən. Hər şey pulsuzdur, heç bir yerdə kart istənmir.

---

> ⚠️ **Vacib:** `assets/js/config.js` faylındakı `EMAIL_DOMAIN = "aliqurbanovfh.github.io"` sətrini **dəyişmə**. Bu, saytın ünvanı deyil, şagird hesablarının daxili adıdır. Dəyişsə, köhnə hesablarla giriş işləməz.

## 1. Supabase layihəsini yarat

1. **supabase.com** → **Dashboard** → **New project**
2. **Name:** `wordora`
3. **Database password:** güclü şifrə yaz və **bir yerdə saxla** (gündəlik işdə lazım olmayacaq, amma itirmə).
4. **Region:** **Central EU (Frankfurt)** — Azərbaycana ən yaxındır.
5. **Create new project** → 1–2 dəqiqə gözlə.

## 2. Bazanı qur

1. Sol menyuda **SQL Editor** → **New query**
2. Bu repodakı `supabase/schema.sql` faylının **hamısını** kopyala, yapışdır.
3. **Run** düyməsini bas. "Success" yazılmalıdır.

## 3. Girişi tənzimlə

1. Sol menyuda **Authentication** → **Sign In / Providers** (və ya **Providers**) → **Email**
2. **Confirm email** — **SÖNDÜR** (vacibdir! Şagirdlər istifadəçi adı ilə girir, e-poçt təsdiqi lazım deyil).
3. **Minimum password length:** `8`
4. **Save**

## 4. Açarları götür

1. Sol menyuda **Project Settings** (dişli çarx) → **API Keys** / **Data API**
2. İki şeyi kopyala:
   - **Project URL** — `https://xxxx.supabase.co` kimi
   - **Publishable key** (`sb_publishable_...`) — köhnə layihələrdə adı **anon public** olur
3. Bu ikisini Claude-a göndər (və ya `assets/js/config.js` faylında özün yaz).

> ⚠️ **secret** və ya **service_role** açarını HEÇ VAXT heç kimə göndərmə və heç yerə yazma. O açar bazanın "ana açarıdır".

## 5. Öz admin hesabını yarat

1. Saytı aç: **https://wordora-english.github.io/**
2. **Qeydiyyat** → öz adınla qeydiyyatdan keç (məs. istifadəçi adı `gulnar`).
3. Supabase → **SQL Editor** → **New query** → bunu yaz (istifadəçi adını özününkü ilə əvəz et) → **Run**:

   ```sql
   update public.profiles set role = 'admin', status = 'approved', approved_at = now()
   where username = 'gulnar';
   ```
4. Saytdan çıx, yenidən daxil ol — **Admin panel** açılacaq.

## 6. Saytın "yatmaması" üçün (keep-alive)

1. GitHub → `wordora-english.github.io` reposu → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
2. İki secret əlavə et:
   - Name: `SUPABASE_URL` → Value: Project URL
   - Name: `SUPABASE_KEY` → Value: Publishable key
3. **Actions** tabı → **Supabase keep-alive** → **Run workflow** — yaşıl ✓ çıxmalıdır.

> Əgər repoda 60 gün heç bir dəyişiklik olmasa, GitHub bu işi dayandırıb e-poçt göndərə bilər. Belə olsa, **Actions** tabında **Enable workflow** düyməsini bas.

## 7. Materiallar, qoruma, sınaqlar və viktorina

Supabase → **SQL Editor** → **New query** → aşağıdakı faylları **ardıcıl**, hər birini ayrıca işə sal:

1. `supabase/02-materials.sql`
2. `supabase/03-security.sql`
3. `supabase/04-tests.sql`
4. `supabase/05-fix-test-pdf.sql`
5. `supabase/06-tor-fix.sql`
6. `supabase/07-password-live.sql`
7. `supabase/08-audio.sql`
8. `supabase/09-words-year-rank.sql`
9. `supabase/10-attendance-messages-parent.sql`
10. `supabase/11-telegram-multi.sql`
11. `supabase/12-homework-bank-online.sql`
12. `supabase/13-sections-rubric-storage.sql`
13. `supabase/14-magistratura.sql`
14. `supabase/15-delete-retake.sql`
15. `supabase/16-variants.sql`
16. `supabase/17-paper-tests.sql`
17. `supabase/18-weekly-report.sql`
18. `supabase/19-backup-errors.sql` — sonda göstərilən **açarı** GitHub-a `BACKUP_SECRET` kimi yaz (aşağıya bax)
19. `supabase/20-study-groups.sql`
20. `supabase/21-attendance-telegram.sql`
21. `supabase/22-chat.sql`
22. `supabase/23-test-groups.sql` — sınağı dərs qruplarına təyin etmək

Hər dəfə: GitHub-da faylı aç → **Copy raw file** → Supabase-ə yapışdır → **Run** → "Success".

## 8. Telegram bildirişləri

Yeni qeydiyyat, pozuntu və blok olanda telefonuna mesaj gəlir.

1. Telegram-da **@BotFather**-i aç → **/newbot** yaz.
2. Bota ad ver (məs. `Wordora Bildiriş`), sonra istifadəçi adı (sonu `bot` ilə bitməlidir, məs. `wordora_gulnar_bot`).
3. BotFather sənə **token** verəcək (`1234567890:AAH...` kimi). **Onu heç kimə göndərmə.**
4. Yeni yaratdığın botu aç və **Start** bas (yoxsa bot sənə yaza bilməz).
5. Telegram-da **@userinfobot**-u aç → **Start** → sənə **Id** göstərəcək (rəqəmlər).
6. Supabase → **SQL Editor** → **New query** → bunu yaz (TOKEN və ID yerinə özününkünü) → **Run**:

   ```sql
   select public.set_telegram('TOKEN', 'ID');
   ```
7. Telefonuna "✅ Wordora bildirişləri qoşuldu" mesajı gəlməlidir.

> Token Supabase-in gizli anbarında (Vault) saxlanır, saytın kodunda və GitHub-da görünmür.

**Bildiriş başqa birinə də getsin** (o, əvvəlcə bota **Start** basmalıdır, Id-ni @userinfobot-dan alır):

```sql
select public.add_telegram_chat('ID');      -- əlavə et
select public.list_telegram_chats();        -- siyahı
select public.remove_telegram_chat('ID');   -- sil
```

---

## Gündəlik istifadə

- **Yeni şagird qeydiyyatdan keçdi** → Admin panel → **Yeni qeydiyyatlar** → **Təsdiqlə** və ya **Rədd et**
- **Şagirdi bloklamaq** → **Şagirdlər** → **Blokla** (səbəb yaza bilərsən, şagird görəcək)
- **Blokdan çıxarmaq** → **Bloklanan / rədd** → **Blokdan çıxar** (xəbərdarlıqlar sıfırlanır)
- **Elan** → **Elanlar** → bütün siniflərə və ya bir sinfə
- **Yeni sınaq** → **Sınaqlar** → **+ Yeni sınaq** → ad, PDF, vaxt, siniflər → cavab açarını yapışdır (`1 A, 2 C, 4 BBAA, 10 went/has gone, 26 esse`) → **Cavab kartını yarat** → esseyə bal yaz → **Balları bərabər payla** → **Şagirdlər görsün** → **Yadda saxla**
- **Sınaq nəticələri** → **Sınaqlar** → **Nəticələr**: bal, cavablar, esse balı, sual analizi, **⬇ Excel**; hazır olanda **Nəticələri şagirdlərə aç**
- **Şagird sınağı yenidən yazsın** → Nəticələr → **Cavablar** → **🔄 Yenidən yazsın** → neçə gün (məs. 3). Köhnə nəticə arxivdə qalır ("🗂 Əvvəlki cəhd"), son tarix keçsə belə şagird yaza bilir. Sınağı ümumiyyətlə yazmayan şagirdə: **Yazmayanlar** → **🔄 Yazmağa icazə ver**
- **Köhnə sınaqdan yenisini düzəlt** → **Kopyala** → adını, PDF-i və açarı dəyiş
- **Davamiyyət** → **✅ Davamiyyət** → sinif və tarix seç → hər şagirdə ✓ / ⏰ / ✕ / 📄 → **Yadda saxla**; **Ay** tabında cədvəl və Excel
- **Şagird sualı** → **💬 Mesajlar** (sual gələndə Telegram-a da bildiriş gedir)
- **Valideyn** → şagird portalda **Valideyn kodu** düyməsi ilə kodu alıb valideyninə verir; valideyn ana səhifədə **Valideyn girişi** ilə baxır. Kodu yeniləmək: şagirdin **📈 Profil** səhifəsi → **Valideyn kodu**
- **Sözlər** → **🔤 Sözlər** → `söz | tərcümə | nümunə` formatında dəst əlavə et — günün sözü və söz kartları avtomatik işləyir
- **Aylıq hesabat** → **📊 Aylıq hesabat** → ay seç → hazır mətni **Kopyala** və ya **Çap et / PDF**, **Excel**
- **Ehtiyat nüsxə** → **💾 Ehtiyat nüsxə** — ayda bir dəfə yüklə
- **Yeni tədris ili** (avqust–sentyabr) → **Şagirdlər** → **🎓 Yeni tədris ili**
- **Material** → **Materiallar** → PDF yüklə; "Şagirdlər yükləyə bilsin" açıqdırsa, hər şagird öz adı və kodu yazılmış nüsxəni yükləyir
- **Pozuntular** → kim, nə vaxt, nə edib; səhv siqnalı **Ləğv et**; xəbərdarlıq limiti və Tor bloku buradan dəyişir
- **Avtomatik bloklanan şagird** → **Bloklanan / rədd** → **Blokdan çıxar** (xəbərdarlıqlar sıfırlanır)
- **Yayılmış PDF tapdın** → faylın hər səhifəsində `WD-XXXXXX` kodu var → Admin panel → **Şagirdlər** → axtarışa kodu yaz
- **Şagird şifrəsini unutdu** → **Şagirdlər** → **🔑 Şifrə** → yeni şifrə avtomatik yaranır (istəsən dəyiş) → ekrandakı şifrəni şagirdə ver
- **Canlı viktorina** → **🎮 Viktorina** → sualları yaz (birinci sətir sual, altında variantlar, düzgünün əvvəlinə `*`, suallar arasında boş sətir) → **▶ Başlat** → telefonu proyektora qoş → **⛶ Tam ekran** → şagirdlər portalda kodu yazır → **Başla ▶**
- **Tam onlayn sınaq** → **+ Yeni sınaq** → **🧩 Tam onlayn sınaq** → sualları yaz (`## başlıq` + mətn; sual + variantlar, düzgünün əvvəlinə `*`; `= cavab` açıq sual; `= esse 70` esse) → **Sualları yarat** → bal → **Yadda saxla**. Şagird sualları yalnız sınağa başlayanda görür
- **Sual bankı** → **🗂 Sual bankı** → mövzu yaz, sualları yapışdır → **Banka əlavə et**; sonra lazım olanları seç → **→ Seçilənlərdən sınaq** və ya **→ Seçilənlərdən viktorina**
- **Ev tapşırığı** → **📝 Tapşırıqlar** → başlıq, tapşırıq, son tarix, bal, siniflər → **Paylaş**; şagird portalda **📝 Ev tapşırıqları**-ndan cavab yazır və ya dəftərin şəklini göndərir → sən **Cavablar** → bal + şərh → **Qiymət ver**. Qiymət qoyulana qədər şagird cavabını dəyişə bilər
- **Bölmələr (MSI üçün)** → sınaqda **Bölmələr** sahəsinə yaz: `Reading: 1-10; Listening: 11-15; Grammar: 16-20; Essay: 21` (onlayn sınaqda sualların arasına `# Reading` yazmaq kifayətdir) → **Nəticələr**-də hər şagirdin və sinfin bölmə üzrə faizi, ən zəif bölmə; Excel-də ayrıca "Bölmələr" vərəqi
- **Qarışdırma** → onlayn sınaqda **🔀 Sualları və variantları qarışdır** (yeni sınaqlarda özü açıqdır) — hər şagird fərqli ardıcıllıq görür
- **Esse yoxlama** → **Nəticələr** → **Cavablar və esse** → 4 meyara bal yaz (cəm özü hesablanır) → şərh yaz və ya hazır şərhə toxun → **Yadda saxla**. Yeni hazır şərh: mətni yaz → **+ Şərhi hazır siyahıya əlavə et**. Şagird nəticələr açılanda balları və şərhi görür
- **Yaddaş** → **🧹 Yaddaş** — fayllar və baza nə qədər dolub; köhnə ev tapşırığı şəkillərini buradan sil. 80%-i keçəndə admin paneldə xəbərdarlıq çıxır
- **Magistratura bölməsi** → admin paneldə yuxarıdakı **🏫 Məktəb / 🎓 Magistratura** düyməsi ilə keç. Magistratura rejimində yüklədiyin material, elan və ev tapşırığını yalnız magistrantlar görür; məktəb rejimində "heç bir sinif seçilməyib" = yalnız 5–11-ci siniflər. Reytinq də ayrıdır. Sınaqlar əvvəlki kimidir (sinif seçimində "Magistratura" var)
- **Şagirdi tamamilə silmək** → **Şagirdlər** (və ya **Bloklanan / məzun**) → **🗑 Sil** → təsdiq üçün istifadəçi adını yaz. Hesab, nəticələr, tapşırıqlar, mesajlar — hamısı silinir, geri qaytarmaq olmur. Yalnız girişi bağlamaq üçün **Blokla** kifayətdir
- **Sınağı silmək** nəticələri də silir — nəticələr qalsın deyə **Gizlət** istifadə et
- **Variantlar (A, B, C...)** → sınağı redaktə et → **3. Variantlar** → **+ B variantı əlavə et** → B-nin PDF-i və cavabları (`1 B, 2 D, ...` — sual sayı və tipləri A ilə eyni) → istəsən öz dinləməsi (yoxsa A-nınkı) → **Yadda saxla**. Şagird "Başla" basanda variant avtomatik verilir (bərabər paylanır, yenidən yazanda başqa variant düşür). Konkret şagirdə variant: **Nəticələr** → **Yazmayanlar** → "Variant" seçimi. Nəticələrdə hər şagirdin variantı görünür, sual analizi variant üzrə ayrıdır
- **Kağız sınaq** → **+ Yeni sınaq** → **📝 Kağız sınaq** işarələ → cavab açarını yarat (PDF məcburi deyil; variantlar da olar) → **Yadda saxla** → **Nəticələr** → yuxarıdakı formada şagirdi seç (siyahıda yoxdursa — "Siyahıda yoxdur", adını yaz) → variantı seç → cavabları sırası ilə yaz (`C D B BBAA went`; çox sözlü cavab varsa vergüllə; boş sual `-`) → **Enter**. Növbəti şagird avtomatik seçilir. Esse — nəticədə 4 meyar üzrə. **📄 PDF hesabatlar** — hər şagird üçün bir səhifə; hər sətirdə **📄 PDF** — tək şagird. Nəticələri açanda qeydiyyatlı şagirdlər portalda görür
- **PDF hesabat** onlayn sınaqlarda da var: **Nəticələr** → **📄 PDF hesabatlar**
- **Həftəlik hesabat** → hər bazar 20:00 Telegram-a xülasə gəlir (sınaqlar, orta bal, yazmayanlar, ev tapşırıqları, yoxlanılmalı esse/tapşırıq, oxunmamış mesajlar, pozuntular, davamiyyət). **Pozuntular** → **Qoruma ayarları** → **📬 Həftəlik Telegram hesabatı**: aç/bağla, **İndi göndər**
- **Həftəlik ehtiyat nüsxə** → hər bazar 20:30 bütün baza `.json.gz` faylı kimi Telegram-a gəlir. Quraşdırma (bir dəfə): 19-backup-errors.sql işə salınanda nəticədə uzun açar çıxır → GitHub → repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** → Name: `BACKUP_SECRET`, Secret: həmin açar → **Add secret** → **Actions** tabı → **Həftəlik ehtiyat nüsxə** → **Run workflow** (yoxlama). Fayl itəndə bərpa üçün Claude-a göndər
- **Xəta bildirişi** → şagirddə sayt xəta verəndə (məs. sınaqda cavablar yadda saxlanmır, PDF açılmır) Telegram-a dərhal xəbər gəlir; siyahı: **Pozuntular** → **🚨 Saytda xətalar**
- **Davamiyyət qrupları** → **✅ Davamiyyət** → yuxarıda cədvəl seç (1-ci və 3-cü gün, 3-cü və 5-ci gün, 2-ci və 4-cü gün, 6-cı və 7-ci gün) → **+ Yeni qrup** (ad: məs. "Saat 15:00") → **👥 Şagirdləri seç** (axtarış, sinif filtri; şagirdin başqa qrupları da görünür) → **Yadda saxla**. Sonra qrupu seç → son dərs günlərindən birinə toxun → davamiyyəti yaz. **🏫 Siniflər** — köhnə sinif üzrə görünüş
- **Davamiyyət → Telegram** → "Yadda saxla" yanında **📨 Telegram** işarəlidirsə, gəlməyən/gecikən/üzrlü şagirdlərin siyahısı Telegram-a gedir. Şagird portalda öz qrupunu görür ("Sənin qrupun: 2-ci və 4-cü gün · Saat 15:00")
- **Chat** → portalda **🗨️ Chat**, admin paneldə **🗨️ Chat**. Otaqlar: **Ümumi chat** (məktəb şagirdləri), **Magistratura chatı**, hər dərs qrupunun öz chatı. Şəkil və PDF göndərmək olar. Hər şey **40 dəqiqədən sonra** silinir; müəllim üçün 7 günlük mətn arxivi (**📜 Arxiv**). Mesajın üstünə toxun → **🗑** sil, **🔇** şagirdi bir neçə saat susdur. **⏸ Chatı bağla** — chat hamı üçün bağlanır
