# Teknik Tasarım Belgesi (TDD): V-Core Ölçeklenebilir Oyun Motoru ve VScript Sanal Makinesi

**Belge Sürümü:** 1.0.0-RC1

**Hedef Dil ve Standartlar:** V (0.4+, `-gc none` / Manuel Bellek Kipinde), ISO C11, C++20 (`extern "C"` ABI Sınırıyla)

**Mimari Paradigma:** Veri Odaklı Tasarım (Data-Oriented Design - DOD), Sıfır Tahsisli (Zero-Allocation) Çalışma Zamanı, Kayıtçı Tabanlı (Register-Based) Bytecode Sanal Makinesi

Bu teknik tasarım belgesi; üçüncü parti hiçbir soyutlama katmanı (SDL, GLFW, Raylib, Sokol, Lua vb.) kullanmadan, doğrudan işletim sistemi çekirdek arayüzleri ve saf C/V birlikte çalışabilirliği (interoperability) üzerine inşa edilecek yüksek frekanslı, deterministik bir oyun motorunun mühendislik spesifikasyonlarını tanımlar.

## 1. Sistem Mimarisi, Tasarım Kısıtları ve Performans Bütçesi

Motorun birincil tasarım hedefi görsel fotorealizm değil, **maksimum simülasyon yoğunluğu ve deterministik ölçeklenebilirliktir**. Tek bir standart masaüstü işlemcide (8 çekirdek, AVX2 destekli) aynı anda **100.000 aktif varlığın (entity)** fiziksel, uzamsal ve betiksel (VScript) durumlarının saniyede **120 sabit adımda (120 Hz Fixed Timestep)** güncellenmesi hedeflenir.

### 1.1 Mimari Değişmezler (Architectural Invariants)

1. **Sıfır Çalışma Zamanı Heap Tahsisi (Zero Runtime Allocation):** Oyun döngüsü (`tick`) başladıktan sonra işletim sisteminden `malloc`, `calloc`, `realloc` veya `free` yoluyla bellek istenmesi kesinlikle yasaktır. Tüm bellek blokları motor başlatılırken (`init` fazında) sanal adres uzayından rezerve edilir.
2. **Önbellek Hizalaması (Cache-Line Alignment):** Tüm bileşen dizileri (SoA) ve iş parçacığı (thread) iletişim kuyrukları, sahte paylaşımı (false sharing) önlemek ve SIMD komut setlerini (`SSE4.2` / `AVX2`) beslemek için **64 baytlık** L1 önbellek satırı sınırlarına hizalanır.
3. **İşaretçi Takibi Yasağı (No Pointer Chasing):** Nesneler birbirine bellek adresleriyle (raw pointer) değil, 64-bitlik **Kuşaksal Tanımlayıcılar (Generational Handles)** üzerinden referans verir.
4. **Tek Yönlü Veri Akışı:** Betik katmanı (VScript) motorun bellek durumunu rastgele değiştiremez; yalnızca salt-okunur (read-only) sorgular yapabilir veya kilitlenmesiz (lock-free) komut kuyruğuna durum değiştirme emirleri (mutation commands) bırakabilir.

### 1.2 Kare Zaman Bütçesi (120 Hz = 8.33 ms / Tick)

| Alt Sistem | Hedef Süre (ms) | Bütçe Oranı (%) | Bellek Erişim Modeli | Yürütme Modeli |
| --- | --- | --- | --- | --- |
| Platform ve Girdi | 0.15 | 1.8 | Sıralı Okuma | Ana İş Parçacığı |
| Uzamsal Hash ve Fizik | 2.40 | 28.8 | SoA SIMD Tarama | Çoklu İş Parçacığı (Job) |
| VScript VM ve Event Bus | 3.10 | 37.2 | Ring-Buffer + Kayıtçı | Çoklu İş Parçacığı (Bölümlü) |
| ECS Komut Birleştirme | 0.68 | 8.2 | Doğrusal Yazma | Bariyer Senkronizasyonlu |
| GPU DMA ve Çizim Çağrısı | 1.20 | 14.4 | Kalıcı Eşlenmiş Tampon | Ana / Render İş Parçacığı |

Tablo 1.2'de belirtilen toplam **7.53 ms**'lik aktif çalışma süresi, işletim sistemi zamanlayıcı sapmaları (scheduler jitter) için kare başına **0.80 ms** güvenlik payı bırakır.

## 2. Deterministik Bellek Yönetim Alt Sistemi

V derleyicisinin varsayılan Boehm GC mekanizması `-gc none` bayrağıyla tamamen devre dışı bırakılır. Motor, işletim sisteminin sanal bellek API'lerini (Windows'ta `VirtualAlloc`, Linux/POSIX'te `mmap`) doğrudan çağırarak devasa bir bitişik (contiguous) bellek bloğu ayırır ve bunu üç alt tahsisatçıya (allocator) böler.

### 2.1 Bellek Hizalama Matematiği

Herhangi bir bellek adresi $p \in \mathbb{N}$ ve $2$'nin kuvveti olan bir hizalama sınırı $k = 2^m$ (örneğin SIMD ve önbellek satırı için $k = 64$) verildiğinde, ileri yönde hizalanmış adres $A(p, k)$ şu bit düzeyinde (bitwise) fonksiyonla hesaplanır:

$$A(p, k) = (p + (k - 1)) \land \sim(k - 1)$$

Belirtilen adresteki ileri sarma (padding) miktarı ise:

$$\Delta_{\text{pad}}(p, k) = (-p) \land (k - 1)$$

Bu işlem dallanma (branch) içermez ve tek bir CPU çevriminde (cycle) tamamlanır.

### 2.2 Üç Katmanlı Bellek Mimarisi

1. **Kalıcı Arena (Persistent Linear Arena):** ECS bileşen dizileri, VScript derlenmiş bytecode blokları ve varlık arama tabloları için kullanılır. Yalnızca seviye (level) geçişlerinde sıfırlanır.
2. **Çift Tamponlu Kare Arenası (Double-Buffered Epoch Arena):** Bir kare içinde üretilen ve bir sonraki karede tüketilmesi gereken olay yükleri (event payloads), çarpışma çiftleri ve geçici sorgu listeleri için kullanılır. $N$. karede `Arena[N & 1]` yazılırken, `Arena[(N - 1) & 1]` okunur. Kare sonunda yazma işaretçisi (`offset`) $O(1)$ sürede sıfıra çekilir.
3. **Bit-Haritalı Havuz Tahsisatçısı (Bitmapped Slab/Pool Allocator):** Dinamik olarak eklenip silinen sabit boyutlu yapılar (örneğin aktif ses kanalları veya zamanlayıcılar) için kullanılır. Boş bloklar 64-bitlik tam sayılardan oluşan bir bit dizisinde (`u64` bitset) tutulur ve donanımsal **Count Trailing Zeros (`ctz` / `tzcnt`)** buyruğu ile $O(1)$ sürede ilk boş yuva bulunur:

