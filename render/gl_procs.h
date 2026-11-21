#ifndef VCORE_RENDER_GL_PROCS_H
#define VCORE_RENDER_GL_PROCS_H

// GL 2.0+ fonksiyon işaretçileri. V modül globalleri -enable-globals ister; bu yüzden C static'lerinde.
// Yuvalar gl.v içindeki slot_* sabitleriyle eşleşir; sınır denetimi yok.
#define VCORE_GL_SLOTS 27

static void *vcore_gl_slots[VCORE_GL_SLOTS];

static void vcore_gl_set(int slot, void *p) { vcore_gl_slots[slot] = p; }
static void *vcore_gl_get(int slot) { return vcore_gl_slots[slot]; }

#endif
