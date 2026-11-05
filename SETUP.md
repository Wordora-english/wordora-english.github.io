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

---

## Gündəlik istifadə

- **Yeni şagird qeydiyyatdan keçdi** → Admin panel → **Yeni qeydiyyatlar** → **Təsdiqlə** və ya **Rədd et**
- **Şagirdi bloklamaq** → **Şagirdlər** → **Blokla** (səbəb yaza bilərsən, şagird görəcək)
- **Blokdan çıxarmaq** → **Bloklanan / rədd** → **Blokdan çıxar** (xəbərdarlıqlar sıfırlanır)
- **Elan** → **Elanlar** → bütün siniflərə və ya bir sinfə
- **Yeni sınaq** → **Sınaqlar** → **+ Yeni sınaq** → ad, PDF, vaxt, siniflər → cavab açarını yapışdır (`1 A, 2 C, 4 BBAA, 10 went/has gone, 26 esse`) → **Cavab kartını yarat** → esseyə bal yaz → **Balları bərabər payla** → **Şagirdlər görsün** → **Yadda saxla**
- **Sınaq nəticələri** → **Sınaqlar** → **Nəticələr**: bal, cavablar, esse balı, sual analizi, **⬇ Excel**; hazır olanda **Nəticələri şagirdlərə aç**
- **Şagird sınağı yenidən yazsın** → Nəticələr → **Cavablar** → **Cəhdi sil**
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