$$\text{FreeIndex} = (\text{BlockWordIndex} \times 64) + \operatorname{ctz}(\sim\text{Bitmask}_{i})$$

```v
module memory

// C seviyesinde işletim sistemi sanal bellek bağlaması
#include <stdlib.h>
#include <stdint.h>

@[aligned: 64]
pub struct LinearArena {
pub mut:
	base_ptr &u8 = unsafe { nil }
	capacity u64
	offset   u64
}

pub fn LinearArena.new(base &u8, cap u64) LinearArena {
	return LinearArena{
		base_ptr: base
		capacity: cap
		offset:   0
	}
}

@[inline]
pub fn (mut a LinearArena) alloc_aligned(size u64, alignment u64) &u8 {
	curr_addr := u64(a.base_ptr) + a.offset
	mask := alignment - 1
	aligned_addr := (curr_addr + mask) & ~mask
	padding := aligned_addr - curr_addr
	new_offset := a.offset + padding + size

	if new_offset > a.capacity {
		panic('Kritik Hata: LinearArena kapasitesi asildi (Zero-Allocation ihlali)')
	}

	a.offset = new_offset
	return unsafe { &u8(aligned_addr) }
}

@[inline]
pub fn (mut a LinearArena) reset() {
	a.offset = 0
}

```

## 3. Veri Odaklı ECS Çekirdeği (Paginated Sparse-Set & SoA)

Klasik nesne yönelimli mimarilerdeki sanal fonksiyon tablosu (`vtable`) aramaları ve parçalı heap yerleşimi, 100.000 varlıkta L1/L2 önbellek ıskalamalarına (cache miss) yol açar. Motorumuz **Sayfalanmış Seyrek Küme (Paginated Sparse-Set)** indekslemesi ile **Dizi Yapıları (Struct of Arrays - SoA)** veri yerleşimini birleştirir.

### 3.1 64-Bit Kuşaksal Varlık Tanımlayıcısı (Generational Entity Handle)

Silinen bir varlığın indeksini yeni bir varlık devraldığında, eski varlığa ait referansların yeni varlığı yanlışlıkla değiştirmesini (ABA Problemi) engellemek için her `EntityID` 64-bitlik bir tam sayı olarak kodlanır:

* **Bit 0..31 (32 Bit - `Index`):** Yoğun (dense) ve seyrek (sparse) dizilerdeki konum. Maksimum $2^{32} - 1$ varlık.
* **Bit 32..55 (24 Bit - `Generation`):** İlgili indeksin kaç kez yeniden kullanıldığını belirten sayaç.
* **Bit 56..63 (8 Bit - `Flags`):** Varlığın aktiflik, statiklik ve ağ senkronizasyon bayrakları.

Bit ayrıştırma ve birleştirme fonksiyonları:

$$\operatorname{Pack}(I, G, F) = (I \land \text{0xFFFFFFFF}) \lor ((G \land \text{0xFFFFFF}) \ll 32) \lor ((F \land \text{0xFF}) \ll 56)$$

$$\operatorname{Index}(E) = E \land \text{0xFFFFFFFF}, \quad \operatorname{Gen}(E) = (E \gg 32) \land \text{0xFFFFFF}$$

### 3.2 Sayfalanmış Seyrek Küme (Paginated Sparse-Set) Matematiği

Her bileşen havuzu için doğrudan $N$ elemanlı düz bir `sparse` dizisi tutmak belleği israf eder. Bunun yerine `sparse` dizisi $P = 4096$ ($2^{12}$) elemanlı sayfalara bölünür. Bir varlık indeksi $i = \operatorname{Index}(E)$ için sayfa numarası ve sayfa içi ofset:

$$\text{PageIndex}(i) = i \gg 12, \quad \text{PageOffset}(i) = i \land \text{0xFFF}$$

### 3.3 Swap-and-Pop ile $O(1)$ Silme Algoritması

Yoğun (dense) dizideki ardışıklığı bozmadan $i$ indeksli varlığın bileşenini silmek için, yoğun dizinin sonundaki eleman ($last$), silinen elemanın konumuna ($d_i = \text{sparse}[i]$) taşınır ve yoğun dizi boyutu $1$ azaltılır:

$$\text{dense}[d_i] \leftarrow \text{dense}[N_{\text{dense}} - 1]$$

$$\text{sparse}[\operatorname{Index}(\text{entities}[N_{\text{dense}} - 1])] \leftarrow d_i$$

