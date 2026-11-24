module winfile

// Windows dosya yazımı: yollar UTF-16 olarak verilir (Unicode yollar için), yazım diske boşaltılır.
// image/png.v ve protocol/scene.v bu modülü kullanır; yazma mantığı tek yerde kalsın diye.

fn C._wfopen(filename &u16, mode &u16) voidptr
fn C.MultiByteToWideChar(cp u32, flags u32, src &char, srclen int, dst &u16, dstlen int) int
fn C.fwrite(ptr voidptr, size usize, n usize, stream voidptr) usize
fn C.fflush(stream voidptr) int
fn C.fclose(stream voidptr) int
fn C._fileno(stream voidptr) int
fn C._commit(fd int) int
fn C.MoveFileExW(existing &u16, new &u16, flags u32) bool
fn C.DeleteFileW(name &u16) bool
fn C.fread(ptr voidptr, size usize, n usize, stream voidptr) usize
// Windows'ta long 32 bit: ftell 2 GiB üstünde negatif döner, bu da reddedilen boyut olur.
fn C.fseek(stream voidptr, offset int, origin int) int
fn C.ftell(stream voidptr) int
fn C.ferror(stream voidptr) int

// Kapasite bir NUL için ayrılır: en uzun yol 1023 UTF-16 birimi.
const max_path_units = 1023

// UTF-8 yolu NUL sonlu UTF-16 tampona çevirir; tampon sıfırdır, dönüşen birim sayısı kadar doldurulur.
fn wide_path(path string, mut w [1024]u16) ! {
	n := C.MultiByteToWideChar(65001, 0, &char(path.str), path.len, &w[0], max_path_units)
	if n <= 0 {
		return error('yol UTF-16e çevrilemedi')
	}
}

// Dosyayı yazar ve diske boşaltır. Yazma, boşaltma ya da kapatma başarısızsa oluşturulan dosya silinir:
// yarım kalmış bir dosya hiçbir zaman başarılı diye bildirilmez.
pub fn write_file(path string, data []u8) ! {
	mut wpath := [1024]u16{}
	wide_path(path, mut wpath)!
	mut wmode := [3]u16{}
	wmode[0] = u16(`w`)
	wmode[1] = u16(`b`)
	f := C._wfopen(&wpath[0], &wmode[0])
	if f == unsafe { nil } {
		return error('dosya açılamadı')
	}
	mut ok := true
	written := C.fwrite(data.data, 1, usize(data.len), f)
	if written != usize(data.len) {
		ok = false
	}
	// Tampon diske ancak flush ve commit ile iner; close hatası da yazım hatasıdır.
	if C.fflush(f) != 0 || C._commit(C._fileno(f)) != 0 {
		ok = false
	}
	if C.fclose(f) != 0 {
		ok = false
	}
	if !ok {
		C.DeleteFileW(&wpath[0])
		return error('dosya diske yazılamadı')
	}
}

// Okunabilecek en büyük dosya: scene ve kayıt dosyaları bu sınırın çok altındadır; daha büyüğü bellek tüketimi olur.
const max_read_bytes = i64(256 * 1024 * 1024)

// Dosyayı baştan sona okur; UTF-8 yol geniş API ile açılır (Türkçe yollar). Açılamazsa, sınırı aşarsa ya da okuma yarım kalırsa hata.
pub fn read_file(path string) ![]u8 {
	return read_file_capped(path, max_read_bytes)
}

// Boyut önce sorulur, tampon ondan sonra ayrılır: sınır aşılırsa bellek hiç ayrılmaz.
fn read_file_capped(path string, cap i64) ![]u8 {
	mut wpath := [1024]u16{}
	wide_path(path, mut wpath)!
	mut wmode := [3]u16{}
	wmode[0] = u16(`r`)
	wmode[1] = u16(`b`)
	f := C._wfopen(&wpath[0], &wmode[0])
	if f == unsafe { nil } {
		return error('dosya açılamadı')
	}
	defer {
		C.fclose(f)
	}
	if C.fseek(f, 0, 2) != 0 {
		return error('dosya okunamadı')
	}
	size := i64(C.ftell(f))
	if size < 0 {
		return error('dosya okunamadı')
	}
	if size > cap {
		return error('dosya çok büyük: ${size} bayt, en çok ${cap} bayt okunur')
	}
	if C.fseek(f, 0, 0) != 0 {
		return error('dosya okunamadı')
	}
	mut data := []u8{len: int(size)}
	if size > 0 {
		n := unsafe { C.fread(&data[0], 1, usize(size), f) }
		if n != usize(size) || C.ferror(f) != 0 {
			unsafe { data.free() }
			return error('dosya okunamadı')
		}
	}
	return data
}

// tmp dosyasını hedefin üzerine taşır (MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH = 0x9).
// Başarısızlıkta tmp silinir; hedef taşıma başarılı olana kadar değişmez.
pub fn replace_file(tmp string, dst string) ! {
	mut wtmp := [1024]u16{}
	mut wdst := [1024]u16{}
	wide_path(tmp, mut wtmp)!
	wide_path(dst, mut wdst) or {
		C.DeleteFileW(&wtmp[0])
		return err
	}
	if !C.MoveFileExW(&wtmp[0], &wdst[0], 0x9) {
		C.DeleteFileW(&wtmp[0])
		return error('dosya yerine taşınamadı')
	}
}
