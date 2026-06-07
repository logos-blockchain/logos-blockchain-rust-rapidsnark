/*
 * glibc >= 2.38 redirects strtoll/strtoull to the C23 interceptor symbols
 * __isoc23_strtoll / __isoc23_strtoull at compile time. The prebuilt iden3
 * rapidsnark archives were compiled against such a glibc, so their verifier
 * objects reference those symbols. When the static archives are linked on a
 * host with an older glibc (e.g. Ubuntu 22.04 / glibc 2.35) the symbols are
 * undefined and linking fails.
 *
 * Provide thin forwarders to the classic strtoll/strtoull symbols. We bind to
 * the legacy symbol names explicitly via asm labels and deliberately avoid
 * including <stdlib.h>, so this translation unit is itself immune to the C23
 * header redirect (otherwise the forwarder would recurse into itself when this
 * file is compiled on a new-glibc build host).
 */
extern long long __legacy_strtoll(const char *, char **, int) __asm__("strtoll");
extern unsigned long long __legacy_strtoull(const char *, char **, int) __asm__("strtoull");

long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
    return __legacy_strtoll(nptr, endptr, base);
}

unsigned long long __isoc23_strtoull(const char *nptr, char **endptr, int base) {
    return __legacy_strtoull(nptr, endptr, base);
}