```v
module ecs

pub type EntityID = u64

pub const max_entities_per_page = 4096
pub const page_shift = 12
pub const page_mask = 0xFFF
pub const null_index = u32(0xFFFFFFFF)

@[inline]
pub fn make_entity(index u32, gen u32, flags u8) EntityID {
	return u64(index) | (u64(gen & 0xFFFFFF) << 32) | (u64(flags) << 56)
}

@[inline]
pub fn (e EntityID) index() u32 {
	return u32(e & 0xFFFFFFFF)
}

@[inline]
pub fn (e EntityID) generation() u32 {
	return u32((e >> 32) & 0xFFFFFF)
}

// SIMD dostu SoA Kinematik ve Transform Veri Yerlesimi
// Her dizi 64-byte sinirina hizalanmistir (AVX2 8xf32 tek komutta islenir)
@[aligned: 64]
pub struct TransformKinematicsSoA {
pub mut:
	count        u32
	capacity     u32
	dense_to_ent &EntityID = unsafe { nil }
	sparse_pages &&u32     = unsafe { nil } // Sayfa tablosu [page_id][offset]

	// SoA Bilesen Kanallari
	pos_x &f32 = unsafe { nil }
	pos_y &f32 = unsafe { nil }
	vel_x &f32 = unsafe { nil }
	vel_y &f32 = unsafe { nil }
	acc_x &f32 = unsafe { nil }
	acc_y &f32 = unsafe { nil }
	rad   &f32 = unsafe { nil } // Carpısma yaricapi
	mass_inv &f32 = unsafe { nil } // 1.0 / kutle (statik nesneler icin 0.0)
}

@[inline]
pub fn (mut soa TransformKinematicsSoA) remove_dense_at(dense_idx u32, ent_idx u32) {
	last_idx := soa.count - 1
	if dense_idx != last_idx {
		unsafe {
			moved_ent := soa.dense_to_ent[last_idx]
			moved_ent_idx := moved_ent.index()

			soa.pos_x[dense_idx] = soa.pos_x[last_idx]
			soa.pos_y[dense_idx] = soa.pos_y[last_idx]
			soa.vel_x[dense_idx] = soa.vel_x[last_idx]
			soa.vel_y[dense_idx] = soa.vel_y[last_idx]
			soa.acc_x[dense_idx] = soa.acc_x[last_idx]
			soa.acc_y[dense_idx] = soa.acc_y[last_idx]
			soa.rad[dense_idx] = soa.rad[last_idx]
			soa.mass_inv[dense_idx] = soa.mass_inv[last_idx]
			soa.dense_to_ent[dense_idx] = moved_ent

			page := moved_ent_idx >> page_shift
			offset := moved_ent_idx & page_mask
			soa.sparse_pages[page][offset] = dense_idx
		}
	}
	unsafe {
		del_page := ent_idx >> page_shift
		del_offset := ent_idx & page_mask
		soa.sparse_pages[del_page][del_offset] = null_index
	}
	soa.count--
}

```

## 4. Deterministik Simülasyon, Kinematik ve Uzamsal İndeksleme

Oyun hızının kare hızından (FPS) bağımsız ve deterministik olması için fizik ve oyun mantığı $\Delta t = \frac{1}{120}\text{ s} \approx 0.008333\text{ s}$ sabit adımıyla çalışır.

### 4.1 Sabit Zaman Adımı Biriktiricisi ve Görsel İnterpolasyon

Gerçek çerçeve süresi $\Delta t_{\text{frame}}$ biriktiriciye ($A$) eklenir. $A \ge \Delta t$ olduğu sürece simülasyon adımı koşturulur. Çizim aşamasında ise titremeyi (temporal aliasing) önlemek için önceki durum ($\mathbf{x}_{n-1}$) ile mevcut durum ($\mathbf{x}_n$) arasında doğrusal interpolasyon yapılır:

$$\alpha = \frac{A}{\Delta t} \in [0, 1)$$

$$\mathbf{x}_{\text{render}} = \mathbf{x}_{n-1} + \alpha (\mathbf{x}_n - \mathbf{x}_{n-1})$$

### 4.2 Semplektik (Yarı-Örtük) Euler İntegrasyonu

Standart açık (explicit) Euler yöntemi zamanla sisteme yapay enerji ekleyerek yörüngelerin patlamasına neden olur. Motor, faz uzayında hacmi koruyan (symplectic) **Birinci Dereceden Yarı-Örtük Euler** integratörünü kullanır. Sönümleme (damping) katsayısı $\gamma$ ve ters kütle $w = m^{-1}$ olmak üzere:

$$\mathbf{v}_{n+1} = \left( \mathbf{v}_n + (\mathbf{F}_{\text{ext}} \cdot w) \Delta t \right) \cdot \frac{1}{1 + \gamma \Delta t}$$

$$\mathbf{x}_{n+1} = \mathbf{x}_n + \mathbf{v}_{n+1} \Delta t$$

Yukarıdaki hız sönümleme çarpanı $\frac{1}{1 + \gamma \Delta t}$, üstel sönümleme $e^{-\gamma \Delta t}$ fonksiyonunun birinci dereceden Padé приближение (yaklaşımı) olup $\Delta t$ büyüdüğünde dahi koşulsuz kararlıdır (unconditionally stable).

### 4.3 Sınırsız Uzamsal Karma Izgarası (Unbounded Spatial Hash Grid)

100.000 varlığın birbirleriyle çarpışmasını $O(N^2)$ karmaşıklıkla kontrol etmek ($10^{10}$ işlem) imkansızdır. Quadtree gibi ağaç yapıları ise her karede yeniden dengelenirken önbellek ıskalaması yaratır. Bunun yerine, düz diziler üzerinde çalışan **Counting-Sort Tabanlı Uzamsal Karma Tablosu** kullanılır.

Dünya koordinatı $(x, y) \in \mathbb{R}^2$ ve ızgara hücre boyutu $s$ (en büyük varlık çapının $2$ katı) için ayrık hücre koordinatları:

$$c_x = \left\lfloor \frac{x}{s} \right\rfloor, \quad c_y = \left\lfloor \frac{y}{s} \right\rfloor$$

Büyük asal sayılar $p_1 = 73856093$ ve $p_2 = 19349663$ ile $M = 2^{17} = 131072$ kova (bucket) boyutlu tabloya eşleme (hash) fonksiyonu:

$$H(c_x, c_y) = \left( (c_x \cdot p_1) \oplus (c_y \cdot p_2) \right) \land (M - 1)$$

**Üç Geçişli (Three-Pass) Sıfır Tahsisli Izgara İnşası:**

1. **Geçiş 1 (Frekans Sayımı):** Her varlık için $h = H(c_x, c_y)$ hesaplanır ve `cell_counts[h]` atomik olarak artırılır.
2. **Geçiş 2 (Önek Toplamı - Prefix Sum):** `cell_offsets` dizisi üzerinde kümülatif toplam alınarak her hücrenin düz `grid_entities` dizisindeki başlangıç indeksi belirlenir:

$$\text{offset}[k] = \sum_{j=0}^{k-1} \text{count}[j]$$


3. **Geçiş 3 (Yerleştirme):** Varlık indeksleri `grid_entities` dizisine yerleştirilir. Bu sayede aynı uzamsal hücredeki tüm varlıklar bellekte yan yana (ardışık) dizilir!

### 4.4 Dar Faz (Narrow-Phase) Elastik Çarpışma Çözümü

İki dairesel/küresel varlık $A$ ve $B$ için merkezler arası fark vektörü $\mathbf{d} = \mathbf{x}_B - \mathbf{x}_A$ ve yarıçaplar toplamı $R = r_A + r_B$ olsun. Karekök (`sqrt`) maliyetinden kaçınmak için önce karesel mesafe kontrol edilir:

$$\Vert{}\mathbf{d}\Vert{}^2 = d_x^2 + d_y^2 \le R^2$$

