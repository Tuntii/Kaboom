#ifndef VCORE_CMD_MAIN_RUN_CTX_H
#define VCORE_CMD_MAIN_RUN_CTX_H

// Ekran görüntüsü kancasının bağlamı: run komutunun yerel durumuna işaretçi. V modül globalleri
// -enable-globals ister; bu yüzden tek işaretçi C static'inde. Yalnız ana thread okur ve yazar.
static void *vcore_run_ctx = 0;

static void vcore_run_set(void *p) { vcore_run_ctx = p; }
static void *vcore_run_get(void) { return vcore_run_ctx; }

#endif
