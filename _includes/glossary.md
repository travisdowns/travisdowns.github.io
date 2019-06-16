{% comment %} this file defines commonly used terms so they can be used using the abbreviation syntax in posts {% endcomment %}

*[p0]: port 0 (ALU, not-taken branches)
*[p1]: port 1 (ALU, integer mul)
*[p2]: port 2 (load/store AGU)
*[p3]: port 3 (load/store AGU)
*[p4]: port 4 (store data)
*[p5]: port 5 (ALU, vector shuffles)
*[p6]: port 6 (ALU, all branches)
*[p7]: port 7 (limited store AGU)

{% assign macro_fuse_def = 'The fusing of an ALU operation and subsequent jump, such as `dec eax; jnz label` into one operation' %}
*[macro-fuse]: {{ macro_fuse_def }}
*[macro-fusion]: {{ macro_fuse_def }}
*[macro-fused]: {{ macro_fuse_def }}
*[delamination]: An situation where an instruction using an indexed addressing mode, that is otherwise eligible for micro-fusion, stays fused in the uop-cache, but then delaminates into two separate uops prior to issue, and so counts as two against the pipeline (rename) limit of four uops.
*[naturally aligned]: Naturally aligned data is data whose location in memory is a multiple of its size, e.g., a 4 byte element whose address is a multiple of 4 bytes.
*[AGU]: Address Generation Unit
*[basic block]: a straight-line code sequence with no branches in except to the entry and no branches out except at the exit (Wikipedia).
*[uop]: Micro-operation: instructions are translated into one or more uops, which are simple operations executed by the CPU's execution units.
*[RFO]: Request for ownership: when a request for a cache line originates from a store, or a type of prefetch that predicts the location is likely to be the target of a store, an RFO is performed which gets the line in an exclusive MESI state.


*[OoO]: Out-of-order execution allows CPUs to execute instructions out of order with respect to the source.
*[UPC]: Uops per cycle: The number of a uops executed per cycle, often closely related to IPC.
*[IPC]: Instructions per cycle: calculated over an interval by measuring the number of instructions executed and the duration in cycles.
*[MLP]: Memory level parallelism: having multiple misses to memory outstanding from a single core. When used as a metric, it refers to the average number of outstanding requests over some period.
*[demand load]: A true load that appears in the source code or assembly, as opposed to loads initiated by software or hardware prefetch.

*[SNB]: Intel's Sandy Bridge architecture, aka 2nd Generation Intel Core i3,i5,i7
*[IVB]: Intel's Ivy Bridge architecture, aka 3rd Generation Intel Core i3,i5,i7
*[HSW]: Intel's Haswell architecture, aka 4th Generation Intel Core i3,i5,i7
*[BDW]: Intel's Broadwell architecture, aka 5th Generation Intel Core i3,i5,i7
*[SKL]: Intel's Skylake (client) architecture, aka 6th Generation Intel Core i3,i5,i7
*[SKX]: Intel's Skylake (server) architecture including Skylake-SP, Skylake-X and Skylake-W
*[SNC]: Intel's Sunny Cove architecture, aka 10th Generation Intel Core i3,i5,i7

*[PRF]: Physical register file: The hardware registers used for renaming architectural (source visible) registers, usually much larger in number than the architectural register count.
*[LSD]: Loop stream decoder: The so-called loop buffer that can cache small loops of up to ~64 uops on recent Intel architectures. Not actually a separate structure: the hardware justs locks the loop down in the IDQ.
*[IDQ]: Queue that collects incoming instructions from the decoder, uop cache or microcode engine and delivers them to the renamer (RAT).
*[MITE]: Intel's name for the "legacy" decoder, i.e., the decoder that usually decodes instructions when they are not found in the MSROM.
*[MSROM]: Intel's name for the microcode engine: a component handles complex instructions which require more than 4 uops using microcode which feeds uops directly into the IDQ.
*[HN]: HackerNews
*[ROB]: Re-order buffer: An ordered buffer which stores in-progress instructions on an out-of-order processor.