Çarpışma gerçekleşmişse normal vektör $\mathbf{n} = \frac{\mathbf{d}}{\Vert{}\mathbf{d}\Vert{}}$, bağıl hız $\mathbf{v}_{\text{rel}} = \mathbf{v}_B - \mathbf{v}_A$ ve esneklik katsayısı (restitution) $e \in [0, 1]$ kullanılarak skaler dürtü (impulse) büyüklüğü $j$ hesaplanır:

$$j = \frac{-(1 + e)(\mathbf{v}_{\text{rel}} \cdot \mathbf{n})}{w_A + w_B}$$

Hızlar anında güncellenir:

$$\mathbf{v}_A' = \mathbf{v}_A - j w_A \mathbf{n}, \quad \mathbf{v}_B' = \mathbf{v}_B + j w_B \mathbf{n}$$

**Konumsal Düzeltme (Baumgarte Stabilizasyonu):** Nesnelerin birbirinin içine geçmesini (sinking) önlemek için penetrasyon derinliği $\delta = R - \Vert{}\mathbf{d}\Vert{}$, düzeltme oranı $\beta = 0.8$ ve tolerans eşiği $\epsilon_{\text{slop}} = 0.01$ ile konumlar ayrıştırılır:

$$\mathbf{p}_{\text{corr}} = \frac{\max(\delta - \epsilon_{\text{slop}}, 0)}{w_A + w_B} \beta \mathbf{n}$$

```c
// C11 AVX2 Destekli Kinematik Integrasyon ve Uzamsal Hash Cekirdegi (physics_kernel.c)
#include <stdint.h>
#include <immintrin.h>

void integrate_symplectic_avx2(
    float* restrict pos_x, float* restrict pos_y,
    float* restrict vel_x, float* restrict vel_y,
    const float* restrict acc_x, const float* restrict acc_y,
    uint32_t count, float dt, float damping_factor
) {
    __m256 v_dt = _mm256_set1_ps(dt);
    __m256 v_damp = _mm256_set1_ps(damping_factor); // 1.0f / (1.0f + gamma * dt)

    uint32_t i = 0;
    uint32_t vec_limit = count & ~7U; // 8'in katlarina yuvarla

    for (; i < vec_limit; i += 8) {
        __m256 px = _mm256_load_ps(&pos_x[i]);
        __m256 py = _mm256_load_ps(&pos_y[i]);
        __m256 vx = _mm256_load_ps(&vel_x[i]);
        __m256 vy = _mm256_load_ps(&vel_y[i]);
        __m256 ax = _mm256_load_ps(&acc_x[i]);
        __m256 ay = _mm256_load_ps(&acc_y[i]);

        // v = (v + a * dt) * damp
        vx = _mm256_mul_ps(_mm256_fmadd_ps(ax, v_dt, vx), v_damp);
        vy = _mm256_mul_ps(_mm256_fmadd_ps(ay, v_dt, vy), v_damp);

        // p = p + v * dt
        px = _mm256_fmadd_ps(vx, v_dt, px);
        py = _mm256_fmadd_ps(vy, v_dt, py);

        _mm256_store_ps(&vel_x[i], vx);
        _mm256_store_ps(&vel_y[i], vy);
        _mm256_store_ps(&pos_x[i], px);
        _mm256_store_ps(&pos_y[i], py);
    }

    // Kalan elemanlar (Tail loop)
    for (; i < count; ++i) {
        vel_x[i] = (vel_x[i] + acc_x[i] * dt) * damping_factor;
        vel_y[i] = (vel_y[i] + acc_y[i] * dt) * damping_factor;
        pos_x[i] += vel_x[i] * dt;
        pos_y[i] += vel_y[i] * dt;
    }
}

```

## 5. VScript: Kayıtçı Tabanlı (Register-Based) Bytecode Sanal Makinesi

Oyun motorunun olaylarını ve varlık kurallarını yöneten **VScript**, yorumlanan (AST-walking) dillerin yavaşlığından ve yığın tabanlı (stack-based) VM'lerin aşırı `PUSH`/`POP` buyruk yükünden kurtulmak için **256 Sanal Kayıtçılı (Register-Based)** bir mimari kullanır.

### 5.1 NaN-Boxing ile 64-Bit Polimorfik Değer Temsili

Sanal makinede her kayıtçı (`R0`..`R255`) tam olarak 64 bit (`u64`) genişliğindedir. Heap üzerinde kutulama (boxing) yapmadan aynı 64 bitlik alanda hem çift duyarlıklı kayan noktalı sayı (`f64`), hem 32-bit tam sayı (`i32`), hem boolean, hem de `EntityID` referansı taşımak için **IEEE 754 Quiet NaN (qNaN)** standardının boş bitleri kullanılır.

IEEE 754 standardında üs (exponent) bitlerinin tamamı $1$ (11 bit) ve en anlamlı mantissa biti (bit 51) + işaret biti $1$ olduğunda sayı geçerli bir `f64` değil, bir `qNaN` değeridir. Kalan **51 bit** tamamen veri yükü (payload) ve tip etiketi için serbesttir:

$$\text{QNaN\_Mask} = \text{0x7FF8000000000000}$$

Bir değer $V \in \mathbb{B}^{64}$, eğer $(V \land \text{QNaN\_Mask}) \neq \text{QNaN\_Mask}$ ise doğrudan donanımsal bir `f64` sayıdır. Aksi halde bit 48..50 arasındaki 3 bitlik alan veri tipini, alt 48 bit ise veriyi taşır:

| Tip Etiketi | Üst 16 Bit Maskesi (Hex) | Alt 48 Bit Yükü (Payload) | Açıklama |
| --- | --- | --- | --- |
| `f64` (Sayı) | `< 0xFFF8` | Standart IEEE 754 | Doğrudan FPU/SIMD işlemi |
| `Nil` (Boş) | `0xFFF8` | `0x000000000000` | Tanımsız / Boş değer |
| `Bool` | `0xFFF9` | `0` veya `1` | Mantıksal doğru/yanlış |
| `i32` (Tam Sayı) | `0xFFFA` | 32-bit işaretli tam sayı | Sayaçlar ve indeksler |
| `EntityHandle` | `0xFFFB` | 32-bit Index + 16-bit Gen | ECS varlık referansı |
| `StringSymbol` | `0xFFFC` | 32-bit Interned String ID | Sabit tablo metin indeksi |

