# V-Core Oyun Motoru — Tasarım Belgesi

**Tarih:** 2026-11-17
**Kaynak:** `mynotes.md` (TDD 1.0.0-RC1) + brainstorming oturumu
**Durum:** Builder kontrolünden geçti, kullanıcı onayı bekliyor

Bu belge `mynotes.md`'nin yerine geçmez; onu temel alır, çelişkilerini düzeltir ve notlarda olmayan iki büyük şartı (ajan-native kontrol, insan editörü) ekler. Notlardaki matematik ve algoritmalar (hizalama, sparse-set, swap-and-pop, semplektik Euler, counting-sort hash grid, impulse çözümü, NaN-boxing, 32-bit buyruk kodlaması, Pratt parser) aksi belirtilmedikçe aynen geçerlidir.

---

## 1. Niyet ve neden

V güçlü ve esnek bir dil ama ciddi bir oyun motoru yok. Amaç, V ile C/C++'a yakın performans ve küçük binary boyutu veren, **motorun kendisi ürün olan** bir oyun motoru inşa etmek. Hedeflenen oyun türleri geniş: 2B, ileride FPS (3B), mobil ve tarayıcı oyunları.

Motoru farklı kılan iki şey:

1. **Ajan-native:** Unity gibi motorlarda yapay zekâ desteği (MCP vb.) sonradan eklenmiş bir yama gibi duruyor. V-Core'da yapay zekâ ajanı baştan birinci sınıf kullanıcıdır: motoru tam kontrol eder, sahneyi tam analiz eder.
2. **İnsan ve ajan eşittir:** Kullanıcı hiç LLM kullanmadan editörde obje ve harita tasarlayabilir; isterse aynı işi ajana yaptırır ya da ikisini karıştırır.

Performans iddiaları benchmark'larla kanıtlanır.

## 2. Hedefler

- G1. Notlardaki performans hedefi: tek masaüstü CPU'da 100.000 aktif varlık, 120 Hz sabit adım (8.33 ms bütçe). Bu bir kilometre taşıdır, ilk gün hedefi değildir.
- G2. Deterministik simülasyon: aynı başlangıç durumu + aynı komut akışı → bit düzeyinde aynı durum.
- G3. Ajanın yapabildiği her şeyi insan editörde yapabilir; insanın yapabildiği her şeyi ajan protokolle yapabilir.
- G4. Ajan sahneyi tahmin yürütmeden okuyabilir: hangi varlıklar var, hangi bileşenler, alanlar, tipler, birimler; uzamsal sorgular; durum özeti (hash); ekran görüntüsü.
- G5. Sıfırdan değil, en alt katmandan başlayarak ince, uçtan uca çalışan dilimlerle ilerlemek; her dilim test ve benchmark ile gelir.
- G6. Platform sınırı baştan doğru çizilir: ilk arka uç Windows, sonra WASM/WebGL2 ve Android eklenebilir olmalı.

## 3. Hedef olmayanlar (şimdilik)

