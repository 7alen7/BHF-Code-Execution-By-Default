#include "parser.h"
/* An owning translation unit so the compile database has a row whose flags
   (including the compiler token) apply to parser.h. */
int consume(const char *d, size_t n) { return parse_record(d, n); }