### 5.2 32-Bit Sabit Genişlikli Buyruk Kodlaması (Instruction Encoding)

Her VScript buyruğu (instruction) tam olarak 32 bit (`u32`) uzunluğundadır ve CPU önbelleğine tek seferde sığar. Üç temel buyruk formatı bulunur:

1. **iABC Formatı:** `[ C: 8 bit (24..31) | B: 8 bit (16..23) | A: 8 bit (8..15) | Opcode: 8 bit (0..7) ]`
* Örnek: `ADD R[A], R[B], R[C]` $\rightarrow R_A \leftarrow R_B + R_C$


2. **iABx Formatı:** `[ Bx: 16 bit İşaretsiz (16..31) | A: 8 bit (8..15) | Opcode: 8 bit (0..7) ]`
* Örnek: `LOADK R[A], K[Bx]` $\rightarrow R_A \leftarrow \text{Constants}[Bx]$


3. **iAsBx Formatı:** `[ sBx: 16 bit İşaretli Dallanma Ofseti (16..31) | A: 8 bit (8..15) | Opcode: 8 bit (0..7) ]`
* İşaretli ofset sapması (bias): $sBx = Bx - 32767$



Buyruk çözme (decoding) fonksiyonları:

$$\operatorname{Op}(I) = I \land \text{0xFF}, \quad \operatorname{ArgA}(I) = (I \gg 8) \land \text{0xFF}$$

$$\operatorname{ArgB}(I) = (I \gg 16) \land \text{0xFF}, \quad \operatorname{ArgC}(I) = (I \gg 24) \land \text{0xFF}, \quad \operatorname{ArgBx}(I) = I \gg 16$$

### 5.3 VScript Çekirdek Opcode Tablosu

| Opcode (Hex) | Mnemonic | Format | Matematiksel / Operasyonel Semantik |
| --- | --- | --- | --- |
| `0x01` | `MOVE` | iABC | $R[A] \leftarrow R[B]$ |
| `0x02` | `LOADK` | iABx | $R[A] \leftarrow K[Bx]$ |
| `0x03` | `ADD_F` | iABC | $R[A] \leftarrow \text{f64}(R[B]) + \text{f64}(R[C])$ |
| `0x04` | `SUB_F` | iABC | $R[A] \leftarrow \text{f64}(R[B]) - \text{f64}(R[C])$ |
| `0x05` | `MUL_F` | iABC | $R[A] \leftarrow \text{f64}(R[B]) \times \text{f64}(R[C])$ |
| `0x06` | `LT_F` | iABC | $\text{if } (\text{f64}(R[B]) \lt \text{f64}(R[C])) \neq A \text{ then } PC \leftarrow PC + 1$ |
| `0x07` | `JMP` | iAsBx | $PC \leftarrow PC + sBx$ |
| `0x10` | `GET_COMP` | iABC | $R[A] \leftarrow \text{ECS\_SoA}[C][\operatorname{Index}(R[B])]$ |
| `0x11` | `SET_COMP` | iABC | $\text{CmdQueue.push}(\text{Entity}: R[A], \text{Comp}: B, \text{Val}: R[C])$ |
| `0x12` | `EMIT_EVT` | iABC | $\text{EventBus.publish}(\text{EventID}: A, \text{Src}: R[B], \text{Arg}: R[C])$ |
| `0x13` | `VEC_SYS` | iABx | SoA kanalı üzerinde vektörel toplu güncelleme döngüsü |
| `0xFF` | `RET` | iABC | Olay işleyicisinden (handler) çıkış |

### 5.4 Tek Geçişli Pratt Parser ve Sıfır Kopyalı Lexer

VScript derleyicisi soyut sözdizimi ağacı (AST) oluşturup heap üzerinde düğüm (node) tahsis etmez. Kaynak kod belleğe tek bir düz metin bloğu olarak yüklenir; Lexer yalnızca başlangıç ve uzunluk belirten `(offset, length)` dilimleri (slices) üretir. **Top-Down Operator Precedence (Vaughan Pratt) algoritması** ile ifadeler okunurken doğrudan bytecode dizisine yazılır.

Her operatör 토큰ı $t$ için **Sol Bağlama Gücü ($\text{lbp}$)** ve **Sağ Bağlama Gücü ($\text{rbp}$)** tanımlanır. İfade çözümleyici $\operatorname{parse\_expr}(\text{min\_bp})$ şu özyinelemeli bağıntıyla çalışır:

$$\text{Sol birincil ifadeyi (nud) oku ve } R_{\text{left}} \text{ kayıtçısına ata.}$$

$$\text{Döngü koşulu: } \operatorname{lbp}(\text{peek\_token}()) \gt \text{min\_bp} \implies \text{Sağ ifadeyi } \operatorname{parse\_expr}(\operatorname{rbp}(\text{op})) \text{ ile çöz ve bytecode üret.}$$

