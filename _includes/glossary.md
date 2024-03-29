{% comment %} this file defines commonly used terms so they can be used using the abbreviation syntax in posts {% endcomment %}

{% comment %} this main section should be in sorted order {% endcomment %}
*[AGU]: Address Generation Unit
*[cross-lane]: A SIMD operation whose lane-wise output depends on elements from lanes other than the same lane in the inputs (lanes are 128 bits in x86).
*[delamination]: An situation where an instruction using an indexed addressing mode, that is otherwise eligible for micro-fusion, stays fused in the uop-cache, but then delaminates into two separate uops prior to issue, and so counts as two against the pipeline (rename) limit of four uops.
*[GP]: General purpose: as opposed to SIMD or FP. On x86 often refers to instructions such as integer addition, or registers such as eax.
*[IP]: Instruction pointer
*[IPC]: Instructions per cycle: calculated over an interval by measuring the number of instructions executed and the duration in cycles.
{% assign macro_fuse_def = 'The fusing of an ALU operation and subsequent jump, such as `dec eax; jnz label` into one operation' %}
*[macro-fuse]: {{ macro_fuse_def }}
*[macro-fusion]: {{ macro_fuse_def }}
*[macro-fused]: {{ macro_fuse_def }}
*[MLP]: Memory level parallelism: having multiple misses to memory outstanding from a single core. When used as a metric, it refers to the average number of outstanding requests over some period.
*[demand load]: A true load that appears in the source code or assembly, as opposed to loads initiated by software or hardware prefetch.
*[naturally aligned]: Naturally aligned data is data whose location in memory is a multiple of its size, e.g., a 4 byte element whose address is a multiple of 4 bytes.
*[microcode]: Internal instructions and other logic forming part of a CPU which may be used to implement user-visible instructions and control other aspects of CPU behavior and which may be modified dynamically by vendor-provided updates. 
*[basic block]: a straight-line code sequence with no branches in except to the entry and no branches out except at the exit (Wikipedia).
*[RFO]: Request for ownership: when a request for a cache line originates from a store, or a type of prefetch that predicts the location is likely to be the target of a store, an RFO is performed which gets the line in an exclusive MESI state.
{% assign ooo_def = 'Out-of-order execution allows CPUs to execute instructions out of order with respect to the source.' %}
*[OoO]: {{ ooo_def }}
*[OOO]: {{ ooo_def }}
*[out-of-order]: {{ ooo_def }}
*[uop]: Micro-operation: instructions are translated into one or more uops, which are simple operations executed by the CPU's execution units.
*[UPC]: Uops per cycle: The number of a uops executed per cycle, often closely related to IPC.

*[p0]: port 0 (GP and SIMD ALU, not-taken branches)
*[p1]: port 1 (GP and SIMD ALU, integer mul)
*[p2]: port 2 (load/store AGU)
*[p3]: port 3 (load/store AGU)
*[p4]: port 4 (store data)
*[p5]: port 5 (GP and SIMD ALU, vector shuffles)
*[p6]: port 6 (GP ALU, all branches)
*[p7]: port 7 (limited store AGU)

{% comment %} Intel uarch abbreviations {% endcomment %}
*[SNB]: Intel's Sandy Bridge architecture, aka 2nd Generation Intel Core i3,i5,i7
*[IVB]: Intel's Ivy Bridge architecture, aka 3rd Generation Intel Core i3,i5,i7
*[HSW]: Intel's Haswell architecture, aka 4th Generation Intel Core i3,i5,i7
*[BDW]: Intel's Broadwell architecture, aka 5th Generation Intel Core i3,i5,i7
*[SKL]: Intel's Skylake (client) architecture, aka 6th Generation Intel Core i3,i5,i7
*[KBL]: Intel's Kaby Lake client CPU architecture (7th, 8th gen): substantially identical to Skylake
*[CNL]: Intel's Cannon Lake (client) architecture, the i3-8121U was the only SKU ever released
*[SKX]: Intel's Skylake (server) architecture including Skylake-SP, Skylake-X and Skylake-W
*[SNC]: Intel's Sunny Cove architecture, aka 10th Generation Intel Core i3,i5,i7
*[RKL]: Intel's Rocket Lake architecture, aka 11th Generation Intel Core i3,i5,i7 and i9

*[Sunny Cove]: The new 7nm microarchitecture used in Ice Lake CPUs.

{% comment %} Apple CPU stuff {% endcomment %}
*[M1]: The first generally available Apple CPU ("Apple Silicon") for laptops with 4 Firestorm and 4 Icestorm cores.
*[Firestorm]: The big, high IPC cores in the Apple M1 CPU.
*[Icestorm]: The low power efficiency cores in the Apple M1 CPU.


*[PRF]: Physical register file: The hardware registers used for renaming architectural (source visible) registers, usually much larger in number than the architectural register count.
*[LSD]: Lysergic acid diethylamide or Loop stream detector, but in the context of this blog probably the latter: The so-called loop buffer that can cache small loops of up to ~64 uops on recent Intel architectures. Not actually a separate structure: the hardware justs locks the loop down in the IDQ.
*[IDQ]: Queue that collects incoming instructions from the decoder, uop cache or microcode engine and delivers them to the renamer (RAT).
*[MITE]: Intel's name for the "legacy" decoder, i.e., the decoder that usually decodes instructions when they are not found in the MSROM.
*[MSROM]: Intel's name for the microcode engine: a component handles complex instructions which require more than 4 uops using microcode which feeds uops directly into the IDQ.
*[HN]: HackerNews
*[ROB]: Re-order buffer: n ordered buffer which stores in-progress instructions on an out-of-order processor.
*[RAT]: Register alias table: a table which maps an architectural register identifier to a physical register.
*[FIVR]: Fully Integrated Voltage Regulator


*[CAS]: Compare-and-swap: an atomic operation implemented on x86 and other CPUs.
*[RMW]: Read-modify-write: an instruction that reads from a memory location, operates on the value, and writes the result back to the same location.
*[immediate]: When discussing assembly instructions an immediate is a value embedded in the instruction itself, e.g., the 1 in add eax, 1.
*[MRU]: Most recently used - an eviction strategy suitable for data with little temporal locality
*[LRU]: Least recently used - an eviction strategy suitable for data with temporal locality
*[SIMD]: Single Instruction Multiple Data: an ISA type or ISA extension like Intel's AVX or ARM's NEON that can perform multiple identical operations on elements packed into a SIMD register.
*[uarch]: Microarchitecture: a specific implementation of an ISA, e.g., "Haswell microarchitecture".
*[ILP]: Instruction level parallelism: a measure of inter-instruction parallelism on a superscalar CPU
