# M2: Minimal ECS + Komut Kuyruğu + Headless Döngü + Protokol + Kayıt/Tekrar Oynatma — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bir ajanın stdio üzerinden JSON-RPC ile sıfırdan sahne kurup 1.000 adım koşturabildiği, sorgulayıp doğrulayabildiği, kaydı iki kez oynatınca bit düzeyinde aynı durum hash'ini aldığı ve tick içinde sıfır `malloc` yapan ilk uçtan uca dilim.

**Architecture:** `ecs/` şema registry (V derleme zamanı reflection), sparse-set + ham SoA kolonlu `ComponentStore` ve `World`'ü taşır. `cmd/` sabit boyutlu 24 baytlık `Command`, `apply`, kaynak sınıfı sırasıyla uygulayan `CommandQueue` ve `Recorder` (bellek tamponu + ikili dosya). `sim/` sabit adım (`dt = 1/120`), hareket sistemi, FNV-1a durum hash'i ve tekrar oynatma. `protocol/` JSON-RPC 2.0 sunucusu (`handle(line) ?string`), `cmd_main/` `vcore headless` ikilisi. Bütün dünya değişiklikleri komut kuyruğundan geçer.

**Tech Stack:** V 0.5.2 (`-gc none`), gcc 16.1 MinGW-W64, V stdlib `x.json2`, `os`, `math`. Tahsis sayacı: V'nin `-d track_heap` kancası (`vheap_alloc`).

**Spec:** `docs/superpowers/specs/2026-11-17-v-core-engine-design.md` (§7.1, §7.2, §7.3, §7.4, §7.5, §7.8, §7.9, §7.13, §7.14, §8 M2)

## Global Constraints

