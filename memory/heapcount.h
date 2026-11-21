#ifndef VCORE_HEAPCOUNT_H
#define VCORE_HEAPCOUNT_H

// V'nin -d track_heap kancaları; yalnızca bu bayrakla çağrılır. Sayaç tek TU'da yaşar.
static unsigned long long vcore_heap_allocs = 0;

void vheap_alloc(void *p, unsigned long long n) {
	(void)p;
	(void)n;
	vcore_heap_allocs++;
}

void vheap_free(void *p) {
	(void)p;
}

unsigned long long vcore_heap_count(void) {
	return vcore_heap_allocs;
}

#endif
