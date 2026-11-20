# M1: Bellek + Varlık Kimlikleri + Benchmark Altyapısı — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** V-Core'un en alt katmanını kurmak: OS sanal bellek rezervasyonu, üç tahsisatçı (lineer arena, çift tamponlu kare arenası, bit-haritalı havuz), 48 bitlik kuşaksal varlık kimliği + tahsisatçısı ve JSON üreten benchmark altyapısı.

**Architecture:** Kök dizinde `v.mod`; her alt sistem kökte bir V modülü klasörü (`memory/`, `ecs/`). Tüm tahsisatçılar tek bir `VirtualAlloc` bloğundan beslenen `LinearArena` üstüne kurulur. Benchmark kütüphanesi `bench/benchkit/`, M1 benchmark programı `bench/m1_memory.v`.

**Tech Stack:** V 0.5.2 (`-gc none`), gcc 16.1 (MinGW-W64), Windows `VirtualAlloc`, V stdlib: `math.bits`, `time`, `json`, `os`.

**Spec:** `docs/superpowers/specs/2026-11-17-v-core-engine-design.md` (§5, §7.1, §7.2, §7.13, §7.14, §8 M1)

## Global Constraints

- V 0.5.2; tüm test ve benchmark komutları `-gc none` ile çalışır.
- Üçüncü parti kod yok (M1'de stb de gerekmiyor).
- Windows tek hedef; OS'e özel dosyalar `_windows.c.v` son ekini alır.
- `memory/` ve `ecs/` içinde V `string`, dinamik `array`, `map` kullanılmaz (testler ve `bench/` hariç).
- Tahsisatçılar taşmada `panic` etmez, `none` döner (spec §7.1).
- `EntityID`: bit 0..31 index, bit 32..47 generation, bit 48..63 her zaman 0 (spec §7.2).
- Generation 0xFFFF'e ulaşan slot emekli edilir, tekrar kullanılmaz (spec §7.2).
- Benchmark JSON alanları: ad, varlık sayısı, min/medyan/p99 ns, bellek, durum hash'i (spec §7.14).
- Kod yorumları Türkçe, tanımlayıcılar İngilizce.
- Commit adımları yalnızca proje git deposuysa uygulanır (şu an değil).

## Review Focus

1. Çağıranın verdiği taban adres 64 bayta hizalı değilse arena yine doğru hizalı adres vermeli → Task 2 testi.
2. `size + padding` u64 taşması (`alloc_aligned(max_u64, 1)`) sarmamalı, `none` dönmeli → Task 2 testi.
3. Protokolden gelen sahte/bayat handle (`make_entity(i, gen+1)`, sınır dışı index) canlı sayılmamalı, `destroy` false dönmeli → Task 6 testi.
4. Havuzda çift `release` veya aralık dışı index sessizce bozulma yaratmamalı, false dönmeli → Task 4 testi.
5. `bench/results/` yoksa rapor yazımı klasörü oluşturmalı → Task 7 testi.

---

### Task 1: Proje iskeleti, hizalama matematiği, OS bellek rezervasyonu

**Files:**
- Create: `v.mod`, `memory/align.v`, `memory/vmem_windows.c.v`
- Test: `memory/align_test.v`, `memory/vmem_test.v`

**Interfaces:**
- Produces: `memory.align_forward(p u64, k u64) u64`, `memory.pad_for(p u64, k u64) u64`, `memory.is_pow2(k u64) bool`, `memory.reserve(size u64) ?&u8`, `memory.release(p &u8) bool`

- [ ] **Step 1: `v.mod` yaz:** `Module { name: 'vcore' description: 'V-Core game engine' version: '0.0.1' }`
- [ ] **Step 2: Başarısız testleri yaz**

```v
// memory/align_test.v
module memory

fn test_align_forward_known_values() {
	assert align_forward(0, 64) == 0
	assert align_forward(1, 64) == 64
	assert align_forward(64, 64) == 64
	assert align_forward(65, 64) == 128
	assert pad_for(1, 64) == 63
	assert pad_for(64, 64) == 0
	assert pad_for(100, 16) == 12
}

fn test_align_property() {
	for p in u64(0) .. 1000 {
		for k in [u64(1), 2, 4, 8, 16, 32, 64, 4096] {
			a := align_forward(p, k)
			assert a == p + pad_for(p, k)
			assert a % k == 0
			assert a - p < k
		}
	}
}

fn test_is_pow2() {
	assert is_pow2(1) && is_pow2(64) && is_pow2(4096)
	assert !is_pow2(0) && !is_pow2(3) && !is_pow2(96)
}

// memory/vmem_test.v
fn test_reserve_release() {
	p := reserve(1 << 20) or { panic('reserve basarisiz') }
	assert u64(p) & 0xFFF == 0
	unsafe {
		p[0] = 7
		p[(1 << 20) - 1] = 9
		assert p[0] == 7 && p[(1 << 20) - 1] == 9
	}
	assert release(p)
}

fn test_reserve_zero_is_none() {
	if _ := reserve(0) {
		assert false
	}
}
```

- [ ] **Step 3: Koştur, başarısızlığı gör.** `v -gc none test memory/` → FAIL (`align_forward` tanımsız)
- [ ] **Step 4: Uygula.** `align.v`: spec'teki dallanmasız formüller; `pad_for` u64'te `(~p + 1) & (k - 1)`. `vmem_windows.c.v`: `#include <windows.h>`, `C.VirtualAlloc(nil, size, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE)`, NULL → `none`; `release` = `VirtualFree(p, 0, MEM_RELEASE)`. (Bu çağrılar V 0.5.2 + gcc 16'da denendi, çalışıyor.)
- [ ] **Step 5: Koştur.** `v -gc none test memory/` → 4 test PASS
- [ ] **Step 6: Commit** `feat(memory): hizalama ve VirtualAlloc rezervasyonu`

---

### Task 2: LinearArena

**Files:**
- Create: `memory/arena.v`
- Test: `memory/arena_test.v`

**Interfaces:**
- Consumes: `align_forward`, `is_pow2`, `reserve`, `release`
- Produces:
  - `@[aligned: 64] pub struct LinearArena { pub mut: base &u8; capacity u64; offset u64; failed_allocs u64 }`
  - `pub fn LinearArena.new(base &u8, cap u64) LinearArena`
  - `pub fn (mut a LinearArena) alloc_aligned(size u64, alignment u64) ?&u8`. Taşmada `none`, `offset` değişmez, `failed_allocs++`. `alignment` 2'nin kuvveti değilse `assert` (programcı hatası).
  - `pub fn (mut a LinearArena) reset()`
  - `pub fn (a &LinearArena) used() u64`

- [ ] **Step 1: Başarısız testleri yaz** (her test kendi `reserve` bloğunu açar, sonunda `release` eder)
  - `test_alloc_is_aligned_and_disjoint`: cap 4096; `p1 := alloc_aligned(10, 64)`, `p2 := alloc_aligned(10, 64)` → ikisi de `% 64 == 0`, `u64(p2) >= u64(p1) + 10`
  - `test_unaligned_base`: `LinearArena.new(base + 1, 4095)`; `alloc_aligned(8, 64)` → sonuç `% 64 == 0`; `used() == pad + 8` (pad = `pad_for(u64(base)+1, 64)`)
  - `test_overflow_returns_none`: cap 128; `alloc_aligned(128, 1)` başarılı; `alloc_aligned(1, 1)` → `none`, `used() == 128`, `failed_allocs == 1`
  - `test_size_wraparound_is_none`: `alloc_aligned(max_u64, 1)` → `none`, `offset == 0`
  - `test_reset`: alloc sonrası `reset()` → `used() == 0`, sonraki `alloc_aligned(1, 1)` == `base`
- [ ] **Step 2: Koştur.** `v -gc none test memory/` → FAIL (`LinearArena` tanımsız)
- [ ] **Step 3: Uygula.** Notlardaki `alloc_aligned` gövdesi, iki değişiklikle: `panic` yerine `none`; taşma kontrolü toplama yapmadan önce `size > capacity - offset - padding` biçiminde (önce `padding > capacity - offset` kontrolü).
- [ ] **Step 4: Koştur.** → PASS
- [ ] **Step 5: Commit** `feat(memory): LinearArena`

---

### Task 3: EpochArena (çift tamponlu kare arenası)

**Files:**
- Create: `memory/epoch.v`
- Test: `memory/epoch_test.v`

**Interfaces:**
- Consumes: `LinearArena`
- Produces:
  - `pub struct EpochArena { pub mut: arenas [2]LinearArena; frame u64 }`
  - `pub fn EpochArena.new(mut parent LinearArena, half_capacity u64) ?EpochArena`: iki yarıyı da parent'tan 64 hizalı alır.
  - `pub fn (mut e EpochArena) alloc(size u64, alignment u64) ?&u8`: yazma arenası `arenas[frame & 1]`
  - `pub fn (e &EpochArena) read_base() &u8` ve `pub fn (e &EpochArena) read_used() u64`: okuma arenası `arenas[(frame - 1) & 1]` (`frame == 0` iken `read_used() == 0`)
  - `pub fn (mut e EpochArena) advance()`: `frame++`, sonra yeni yazma arenasını `reset()`

- [ ] **Step 1: Başarısız test yaz:** `test_epoch_double_buffer`
  - frame 0: `p := alloc(8, 8)`, `*p = 42` (u64)
  - `advance()` → `read_base() == p`, okunan değer 42, `read_used() == 8`, yeni yazma arenasının `used() == 0`
  - frame 1: `q := alloc(8, 8)`, `*q = 43`; `advance()` → frame 2 yazma arenası frame 0'ınki ve `used() == 0`; `read_base() == q`, değer 43
  - `test_epoch_overflow`: `half_capacity` 64; `alloc(65, 1)` → `none`
  - `test_epoch_parent_too_small`: parent cap 100, `EpochArena.new(mut parent, 64)` → `none`
- [ ] **Step 2: Koştur** → FAIL
- [ ] **Step 3: Uygula** (yukarıdaki imzalar; gövde belirsiz değil)
- [ ] **Step 4: Koştur** → PASS
- [ ] **Step 5: Commit** `feat(memory): EpochArena`

---

### Task 4: PoolAllocator (bit-haritalı havuz)

**Files:**
- Create: `memory/pool.v`
- Test: `memory/pool_test.v`

**Interfaces:**
- Consumes: `LinearArena`, `align_forward`, `math.bits.trailing_zeros_64`
- Produces:
  - `pub struct PoolAllocator { slots &u8; stride u64; slot_count u32; free_bits &u64; word_count u32; live u32 }`. `free_bits`'te 1 = boş. Son kelimede `slot_count`'u aşan bitler 0 (hiç verilmez).
  - `pub fn PoolAllocator.new(mut parent LinearArena, slot_size u64, slot_count u32) ?PoolAllocator`: `stride = align_forward(slot_size, 16)`, slot bloğu ve bitmap 64 hizalı parent'tan
  - `pub fn (mut p PoolAllocator) acquire() ?u32`: ilk sıfır olmayan kelime `w` için `w*64 + ctz(word)`; dolu ise `none`. (Notlardaki `ctz(~used_mask)` ile aynı, biz boş bitleri tutuyoruz.)
  - `pub fn (mut p PoolAllocator) release(idx u32) bool`: aralık dışı ya da zaten boşsa `false`
  - `pub fn (p &PoolAllocator) slot_ptr(idx u32) &u8`
  - `pub fn (p &PoolAllocator) live_count() u32`

- [ ] **Step 1: Başarısız testleri yaz**
  - `test_acquire_all_ascending`: slot_count 130; 130 `acquire` → sırasıyla 0..129; 131. → `none`; `live_count() == 130`
  - `test_release_reuses_lowest`: hepsini al, `release(5)`, `release(70)` → `acquire() == 5`, sonra `70`
  - `test_double_and_oob_release`: `release(5)` true, tekrar `release(5)` false, `release(130)` false; `live_count()` tutarlı
  - `test_word_boundaries`: slot_count 64 ve 1 için tümünü al → bir fazlası `none`
  - `test_slot_ptr_layout`: slot_size 24 → `stride == 32`; `slot_ptr(i)` 16 hizalı, `slot_ptr(i+1) - slot_ptr(i) == 32`
- [ ] **Step 2: Koştur** → FAIL
- [ ] **Step 3: Uygula.** `// shortcut: acquire boş kelimeyi doğrusal tarar, havuz binlerce kelimeye çıkarsa ipucu (hint) indeksi ekle`
- [ ] **Step 4: Koştur** → PASS
- [ ] **Step 5: Commit** `feat(memory): bit-haritalı PoolAllocator`

---

### Task 5: EntityID (48 bit kuşaksal tanımlayıcı)

**Files:**
- Create: `ecs/entity.v`
- Test: `ecs/entity_test.v`

**Interfaces:**
- Produces:
  - `pub type EntityID = u64`
  - `pub const max_generation = u16(0xFFFF)`, `pub const null_index = u32(0xFFFFFFFF)`, `pub const null_entity = make_entity(null_index, 0)`
  - `pub fn make_entity(index u32, gen u16) EntityID`
  - `pub fn (e EntityID) index() u32`, `pub fn (e EntityID) generation() u16`, `pub fn (e EntityID) is_null() bool`

- [ ] **Step 1: Başarısız test yaz**

```v
module ecs

fn test_pack_roundtrip() {
	e := make_entity(0xFFFFFFFE, 0xFFFF)
	assert u64(e) == u64(0x0000FFFF_FFFFFFFE)
	assert e.index() == 0xFFFFFFFE && e.generation() == 0xFFFF
	assert u64(e) >> 48 == 0
}

fn test_null() {
	assert null_entity.is_null()
	assert !make_entity(0, 0).is_null()
}
```

- [ ] **Step 2: Koştur.** `v -gc none test ecs/` → FAIL
- [ ] **Step 3: Uygula** (`@[inline]`, bit işlemleri spec §7.2)
- [ ] **Step 4: Koştur** → PASS
- [ ] **Step 5: Commit** `feat(ecs): 48 bit EntityID`

---

### Task 6: EntityAllocator

**Files:**
- Create: `ecs/entity_alloc.v`
- Test: `ecs/entity_alloc_test.v`

**Interfaces:**
- Consumes: `memory.LinearArena`, `EntityID`, `make_entity`, `max_generation`, `null_index`
- Produces:
  - `pub struct EntityAllocator { generations &u16; free_next &u32; alive_bits &u64; free_head u32; capacity u32; high_water u32; alive u32; retired u32 }`. Boş liste `free_next` içinden LIFO bağlı, boşken `free_head == null_index`.
  - `pub fn EntityAllocator.new(mut parent memory.LinearArena, capacity u32) ?EntityAllocator`: `capacity < null_index` olmalı
  - `pub fn (mut a EntityAllocator) create() ?EntityID`: önce boş listeden, yoksa `high_water++`; ikisi de yoksa `none`
  - `pub fn (mut a EntityAllocator) destroy(e EntityID) bool`: canlı değilse `false`. Canlıysa alive bitini sil. `generations[i] == max_generation` ise slotu emekli et (`retired++`, boş listeye girmez). Değilse `generations[i]++` yap ve boş listeye it.
  - `pub fn (a &EntityAllocator) is_alive(e EntityID) bool`: `index < high_water && alive bit && generations[index] == e.generation()`
  - `pub fn (a &EntityAllocator) alive_count() u32`, `pub fn (a &EntityAllocator) retired_count() u32`

- [ ] **Step 1: Başarısız testleri yaz**
  - `test_create_sequential`: cap 8; 3 `create` → index 0,1,2, gen 0; `alive_count() == 3`
  - `test_reuse_bumps_generation`: `b` (index 1) `destroy` → true; `create()` → index 1 gen 1; `is_alive(b) == false` (ABA)
  - `test_untrusted_handles`: `destroy(b)` ikinci kez false; `is_alive(make_entity(1, 2))` false (sahte gen); `is_alive(make_entity(5, 0))` false (high_water dışı); `is_alive(null_entity)` false; `destroy(make_entity(7, 0))` false
  - `test_capacity_exhausted`: cap 2; 2 `create` sonra → `none`
  - `test_generation_retire`: cap 2; `e := create()` (idx 0); `0xFFFF` kez `{ destroy(e); e = create() }` → `e.index() == 0 && e.generation() == 0xFFFF`; `destroy(e)` true, `retired_count() == 1`; `create()` → index 1 gen 0; sonraki `create()` → `none`
- [ ] **Step 2: Koştur** → FAIL
- [ ] **Step 3: Uygula** (diziler parent arenadan 64 hizalı)
- [ ] **Step 4: Koştur.** `v -gc none test ecs/` → PASS
- [ ] **Step 5: Commit** `feat(ecs): EntityAllocator, ABA koruması ve slot emekliliği`

---

### Task 7: Benchmark altyapısı + M1 bellek benchmark'ı

**Files:**
- Create: `bench/benchkit/benchkit.v`, `bench/m1_memory.v`, `bench/results/.gitkeep`
- Test: `bench/benchkit/benchkit_test.v`

**Interfaces:**
- Consumes: Task 1–6'nın tümü (yalnızca `m1_memory.v`)
- Produces (modül `benchkit`, import yolu `bench.benchkit`):
  - `pub struct Stats { pub: min_ns u64; median_ns u64; p99_ns u64; samples int }`
  - `pub fn summarize(samples []u64) ?Stats`: boşsa `none`. Kopyayı sıralar; medyan = alt medyan `s[(n-1)/2]`; p99 = nearest-rank `s[ceil(0.99*n) - 1]`
  - `pub fn measure(warmup int, iterations int, f fn ()) Stats`: her örnek `time.sys_mono_now()` ile ölçülür (stdlib zaten QPC kullanıyor ve taşma güvenli oran tutuyor; platform zamanlayıcısı M3'te gelir)
  - `pub struct Result { pub: name string; entities u32; ops_per_sample u32; stats Stats; mem_bytes u64; state_hash string }` (`state_hash` M2'ye kadar `""`)
  - `pub struct Report { pub: label string; date string; v_version string; results []Result }`
  - `pub fn write_report(r Report, dir string) !string`: `dir` yoksa oluşturur. Dosya `<dir>/<r.date>-<r.label>.json`, `date` biçimi `YYYY-MM-DD-HHMMSS`. Yazılan yolu döner.
  - `pub fn latest_report(dir string, exclude_path string) ?Report`: dosya adına göre sıralanınca sonuncusu (`exclude_path` hariç)
  - `pub fn compare(prev Report, cur Report) string`: aynı adlı her sonuç için medyan ve p99 değişimi `%+.1f%%`. Medyan %10'dan fazla arttıysa satıra `YAVASLADI` eklenir. Önceki raporda olmayan sonuç `YENI` olarak işaretlenir.

- [ ] **Step 1: Başarısız testleri yaz**
  - `test_summarize`: 1..100 → min 1, medyan 50, p99 99, samples 100; `[u64(7)]` → hepsi 7; `[]u64{}` → `none`
  - `test_write_and_read_report`: geçici klasörde **olmayan** alt klasör `x/y` → `write_report` dosyayı oluşturur; `json.decode(Report, ...)` eşit; iki rapor yazılınca `latest_report` daha yeni tarihliyi döner
  - `test_compare`: prev medyan 100, cur 120 → çıktı ad, `+20.0%` ve `YAVASLADI` içerir; 100→105 `YAVASLADI` içermez; yalnızca cur'da olan ad `YENI` içerir
- [ ] **Step 2: Koştur.** `v -gc none test bench/benchkit/` → FAIL
- [ ] **Step 3: `benchkit.v`'yi uygula**
- [ ] **Step 4: Koştur** → PASS
- [ ] **Step 5: `bench/m1_memory.v` (module main) yaz.** 256 MiB `reserve`. Ölçümler (her biri warmup 10, iterations 200, örnek başına 100.000 işlem):
  - `arena_alloc_64b`: 100k × `alloc_aligned(64, 64)` + `reset`
  - `pool_acquire_release`: 100k slot (32 B), tümünü al, tümünü bırak
  - `entity_create_destroy`: cap 100k, 100k `create`, 100k `destroy`
  - `epoch_advance`: 100k × (`alloc(32, 16)` + her 1.000'de bir `advance`)

  `mem_bytes` = ilgili yapı için kullanılan arena baytı. Etiket `os.args[1]`, yoksa `local`. Rapor `bench/results/` altına yazılır. Önceki rapor varsa `compare` çıktısı basılır.
- [ ] **Step 6: Koştur.** `v -gc none -prod run bench/m1_memory.v m1` → 4 satırlık tablo, rapor yolu, `bench/results/<tarih>-m1.json` oluşur. İkinci koşu karşılaştırma tablosu basar.
- [ ] **Step 7: Tüm testler.** `v -gc none test memory/ ecs/ bench/benchkit/` → hepsi PASS
- [ ] **Step 8: Commit** `feat(bench): benchkit ve M1 bellek benchmark'ı`

---

## M1 bitti sayılır, eğer (spec §8)

- Arena, epoch ve havuz testleri geçiyor (Task 2–4)
- Handle ABA testi geçiyor (Task 6)
- Tahsis benchmark'ı JSON üretiyor (Task 7)