```v
module vscript

// NaN-Boxing Sabitleri ve Yardimci Fonksiyonlar
pub type Value = u64

pub const qnan_mask   = u64(0x7FF8000000000000)
pub const sign_bit    = u64(0x8000000000000000)
pub const tag_nil     = u64(0xFFF8000000000000)
pub const tag_bool    = u64(0xFFF9000000000000)
pub const tag_i32     = u64(0xFFFA000000000000)
pub const tag_entity  = u64(0xFFFB000000000000)

@[inline]
pub fn val_from_f64(n f64) Value {
	return unsafe { *(&u64(&n)) }
}

@[inline]
pub fn val_to_f64(v Value) f64 {
	return unsafe { *(&f64(&v)) }
}

@[inline]
pub fn val_from_i32(i i32) Value {
	return tag_i32 | u64(u32(i))
}

@[inline]
pub fn val_from_entity(index u32, gen u16) Value {
	payload := u64(index) | (u64(gen) << 32)
	return tag_entity | payload
}

// Buyruk Kodlama
pub enum Opcode as u8 {
	op_move     = 0x01
	op_loadk    = 0x02
	op_add_f    = 0x03
	op_sub_f    = 0x04
	op_mul_f    = 0x05
	op_lt_f     = 0x06
	op_jmp      = 0x07
	op_get_comp = 0x10
	op_set_comp = 0x11
	op_emit_evt = 0x12
	op_ret      = 0xFF
}

@[inline]
pub fn encode_abc(op Opcode, a u8, b u8, c u8) u32 {
	return u32(op) | (u32(a) << 8) | (u32(b) << 16) | (u32(c) << 24)
}

@[inline]
pub fn encode_abx(op Opcode, a u8, bx u16) u32 {
	return u32(op) | (u32(a) << 8) | (u32(bx) << 16)
}

@[aligned: 64]
pub struct VMState {
pub mut:
	registers [256]Value
	constants &Value = unsafe { nil }
	code      &u32   = unsafe { nil }
	pc        u32
	fuel      i32 // Sonsuz donguleri kesmek icin deterministik buyruk sayaci
}

pub fn (mut vm VMState) execute_event_handler(entry_pc u32, max_fuel i32, mut soa ecs.TransformKinematicsSoA) bool {
	vm.pc = entry_pc
	vm.fuel = max_fuel

	for vm.fuel > 0 {
		vm.fuel--
		instr := unsafe { vm.code[vm.pc] }
		vm.pc++

		op := unsafe { Opcode(instr & 0xFF) }
		a := u8((instr >> 8) & 0xFF)

		match op {
			.op_move {
				b := u8((instr >> 16) & 0xFF)
				vm.registers[a] = vm.registers[b]
			}
			.op_loadk {
				bx := u16(instr >> 16)
				vm.registers[a] = unsafe { vm.constants[bx] }
			}
			.op_add_f {
				b := u8((instr >> 16) & 0xFF)
				c := u8((instr >> 24) & 0xFF)
				res := val_to_f64(vm.registers[b]) + val_to_f64(vm.registers[c])
				vm.registers[a] = val_from_f64(res)
			}
			.op_sub_f {
				b := u8((instr >> 16) & 0xFF)
				c := u8((instr >> 24) & 0xFF)
				res := val_to_f64(vm.registers[b]) - val_to_f64(vm.registers[c])
				vm.registers[a] = val_from_f64(res)
			}
			.op_mul_f {
				b := u8((instr >> 16) & 0xFF)
				c := u8((instr >> 24) & 0xFF)
				res := val_to_f64(vm.registers[b]) * val_to_f64(vm.registers[c])
				vm.registers[a] = val_from_f64(res)
			}
			.op_lt_f {
				b := u8((instr >> 16) & 0xFF)
				c := u8((instr >> 24) & 0xFF)
				cmp := val_to_f64(vm.registers[b]) < val_to_f64(vm.registers[c])
				expected := a != 0
				if cmp != expected {
					vm.pc++
				}
			}
			.op_jmp {
				sbx := i32(instr >> 16) - 32767
				vm.pc = u32(i32(vm.pc) + sbx)
			}
			.op_get_comp {
				b := u8((instr >> 16) & 0xFF)
				comp_channel := u8((instr >> 24) & 0xFF)
				ent_idx := u32(vm.registers[b] & 0xFFFFFFFF)
				unsafe {
					page := ent_idx >> ecs.page_shift
					offset := ent_idx & ecs.page_mask
					dense_idx := soa.sparse_pages[page][offset]
					val := match comp_channel {
						0 { f64(soa.pos_x[dense_idx]) }
						1 { f64(soa.pos_y[dense_idx]) }
						2 { f64(soa.vel_x[dense_idx]) }
						else { f64(soa.vel_y[dense_idx]) }
					}
					vm.registers[a] = val_from_f64(val)
				}
			}
			.op_set_comp {
				b := u8((instr >> 16) & 0xFF)
				c := u8((instr >> 24) & 0xFF)
				ent_idx := u32(vm.registers[a] & 0xFFFFFFFF)
				new_val := f32(val_to_f64(vm.registers[c]))
				unsafe {
					page := ent_idx >> ecs.page_shift
					offset := ent_idx & ecs.page_mask
					dense_idx := soa.sparse_pages[page][offset]
					match b {
						0 { soa.pos_x[dense_idx] = new_val }
						1 { soa.pos_y[dense_idx] = new_val }
						2 { soa.vel_x[dense_idx] = new_val }
						else { soa.vel_y[dense_idx] = new_val }
					}
				}
			}
			.op_ret {
				return true
			}
			else {
				return false
			}
		}
	}
	return false // Fuel bitti (Zaman asimi korumasi)
}

```

### 5.5 VScript Dilinin İkili Çalışma Modeli (Dual Execution Mode)

VScript dosyaları (`.vs`) iki farklı blok türü içerir:

1. **`@event` Blokları:** Sadece fizik motoru veya oyun mantığı bir olay fırlattığında (`on_collision`, `on_spawn`, `on_timer`) yukarıdaki Bytecode VM üzerinde tekil olay bağlamıyla çalışır.
2. **`@system` Blokları:** Her karede binlerce varlık üzerinde çalışması gereken kurallar (örneğin güdümlü mermilerin hedefe yönelmesi), VScript derleyicisi tarafından derleme zamanında **vektörel bytecode döngülerine (`OP_VEC_SYS`)** veya doğrudan C/V fonksiyon işaretçilerine dönüştürülür. Böylece her varlık için ayrı VM çağrısı yapılmaz; tek bir VM çağrısı içinde SoA dizisi baştan sona taranır.

## 6. Lock-Free Olay Yönlendirici (Event Bus) ve Paralel İş Sistemi

Fizik iş parçacıkları çarpışmaları tespit ederken aynı anda binlerce `CollisionEvent` üretir. Bu olayları mutex (kilit) kullanarak ortak bir listeye yazmak iş parçacıklarını birbirine bekletir (contention). Motor, **Dmitry Vyukov'un Sınırlı MPMC (Multi-Producer Multi-Consumer) Lock-Free Ring Buffer** algoritmasını kullanır.

### 6.1 Dairesel Kuyruk (Ring Buffer) Matematiği

Kapasitesi $N = 2^k$ (örneğin $N = 65536$) olan bir dairesel tamponda, atomik yazma sayacı $W$ ve okuma sayacı $R$ sürekli artan 64-bit tam sayılardır. Herhangi bir $W$ değeri için dizideki fiziksel yuva indeksi modülo (`%`) bölmesi yerine bit maskeleme ile bulunur:

$$\text{Slot}(W) = W \land (N - 1)$$

Her yuva (slot) kendi içinde atomik bir `sequence` sayacı tutar. Bir üretici iş parçacığı $W$ konumuna yazmak istediğinde, yuvanın sıra numarası $S = \text{Slot}[W \land (N-1)].\text{seq}$ değerini okur ve şu farkı hesaplar:

