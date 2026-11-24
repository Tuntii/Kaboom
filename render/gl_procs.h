#ifndef VCORE_RENDER_GL_PROCS_H
#define VCORE_RENDER_GL_PROCS_H

// GL 2.0+ fonksiyon işaretçileri. V modül globalleri -enable-globals ister; bu yüzden C static'lerinde.
// Yuvalar gl.v içindeki slot_* sabitleriyle eşleşir; sınır denetimi yok.
#define VCORE_GL_SLOTS 40

static void *vcore_gl_slots[VCORE_GL_SLOTS];
// 1 yalnız her fonksiyon yüklendiğinde; kısmi yükleme durumu bırakılmaz.
static int vcore_gl_ready_flag = 0;

static void vcore_gl_set(int slot, void *p) { vcore_gl_slots[slot] = p; }
static void *vcore_gl_get(int slot) { return vcore_gl_slots[slot]; }
static int vcore_gl_ready(void) { return vcore_gl_ready_flag; }
static void vcore_gl_set_ready(int v) { vcore_gl_ready_flag = v; }

// Tüm yuvaları ve hazır bayrağını sıfırlar.
static void vcore_gl_clear(void) {
	for (int i = 0; i < VCORE_GL_SLOTS; i++) vcore_gl_slots[i] = 0;
	vcore_gl_ready_flag = 0;
}

#endif
