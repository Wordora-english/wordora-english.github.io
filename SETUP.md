# Wordora — quraşdırma bələdçisi

Bu addımları bir dəfə edirsən. Hər şey pulsuzdur, heç bir yerdə kart istənmir.

---

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

1. Saytı aç: **https://aliqurbanovfh.github.io/wordora/**
2. **Qeydiyyat** → öz adınla qeydiyyatdan keç (məs. istifadəçi adı `gulnar`).
3. Supabase → **SQL Editor** → **New query** → bunu yaz (istifadəçi adını özününkü ilə əvəz et) → **Run**:

   ```sql
   update public.profiles set role = 'admin', status = 'approved', approved_at = now()
   where username = 'gulnar';
   ```
4. Saytdan çıx, yenidən daxil ol — **Admin panel** açılacaq.

## 6. Saytın "yatmaması" üçün (keep-alive)

1. GitHub → `wordora` reposu → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
2. İki secret əlavə et:
   - Name: `SUPABASE_URL` → Value: Project URL
   - Name: `SUPABASE_KEY` → Value: Publishable key
3. **Actions** tabı → **Supabase keep-alive** → **Run workflow** — yaşıl ✓ çıxmalıdır.

> Əgər repoda 60 gün heç bir dəyişiklik olmasa, GitHub bu işi dayandırıb e-poçt göndərə bilər. Belə olsa, **Actions** tabında **Enable workflow** düyməsini bas.

---

## Gündəlik istifadə

- **Yeni şagird qeydiyyatdan keçdi** → Admin panel → **Yeni qeydiyyatlar** → **Təsdiqlə** və ya **Rədd et**
- **Şagirdi bloklamaq** → **Şagirdlər** → **Blokla** (səbəb yaza bilərsən, şagird görəcək)
- **Blokdan çıxarmaq** → **Bloklanan / rədd** → **Blokdan çıxar** (xəbərdarlıqlar sıfırlanır)
- **Elan** → **Elanlar** → bütün siniflərə və ya bir sinfə
- **Şagird şifrəsini unutdu** → hələlik: Supabase → **Authentication** → **Users** → həmin istifadəçini sil, şagird yenidən qeydiyyatdan keçsin. Növbəti mərhələlərdə admin paneldə "şifrəni sıfırla" düyməsi olacaq.