$$\Delta_{\text{seq}} = S - W$$

* **$\Delta_{\text{seq}} = 0$ ise:** Yuva yazmaya hazırdır. Üretici `CAS(enqueue_pos, W, W + 1)` atomik işlemini dener. Başarılı olursa veriyi yazar ve yuvanın sıra numarasını $W + 1$ olarak (`memory_order_release` ile) günceller.
* **$\Delta_{\text{seq}} \lt 0$ ise:** Tampon tamamen doludur (Backpressure durumu).
* **$\Delta_{\text{seq}} \gt 0$ ise:** Başka bir iş parçacığı bu yuvayı daha önce kapmıştır; $W$ yeniden okunur.

```v
module eventbus

// 32-Bayt Sabit Boyutlu Olay Paketi (1 Cache Line'a 2 Olay Sigar)
@[packed]
pub struct EngineEvent {
pub mut:
	sequence   u64 // Atomik sira numarasi
	event_type u16
	flags      u16
	timestamp  u32
	source_ent u64 // EntityID
	target_ent u64 // EntityID veya Payload
}

// Lock-Free Ring Buffer Başlığı (False Sharing onlemek icin 64-byte padding)
@[aligned: 64]
pub struct EventRingBuffer {
pub mut:
	capacity_mask u64
	slots         &EngineEvent = unsafe { nil }
	pad0          [48]u8
	enqueue_pos   u64 // Atomik yazma imleci (ayri cache line)
	pad1          [56]u8
	dequeue_pos   u64 // Atomik okuma imleci (ayri cache line)
	pad2          [56]u8
}

```

### 6.2 Sistemler Arası Bağımlılık Grafiği (DAG) ve İş Çalma (Work-Stealing)

ECS sistemleri çalıştırılmadan önce okudukları (`ReadMask`) ve yazdıkları (`WriteMask`) bileşen kanallarını 64-bitlik bit maskeleri olarak bildirir. İki sistem $S_A$ ve $S_B$ arasındaki çakışma (conflict) koşulu Bernstein Koşulları ile denetlenir:

$$\operatorname{Conflict}(S_A, S_B) = (W_A \land R_B) \lor (R_A \land W_B) \lor (W_A \land W_B) \neq 0$$

$\operatorname{Conflict}(S_A, S_B) = 0$ olan tüm sistemler hiçbir kilit mekanizmasına ihtiyaç duymadan iş parçacığı havuzunda (Thread Pool) aynı anda koşturulur.

## 7. Saf C/OS Platform Katmanı ve Tek-Çağrılı Grafik Boru Hattı

Motor hiçbir pencere veya grafik kütüphanesi (SDL/GLFW/GLEW) kullanmaz. Platform soyutlaması doğrudan işletim sistemi çekirdek kütüphanelerine (`kernel32.dll`, `user32.dll`, `gdi32.dll`, `opengl32.dll` veya Linux `libX11.so`, `libGL.so`) bağlanır.

### 7.1 Yüksek Çözünürlüklü Donanım Zamanlayıcısı

Deterministik 120 Hz döngüsü için standart zaman fonksiyonları yetersizdir. Doğrudan CPU'nun `TSC` (Time Stamp Counter) donanımına dayanan işletim sistemi sayaçları kullanılır:

$$t_{\text{ns}} = \left\lfloor \frac{C_{\text{current}} - C_{\text{start}}}{F_{\text{freq}}} \times 10^9 \right\rfloor$$

Burada $C_{\text{current}}$ Windows'ta `QueryPerformanceCounter`, Linux'ta `clock_gettime(CLOCK_MONOTONIC_RAW)` çıktısıdır.

### 7.2 Sıfır Sürücü Yükü (AZDO) ve Kalıcı Eşlenmiş GPU Tamponu

100.000 varlığı ekrana çizerken her varlık için `glDrawArrays` çağırmak CPU-GPU veri yolunu kilitler. Bunun yerine **Kalıcı Eşlenmiş Tampon (Persistent Mapped Buffer - OpenGL 4.4 / `GL_ARB_buffer_storage`)** ve **Donanımsal Örnekleme (Hardware Instancing)** kullanılır:

1. Başlangıçta GPU VRAM üzerinde **Üçlü Tampon (Triple-Buffered)** bir bellek alanı `GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT` bayraklarıyla ayrılır ve doğrudan bir V/C işaretçisine (`&InstanceData`) eşlenir.
2. Her karede CPU, `glBindBuffer` veya `glBufferSubData` gibi hiçbir sürücü fonksiyonu çağırmadan, doğrudan bu bellek adresine aktif varlıkların $(x, y, \text{radius}, \text{color\_rgba}, \text{sprite\_id})$ verilerini SIMD ile kopyalar.
3. Tüm sahne **tek bir `glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, active_entity_count)**` çağrısıyla çizilir.

### 7.3 2B Ortografik Projeksiyon ve Köşe (Vertex) Dönüşüm Matematiği

GPU'ya her varlık için $4 \times 4$ matris (64 bayt) göndermek bant genişliğini (bandwidth) tüketir. Bunun yerine GPU'ya varlık başına yalnızca **16 baytlık** sıkıştırılmış bir yapı gönderilir:

```c
// GPU'ya gonderilen 16-Baytlik Sikistirilmis Ornek Verisi (Instance Payload)
typedef struct {
    float pos_x;       // 4 byte: Dunya X koordinati
    float pos_y;       // 4 byte: Dunya Y koordinati
    uint16_t scale_x;  // 2 byte: Half-float veya sabit noktali olcek X
    uint16_t scale_y;  // 2 byte: Half-float veya sabit noktali olcek Y
    uint16_t rot_sin;  // 2 byte: Normalize edilmis aci veya Sprite UV ID
    uint16_t color_id; // 2 byte: RGBA5551 veya Palet Indeksi
} InstancePayload;     // Toplam = 16 Byte (100.000 nesne = sadece 1.6 MB/frame!)

```

Vertex Shader içerisinde birim dörtgen (unit quad) köşesi $\mathbf{q} \in [-0.5, 0.5]^2$, dönüş açısı $\theta$, ölçek $\mathbf{s} = (s_x, s_y)$ ve konum $\mathbf{p} = (p_x, p_y)$ kullanılarak dünya koordinatı $\mathbf{w}$ şu dönüşümle hesaplanır:

