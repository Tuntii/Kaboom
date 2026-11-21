#ifndef VCORE_CJ_ARENA_H
#define VCORE_CJ_ARENA_H

// cJSON'un bellek kancaları ve düğüm erişimcileri. V globalleri -enable-globals ister; imleç
// bu yüzden burada, tek TU'da yaşar. Bir seferde yalnız bir Server bu kancaları kullanır.
#include <stddef.h>

static unsigned char *vcore_cj_base = NULL;
static unsigned long long vcore_cj_cap = 0;
static unsigned long long vcore_cj_off = 0;
static int vcore_cj_failed = 0;

// Bump tahsisi, 16 bayta hizalı. Sığmazsa NULL döner ve bayrak kalkar; free no-op.
static void *vcore_cj_malloc(size_t sz) {
	unsigned long long start = vcore_cj_off + ((16 - (vcore_cj_off & 15)) & 15);
	if (vcore_cj_base == NULL || start > vcore_cj_cap || sz > vcore_cj_cap - start) {
		vcore_cj_failed = 1;
		return NULL;
	}
	vcore_cj_off = start + sz;
	return vcore_cj_base + start;
}

static void vcore_cj_free(void *p) {
	(void)p;
}

// Bölgeyi bağlar; base NULL ise her tahsis NULL döner.
void vcore_cj_set(unsigned char *base, unsigned long long cap) {
	vcore_cj_base = base;
	vcore_cj_cap = cap;
	vcore_cj_off = 0;
	vcore_cj_failed = 0;
}

// Her istekte çağrılır: önceki isteğin tüm düğüm ve tamponları geri alınır.
void vcore_cj_reset(void) {
	vcore_cj_off = 0;
	vcore_cj_failed = 0;
}

int vcore_cj_exhausted(void) {
	return vcore_cj_failed;
}

void vcore_cj_install(void) {
	cJSON_Hooks h;
	h.malloc_fn = vcore_cj_malloc;
	h.free_fn = vcore_cj_free;
	cJSON_InitHooks(&h);
}

cJSON *vcore_cj_child(const cJSON *item) {
	return item ? item->child : NULL;
}

cJSON *vcore_cj_next(const cJSON *item) {
	return item ? item->next : NULL;
}

const char *vcore_cj_key(const cJSON *item) {
	return item ? item->string : NULL;
}

#endif