- V 0.5.2; tüm test/benchmark komutları `-gc none` ile. Testler: `v -gc none test memory/ ecs/ cmd/ sim/ protocol/ bench/benchkit/ tests/`.
- Sıfır tahsis kuralı **tick yolu** için: `World` mutasyonları, `ComponentStore` işlemleri, `cmd.apply`, `CommandQueue.push/flush`, `Recorder.append`, `Sim.step`. Bu yolda V `string`, dinamik `array` büyütme, `map`, closure yok. Kurulum kodu (`new`, registry, protokol, dosya I/O) tahsis yapabilir (spec §7.1).
- `EntityID`: bit 0..31 index, 32..47 generation, 48..63 = 0 (spec §7.2). M1'deki `ecs.EntityAllocator` aynen kullanılır.
- Komutlar sabit boyutlu ikili kayıt: `sizeof(cmd.Command) == 24`. Uygulama sırası: kaynak sınıfı (`script` < `editor` < `agent`), sınıf içinde push sırası (spec §7.4).
- Kayıt birimi `(tick, komut)`; tekrar oynatma tick indeksine göre uygular (spec §7.4).
- Determinizm: simülasyon f32, FMA yok; `sim` modülü `#flag -ffp-contract=off` taşır; libm transandantal fonksiyon yok (spec §7.5).
- Sabit adım `dt = f32(1.0) / f32(120.0)`.
- Tahsisatçılar taşmada `panic` etmez; `none` / durum kodu döner (spec §7.1).
- Protokol: JSON-RPC 2.0, satır başına bir mesaj, yanıtlar tek satır. Her hata `{code, message, data}` (spec §7.8).
- Kod yorumları Türkçe, tanımlayıcılar İngilizce.
- V 0.5.2 tuzakları (M1'de görüldü): `&u8` parametreyi struct alanına yazmak `unsafe { p }` ister; `nil` → `unsafe { nil }`; test dosyalarında `module` satırı şart; değişken alanlar `mut:` bölümünde; sabit dizi literali `[a, b]!`; enum boyutu `enum X as u8`.
- Proje git deposu değil: commit adımları yok.

## Kararlar (spec'in builder'a bıraktığı ya da M2'de ertelenen)

- **Düz sparse dizi:** `ComponentStore` sparse dizisi sayfalı değil, `capacity × 4 B`. `shortcut:` yorumu ile işaretlenir; M6'da betik bileşenleri çoğalınca sayfalıya geçilir.
- **Kayıt yalnızca dış komutları tutar** (protokol/editör), sadece `ok` olanları. Spawn kaydında `entity` alanı oluşan id'dir; replay aynı id'yi bekler, farklıysa ayrışma hatası verir.
- **`record.start` yalnızca bozulmamış dünyada:** `tick == 0` ve `high_water == 0`. Aksi halde hata 1008. Ajan önce `sim.reset` çağırır. Snapshot'lı kayıt sahne formatıyla (M4) gelir.
- **M2 protokolü:** `entity.spawn/despawn`, `component.add/remove/set`, `entity.get`, `query.entities`, `schema.components`, `schema.commands`, `sim.step`, `sim.reset`, `sim.state_hash`, `record.start/stop`, `replay.run`. Ertelenenler:
  - `sim.pause/resume`: M3, sürekli koşan döngüyle gelir.
  - `query.region/ray`: M5.
  - `capture.*`: M3.
  - `scene.*`, `history.*`, `subscribe.changes`: M4.
  - `replay.diff`: M5.
- **Alan tipleri:** şema `f32, i32, bool, entity, symbol` tiplerini tanır. Depolama hepsini ham bit olarak taşır. Protokolün JSON dönüşümü M2'de yalnızca `f32`; diğerleri `-32602` döner ve `shortcut:` yorumu taşır.
- **Durum hash'i:** FNV-1a 64 (offset `0xcbf29ce484222325`, prime `0x100000001b3`) ve bayt sırası Task 7'de sabitlendi.
- **M1 borcundan ertelenen:** `PoolAllocator.slot_ptr` assert'i ve havuz kopyalama notu. M2 havuzu kullanmıyor.

## Review Focus

1. Windows'ta stdin satırları `\r\n` ile gelir; boş satırlar da gelebilir. `\r` atılmalı, boş satır yanıt üretmemeli → Task 9 testi.
2. Bayat ya da sahte entity id'si (`despawn` sonrası `component.set`, bit 48..63 dolu id) çökme değil, 1001 `dead_entity` hatası vermeli → Task 4, Task 5, Task 9 testleri.
3. Kesik, yanlış magic'li ya da bozulmuş kayıt dosyası `replay.run`'a verilirse çökme yok, yapılandırılmış hata dönmeli → Task 6 ve Task 8 testleri.
4. Yanlış bileşen/alan adı, sayı yerine string değer, readonly alana yazma → `-32602` / 1002 / 1003 / 1009, dünya değişmemeli → Task 9 testi.
5. Dünya kapasitesi ya da kuyruk dolunca `entity.spawn` yarım varlık bırakmamalı, 1006 / 1007 dönmeli → Task 5, Task 6, Task 9 testleri.

---

### Task 1: M1 borcu — arena geri sarma, `new()` rollback, tahsisatçı sorguları

**Files:**
- Modify: `memory/arena.v`, `memory/epoch.v`, `memory/pool.v`, `ecs/entity_alloc.v`
- Test: `memory/arena_test.v`, `memory/epoch_test.v`, `memory/pool_test.v`, `ecs/entity_alloc_test.v`

**Interfaces:**
- Produces: `(a &LinearArena) mark() u64`, `(mut a LinearArena) rewind(m u64)`, `(a &EntityAllocator) high_water() u32`, `(a &EntityAllocator) handle_at(idx u32) ?EntityID`

- [ ] **Step 1: Başarısız testler**

```v
// memory/arena_test.v
fn test_mark_rewind() {
	mut buf := []u8{len: 1024}
	mut a := LinearArena.new(buf.data, 1024)
	a.alloc_aligned(100, 1) or { panic('') }
	m := a.mark()
	a.alloc_aligned(200, 1) or { panic('') }
	a.rewind(m)
	assert a.used() == 100
	a.rewind(900) // ileri sarma yok sayilir
	assert a.used() == 100
}

// memory/epoch_test.v: ikinci yari sigmazsa parent degismez
fn test_epoch_new_rolls_back() {
	mut buf := []u8{len: 256}
	mut parent := LinearArena.new(buf.data, 192)
	before := parent.used()
	if _ := EpochArena.new(mut parent, 128) { assert false }
	assert parent.used() == before
}
// memory/pool_test.v ve ecs/entity_alloc_test.v: aynı kalıp. Parent ilk alloc'a yetsin, son alloc'a yetmesin; none döndükten sonra parent.used() == before.

// ecs/entity_alloc_test.v
fn test_handle_at_and_high_water() {
	// cap 8, create 3 (idx 0,1,2), destroy idx 1
	assert a.high_water() == 3
	assert a.handle_at(0)? == e0
	assert a.handle_at(1) == none   // ölü
	assert a.handle_at(7) == none   // high_water dışı
}
```

- [ ] **Step 2:** `v -gc none test memory/ ecs/` → yeni testler FAIL.
- [ ] **Step 3: Uygula.** `rewind(m)` yalnızca `m <= offset` ise `offset = m` yapar. Üç `new()` fonksiyonu girişte `mark()` alır, herhangi bir alt tahsis başarısız olursa `rewind` edip `none` döner. `handle_at`, `idx < high_water` ve alive bit set ise `make_entity(idx, generations[idx])` döner.
- [ ] **Step 4:** `v -gc none test memory/ ecs/` → PASS (M1 testleri dahil).

---

### Task 2: Şema registry + çekirdek bileşenler

**Files:**
- Create: `ecs/schema.v`, `ecs/core.v`
- Test: `ecs/schema_test.v`

**Interfaces:**
- Produces:
  - `pub enum FieldType as u8 { f32_ i32_ bool_ entity symbol }`
    - `(t FieldType) name() string` → `'f32','i32','bool','entity','symbol'`
    - `(t FieldType) size() u32` → `4,4,4,8,4`
  - `pub struct FieldSchema { pub: name string; typ FieldType; unit string; min f64; max f64; desc string; readonly bool }`
  - `pub struct ComponentSchema { pub: id u16; name string; fields []FieldSchema }`
    - `(s &ComponentSchema) field_index(name string) ?u16`
  - `pub struct Registry`
    - `(mut r Registry) register[T]() !u16`
    - `(r &Registry) count() u16`
    - `(r &Registry) component(id u16) ?ComponentSchema`
    - `(r &Registry) find(name string) ?u16`
  - `pub const max_components = 64`, `pub const max_fields = 16`
  - `pub fn core_registry() !Registry` → `Transform` id 0, `Body` id 1
  - `pub struct Transform { x, y, prev_x, prev_y f32 }`, `pub struct Body { vx, vy f32 }`
  - `pub const transform_id = u16(0)`, `pub const body_id = u16(1)`

- [ ] **Step 1: Başarısız testler**

```v
// ecs/schema_test.v
module ecs

fn test_core_registry_layout() {
	r := core_registry()!
	assert r.count() == 2
	t := r.component(transform_id)?
	assert t.name == 'Transform'
	assert t.fields.map(it.name) == ['x', 'y', 'prev_x', 'prev_y']
	assert t.fields[0].typ == .f32_ && t.fields[0].unit == 'm'
	assert t.fields[2].readonly && !t.fields[0].readonly
	b := r.component(body_id)?
	assert b.fields.map(it.name) == ['vx', 'vy']
	assert b.fields[0].unit == 'm/s'
	assert r.find('Body')? == body_id
	assert r.find('Nope') == none
	assert t.field_index('prev_y')? == 3
}

struct Ranged { v f32 @[min: '-5'; max: '5'; desc: 'aralik'] }
fn test_attr_parsing() {
	mut r := Registry{}
	id := r.register[Ranged]()!
	f := r.component(id)?.fields[0]
	assert f.min == -5.0 && f.max == 5.0 && f.desc == 'aralik'
}

struct BadType { s string }
fn test_register_rejects() {
	mut r := core_registry()!
	if _ := r.register[Transform]() { assert false } // ayni ad
	if _ := r.register[BadType]() { assert false }   // desteklenmeyen tip
}
```

- [ ] **Step 2:** `v -gc none test ecs/` → FAIL.
- [ ] **Step 3: Uygula.**
  - `register[T]` `$for f in T.fields` ile döner.
  - Tip eşlemesi: `$if f.typ is f32` → `.f32_`, `i32` → `.i32_`, `bool` → `.bool_`, `EntityID` → `.entity`. Başka tip hata verir.
  - `f.attrs` öğeleri `unit: 'm'` biçiminde gelir (tırnaklar dahil). İlk `': '` noktasından bölünür, değerin tırnakları soyulur. `readonly` tek kelimelik bir attr'dir.
  - `min`/`max` verilmezse ±`3.4028234663852886e38` olur. Sayıya çevrilemezse hata.
  - Bileşen adı `T.name`'dir. Ad tekrarı, `max_components` ve `max_fields` aşımı hata verir.
  - `core.v` alan attr'ları:
    - `x`, `y`: `unit: 'm'`
    - `prev_x`, `prev_y`: `unit: 'm'; readonly; desc: 'Önceki tick konumu (interpolasyon)'`
    - `vx`, `vy`: `unit: 'm/s'`
- [ ] **Step 4:** `v -gc none test ecs/` → PASS.

---

### Task 3: `ComponentStore` — sparse-set + ham SoA kolonlar

**Files:**
- Create: `ecs/store.v`
- Test: `ecs/store_test.v`

**Interfaces:**
- Consumes: `memory.LinearArena` (`mark/rewind`), `FieldType.size()`, `max_fields`, `null_index`
- Produces:
  - Kurulum: `ComponentStore.new(mut parent memory.LinearArena, fields []FieldType, capacity u32) ?ComponentStore`
  - Değiştirenler:
    - `(mut s ComponentStore) insert(index u32) ?u32`: satır no döner. Satırın tüm alanları 0'lanır. Varsa ya da `index >= capacity` ise `none`.
    - `(mut s ComponentStore) remove(index u32) bool`: swap-and-pop.
    - `(mut s ComponentStore) set_raw(row u32, field u16, bits u64)`
  - Sorgular:
    - `(s &ComponentStore) has(index u32) bool`
    - `(s &ComponentStore) row_of(index u32) ?u32`
    - `(s &ComponentStore) len() u32`
    - `(s &ComponentStore) index_at(row u32) u32`
    - `(s &ComponentStore) field_count() u16`
    - `(s &ComponentStore) field_size(field u16) u32`
  - Ham erişim:
    - `(s &ComponentStore) get_raw(row u32, field u16) u64`: ham bitler, küçük-uçlu, sıfır genişletilmiş. `set_raw` yalnızca alanın `size` baytını yazar.
    - `(s &ComponentStore) column_f32(field u16) &f32`

- [ ] **Step 1: Başarısız testler**

```v
// ecs/store_test.v
module ecs
import memory
import math

fn new_store(cap u32) ComponentStore {
	region := memory.reserve(1 << 20) or { panic('') }
	mut a := memory.LinearArena.new(region, 1 << 20)
	return ComponentStore.new(mut a, [FieldType.f32_, .f32_, .entity], cap) or { panic('') }
}

fn test_insert_set_get() {
	mut s := new_store(16)
	r := s.insert(5)?
	assert s.has(5) && s.row_of(5)? == r && s.len() == 1
	assert s.get_raw(r, 0) == 0
	s.set_raw(r, 1, u64(math.f32_bits(2.5)))
	s.set_raw(r, 2, u64(0x0000_0003_0000_0007))
	assert math.f32_from_bits(u32(s.get_raw(r, 1))) == 2.5
	assert s.get_raw(r, 2) == u64(0x0000_0003_0000_0007)
	assert s.insert(5) == none
	assert s.insert(16) == none
}

fn test_swap_and_pop_keeps_data() {
	mut s := new_store(16)
	for i in [u32(1), 2, 3] { r := s.insert(i)?; s.set_raw(r, 0, u64(math.f32_bits(f32(i)))) }
	assert s.remove(1)
	assert !s.has(1) && s.len() == 2
	r3 := s.row_of(3)?
	assert r3 == 0 && s.index_at(0) == 3
	assert math.f32_from_bits(u32(s.get_raw(r3, 0))) == 3.0
	assert !s.remove(1)
}

fn test_columns_64_aligned() {
	s := new_store(16)
	assert u64(s.column_f32(0)) % 64 == 0
}

fn test_new_rejects_too_many_fields() {
	// 17 alanlı fields dizisi → none ve parent.used() değişmez
}
```

- [ ] **Step 2:** `v -gc none test ecs/` → FAIL.
- [ ] **Step 3: Uygula.**
  - Bellek düzeni:
    - `sparse` (`capacity × u32`, `null_index` ile doldurulur)
    - `dense` (`capacity × u32`)
    - alan başına bir kolon (`capacity × size`)
    - hepsi 64 hizalı, parent'tan alınır
  - Sabit dizilerin alanları: `columns [max_fields]&u8`, `sizes [max_fields]u8`.
  - Sparse dizinin üstüne bir satır yorum: `// shortcut: düz sparse dizi (kapasite × 4 B); M6'da betik bileşenleri çoğalınca sayfalı yapıya geç`.
- [ ] **Step 4:** `v -gc none test ecs/` → PASS.

---

### Task 4: `World`

**Files:**
- Create: `ecs/world.v`
- Test: `ecs/world_test.v`

**Interfaces:**
- Consumes: `EntityAllocator` (Task 1 dahil), `ComponentStore`, `Registry`
- Produces:
  - Tipler ve kurulum:
    - `pub enum Status as u8 { ok dead_entity unknown_component unknown_field already_has missing_component capacity_full }`
    - `World.new(mut parent memory.LinearArena, reg &Registry, capacity u32) ?World`: kayıtlı her bileşen için bir store açılır, store id'si bileşen id'sine eşittir.
  - Değiştirenler:
    - `(mut w World) spawn() ?EntityID`
    - `(mut w World) despawn(e EntityID) bool`: varlığı tüm store'lardan çıkarır.
    - `(mut w World) add_component(e EntityID, comp u16) Status`
    - `(mut w World) remove_component(e EntityID, comp u16) Status`
    - `(mut w World) set_field(e EntityID, comp u16, field u16, bits u64) Status`
  - Sorgular:
    - `(w &World) is_alive(e EntityID) bool`
    - `(w &World) has(e EntityID, comp u16) bool`
    - `(w &World) get_field(e EntityID, comp u16, field u16) ?u64`
    - `(w &World) store_count() u16`
    - `(w &World) store(comp u16) &ComponentStore`: çağıran `comp < store_count()` garantiler.
    - `(w &World) entities() &EntityAllocator`
    - `(w &World) alive_count() u32`

- [ ] **Step 1: Başarısız testler.** Hepsi `core_registry()` ve `capacity 8` ile.

```v
// ecs/world_test.v
fn test_spawn_add_set_get() {
	e := w.spawn()?
	assert w.add_component(e, transform_id) == .ok
	assert w.add_component(e, transform_id) == .already_has
	assert w.set_field(e, transform_id, 0, u64(math.f32_bits(4.0))) == .ok
	assert math.f32_from_bits(u32(w.get_field(e, transform_id, 0)?)) == 4.0
	assert w.set_field(e, body_id, 0, 0) == .missing_component
	assert w.set_field(e, transform_id, 9, 0) == .unknown_field
	assert w.add_component(e, 7) == .unknown_component
}

fn test_despawn_clears_stores_and_stale_handle() {
	e := w.spawn()?
	w.add_component(e, transform_id)
	w.add_component(e, body_id)
	assert w.despawn(e)
	assert w.store(transform_id).len() == 0 && w.store(body_id).len() == 0
	assert w.set_field(e, transform_id, 0, 0) == .dead_entity
	assert w.add_component(EntityID(u64(e) | (u64(1) << 50)), transform_id) == .dead_entity
	assert !w.despawn(e)
}

fn test_capacity_full() {
	for _ in 0 .. 8 { w.spawn()? }
	assert w.spawn() == none
}
```

- [ ] **Step 2:** `v -gc none test ecs/` → FAIL.
- [ ] **Step 3: Uygula.**
  - Store'lar `[]ComponentStore` içinde tutulur, kurulumda bir kez doldurulur. Tick yolunda büyütülmez.
  - Hata kontrol sırası: `dead_entity` → `unknown_component` → `missing_component`/`already_has` → `unknown_field`.
  - `World.new` başarısız olursa parent geri sarılır.
- [ ] **Step 4:** `v -gc none test ecs/` → PASS.

---

### Task 5: `Command` ve `apply`

**Files:**
- Create: `cmd/command.v`
- Test: `cmd/command_test.v`

**Interfaces:**
- Consumes: `ecs.World` mutasyonları, `ecs.Status`
- Produces:
  - `pub enum CommandKind as u8 { spawn despawn add_component remove_component set_field }`
  - `pub enum Source as u8 { script editor agent }`: uygulama sırası budur.
  - `pub struct Command { pub mut: kind CommandKind; source Source; comp u16; field u16; pad u16; entity ecs.EntityID; value u64 }`: 24 bayt.
  - `pub struct ApplyResult { pub: status ecs.Status; entity ecs.EntityID }`
  - `pub fn apply(mut w ecs.World, c Command) ApplyResult`: `spawn` için `entity` yeni id'dir, diğer komutlarda `c.entity`. Spawn başarısızsa `capacity_full` ve `ecs.null_entity` döner.

- [ ] **Step 1: Başarısız testler**

```v
// cmd/command_test.v
module cmd
fn test_command_is_24_bytes() { assert sizeof(Command) == 24 }

fn test_apply_each_kind() {
	sp := apply(mut w, Command{ kind: .spawn, source: .agent })
	assert sp.status == .ok
	e := sp.entity
	assert apply(mut w, Command{ kind: .add_component, entity: e, comp: ecs.body_id }).status == .ok
	assert apply(mut w, Command{ kind: .set_field, entity: e, comp: ecs.body_id, field: 1, value: u64(math.f32_bits(3.0)) }).status == .ok
	assert apply(mut w, Command{ kind: .remove_component, entity: e, comp: ecs.body_id }).status == .ok
	assert apply(mut w, Command{ kind: .despawn, entity: e }).status == .ok
	assert apply(mut w, Command{ kind: .despawn, entity: e }).status == .dead_entity
}

fn test_spawn_capacity_full() {
	// capacity 2 dünyada üçüncü spawn → .capacity_full, entity == ecs.null_entity
}
```

- [ ] **Step 2:** `v -gc none test cmd/` → FAIL.
- [ ] **Step 3: Uygula.** `apply`, `kind` üzerinden `match` ile `World`'e yönlendirir. `despawn` false dönerse durum `dead_entity` olur.
- [ ] **Step 4:** `v -gc none test cmd/` → PASS.

---

### Task 6: `Recorder` (tampon + ikili dosya) ve `CommandQueue`

**Files:**
- Create: `cmd/record.v`, `cmd/queue.v`
- Test: `cmd/record_test.v`, `cmd/queue_test.v`

**Interfaces:**
- Consumes: `Command`, `apply`, `memory.LinearArena`
- Produces:
  - Kayıt tipleri:
    - `pub struct RecordEntry { pub: tick u64; cmd Command }`: 32 bayt.
    - `pub struct Recording { pub: capacity u32; end_tick u64; entries []RecordEntry }`
  - `Recorder`, kurulum ve yaşam döngüsü:
    - `Recorder.new(mut parent memory.LinearArena, capacity u32) ?Recorder`
    - `(mut r Recorder) start()`: len, overflow ve active durumunu sıfırlar.
    - `(mut r Recorder) stop()`
  - `Recorder`, tick yolu:
    - `(mut r Recorder) append(tick u64, c Command)`: aktif değilse no-op. Tampon doluysa `overflowed = true` olur, kayıt atılır.
  - `Recorder`, sorgular:
    - `(r &Recorder) is_active() bool`
    - `(r &Recorder) len() u32`
    - `(r &Recorder) overflowed() bool`
  - `Recorder`, dosya:
    - `(r &Recorder) save(path string, world_capacity u32, end_tick u64) !`: taşma olduysa hata.
    - `pub fn load_recording(path string) !Recording`
  - `CommandQueue`:
    - `CommandQueue.new(mut parent memory.LinearArena, capacity u32) ?CommandQueue`
    - `(mut q CommandQueue) push(c Command) bool`: doluysa false. Flush'tan sonraki ilk push kuyruğu ve sonuçları temizler.
    - `(mut q CommandQueue) flush(mut w ecs.World, tick u64, mut rec Recorder) u32`: uygulanan (`ok`) komut sayısını döner.
    - `(q &CommandQueue) len() u32`
    - `(q &CommandQueue) result(i u32) ApplyResult`: i'inci push edilen komutun sonucu, bir sonraki push'a kadar geçerli.
- Dosya biçimi (doğal bayt sırası, x86'da küçük-uçlu):
  - 32 baytlık başlık, sırayla:
    - `magic u32 = 0x43524356` ("VCRC")
    - `version u32 = 1`
    - `world_capacity u32`
    - `reserved u32 = 0`
    - `end_tick u64`
    - `count u64`
  - Ardından `count × RecordEntry`.

- [ ] **Step 1: Başarısız testler**

```v
// cmd/queue_test.v
fn test_flush_applies_by_source_class_then_push_order() {
	// e önceden var, Transform'u var. Aynı alana üç set:
	q.push(Command{ kind: .set_field, source: .agent,  entity: e, comp: 0, field: 0, value: bits(3.0) })
	q.push(Command{ kind: .set_field, source: .script, entity: e, comp: 0, field: 0, value: bits(1.0) })
	q.push(Command{ kind: .set_field, source: .editor, entity: e, comp: 0, field: 0, value: bits(2.0) })
	assert q.flush(mut w, 0, mut rec) == 3
	assert f32_of(w.get_field(e, 0, 0)?) == 3.0      // agent en son uygulanır
	assert q.result(1).status == .ok
}

fn test_flush_records_ok_only_with_spawn_id() {
	rec.start()
	q.push(Command{ kind: .spawn, source: .agent })
	q.push(Command{ kind: .despawn, source: .agent, entity: ecs.make_entity(99, 0) }) // dead_entity
	q.flush(mut w, 7, mut rec)
	assert rec.len() == 1
	// kayıttaki spawn komutunun entity alanı q.result(0).entity'dir, tick 7
}

fn test_push_full_returns_false() { /* capacity 2: üçüncü push false */ }

// cmd/record_test.v
fn test_save_load_roundtrip() {
	// 3 entry append, save(path, 100, 42), load: capacity 100, end_tick 42, entries aynı
}
fn test_load_rejects_bad_files() {
	// yok olan dosya, 10 baytlık dosya, yanlış magic, count ile boyut uyuşmayan (kesik) dosya → hepsi hata
}
fn test_overflow_blocks_save() { /* capacity 1, 2 append → overflowed, save hata */ }
fn test_entry_is_32_bytes() { assert sizeof(RecordEntry) == 32 }
```

- [ ] **Step 2:** `v -gc none test cmd/` → FAIL.
- [ ] **Step 3: Uygula.**
  - `flush` her `Source` değeri için sırayla bütün kuyruğu tarar ve o sınıfın komutlarını push sırasıyla uygular. Sıralama tamponu yoktur, tahsis yoktur.
  - Kayıt yalnızca `status == .ok` olan komutlar için yapılır. Spawn için `entity` alanı sonuçtaki id ile yazılır.
  - `save` ve `load_recording` dosya I/O yapar, tick dışındadır. Ham baytlar `unsafe { vmemcpy }` ile kopyalanır.
  - `load` tüm uzunluk ve başlık kontrollerini kopyalamadan önce yapar.
- [ ] **Step 4:** `v -gc none test cmd/` → PASS.

---

### Task 7: `Sim` — sabit adım, hareket sistemi, durum hash'i, tahsis sayacı

**Files:**
- Create: `sim/sim.v`, `sim/hash.v`, `memory/heapcount.v`, `memory/heapcount.h`
- Test: `sim/sim_test.v`, `sim/hash_test.v`, `sim/alloc_test.v`

**Interfaces:**
- Consumes: `ecs.World`, `cmd.CommandQueue`, `cmd.Recorder`, `ecs.transform_id/body_id`
- Produces:
  - Yapılandırma ve kurulum:
    - `pub const dt = f32(1.0) / f32(120.0)`
    - `pub struct Config { pub: capacity u32 = 100_000; queue_capacity u32 = 65_536; record_capacity u32 = 1_048_576 }`
    - `pub fn (c Config) bytes_needed(reg &ecs.Registry) u64`: tüm alt tahsislerin tam boyutlarının toplamı, artı tahsis başına 64 bayt.
    - `Sim.new(mut parent memory.LinearArena, reg &ecs.Registry, cfg Config) ?Sim`
  - `Sim` alanları: `pub mut: world ecs.World; queue cmd.CommandQueue; recorder cmd.Recorder`. `tick` özeldir.
  - `Sim` metotları:
    - `(mut s Sim) push(c cmd.Command) bool`
    - `(mut s Sim) flush() u32`: o anki tick numarasıyla.
    - `(mut s Sim) step()`
    - `(s &Sim) tick() u64`
    - `(s &Sim) state_hash() u64`
  - Hash: `pub fn state_hash(w &ecs.World, tick u64) u64`
  - Tahsis sayacı:
    - `memory.heap_alloc_count() u64`
    - `memory.heap_tracking_enabled() bool`

- [ ] **Step 1: Başarısız testler**

```v
// sim/sim_test.v
fn test_step_order_and_motion() {
	// e: Transform{x:0} + Body{vx:1}; s.step() bir kez
	// sonra: prev_x == 0, x == dt, tick == 1
	// e2: yalnız Transform{x:5}; komutla x=9 set edilip step → prev_x == 9, x == 9 (ışınlanma süzülmez)
}
fn test_thousand_steps() {
	// vx = 1, 1000 step → x, f32 toplamıyla elde edilir: beklenen değer döngüde `x += f32(1.0) * dt` ile hesaplanır, == ile karşılaştırılır (bit eşit)
}

// sim/hash_test.v
fn test_hash_known_vector() {
	// boş dünya, tick 0 → FNV-1a(8 bayt sıfır) = 0xa8c7f832281a39c5
	assert state_hash(w, 0) == u64(0xa8c7f832281a39c5)
}
fn test_hash_sensitive_and_stable() {
	// iki ayrı Sim'de aynı komutlar → aynı hash; tek alan değişince farklı hash; tick farkı → farklı hash
}

// sim/alloc_test.v
fn test_tick_has_zero_heap_allocs() {
	if !memory.heap_tracking_enabled() {
		eprintln('atlandi: -d track_heap ile calistir')
		return
	}
	x := 'canli mi'.repeat(3)               // kanca gerçekten sayıyor mu?
	before0 := memory.heap_alloc_count()
	_ = x + '!'
	assert memory.heap_alloc_count() > before0
	// 1000 varlık Transform+Body, 1000 set_field push edilmiş, kayıt aktif
	before := memory.heap_alloc_count()
	for _ in 0 .. 100 { s.step() }
	assert memory.heap_alloc_count() == before
}
```

- [ ] **Step 2:** `v -gc none test sim/` → FAIL.
- [ ] **Step 3: Uygula.**
  - **`step()`:**
    1. `flush()` (tick = mevcut tick)
    2. Tüm Transform satırlarında `prev_x = x`, `prev_y = y`
    3. Body store'un her satırında, varlıkta Transform varsa `x += vx * dt`, `y += vy * dt`
    4. `tick++`

    `sim/sim.v` dosyasına `#flag -ffp-contract=off` eklenir.
  - **Hash:** FNV-1a 64, tek tek baytlar üzerinden. Sıra:
    1. `idx = 0 .. high_water` artan sırayla, her canlı varlık için:
       - `EntityID`'nin 8 baytı
       - id'si artan sırada, varlıkta bulunan her bileşen için: `comp id` (2 bayt) ve alanları sırayla, her alan kendi `size` baytı kadar
    2. En sonda `tick` (8 bayt)

    Tüm sayılar küçük-uçlu.
  - **Tahsis sayacı:** `heapcount.h`, V'nin `-d track_heap` kancası olan `void vheap_alloc(void* p, unsigned long long n)` içinde bir sayaç artırır. `vheap_free` de tanımlanır. `heapcount.v` bu header'ı her derlemede `#include "@VMODROOT/memory/heapcount.h"` ile alır; kanca yalnızca `-d track_heap` ile çağrılır. `heap_tracking_enabled()` için `$if track_heap ? { return true }`.
- [ ] **Step 4:** `v -gc none test sim/` ve `v -gc none -d track_heap test sim/` → PASS. İkincisinde alloc testi atlanmadan geçmeli.

---

### Task 8: Tekrar oynatma ve determinizm

**Files:**
- Create: `sim/replay.v`
- Test: `sim/replay_test.v`

**Interfaces:**
- Consumes: `cmd.Recording`, `cmd.load_recording`, `cmd.apply`, `Sim`, `Config.bytes_needed`, `memory.reserve/release`
- Produces:
  - `pub struct ReplayResult { pub: end_tick u64; hash u64 }`
  - `pub fn replay(rec cmd.Recording, reg &ecs.Registry) !ReplayResult`

- [ ] **Step 1: Başarısız testler**

```v
// sim/replay_test.v
fn test_record_replay_twice_bit_identical() {
	// canlı Sim: recorder.start; 10 spawn + Transform/Body + set (Source.agent, push+flush);
	// 500 step; 3 set_field + 1 despawn; 500 step; recorder.stop; save(tmp, cap, s.tick())
	live := s.state_hash()
	rec := cmd.load_recording(tmp)!
	a := replay(rec, reg)!
	b := replay(rec, reg)!
	assert a.hash == live && b.hash == live && a.end_tick == 1000
}
fn test_replay_detects_divergence() {
	// kaydı yükle, entries'teki ilk set_field'in entity'sini make_entity(9999, 0) yap → replay hata döner, mesajda tick var
	// spawn entry'sinin entity'si beklenenden farklıysa → hata
}
```

- [ ] **Step 2:** `v -gc none test sim/` → FAIL.
- [ ] **Step 3: Uygula.**
  - Kurulum: `Config{capacity: rec.capacity, record_capacity: 1}` için `bytes_needed` kadar bölge `reserve` edilir ve taze bir `Sim` kurulur.
  - Her entry için, kayıt sırasıyla:
    1. `tick < entry.tick` olduğu sürece `step()`
    2. `cmd.apply(mut s.world, entry.cmd)`
    3. Durum `ok` değilse ya da komut spawn ise ve dönen id `entry.cmd.entity`'den farklıysa: `error('replay ayrıştı: tick ${t}')`

    Kuyruk kullanılmaz; kayıt sırası zaten uygulama sırasıdır.
  - Bitiş: `tick < end_tick` olduğu sürece `step()`, sonra hash alınır.
  - Bölge hem hata hem başarı yolunda `release` edilir (`defer`).
- [ ] **Step 4:** `v -gc none test sim/` → PASS.

---

### Task 9: JSON-RPC protokol sunucusu

**Files:**
- Create: `protocol/server.v`, `protocol/methods.v`, `protocol/errors.v`
- Test: `protocol/server_test.v`

**Interfaces:**
- Consumes: `sim.Sim`, `sim.Config`, `sim.replay`, `cmd.*`, `ecs.core_registry`, `memory.reserve/release`
- Produces:
  - `Server.new(cfg sim.Config) !Server`: kendi bölgesini rezerve eder.
  - `(mut s Server) handle(line string) ?string`: `none` döner, yanıt yoksa (bildirim ya da boş satır).
  - `(mut s Server) close()`
- Mesajlar:
  - İstek: `{"jsonrpc":"2.0","id":<sayı|string>,"method":"...","params":{...}}`
  - Başarı yanıtı: `{"jsonrpc":"2.0","id":..,"result":..}`
  - Hata yanıtı: `{"jsonrpc":"2.0","id":..,"error":{"code":..,"message":"..","data":{..}}}`
  - `id` alanı yoksa istek bildirimdir, yanıt yok. Ayrıştırma hatasında `id` değeri `null` olur.
- Hata kodları (`errors.v` sabitleri):
  - JSON-RPC standart kodları:

    | Kod | Anlam |
    |---|---|
    | `-32700` | parse |
    | `-32600` | invalid request (dizi/batch dahil) |
    | `-32601` | method not found |
    | `-32602` | invalid params |

  - Motor kodları:

    | Kod | Anlam |
    |---|---|
    | `1001` | dead_entity |
    | `1002` | unknown_component |
    | `1003` | unknown_field |
    | `1004` | already_has |
    | `1005` | missing_component |
    | `1006` | capacity_full |
    | `1007` | queue_full |
    | `1008` | record_state |
    | `1009` | readonly_field |
    | `1010` | io_error |
    | `1011` | replay_diverged |

  - `data`: ilgili `entity` / `component` / `field` ve bir cümlelik `hint`.
- Entity id JSON'da tamsayıdır (≤ 2^48, JS güvenli). Hash `"0x%016x"` biçiminde string.
- Metotlar:
  - **Dünya:**

    | Metot | `params` | `result` |
    |---|---|---|
    | `entity.spawn` | `{"components"?: {"<Comp>": {"<field>": num}}}` | `{"entity": id}` |
    | `entity.despawn` | `{entity}` | `{}` |
    | `component.add` | `{entity, component, values?}` | `{}` |
    | `component.remove` | `{entity, component}` | `{}` |
    | `component.set` | `{entity, component, field, value}` | `{}` |

  - **Sorgu ve şema:**

    | Metot | `params` | `result` |
    |---|---|---|
    | `entity.get` | `{entity}` | `{"entity": id, "index", "generation", "components": {"Transform": {"x":..}}}` |
    | `query.entities` | `{"with": ["Comp", ...], "limit"?: n}` | `{"entities": [id...], "count": n}`; index artan sırada; `count` limit öncesi toplam |
    | `schema.components` | — | `{"components":[{"id","name","fields":[{"name","type","unit","min","max","desc","readonly"}]}]}` |
    | `schema.commands` | — | `{"commands":[{"method","params","result"}]}`; `methods.v` içindeki sabit tablodan, her değer bir açıklama string'i |

  - **Simülasyon ve kayıt:**

    | Metot | `params` | `result` |
    |---|---|---|
    | `sim.step` | `{"n": 1..1_000_000}` | `{"tick": t}` |
    | `sim.reset` | — | `{}`; dünyayı, kuyruğu ve kaydı sıfırlar |
    | `sim.state_hash` | — | `{"tick", "hash"}` |
    | `record.start` | — | `{}` |
    | `record.stop` | `{"path"}` | `{"path", "commands", "end_tick", "hash"}` |
    | `replay.run` | `{"path"}` | `{"end_tick", "hash"}` |

- [ ] **Step 1: Başarısız testler.** Her test `Server.new(sim.Config{capacity: 64, queue_capacity: 64, record_capacity: 1024})` ile.

```v
// protocol/server_test.v
fn call(mut s Server, line string) json2.Any { return json2.decode[json2.Any](s.handle(line) or { panic('yanit yok') }) or { panic(err) } }

fn test_spawn_with_components_then_get() {
	r := call(mut s, '{"jsonrpc":"2.0","id":1,"method":"entity.spawn","params":{"components":{"Transform":{"x":1.5},"Body":{"vx":2}}}}')
	// result.entity == 0
	g := call(mut s, '{"jsonrpc":"2.0","id":2,"method":"entity.get","params":{"entity":0}}')
	// result.components.Transform.x == 1.5, Body.vx == 2.0, Transform.y == 0
}
fn test_errors_are_structured() {
	// "{bozuk" → error.code -32700, id null
	// method "nope" → -32601
	// component.set entity 0 (yok) → 1001
	// spawn {"components":{"Nope":{}}} → 1002 ve dünyada varlık YOK (alive 0)
	// spawn {"components":{"Transform":{"zz":1}}} → 1003, varlık yok
	// spawn {"components":{"Transform":{"x":"a"}}} → -32602, varlık yok
	// component.set Transform.prev_x → 1009
	// '[1,2]' → -32600
}
fn test_blank_and_crlf_lines() {
	assert s.handle('') == none
	assert s.handle('\r') == none
	// '{"jsonrpc":"2.0","id":5,"method":"sim.state_hash"}\r' → geçerli yanıt, id 5
	// id'siz istek → none
}
fn test_capacity_full_spawn() { /* capacity 64: 64 spawn ok, 65. → 1006, alive 64 */ }
fn test_query_and_step() {
	// 3 spawn (yalnız 0 ve 2 Body'li); query with ["Body"] → [0,2], count 2; limit 1 → [0], count 2
	// sim.step n=0 → -32602; n=10 → tick 10
}
fn test_record_start_requires_pristine_world() {
	// spawn → record.start → 1008; sim.reset → record.start ok; ikinci record.start → 1008
	// record.stop başlamadan → 1008
}
```

- [ ] **Step 2:** `v -gc none test protocol/` → FAIL.
- [ ] **Step 3: Uygula.**
  - **Ayrıştırma:** `x.json2` ile. Satır önce `trim_space` ile kırpılır; `\r` ve boşluklar atılır.
  - **Dünyayı değiştiren çağrılar:** önce tüm adlar, alanlar, tipler ve readonly kuralı doğrulanır. Sonra `Command{source: .agent}` olarak push edilir ve `flush()` çağrılır.
  - **`entity.spawn` (components ile):**
    1. Doğrulama.
    2. Kuyrukta en az `1 + bileşen + alan` boş yer olduğu kontrol edilir; yoksa 1007.
    3. Spawn push + flush; dönen id alınır.
    4. add/set push + flush.
  - **Değer dönüşümü:** f32 dışı tipler `-32602` döner, `// shortcut: yalnız f32 JSON dönüşümü; i32/bool/entity M6'da` yorumu ile.
  - **`sim.reset`:** bölge `release`, sonra taze `reserve` ve `Sim.new`.
  - **`record.start`:** `tick() == 0 && world.entities().high_water() == 0` olmalı.
  - **`record.stop`:** `recorder.stop()`, sonra `save(path, cfg.capacity, tick)`. Hata 1010 döner.
  - **`replay.run`:** `load_recording` hatası 1010, `replay` hatası 1011 döner.
- [ ] **Step 4:** `v -gc none test protocol/` → PASS.

---

### Task 10: `vcore headless` ikilisi + ilk ajan senaryosu

**Files:**
- Create: `cmd_main/main.v`, `tests/scenarios/m2_agent.jsonl`
- Test: `tests/agent_scenario_test.v`

**Interfaces:**
- Consumes: `protocol.Server`, `sim.Config`
- Produces:
  - `vcore headless [--capacity N]`:
    - stdin'den satır okur, her yanıtı tek satır yazar ve stdout'u flush eder.
    - EOF'ta çıkış kodu 0.
    - Bilinmeyen mod ya da argüman: stderr'e kullanım mesajı, çıkış kodu 2.
  - Derleme: `v -gc none -prod -o bin/vcore.exe cmd_main`.

- [ ] **Step 1: Senaryo dosyası** (`tests/scenarios/m2_agent.jsonl`, satır başına bir istek, id'ler 1'den artan):
  1. `schema.components`
  2. `record.start`
  3. Üç spawn:
     - A: `Transform{x:0,y:0}`, `Body{vx:1,vy:0.5}`
     - B: `Transform{x:10,y:10}`
     - C: `Transform{x:0,y:0}`, `Body{vx:-2,vy:0}`
  4. `sim.step n=1000`
  5. `entity.get 0`
  6. `query.entities with ["Body"]`
  7. `entity.despawn 2`
  8. `query.entities with ["Transform"]`
  9. `component.set` entity 2 (`dead_entity` beklenir)
  10. `sim.state_hash`
  11. `record.stop path "m2_agent.vcrec"`
  12. `replay.run` aynı path
  13. `replay.run` aynı path
- [ ] **Step 2: Başarısız test** `tests/agent_scenario_test.v` (`module main`):
  - Hazırlık:
    - `@VMODROOT/cmd_main` geçici klasöre `v -gc none -o <tmp>/vcore.exe` ile derlenir.
    - `os.chdir(tmp)`, sonra `os.execute('vcore.exe headless < "<VMODROOT>/tests/scenarios/m2_agent.jsonl"')`.
    - Çıkış kodu 0 olmalı. Çıktı satırları id'ye göre eşlenir, her satır geçerli JSON olmalı.
  - Beklenen yanıtlar:
    - spawn id'leri 0, 1, 2
    - adım 5: `x` ile `1000 * dt` farkı `< 1e-3`, `y` ile `500 * dt` farkı `< 1e-3`
    - adım 6: `[0, 2]`
    - adım 8: `[0, 1]`
    - adım 9: `error.code == 1001`
    - adım 10, 11, 12 ve 13'teki hash'lerin hepsi aynı
    - adım 12'de `end_tick == 1000`
  - Ek test: `vcore.exe nope` çıkış kodu 2 vermeli.
- [ ] **Step 3:** `v -gc none test tests/` → FAIL.
- [ ] **Step 4: Uygula** `cmd_main/main.v`: `os.get_raw_line()` döngüsü, `Server.handle`, `println` ve `flush_stdout()`. Satır sonu kırpma `handle` içinde yapılır.
- [ ] **Step 5:** `v -gc none test tests/` → PASS. `v -gc none -prod -o bin/vcore.exe cmd_main` hatasız derlenmeli.

---

### Task 11: Benchmark — benchkit borcu + `m2_tick`

**Files:**
- Modify: `bench/benchkit/benchkit.v`, `bench/benchkit/benchkit_test.v`, `bench/m1_memory.v`, `bench/results/*.json` (4 dosya)
- Create: `bench/m2_tick.v`

**Interfaces:**
- Produces:
  - Yeni alanlar: `Report.suite string`, `Result.seed u64`
  - `write_report(r Report, dir string) !string`: dosya adı `<date>-<suite>-<label>.json`
  - `latest_report(dir string, suite string, exclude_path string) ?Report`: yalnız aynı `suite` raporları.
  - `compare(prev, cur)`: önceki raporda olup şimdikinde olmayan ölçüm için ayrıca `<name>: KAYIP` satırı.
  - Sonuç klasörü: `os.join_path(@VMODROOT, 'bench', 'results')`

- [ ] **Step 1: Başarısız testler** (`benchkit_test.v`):
  - `compare` çıktısı: önceki raporda `a, b`, şimdikinde `a` varsa `b: KAYIP` içermeli.
  - `latest_report(dir, 'x', '')` farklı suite'li daha yeni bir raporu atlamalı.
  - `write_report` dosya adı `-<suite>-<label>.json` ile bitmeli.
- [ ] **Step 2:** `v -gc none test bench/benchkit/` → FAIL.
- [ ] **Step 3: benchkit'i uygula.**
  - `m1_memory.v`: `suite: 'm1_memory'`, results dir `@VMODROOT`.
  - Mevcut 4 JSON dosyasına `"suite":"m1_memory"` eklenir. Dosya adları değişmez.
- [ ] **Step 4: `bench/m2_tick.v` yaz.**
  - Ortak kurulum:
    - `suite: 'm2_tick'`, `const seed = u64(0x5EED)`
    - 100k varlık, `Transform` + `Body`
    - Değerler splitmix64'ten f32: konum `[-100, 100)`, hız `[-10, 10)`. Kurulum komutlarla, kuyruk üzerinden yapılır.
  - Üç ölçüm:

    | Ölçüm | Örnek başına iş | `ops_per_sample` | `state_hash` |
    |---|---|---|---|
    | `tick_motion_100k` | bir `step()` | 1 | ölçüm sonrası, hex |
    | `cmd_flush_set_100k` | 100k `set_field` push + `flush` | 100k | — |
    | `state_hash_100k` | — | — | — |

    Isınma 10, iterasyon 200.
  - Determinizm kontrolü: aynı tohumla iki ayrı `Sim` kurulur, her biri 1000 adım koşar, hash'ler eşit değilse `panic`.
  - Çıktı: tablo, rapor yolu ve aynı suite'in önceki raporuyla karşılaştırma.
- [ ] **Step 5:** `v -gc none test bench/benchkit/` → PASS. Ardından iki kez `v -gc none -prod run bench/m2_tick.v m2` → JSON yazılır. İki koşuda `tick_motion_100k` hash'i aynı olmalı, ikinci koşu ilkiyle karşılaştırma basmalı. `v -gc none -prod run bench/m1_memory.v m1` de çalışmalı.
- [ ] **Step 6: Tam doğrulama:**
  - `v -gc none test memory/ ecs/ cmd/ sim/ protocol/ bench/benchkit/ tests/`
  - `v -gc none -d track_heap test sim/`

  İkisi de PASS olmalı.
