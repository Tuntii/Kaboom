# V-Core ertelenen işler

M1/M2 incelemelerinden kalan, bilerek ertelenen maddeler. Hedef dilim parantez içinde.

## M3
- Protokol tarafında istek başına ~14 KB heap sızıntısı (`-gc none`; 100k `entity.get` ≈ 1,35 GB). İstek başına arena ya da protokol tarafına GC. Tick yolu etkilenmiyor.
- `sim/sim.v` alan indeksleri sabit kodlu (x=0, vx=0…); `Sim.new` içinde `field_index` ile çözülmeli.
- `ComponentStore.column_f32` alan indeksini kontrol etmiyor (renderer kolon okumaya başlamadan assert).
- Şema `min`/`max` yayınlanıyor ama protokolde uygulanmıyor; aralıklı ilk bileşenden önce uygula ya da kaldır (M3/M4).
- Malformed-input testi eksik yanıtları `or { continue }` ile atlıyor; 1012 protokol testi yok.

## M4
- Yeniden kullanılan slottaki bayat handle ile mutator testleri (undo/redo handle'ları çok yeniden kullanacak).
- `record.start` yalnızca bozulmamış dünyada; sahne formatı gelince snapshot'lı kayıt.

## Kayıt formatı bir sonraki değiştiğinde
- Sağlama toplamı yalnızca gövdeyi kapsıyor; başlıktaki `end_tick`/`capacity` korumasız (bozuk `end_tick` uzun replay'e yol açabilir).
- Kayıt bitiş hash'ini saklasın, `replay.run` `matches` dönsün.

## M6
- `symbol` alan tipi `register` ile üretilemiyor; i32/bool/entity JSON dönüşümü yok; tip başına varsayılan aralık.
- `CommandQueue.push` geçersiz `source`'u "dolu" ile aynı şekilde reddediyor.

## Küçük / fırsat buldukça
- Hata ipucuna geçersiz UTF-8 method adı kopyalanıyor; 2^53 üstü JSON-RPC id'ler birebir yankılanmıyor.
- `protocol/methods.v` büyük (params.v ayrılabilir); test yardımcıları üç dosyada kopya; `heapcount.h` static değil.
- `PoolAllocator.slot_ptr` assert'i `-prod`'da kaybolur; havuz kopyalama notu.
- `record.stop` taşma dalının testi yok.
