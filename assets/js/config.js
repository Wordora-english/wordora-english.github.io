// =========================================================
//  WORDORA — tənzimləmələr
//  Supabase layihəsini yaradandan sonra aşağıdakı iki sətri dəyiş.
//  (Bu açar "publishable/anon" açardır — açıq olması təhlükəsizdir,
//   bütün qoruma bazadakı qaydalarla təmin olunur.)
// =========================================================

export const SUPABASE_URL = "https://pjxrhkzdjytyxcqrvifw.supabase.co";
export const SUPABASE_KEY = "sb_publishable_l2bVnPADiLvdFB7l8CCuAg_stO_NFzh";

// Şagirdlər istifadəçi adı ilə girir. Arxa planda istifadəçi adı
// bu domenlə e-poçt formatına çevrilir (heç bir e-poçt göndərilmir).
export const EMAIL_DOMAIN = "aliqurbanovfh.github.io";

// Qeydiyyatda seçilə bilən siniflər
export const CLASSES = ["5", "6", "7", "8", "9", "10", "11", "Magistratura"];
// Magistrantlar ayrıca bölmədir: materiallar, elanlar, ev tapşırıqları və reytinq məktəblilərdən ayrıdır
export const MAG_CLASS = "Magistratura";

// Sertifikatlarda müəllimin adı
export const TEACHER_NAME = "Gülnar Salayeva";

// Bu faizdən yuxarı nəticə üçün şagird sertifikat yükləyə bilər
export const CERT_MIN_PERCENT = 85;

// Esse yoxlanarkən meyarlar (esse balı bunlara bərabər bölünür)
export const RUBRIC = ["Məzmun", "Qrammatika", "Lüğət", "Quruluş"];
