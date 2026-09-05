#ifndef PARSER_H
#define PARSER_H
#include <stddef.h>
#include <string.h>
/* Header-only fuzzable function. Its presence makes parser.h a govfuzz target,
   which drives the standalone-header preflight in generate_harness.rs. */
static inline int parse_record(const char *data, size_t len) {
    char buf[8];
    if (len) memcpy(buf, data, len);
    return (int)buf[0];
}
#endif