- 3B render, FPS kamera, iskelet animasyonu (2B çekirdek oturduktan sonra).
- Ağ / çok oyunculu (determinizm ileride lockstep'e kapı açar ama kapsam dışı).
- Ses (ileride bit-haritalı havuzla).
- Fotorealizm. Öncelik simülasyon yoğunluğu.
- Linux/macOS arka uçları (sınır buna izin verir ama bu belgede yazılmaz).

## 4. Başarısızlık koşulları (anti-goal)

- **Editör ucuz, generic ya da "AI yapmış" görünürse proje başarısız sayılır.** Dear ImGui'nin varsayılan "geliştirici paneli" görünümü kabul edilmez. Hedef his: Figma / Linear gibi sakin, tutarlı, özenli.
- Ajan desteği sonradan takılmış bir katman gibi durursa (bazı işlemler yalnızca editörden ya da yalnızca protokolden yapılabiliyorsa) başarısızdır.
- Performans iddiası benchmark'sız yapılırsa geçersizdir.

## 5. Kısıtlar

- **Dil:** V 0.5.2 (makinede kurulu: `V 0.5.2 7647ce1`). C11 yalnızca SIMD çekirdekleri ve V'nin doğrudan ifade edemediği OS çağrıları için. C++ kullanılmaz (notlardaki `extern "C"` C++20 sınırı gereksiz, çıkarıldı).
- **Derleyici:** gcc 16.1 (MinGW-W64). clang/tcc kurulu değil.
- **Bellek:** `-gc none`. Sıfır tahsis kuralı **simülasyon tick'i** için geçerlidir (aşağıda 7.1).
- **Üçüncü parti:** SDL, GLFW, Raylib, Sokol, Lua gibi soyutlama katmanları/runtime'lar yasak. **Benim kararım:** tek dosyalık, public-domain, vendor'lanan format kütüphaneleri serbest: `stb_truetype.h` (font rasterizasyonu), `stb_image.h` / `stb_image_write.h` (doku yükleme, ekran görüntüsü PNG). Gerekçe: bunlar soyutlama katmanı değil, dosya formatı ayrıştırıcısı; TTF rasterizer yazmak motorun amacına hizmet etmez.
- **Proje klasörü** `Kaboom/` şu an git deposu değil.

## 6. Yaklaşımlar

| Yaklaşım | Özet | Artı | Eksi | Karar |
|---|---|---|---|---|
| A. Katı katman katman | Notlardaki sırayla: bellek → ECS → fizik → VScript → event bus → render → protokol → editör | Her katman sağlam | Protokol/editör en sona kalır; ajan şartının alt katmanlara etkisi geç görülür; uzun süre görünür çıktı yok | Elendi |
| **B. Alttan başlayan ince dilimler** | Her dilim en alt katmandan başlar, uçtan uca çalışan ince bir parça bırakır | "Low level'dan başla" isteğine uyar; protokol omurga olarak erken şekillenir; hatalar erken çıkar | Bazı katmanlar ilk turda ince kalır, sonra derinleştirilir | **Seçildi (kullanıcı onayı)** |
| C. Önce protokol + editör, sahte çekirdek | | Hızlı demo | "Low level'dan başlayalım" isteğine ters | Elendi |

## 7. Mimari kararlar

### 7.1 Bellek

Notlardaki üç katmanlı yapı aynen: Kalıcı Arena, Çift Tamponlu Kare Arenası, Bit-Haritalı Havuz. Ana blok `VirtualAlloc` (Windows) ile rezerve edilir.

- **Sıfır tahsis kuralının kapsamı:** simülasyon tick'i (fizik, ECS, VM, komut uygulama, render veri hazırlığı). Protokol ayrıştırma (JSON), dosya I/O, editör UI düzeni ve derleyici tick dışında, kendi arenalarında çalışır; bu sistemler tick'e yalnızca sabit boyutlu ikili komut kayıtları verir.
- **V ile sıfır tahsis:** tick içinde V'nin `string`, dinamik `array`, `map` tipleri kullanılmaz; arena üstünde sabit kapasiteli kendi tiplerimiz kullanılır.
- **Doğrulama:** debug build'de tick içi `malloc` sayacı testle sıfır olduğu doğrulanır (yöntem builder'a kalmış, ör. `-Wl,--wrap=malloc`).
- Arena taşması `panic` yerine hata kodu döner + debug'da assert (ajan protokolü üzerinden raporlanabilsin diye).

### 7.2 Varlık tanımlayıcısı (notlardan değişiklik)

Notlarda ECS handle'ı 32 index + 24 gen + 8 flag, VM'deki NaN-box ise 32 index + 16 gen taşıyor; ikisi uyuşmuyor.

**Karar:** `EntityID = u64`, **bit 0..31 index, bit 32..47 generation (16 bit), bit 48..63 sıfır.** Böylece handle NaN-box'ın 48 bitlik yüküne birebir sığar.

- Flag'ler handle'dan çıkarılır, bileşen verisine taşınır (flag değişince kimliğin değişmesi yanlıştır).
- Generation 0xFFFF'e ulaşan slot emekli edilir, bir daha kullanılmaz (ABA koruması).

### 7.3 ECS

Notlardaki Paginated Sparse-Set + SoA, 64 bayt hizalama, swap-and-pop aynen.

