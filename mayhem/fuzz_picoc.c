/* In-process libFuzzer harness for picoc.
 *
 * picoc is a small C interpreter. Upstream ships a raw file-input CLI
 * (`picoc <file.c>`) as its only entry point; the previous Mayhem target ran
 * that binary over a file (`/picoc @@`). Driving the interpreter in-process
 * over the same code path (scan the source, then call main() — exactly what
 * `picoc <file.c>` does in its default "program" mode) instruments the whole
 * interpreter (lex/parse/expression/type/variable/heap) for far denser
 * coverage while preserving the fuzzed code path.
 *
 * picoc reports every error via PlatformExit() -> longjmp(pc->PicocExitBuf),
 * so setting the exit point with PicocPlatformSetExitPoint() cleanly recovers
 * from any parse/run error without tearing down the process. The interpreter's
 * whole working set lives on a heap arena freed en masse by PicocCleanup(), so
 * even an error mid-parse leaves nothing leaked.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "picoc.h"

/* Same stack/heap arena size picoc's own main() uses (PICOC_STACK_SIZE). */
#define PICOC_STACK_SIZE (128000 * 4)

int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size)
{
    Picoc pc;
    char *Source;

    /* picoc's lexer requires a NUL-terminated source string. */
    Source = (char *)malloc(Size + 1);
    if (Source == NULL)
        return 0;
    memcpy(Source, Data, Size);
    Source[Size] = '\0';

    PicocInitialize(&pc, PICOC_STACK_SIZE);

    /* setjmp target for PlatformExit()/ProgramFail(); 0 == first return. */
    if (PicocPlatformSetExitPoint(&pc) == 0) {
        /* CleanupSource=false: we own Source and free it after cleanup, so
         * function bodies parsed here stay valid through PicocCallMain(). */
        PicocParse(&pc, "fuzz", Source, (int)Size, true, false, false, false);
        PicocCallMain(&pc, 0, NULL);
    }

    PicocCleanup(&pc);
    free(Source);
    return 0;
}