$$\mathbf{w} = \begin{bmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{bmatrix} \begin{bmatrix} s_x & 0 \\ 0 & s_y \end{bmatrix} \begin{bmatrix} q_x \\ q_y \end{bmatrix} + \begin{bmatrix} p_x \\ p_y \end{bmatrix}$$

Ardından kamera görünüm alanı $[L, R] \times [B, T]$ için **Ortografik Projeksiyon Matrisi** uygulanarak Normalize Edilmiş Cihaz Koordinatları ($\mathbf{x}_{\text{NDC}} \in [-1, 1]^2$) elde edilir:

$$\mathbf{x}_{\text{NDC}} = \begin{bmatrix} \frac{2}{R - L} & 0 & 0 & -\frac{R + L}{R - L} \\ 0 & \frac{2}{T - B} & 0 & -\frac{T + B}{T - B} \\ 0 & 0 & -1 & 0 \\ 0 & 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} w_x \\ w_y \\ 0 \\ 1 \end{bmatrix}$$

```v
module platform

// Saf Win32 ve OpenGL C Bildirimleri (Hicbir harici wrapper yok)
#flag windows -luser32 -lgdi32 -lopengl32 -lkernel32

#include <windows.h>
#include <GL/gl.h>

fn C.QueryPerformanceFrequency(freq &i64) bool
fn C.QueryPerformanceCounter(counter &i64) bool
fn C.SwapBuffers(hdc voidptr) bool

// OpenGL 3.3+ Fonksiyon Isaretcisi Yukleyici
fn C.wglGetProcAddress(name &char) voidptr

pub type PFNGLDRAWARRAYSINSTANCEDPROC = fn (mode u32, first i32, count i32, primcount i32)

pub struct RawTimer {
pub mut:
	freq       i64
	start_tick i64
}

pub fn RawTimer.new() RawTimer {
	mut t := RawTimer{}
	C.QueryPerformanceFrequency(&t.freq)
	C.QueryPerformanceCounter(&t.start_tick)
	return t
}

@[inline]
pub fn (t &RawTimer) elapsed_nanos() u64 {
	mut now := i64(0)
	C.QueryPerformanceCounter(&now)
	diff := u64(now - t.start_tick)
	return (diff * 1_000_000_000) / u64(t.freq)
}

```

## 8. Durum Koruyan Canlı Yeniden Yükleme (State-Preserving Hot-Reload)

Hızlı oyun geliştirme vizyonunun en kritik ayağı, oyun çalışırken `.vs` (VScript) veya `.vdata` (varlık konfigürasyon) dosyalarında yapılan değişikliklerin oyunu kapatmadan **1 milisaniyenin altında** motora yansımasıdır.

### 8.1 Sembol Tablosu Yamalama (Atomic Bytecode Patching)

1. Arka planda çalışan düşük öncelikli bir izleyici iş parçacığı (Windows'ta `ReadDirectoryChangesW`, Linux'ta `inotify_init1`), `scripts/` dizinindeki dosya kaydetme (`FILE_NOTIFY_CHANGE_LAST_WRITE`) sinyallerini yakalar.
2. Değişen `.vs` dosyası **Yedek Derleme Arenası (Staging Arena)** üzerinde yeni bir `BytecodeChunk` yapısına derlenir.
3. Eğer derleme hatasız tamamlanırsa, mevcut kare (`tick`) sonunda ana iş parçacığı bir **Bellek Bariyeri (Memory Barrier)** koyar.
4. Olay yönlendirici tablosundaki (`EventDispatchTable`) ilgili olayların giriş adresleri (`entry_pc`), eski bytecode dizisinden yeni bytecode dizisine atomik işaretçi takası (`atomic_exchange`) ile yönlendirilir.
5. ECS içerisindeki 100.000 varlığın konum, hız, can ve durum verileri `TransformKinematicsSoA` içinde tutulduğu (VM içinde tutulmadığı) için, **oyun durumu hiçbir kayba uğramadan** yeni mantık kurallarıyla akmaya devam eder.

## 9. Ana Motor Döngüsü (Master Tick Orchestration)

Tüm alt sistemlerin tek bir deterministik çerçevede birleştiği ana yürütme döngüsü aşağıdaki gibidir:

```v
module main

import memory
import ecs
import vscript
import eventbus
import platform

pub const fixed_dt_ns = u64(8_333_333) // 120 Hz = 8.333 ms
pub const fixed_dt_sec = f32(1.0 / 120.0)

pub fn run_engine_loop(mut soa ecs.TransformKinematicsSoA, mut vm vscript.VMState, mut ev_bus eventbus.EventRingBuffer) {
	timer := platform.RawTimer.new()
	mut prev_time := timer.elapsed_nanos()
	mut accumulator := u64(0)

	for {
		curr_time := timer.elapsed_nanos()
		mut frame_time := curr_time - prev_time
		prev_time = curr_time

		// Spiral of Death (Olum Sarmali) Korumasi: Maksimum 250 ms birikmeye izin ver
		if frame_time > 250_000_000 {
			frame_time = 250_000_000
		}
		accumulator += frame_time

		// 1. OS Pencere ve Girdi Mesajlarini Tuket (Zero-Allocation)
		// platform.pump_os_messages()

		// 2. Deterministik 120 Hz Simülasyon Adimlari
		for accumulator >= fixed_dt_ns {
			// A. Uzamsal Karma Tablosunu (Spatial Hash Grid) Insa Et (3-Pass)
			// physics.build_spatial_hash(mut soa)

			// B. AVX2 C Cekirdegi ile Semplektik Euler Integrasyonu ve Carpısma Tespiti
			// C.integrate_symplectic_avx2(soa.pos_x, soa.pos_y, soa.vel_x, soa.vel_y, soa.acc_x, soa.acc_y, soa.count, fixed_dt_sec, 0.995)

			// C. Lock-Free Kuyruktaki Tum Olaylari VScript VM Uzerinde Kostur
			// for ev in ev_bus.poll() { vm.execute_event_handler(ev.handler_pc, 10000, mut soa) }

			// D. Hot-Reload Sinyali Varsa Bytecode Tablosunu Atomik Olarak Takas Et
			// hotreload.swap_if_pending(mut vm)

			accumulator -= fixed_dt_ns
		}

		// 3. Gorsel Interpolasyon Katsayisi (Alpha) ve Tek Draw Call ile Cizim
		alpha := f32( f64(accumulator) / f64(fixed_dt_ns) )
		_ = alpha
		// renderer.submit_instanced_dma(soa, alpha)
	}
}

```