- **İnterpolasyon için** `prev_pos_x/prev_pos_y` kanalları eklenir (notlarda formül var ama veri yok).
- **İki tür bileşen, tek model (kullanıcı kararı: seçenek b):**
  - *Çekirdek bileşenler* (Transform, Body, Sprite…): V struct'ı, derleme zamanında kayıtlı. Her biri kendi sparse-set + SoA kanallarına sahip. Notlardaki `TransformKinematicsSoA` bunlardan biri olur, motorun tek bileşeni olmaktan çıkar.
  - *Betik bileşenleri*: VScript'te `@component Health { hp: f32 }` ile tanımlanır, derlemeden ve hot-reload ile eklenir. Depolama: tip başına sparse-set + alan başına bir kolon. Kolon tipleri: `f32`, `i32`, `bool`, `entity`, `symbol`. Kolonlar çekirdek SoA ile aynı düzende (64 bayt hizalı, yoğun dizi) tutulur; böylece `@system` vektör döngüleri ve SIMD yolları iki tür bileşende aynı şekilde çalışır.
  - İki tür de aynı şema registry'ye kaydolur; protokol, editör inspector'ı ve sahne dosyası aralarında fark görmez.
  - *Betik bileşeni hot-reload'da değişirse:* aynı ad ve tipteki alanların verisi korunur, yeni alanlar varsayılan değerle eklenir, silinen alanlar atılır. Kolon kapasitesi Kalıcı Arena'dan ayrılır; yeniden düzenleme tick dışında, hot-reload bariyerinde yapılır.
  - Betik bileşen tanımı da bir komuttur (`component.define`): ajan protokolle doğrudan da tanımlayabilir.
- **Bileşen reflection:** Her bileşen tipi bir şema kaydı üretir: alan adı, tip, birim (ör. `m`, `m/s`, `rad`), aralık, açıklama. V'nin derleme zamanı reflection'ı (`$for field in T.fields`) ve alan attribute'ları kullanılır. Bu şema hem protokolün `schema` sorgusunu hem editör inspector'ını hem sahne dosyası serileştirmesini besler. **Tek kaynak.**

### 7.4 Komut kuyruğu = motorun omurgası

Notlardaki Kural 4 ("betik durumu değiştiremez, komut kuyruğuna yazar") genişletilir: **dünyayı değiştiren her şey bir komuttur.** Kaynağı fark etmez: VScript, editör, protokol/ajan, tekrar oynatma.

- Komutlar sabit boyutlu ikili kayıtlardır (tip, hedef entity, bileşen/alan id, değer).
- Tick içinde biriktirilir, **tick sonundaki bariyerde deterministik sırayla** uygulanır.
- Sıralama anahtarı: (kaynak sınıfı, kaynak sıra no). Böylece çok iş parçacıklı üretim olsa bile uygulama sırası sabittir.
- Her uygulanan komutun **tersi** (önceki değer) kaydedilebilir → editörde geri al/yinele.
- Uygulanan komut akışı diske yazılabilir → **kayıt/tekrar oynatma**.
- **Kayıt birimi `(tick, komut)` çiftidir.** Canlı modda protokol/editör komutunun varış anı belirsizdir; komut hangi tick'in bariyerinde uygulandıysa o tick numarasıyla kaydedilir. Tekrar oynatma duvar saatine değil tick indeksine göre uygular. Determinizm (G2) bu tanımla geçerlidir.

**Notlardaki hatanın düzeltmesi:** VM'deki `SET_COMP` doğrudan SoA'ya yazıyordu. Artık yalnızca komut kuyruğuna yazar.

### 7.5 Determinizm

