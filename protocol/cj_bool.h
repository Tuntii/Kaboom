#ifndef VCORE_PROTOCOL_CJ_BOOL_H
#define VCORE_PROTOCOL_CJ_BOOL_H

// cJSON.c, true/false makrolarını ((cJSON_bool)1) gibi tanımlar. V'nin closure kodu '#if false' yazar ve
// bu ifade önişlemcide geçersizdir. Makrolar burada düz tamsayıya çevrilir; değerler aynıdır. cJSON'a dokunulmaz.
#undef true
#define true 1
#undef false
#define false 0

#endif
