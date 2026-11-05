# Wordora

**More Words • Bigger Dreams** — ingilis dili dərsləri üçün şəxsi platforma.

🌐 **Sayt:** https://wordora-english.github.io/

## Nə var (1-ci mərhələ)

- Şagird qeydiyyatı (istifadəçi adı + şifrə)
- Admin təsdiqi: yeni qeydiyyat "gözləmədə" qalır, müəllim təsdiqləyəndən sonra portal açılır
- Hər şagirdə avtomatik **şəxsi gizli kod** (PDF su nişanları üçün)
- Şagird portalı: elanlar, sınaqlar/materiallar/nəticələr bölmələri (tezliklə)
- Admin panel: təsdiq, rədd, blok, blokdan çıxarma, sinif dəyişmə, elanlar
- Bütün qoruma bazada (Supabase Row Level Security) — rol və status yalnız admin funksiyaları ilə dəyişir

## Plan

1. ✅ Təməl: qeydiyyat, təsdiq, portal, admin panel
2. ✅ Materiallar: su nişanlı baxış və su nişanlı yükləmə, kim baxıb/yükləyib
3. ✅ Qoruma: pozuntu aşkarlama, 2 xəbərdarlıq → blok, Telegram bildirişi, tək cihaz, Tor bloku
4. ✅ Sınaqlar (PDF + onlayn cavab kartı): taymer, avtomatik yadda saxlama və təhvil, serverdə yoxlama, esse, nəticələr, sual analizi, Excel
5. ✅ Şifrə sıfırlama və 🎮 canlı viktorina (proyektor rejimi)
6. ✅ Dinləmə (audio), günün sözü, söz kartları (səsləndirmə ilə), reytinq, sertifikat, nəticələrim, yeni tədris ili
7. ✅ Davamiyyət, müəllimə sual, valideyn baxışı, aylıq hesabat, ehtiyat nüsxə, qaranlıq rejim, telefona quraşdırma (PWA)
8. ✅ Tam onlayn sınaq (suallar və oxu mətnləri saytda, başlamadan görünmür), sual bankı, ev tapşırığı (şəkil/PDF ilə)
9. ✅ Bölmələr üzrə nəticə (MSI), sual/variant qarışdırma, esse meyarları + hazır şərhlər, yaddaş nəzarəti

## Texnologiya (hamısı pulsuz)

- **GitHub Pages** — sayt
- **Supabase** — baza, giriş, fayllar
- Sadə HTML / CSS / JavaScript (build lazım deyil)

Quraşdırma: [SETUP.md](SETUP.md)