- Simülasyon matematiği IEEE 754 f32 temel işlemleriyle sınırlı. **FMA kullanılmaz;** C çekirdekleri `-ffp-contract=off`, `-ffast-math` yasak. (Notlardaki AVX2 döngüsü FMA, kuyruk döngüsü çarp+topla kullanıyordu; sonuç varlık sayısına bağlıydı.)
- Simülasyonda libm transandantal fonksiyonları (`sin`, `cos`, `sqrt` hariç: `sqrt` IEEE'de kesin) kullanılmaz; gerekirse kendi deterministik yaklaşımlarımız.
- Her SIMD çekirdeğinin skaler referans uygulaması vardır; testler bit düzeyinde eşitlik kontrol eder.
- **Paralel işler deterministik birleşir:** her worker kendi tamponuna yazar, sonuçlar worker sırasıyla değil **veri sırasıyla** (ör. hücre sırası, entity index) birleştirilir.
- Hash grid: geçiş 1 (sayım) atomik olabilir (toplama sıradan bağımsız). Geçiş 3 (yerleştirme) atomik sırayla yapılmaz; veri bölümlerine ayrılır, her bölümün ofseti prefix-sum ile önceden hesaplanır.
- Çarpışma çözümü sabit sırayla (hücre sırası, sonra çift index) işlenir.
- **Determinizm seviyeleri:** M2'de "aynı binary, aynı makine" zorunlu. "Platformlar arası" (x86 ↔ WASM ↔ ARM) WASM arka ucu geldiğinde doğrulanır; yukarıdaki kurallar buna izin verecek şekilde seçildi.
- Durum hash'i: tüm SoA kanallarının deterministik hash'i (ör. xxhash64 benzeri, kendi uygulamamız). Protokolden sorgulanabilir.

### 7.6 Olay sistemi (notlardan sadeleştirme)

Simülasyon içi olaylar (çarpışma vb.) için Vyukov MPMC ring buffer **kullanılmaz**: MPMC'de olay sırası belirsizdir ve determinizmi bozar. Yerine:

- Her worker kare arenasındaki kendi lineer olay tamponuna yazar.
- Tick sonunda tamponlar (olay tipi, kaynak entity, hedef entity) anahtarıyla deterministik birleştirilir ve dağıtılır.

MPMC kuyruk yalnızca simülasyon dışı kanallarda kullanılır: protokolden gelen komutlar, hot-reload sinyali, dosya izleyici.

### 7.7 VScript

Notlardaki tasarım geçerli: 256 kayıtçı, 32-bit buyruk, Pratt parser, sıfır kopyalı lexer, `@event` / `@system` blokları, fuel sayacı, hot-reload.

**NaN-boxing düzeltmesi:** x86'da `0/0` gibi geçersiz işlemler `0xFFF8000000000000` üretir; bu notlardaki `tag_nil` ile aynı. Hatalı bir hesap sessizce `nil` olurdu.

**Karar:** Her f64 aritmetik sonucundan sonra NaN kanonikleştirilir (`x != x` ise → `0x7FF8000000000000`). Etiketler sign biti 1 olan aralıkta kalır (`0xFFF9...` nil, `0xFFFA...` bool, `0xFFFB...` i32, `0xFFFC...` entity, `0xFFFD...` symbol). `0xFFF8` hiçbir etikete atanmaz. Böylece kanonik NaN asla etiketle çakışmaz.

**Bileşen erişim kodlaması (notlardan değişiklik):** Notlardaki `GET_COMP`/`SET_COMP` dört sabit kanala (pos_x, pos_y, vel_x, vel_y) bağlıydı. Artık her bytecode chunk'ının bir **alan tablosu** vardır: girdi = (bileşen tip id u16, alan id u16), yükleme ve hot-reload sırasında çözülür.
- `GET_COMP A B C`: `R[A] ← alan[C]( R[B] entity )`. C alan tablosu indeksi.
- `SET_COMP A B C`: `CmdQueue.push(entity R[A], alan tablosu[B], değer R[C])`.
- Chunk başına en çok 256 farklı alan referansı (8 bit). Yetmezse builder `iABx` biçimli geniş varyant ekler.
- Entity'si olmayan ya da bileşeni taşımayan erişim çalışma zamanı hatası olarak raporlanır.

**f64 VM / f32 bileşen:** VM değerleri f64 taşır; f32 bileşene yazarken IEEE f64→f32 yuvarlaması deterministiktir. "Yalnızca f32" kuralı simülasyon çekirdekleri içindir, VM'i kapsamaz.

**Ajan için:**
- Derleyici hataları yapılandırılmış döner: dosya, satır, sütun, hata kodu, mesaj, mümkünse önerilen düzeltme. Protokol bunları JSON olarak verir.
- Fuel tükenmesi, geçersiz entity erişimi gibi çalışma zamanı hataları olay olarak raporlanır (motor çökmez).
- Dil referansı tek bir makine-okunur dosyada (opcode'lar, yerleşik fonksiyonlar, bileşen erişimi) tutulur ve protokolden sorgulanabilir.

### 7.8 Ajan protokolü

**Tek kapı.** Editör, ajan ve test araçları motoru aynı protokolle kontrol eder.

- **Format:** JSON-RPC 2.0. Taşıma: headless modda stdio (satır başına bir mesaj), çalışan motorda localhost TCP. Tarayıcı arka ucu geldiğinde WebSocket eklenir.
- **MCP:** ayrı ince bir adaptör (`vcore mcp` modu). MCP tool'larını protokol çağrılarına birebir çevirir; kendi mantığı yoktur. Protokole eklenen her komut otomatik MCP tool'u olur (şema registry'den üretilir).
- **Komut aileleri (ilk sürüm):**
  - *Dünya:* `entity.spawn`, `entity.despawn`, `component.add`, `component.remove`, `component.set` (alan bazında)
  - *Sorgu:* `query.entities` (bileşen filtresi), `query.region` (AABB), `query.ray`, `entity.get`, `schema.components`, `schema.commands`
  - *Simülasyon:* `sim.pause`, `sim.resume`, `sim.step(n)`, `sim.run_until(tick)`, `sim.state_hash`
  - *Yakalama:* `capture.screenshot` (PNG), `capture.snapshot` (tam durum, sahne formatında)
  - *Kayıt:* `record.start/stop`, `replay.run`, `replay.diff` (iki tekrar oynatma arasında ilk ayrışan tick ve entity)
  - *Dosya:* `scene.load/save`, `script.load` (derleme hatalarını döner)
  - *Editör senkronu:* `subscribe.changes`: uygulanan komutların akışı (insan editörde bir şey değiştirince ajan görür; tersi de geçerli)
  - *Geçmiş:* `history.undo`, `history.redo`
- Protokol çağrıları simülasyonu doğrudan değiştirmez; komut kuyruğuna 7.4'teki gibi girer.
- Her hata yapılandırılmış döner: kod, mesaj, ilgili entity/alan, mümkünse öneri.

### 7.9 Headless mod

`vcore headless <scene>`: pencere ve GPU yok, simülasyon gerçek zamandan bağımsız (olabildiğince hızlı) koşar. Protokol stdio üzerinden. Benchmark'lar ve ajan testleri bunu kullanır.

### 7.10 Sahne formatı

`.vscene`: insan ve ajan tarafından okunabilir, git farkı anlamlı metin.

- **Karar:** JSON, deterministik anahtar sırası, deterministik sayı biçimi, varlık başına bir nesne. V stdlib `json` modülü (tick dışında, tahsis serbest).
- Alanlar bileşen şemasından (7.3) serileştirilir.
- Büyük düzenli veriler (ör. tile map) ayrı bileşen dizileri olarak kompakt tutulur; ayrıntı builder'a kalmış.

### 7.11 Platform ve render

- **Platform sınırı:** `platform` modülü küçük bir arayüz sunar: pencere oluştur, olay pompala, zamanlayıcı, dosya izleme, GL context. İlk uygulama: Win32 (`user32`, `gdi32`, `kernel32`, `opengl32`) + WGL.
- **Render tabanı:** OpenGL 3.3 core. Gerekçe: WebGL2 ve GLES 3.0 ile ortak alt küme, yani tarayıcı ve mobil arka uçlar aynı shader/çizim yolunu kullanabilir. Notlardaki OpenGL 4.4 kalıcı eşlenmiş tampon, yetenek kontrolüyle açılan **isteğe bağlı hızlı yol** olur; benchmark kazancı göstermezse eklenmez.
- **Çizim:** notlardaki tek `glDrawArraysInstanced` + 16 baytlık `InstancePayload` aynen. Dönüş açısı u16 normalize açı olarak.
- **Zamanlayıcı:** notlardaki `QueryPerformanceCounter`. Notlardaki `(diff * 1e9) / freq` 64-bit taşar (birkaç saat sonra); bölme önce saniye/kalan olarak yapılır.

### 7.12 Editör

- **Editör, protokolün bir istemcisidir.** Motorla aynı süreçte çalışır ama yalnızca protokol komutları gönderir. Editörde objeyi sürüklemek `component.set` komutu üretir. Editörün özel arka kapısı yoktur.
- Motorun kendi renderer'ıyla çizilir. UI V ile yazılmış immediate-mode bir kütüphane.
- **Tasarım sistemi (anti-slop):**
  - token'lar: renk paleti (koyu tema öncelikli), aralık ölçeği (4px tabanlı), köşe yarıçapları, tipografi ölçeği
  - SDF font atlası (`stb_truetype` ile üretilir), tek bir kaliteli sans + tek bir mono font
  - tutarlı ikon seti (vektör, tek çizgi kalınlığı)
  - sakin hareket: kısa, amaçlı geçişler; parıltı, gradyan, gereksiz animasyon yok
  - her yeni panel ekran görüntüsüyle gözden geçirilir; görünümü kötüyse bitmiş sayılmaz
- **v0 kapsamı:** sahne görünümü (pan/zoom), obje seçme, taşıma gizmosu, inspector (şemadan otomatik), hiyerarşi listesi, obje oluştur/sil, bileşen ekle/çıkar, simülasyon duraklat/devam/adım, geri al/yinele, kaydet/yükle.
- **G3 (tam eşitlik) hedef durumdur, M4 kapısı değildir.** Kayıt/tekrar oynatma ve durum hash'i M5'te, betik yükleme ve hata paneli M6'da editöre gelir; M6 sonunda protokoldeki her komutun editörde karşılığı olmalıdır. Her dilim, eklediği protokol komutlarının editör karşılığını da listeler.
- **Görsel onay:** M4 sonunda editörün ekran görüntüleri kullanıcıya sunulur; kullanıcı onaylamadan M4 bitmiş sayılmaz.

### 7.13 Modül yapısı

```
Kaboom/
  v.mod
  memory/      arena, epoch arena, pool, VirtualAlloc
  ecs/         entity, sparse-set, SoA, şema/reflection
  cmd/         komut kayıtları, kuyruk, uygulama, geri al, kayıt/tekrar oynatma
  sim/         sabit adım döngüsü, durum hash'i
  physics/     hash grid, integratör, çarpışma
  kernels/     C11: SIMD çekirdekleri + skaler referanslar
  vscript/     lexer, Pratt derleyici, VM
  protocol/    JSON-RPC, komut registry, stdio/TCP taşıma, MCP adaptörü
  platform/    platform arayüzü + win32/
  render/      GL loader, instanced renderer, font atlas
  ui/          immediate-mode UI + tasarım token'ları
  editor/      editör panelleri
  cmd_main/    vcore ikilisi: headless | editor | mcp
  bench/       benchmark'lar + results/
  tests/
  third_party/ stb_truetype.h, stb_image.h, stb_image_write.h
```

### 7.14 Benchmark altyapısı

- Her benchmark sabit tohumla (seed) çalışır, JSON sonuç üretir: ölçüm adı, varlık sayısı, tick başına ns (min/medyan/p99), bellek kullanımı, durum hash'i.
- Sonuçlar `bench/results/` altına tarih + commit/etiketle yazılır; bir önceki sonuçla karşılaştırma raporu üretilir.
- Determinizm benchmark'ın parçasıdır: aynı tohum → aynı durum hash'i.
- **100k @ 120 Hz hedefinin tanımı:** geliştirme makinesinde, render hariç tam simülasyon tick'i (fizik + VScript + komut uygulama + olaylar), **p99 ≤ 8.33 ms**. Render ayrı ölçülür ve ayrı raporlanır. Bu eşik yalnızca M7'nin kapısıdır; önceki dilimler eşik koymaz, yalnızca ölçer ve geriye gidişi raporlar.
- **Gösterim sahnesi:** hedef bir oyun yok (amaç motorun kendisi). Yerine `bench/` altında tek bir gösterim sahnesi büyür: M3'te 100k çizilen quad, M5'te çarpışan 100k daire, M6'da VScript kurallarıyla davranan varlıklar.

## 8. Kilometre taşları (dilimler)

Her dilim: testler + benchmark + çalışan bir uçtan uca senaryo. Bir dilim bitmeden sonrakine geçilmez.

| # | Dilim | Bitti sayılması için |
|---|---|---|
| M1 | Bellek + handle'lar + benchmark altyapısı | Arena/epoch/pool testleri; handle ABA testi; tahsis benchmark'ı JSON üretiyor |
| M2 | Minimal ECS + sabit adım headless döngü + komut kuyruğu + protokol iskeleti + kayıt/tekrar oynatma | **İlk ajan senaryosu:** ajan stdio protokolüyle sıfırdan sahne kurar, 1.000 adım koşturur, sorgular, sonucu doğrular; aynı kayıt iki kez oynatılınca durum hash'leri bit düzeyinde aynı. Tick içi tahsis sayacı = 0 |
| M3 | Win32 pencere + GL 3.3 instanced 2B çizim + interpolasyon | 100k quad tek draw call'la çiziliyor; `capture.screenshot` çalışıyor; render benchmark'ı |
| M4 | UI kütüphanesi + tasarım sistemi + editör v0 | 7.12'deki v0 kapsamı; editördeki her değişiklik protokol komutu; ajan editör açıkken değişiklik yapınca editörde görünür; ekran görüntüleri anti-slop gözden geçirmesinden geçer |
| M5 | Hash grid + fizik (integratör, çarpışma, Baumgarte) | Şekiller: daire–daire ve daire–statik AABB (duvar); tile çarpışması sonraki dilimlere. Skaler ve SIMD bit-eşit; 100k varlık fizik benchmark'ı; determinizm testi |
| M6 | VScript (lexer, derleyici, VM, `@event`, `@component`, hot-reload) | Ajan derlemeden yeni bir betik bileşeni tanımlar, editör inspector'ında görünür ve sahneye kaydedilir; ajan bir betik yükler, derleme hatası alırsa yapılandırılmış hata görür, düzeltir; hot-reload durum kaybetmeden çalışır |
| M7 | Derinleştirme | `@system` vektörel yürütme, iş parçacığı havuzu + DAG zamanlama, 100k @ 120 Hz hedefine ulaşma |
| M8+ | Yeni arka uçlar | WASM/WebGL2, Android/GLES3; platformlar arası determinizm doğrulaması; sonra 3B |

## 9. Builder'a kalanlar

- JSON-RPC mesaj şemalarının tam alanları ve hata kodu listesi.
- UI widget setinin detayı, renk değerleri, font seçimi (7.12'deki ilkelerle).
- Durum hash algoritmasının tam seçimi (deterministik ve hızlı olması şartıyla).
- GL fonksiyon yükleyicinin yapısı.
- Tile map / büyük veri serileştirme biçimi.
- Tick içi tahsis sayacının yöntemi.
- Benchmark karşılaştırma raporunun biçimi.

## 10. Notlardan yapılan değişikliklerin özeti

| Notlarda | Bu belgede | Neden |
|---|---|---|
| Yalnızca Win32 + AVX2 + GL 4.4 | Platform sınırı; GL 3.3 taban, 4.4 isteğe bağlı | Tarayıcı ve mobil hedefi |
| Handle: 32+24+8 bit, VM'de 32+16 | 32 index + 16 gen, flag'ler bileşende | NaN-box'a sığmalı, iki tanım tutarlı olmalı |
| `tag_nil = 0xFFF8...` | Etiketler 0xFFF9'dan başlar + NaN kanonikleştirme | x86 varsayılan NaN'ı ile çakışma |
| `SET_COMP` SoA'ya doğrudan yazar | Komut kuyruğuna yazar | Kural 4 ve veri yarışı |
| Tek sabit `TransformKinematicsSoA`, VM'de 4 sabit kanal | Çekirdek (V) + betik (`@component`) bileşenleri, chunk alan tablosu | Kullanıcı kararı: ajan derlemeden bileşen tanımlayabilmeli |
| AVX2 FMA + skaler çarp-topla | FMA yok, `-ffp-contract=off` | Determinizm |
| Simülasyon olayları MPMC ring buffer'da | Worker başına tampon + deterministik birleştirme | MPMC sırası belirsiz |
| Grid yerleştirme atomik | Bölümlü, önceden hesaplanmış ofsetler | Determinizm |
| `diff * 1e9 / freq` | Saniye + kalan olarak bölme | 64-bit taşma |
| V 0.4+ | V 0.5.2 | Kurulu sürüm |
| C++20 `extern "C"` sınırı | C++ yok | Gereksiz |
| — | Ajan protokolü, headless mod, reflection, kayıt/tekrar oynatma, editör, sahne formatı, benchmark altyapısı | Yeni şartlar |
