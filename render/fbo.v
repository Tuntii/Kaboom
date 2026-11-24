module render

// Çerçeve tamponu (FBO): ekran görüntüsü ekran arka tamponu yerine buraya çizilir ve okunur.
// Renk eki tek RGBA8 renderbuffer; derinlik yok (quad ve UI çizimi derinlik testi kullanmaz).
pub struct Fbo {
mut:
	fb u32
	rb u32
	w  int
	h  int
}

// Yeni FBO kurar. Önkoşul: gl_ready() true. Hata durumunda kaynakları geri verir.
pub fn Fbo.new(w int, h int) !Fbo {
	if !gl_ready() {
		return error('GL hazir degil: load_gl basarisiz ya da cagrilmadi')
	}
	if w <= 0 || h <= 0 {
		return error('FBO boyutu sifir veya negatif: ${w}x${h}')
	}
	fb := gen_framebuffer()
	rb := gen_renderbuffer()
	bind_renderbuffer(gl_renderbuffer, rb)
	renderbuffer_storage(gl_renderbuffer, gl_rgba8, w, h)
	bind_renderbuffer(gl_renderbuffer, 0)
	bind_framebuffer(gl_framebuffer, fb)
	framebuffer_renderbuffer(gl_framebuffer, gl_color_attachment0, gl_renderbuffer, rb)
	status := check_framebuffer_status(gl_framebuffer)
	bind_framebuffer(gl_framebuffer, 0)
	if status != gl_framebuffer_complete {
		delete_framebuffer(fb)
		delete_renderbuffer(rb)
		return error('FBO tam degil: durum 0x${status:X}')
	}
	return Fbo{
		fb: fb
		rb: rb
		w:  w
		h:  h
	}
}

// Çizimleri bu FBO'ya yönlendirir. Çağıran unbind_fbo ile geri almalı.
pub fn (f &Fbo) bind() {
	// fb == 0 olsaydı çizim sessizce ekran arka tamponuna giderdi.
	assert f.fb != 0, 'Fbo.bind: boyutlandirilmamis FBO'
	bind_framebuffer(gl_framebuffer, f.fb)
}

// Yakalama pikselleri opak olmalı: FBO RGBA8'dir, ekran arka tamponunda alfa yoktur; kenar karışımı
// alfayı 255'in altına indirebilir. PNG'ye yazmadan önce her alfa baytı 255 yapılır.
pub fn make_opaque(mut px []u8) {
	for i := 3; i < px.len; i += 4 {
		px[i] = 255
	}
}

// Çizimleri ekran arka tamponuna (framebuffer 0) geri yönlendirir.
pub fn unbind_fbo() {
	bind_framebuffer(gl_framebuffer, 0)
}

// Boyut değişince yeniden kurar; aynı boyutta hiçbir şey yapmaz. İlk çağrıda FBO'yu tembel oluşturur.
pub fn (mut f Fbo) resize(w int, h int) ! {
	if f.fb != 0 && f.w == w && f.h == h {
		return
	}
	next := Fbo.new(w, h)!
	f.close()
	f = next
}

// Kaynakları serbest bırakır; tekrar çağrılabilir. Context canlıyken çağrılmalı.
pub fn (mut f Fbo) close() {
	if f.fb != 0 {
		delete_framebuffer(f.fb)
	}
	if f.rb != 0 {
		delete_renderbuffer(f.rb)
	}
	f.fb = 0
	f.rb = 0
	f.w = 0
	f.h = 0
}
