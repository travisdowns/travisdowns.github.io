---
layout: post
title:  "What has your microcode done for you lately?"
date:   2019-03-19 12:00:00 -300
category: blog
tags: [intel, memory, performance]
assets: /assets/2019-03-19
---


## Microcode Mystery 

Did you ever wonder what is *inside* those microcode updates that get silently applied to your CPU via Windows update, BIOS upgrades, and various microcode packages on Linux?

Well, you are in the wrong place, because this blog post won't answer that question (you might like [this](https://www.emsec.ruhr-uni-bochum.de/media/emma/veroeffentlichungen/2017/08/16/usenix17-microcode.pdf) though).

In fact, the overwhelming majority of this this post is about the performance of scattered writes, and not very much at all about the details of CPU microcode. Where the microcode comes in, and what might make this more interesting than usual, is that performance on a purely CPU-bound benchmark can vary dramatically _depending on microcode version_. In particular, we will show that the most recent Intel microcode version can significantly slow down a store heavy workload when some stores hit in the L1 data cache, and some miss.

My results are intended to be reproducible and the benchmarking and data collection code is available as described [at the bottom](#the-source). 

## A series of random writes

How fast can you perform a series of random writes? Because of the importance of caching, you might reasonably expect that it depends heavily on how big of a region the writes are scattered across, and you'd be right. For example, if we test a series of random writes to a region that fits entirely in L1, we find that random writes take almost exactly 1 cycle on modern Intel chips, matching the published limit of one write per cycle [^2].

If we use larger regions, we expect performance to slow down as many of the writes miss to outer cache levels. In fact, I measure roughly the following performance whether for linear (64 byte stride) or random writes to various sized regions:

| Region Size | Cycles/Write | Typical Read Latency |
|-|
| L1 | 1 | 5 |
| L2 | 3 | 12 | 
| L3 | 5-6 | ~35 |
| RAM | 15-20 | ~200 |

I've also included a third column in the table above which records typical read latency figures for each cache level. This gives an indication of roughly how *far away* a cache is from the core, based on the round-trip read time. Since all normal stores[^normal-stores] also involve a read (to get the cache line to write to into the L1 cache with its existing contents), the time to "complete" a single store should be at least that long[^4]. As the observed time per write is much less, these tests must exhibit significant [memory level parallelism](https://en.wikipedia.org/wiki/Memory-level_parallelism) (MLP), i.e., several store misses are in-progress in the memory subsystem at once and their latencies overlap.  We usually care about MLP when it comes to loads, but it is important also for a long stream of stores such as these benchmarks. The last line in above table implies that we may have requests for 10 or more stores in flight in the memory subsystem at once, in order to achieve average store time of 15-20 cycles with a memory latency of 200 cycles.

You can reproduce this table yourself using the `wrandom1-unroll` and `wlinear1` tests.

## Interleaved writes

Let's move on to the case where we actually observe some interesting behavior. Here we tackle the same scenario that I asked about in a [twitter poll](https://twitter.com/trav_downs/status/1103396480994422784).

Consider the following loop, which writes randomly to _two_ character arrays.

```c++
int writes_inter(size_t iters, char* a1, size_t size1, char *a2, size_t size2) {
    rng_state rng = RAND_INIT;
    do {
        uint32_t val = RAND_FUNC(&rng);
        a1[(val & (size1 - 1))] = 1;
        a2[(val & (size2 - 1))] = 2;
    } while (--iters > 0);
    return 0;
}
```

Let's say we fix the size of the first array, `size1`, to something like half the size of the L2 cache, and evaluate the performance for a range of sizes for the second array, `size2`. What type of performance do we expect? We already know the time it takes for a single write to regions of various size, so in principle one might expect the above loop to perform something like the sum of the time of one write to an L2-sized region (the write to `a1`) and one write to a `size2` sized region (the write to `a2`).

Let's try it! Here's a test of single stores vs interleaved stores (with one of the interleaved stores accessing a fixed 128 KiB region), varying the size of the other region, run on my Skylake i7-6700HQ.

![Interleaved vs Single stores]({{page.assets}}/skl/i-vs-s-old.svg)

Overall we see that behavior of the two benchmarks roughly track each other, with the interleaved version (twice as many stores) taking longer than the single store version, as expected.

Especially for large region sizes (the right side of the graph), the assumption that interleaved accesses are more or less additive with the same accesses by themselves mostly pans out: there is a gap of about 4 cycles between the single stream and the stream with interleaved accesses, which is just slightly more than the cost of an L2 access. For small region sizes, the correspondence is less exact. In particular, the single stream drops down to ~1 cycle accesses when the region fits in L1, but in the interleaved case this doesn't occur.

At least part of this behavior makes sense: the two streams of stores will interact in the caches, and the L1 contained region isn't really "L1 contained" in the interleaved case because the second stream of stores will be evicting lines from L1 constantly. So with a 16 KiB second region, the test really behaves as if a 16 + 128 = 144 KiB region was being accessed, i.e., L2 resident, but in a biased way (with the 16 KiB block being accessed much more frequently), so there is no sharp decrease in iteration time at the 32 KiB boundary[^5].

## The weirdness begins

So far, so good and nothing too weird. However, starting now, it _is_ about to get weird!

Everything above is a reduced version of a benchmark I was using to test some *real code*[^1], about a year ago. This code had a tight loop with a table lookup and then writes to two different arrays. When I benchmarked this code, performance was usually consistent with the performance of "interleaved" benchmark plotted above.

Recently, I returned to the benchmark to check the performance on newer CPU architectures. First, I went back to check the results on the original hardware (the [Skylake i7-6700HQ](https://ark.intel.com/products/88967) in my laptop). I failed to reproduce it -- I wasn't able to achieve the same performance, with the same test and on the same hardware as before: it was always running significantly slower (about half the original speed).

With some help from user Adrian on the [RWT forums](https://www.realworldtech.com/forum/?roomid=1) I was able to bisect the difference down to a CPU microcode update. In particular, with newest microcode version [^7], `0xc6` the interleaved stores scenario runs _much_ slower. For example, the same benchmark as above now looks like this, every time you run it:

![Interleaved vs Single Stores (New Microcode)]({{page.assets}}/skl/i-vs-s-new.svg)

The behavior of interleaved for small regions (left hand side of chart) is drastically different - the throughput is less than half of the old microcode. It is not obvious just by visual comparison it, but performance is actually reduced across the range of tested sizes for the interleaved case, albeit by only a few cycles as the region size becomes large. I tested various microcode versions and found that only the most recent SKL microcode, revision `0xc6` and released in August 2018 exhibits the "always slow" behavior shown above. The preceding version `0xc2` usually results in the fast behavior. 

What's up with that?

### Performance Counters

We can check the performance counters to see if they reveal anything. We'll use the `l2_rqsts.references`, `l2_rqsts.all_rfo` and `l2_rqsts.rfo_miss` counters, which count the total number of accesses (`references`) and total accesses related to RFO requests (`all_rfo` aka _stores_) from the core as well as the number that miss (`rfo_miss`). Since we are only performing stores, we expect these counts to match and to correspond to the number of L1 store misses, since any store that misses in L1 ultimately contributes[^9] to an L2 access.

Here's the old microcode:

![Interleaved Stores w/ Perf Counters (old microcode)]({{page.assets}}/skl/i-plus-counters-old.svg)

... and the new microcode:

![Interleaved Stores w/ Perf Counters (new microcode)](/assets/2019-03-07/skl/i-plus-counters-new.svg)

Despite the large difference in performance, there is very little to no difference in the relevant performance counters. In both cases, the number of L1 misses (i.e., L2 references) approaches 0.75 as the second region size approaches zero as we'd expect (all L1 hits in the second region, and about 25% L1 hits in the 128 KiB fixed region as the L1D is 25% of the size of L2). On the right side, the number of L1 misses approaches something like 1.875, as the L1 hits in the 128 KiB region are cut in half by competition with with the other large region.

So despite the much slower performance, for L1-sized second regions, the difference doesn't obviously originate in different cache hit behavior. Indeed, with the new microcode, performance goes _down_ as the L1 hit rate goes _up_.

So it seems that the likeliest explanation is that _the presence of an L1 hit in the store buffer prevents overlapping of miss handling for stores on either side_, at least with the new microcode, on SKL hardware. That is, a series of consecutive stores can be handled in parallel only if none of them is an L1 hit. In this way L1 store hits somehow act as a store fence with the new microcode. The performance is in line with each store going alone to the memory hierarchy: roughly the L2 latency plus a few cycles. 

### Will the real sfence please stand up

Let's test the "L1 hits act as a store fence" theory. In fact, there is already an instruction that acts as a store force in the x86 ISA: [`sfence`](https://www.felixcloutier.com/x86/sfence). Repeatedly executed back-to-back this instruction only takes a [few cycles](http://uops.info/html-instr/SFENCE-1063.html) but its most interesting effect occurs when stores are in the pipeline: this instruction blocks dispatch of subsequent stores until all earlier stores have committed to the L1 cache, implying that stores on different sides of the fence cannot overlap[^sfence-note].

We will look at two version of the interleaved loop with `sfence`: one with `sfence` inserted right after the store to the first region (fixed 128 KiB), and the other inserted after the store to the second region - let's call them sfenceA and sfenceB respectively. Both have the same number of fences (one per iteration, i.e., per pair of stores) and only differ in what store happens to be last in the store buffer when the `sfence` executes. Here's the result on the new microcode (the results on the old microcode are [over here]({{page.assets}}/skl/i-sfence-old.svg)):

![Interleaved Stores w/ SFENCE]({{page.assets}}/skl/i-sfence-new.svg)

The right side of the grpah is fairly unremarkable: both versions with sfence perform roughly at the latency for the associated cache level because there is zero memory level parallelism (no, I don't know why one performs better than other or why the performance crosses over near 64 KiB). The left part is pretty amazing though: one of the sfence configurations is _faster than the same code without sfence_. That's right, adding a store serializing instruction like sfence, can speed up the code by several cycles. It doesn't come close to the fast performance of the old microcode versions, but the behavior is very surprising nonetheless.

The version that was faster, sfenceA, had the `sfence` between the 128 KiB store and the L1 store. So perhaps there is some kind of penalty when an L1 hit store arrives right after a L1-miss-L2-hit store, in addition to the "no MLP" penalty we normally see.

## Larger fixed regions

To this point we've been we've been looking at the scenario where a write to a 128 KiB region is interleaved with a write to a region of varying size. The fixed size of 128 KiB means that most[^13] of those writes will be L2 hits. What if we make the fixed size region larger? Let's say 2 MiB, which is much larger than L2 (256 KiB) but still fits easily in L3 (6 MiB on my CPU). Now we expect most writes to the fixed region to be L2 misses but L3 hits.

What's the behavior? Here's the old microcode:

![Interleaved Stores w/ 2048 KiB Fixed Region]({{page.assets}}/skl/i-vs-s-2mib-old.svg)

... and the new:

![Interleaved Stores w/ 2048 KiB Fixed Region]({{page.assets}}/skl/i-vs-s-2mib-new.svg)

Again we see a large performance impact with the new microcode, and the results are consistent with the theory that L1 hits in the store stream prevent overlapping of store misses on either side. In particular we see that the region with L1 hits takes about 37 cycles, almost exactly the L3 latency on this CPU. In this scenario, it is _slower to have L1 hits mixed in to the stream of accesses than to replace those L1 hits with misses to DRAM_. That's a remarkable demonstration of the power of memory level parallelism and of the potential impact of this change.

## Why?

I can't tell you for certain why the store related machinery acts the way it does in this case. Speculating is fun though, so lets do that. Here are a couple possibilities for why the memory model acts the way it does.

### The x86 Memory Model

First, let's quickly review the x86 memory model.

The x86 has a relatively strong memory model. Intel doesn't give it a handy name, but lets call it [x86-TSO](https://www.cl.cam.ac.uk/~pes20/weakmemory/cacm.pdf). In x86-TSO, stores from all CPUs appear in a global total order with stores from each CPU consistent with program order. If a given CPU makes stores A and B in that order, all other CPUs will observe not only a consistent order of stores A and B, but the *same* A-before-B order as the program order. All this store ordering complicates the pipeline. In weaker memory models like ARM and POWER, in the absence of fences, you can simply commit senior stores[^17] in whatever order is convenient. If some store locations are already present in L1, you can commit those, while making RFO requests for other store locations which aren't in L1.

An x86 CPU has a to take more conservative strategy. The basic idea is that stores are only made globally observable _in program order_ as they reach the head of the store buffer. The CPU may still try to get parallelism by prefetching upcoming stores, as described for example in Intel's [US patent 7130965](https://patents.google.com/patent/US7130965/en)[^patent-note] - but care must be taken. For example, any snoop request that comes in for any of the lines in flight must get a consistent result: whether the lines are in a write-back buffer being evicted from L1, in a fill buffer making their way to L2, in a write-combining buffer[^wc-note] waiting to commit to L1, and so on.

### Write Combining Buffers

With that out of the way, let's talk about how the store pipeline might actually work.

Let's assume that when a store misses in the L1 it allocates a _fill buffer_ to fetch the associated line from the outer levels of the memory hierarchy (we can be pretty sure this is true). Lets further assume that if another stores in the store buffer reaches the head of the store buffer and is to the same line, we get effectively a "fill buffer hit", and that in this case the store is _merged into the existing fill buffer and removed from the store buffer_*. That is, the fill buffer entry itself keeps track of the written bytes, and merges those bytes with any unwritten ones when the line returns from the memory hierarchy, before finally committing it to L1[^wc-stores].

In the scenario where there are outstanding fill buffers containing store stater, committing stores that hit in L1 is tricky: if you have several outstanding fill buffers for outstanding stores, as well as several interleaved L1-hit stores, the strong memory model[^x86-memmodel] used by x86 means that you have to ensure that any incoming snoop requests see all those stores in the same order. You can't just snoop all the fill buffers and then the L1 or vice-versa since that might change the apparent order. Additionally, stores become globally visible if they are committed to the L1, but the global observability point for stores whose data is being collected in the fill buffers is less clear.

One simple approach for dealing with L1-hits stores when there are outstanding stores in the fill buffers is to delay the store until the outstanding stores complete and are committed to L1. This could prevent any parallelism between stores with an intervening L1 hit, unless RFO prefetching kicks in. So perhaps the difference is whether the RFO prefetch heuristic determines it is profitable to prefetch stores. Or perhaps the CPU is able to choose between two strategies in this scenario, one of which allows parallelism and one which doesn't. For example, perhaps the L1 stores could themselves be buffered in fill buffers, which seems silly except that it may allow preserving the order among stores which both hit and miss in L1. For whatever reason the CPU choose the no-parallelism strategy more in the case of the new microcode.

Perhaps the overlapping behavior was completely disabled to support some recent type of Spectre mitigation (see for example [SSB disable](https://en.wikipedia.org/wiki/Speculative_Store_Bypass) functionality which was probably added in this newest microcode version).

Without more details on the mechanisms on modern Intel CPUs it is hard to say more, but there are certainly cases where extreme care has to be taken to preserve the order of writes. The _fill buffers_ used for L1 misses, as well as associated components in the outer cache layers already need to be ordered to support the memory model (which also disallows load-load reordering), so in that sense all the stores that miss L1 are already in good hands. Stores that want to commit directly to L1 are more problematic since they are no longer tracked and have become globally observable (a snoop may arrive at any moment and see the newly written) value. I did take a good long look at the patents, but didn't find any smoking gun to explain the current behavior.

## Workarounds

Now that we're aware of the problem, is there anything we can do in the case we are bitten by it? Yes.

### Avoid or reduce fine-grained interleaving

The problem occurs when you have _fine-grained_ interleaving between L1 hits and L1 misses. Sometimes you can avoid the interleaving entirely, but if you not you can perhaps make it coarser grained. For example, the current interleaved test alternates between L1 misses and L1 misses, like `L1-hit, L1-miss, L1-hit, L1-miss`. If you unroll by a factor of two and then move the writes to the same region to be adjacent in the source (which doesn't change the semantics since the regions are not overlapping), you'll coarser grained interleaving, like: `L1-hit, L1-hit, L1-miss, L1-miss`. Based on our theory of reduced memory level parallelism, grouping the stores in this way will allow at least _some_ overlapping (in this example, two stores can be overlapped).

Let's try this, comparing unrolling by a factor of two and four versus the plain unrolled version. The main loop in the factor of two unrolled version (the factor of 4 is equivalent) looks like:

```c++
do {
    uint32_t val1 = RAND_FUNC(&rng);
    uint32_t val2 = RAND_FUNC(&rng);
    a1[(val1 & (size1 - 1))] = 1;
    a1[(val2 & (size1 - 1))] = 1;
    a2[(val1 & (size2 - 1))] = 2;
    a2[(val2 & (size2 - 1))] = 2;
} while (--iters > 0);
```

Here's is the performance with a fixed array size of 2048 KiB (since the performance degradation is more dramatic with large fixed region sizes):

![Interleaved Stores with Unrolling]({{page.assets}}/skl/i-unrolled-2mib-new.svg)

For the region where L1 hits occur, the unroll by gives a 1.6x speedup, and the unroll by 4 a 2.5x speed. Even when unrolling by 4 we still see an impact from this issue (performance still improves once almost every store is an L1 miss) - but we are much closer to the expected the baseline performance before the microcode update.

This change doesn't come for free: unrolling the loop by hand has a cost in development complexity as the unrolled loop is more complicated. Indeed, the implementation in the benchmark doesn't handle values of `iters` which aren't a multiple or 2 or 4. It also has a cost in code size as the unrolled functions are larger:

| Function | Loop Size in Bytes | Function Size in Bytes |
|-|
| Original | 40 | 74 |
| Unrolled 2x | 72 | 108 |
| Unrolled 4x | 140 | 191 |

Finally, note that while more unrolling is faster in the region where L1 hists is faster, the situation reverses itself around 64 KiB, and after that point no unrolling is fastest.

All this means that in this particular example you would face some tough tradeoffs if you want to reduce the impact by unrolling.

### Prefetching

You can solve this particular problem using software prefetching instructions. If you prefetch the lines you are going to store to, a totally different path is invoked: the same one that handles loads, and here the memory level parallelism will be available regardless of the the limitations of the store path. One complication is that, except for `prefetchw`[^prefetchw], such prefetches will be "shared OK" requests for the line, rather than an RFO (request for ownership). This means that the core might receive the line in the S MESI state, adn then When the store occurs, a _second_ request may be incurred to change the line from S state to M state. In my testing this didn't see to be a problem in practice, perhaps because the lines are not shared across cores so generally arrive in the E state, and the E->M transition is cheap.

### Avoiding Microcode Updates

The simplest solution is to simply avoid the newest microcode updates. These updates seem drive by new spectre mitigations, so if you are not enabling that functionality (e.g., SSDB is disabled by default in Linux, so if you aren't explicitly enabling it, you won't get it), perhaps you can do without these updates.

This strategy is not feasible once the microcode update contains something you need.

Additionally, as noted above, even the old microcodes _sometimes_ experience the same slower performance that new microcodes always exhibit. I cannot exactly characterize the conditions in which this occurs, but one should at least be aware that old microcodes aren't _always_ fast. 

## Other findings

This post is already longer than I wanted it to be. The idea is for posts to closer to [JVM Anatomy Park](https://shipilev.net/jvm/anatomy-quarks/) than [War and Peace](https://en.wikipedia.org/wiki/War_and_Peace). Still, there is a bunch of stuff uncovered which I'll summarize here:

 - The current test uses regions whose addresses whose bottom 12 bits are identically zero, but whose 13th bit varies. That is, the regions "4K alias" but do not "8K alias". Since the main loop uses the same random address for both regions (wrapped to region size by masking) in each iteration, this means that the stores alias as describe above. However, this is not the cause of the main effects reported here: you can remove the aliasing completely and the behavior is largely the same[^11].
 - You can go the other way too: if you increase the aliasing (you can try this by setting environment variable `ALLOW_ALIAS=1`) up to 64 KiB (bottom 16 bits of the _physical_ address), I found a strong effect where performance was slower with the _old_ microcode. This effect seems to have disappeared with the new microcode. Now 64 KiB aliasing (especially _physical_ aliasing) is probably a lot more rare than mixed L1 hits and L1 misses in the stream of stores, so I'd rather the old behavior than the new - but this is probably interesting enough to write about separately.
 - I do sometimes see the "slow mode" behavior with earlier microcode versions. Almost a year ago, when the last several version of the microcode didn't even exist, I experienced periodic slow mode behavior while benchmarking - the same type of performance in the L1 region as the current microcode shows all the time. On older microcode I can still reproduce this consistently: _if all CPUs are loaded when I start the `bench` process_. For example `./bench interleaved` consistently gives fast mode, but `stress -c 4 & ./bench interleaved` consistently gives slow timings ... _even when I kill the CPU using processes before the results roll in_. In that case, the tests keep running in slow mode even though it's the only thing running on the system.<br><br>This seems to explain why I randomly got slow mode in the past. For example, I noticed that something like `./bench interleaved > data; plot-csv.py data` would give fast mode results, but when I shortened it to `./bench interleaved | plot-csv.py` it would be in slow mode, because apparently launching the python interpreter in parallel on the RHS of the pipe used enough CPU to trigger the slow mode. I had a weird 10 minutes or so where I'd run `./bench` without piping it and look at the data, and then try to plot it and it would be totally different, back and forth.
  - I considered the idea that this bad behavior only shows up when the store buffer is full, e.g., because of some interaction that occurs when renaming is stalled on store buffer entries, but versions of the test which periodically drain the store buffer with `sfence` so it never becomes very full showed the same result.
 - I examined the values of a lot more performance counters than the few shown above, but none of them provided any smoking gun for the behavior: they were all consistent with L1 hits simply blocking overlap of L1 miss stores on either side.


### Other platforms

An obvious and immediate question is what happens on other micro-architectures, beyond my Skylake client core. 

On Haswell, the behavior is _always slow_. That is, whether with old or new microcode, store misses mixed with L1 store hits were much slower than expected. So if you target Haswell or (perhaps) Broadwell era hardware, you might want to keep this in mind regardless of microcode version.

On Skylake-X (Xeon W-2401), the behavior is _always fast_. That is, even with the newest microcode version I did not see the slow behavior. I also was not able to trigger the behavior by starting the test with loaded CPUs as I was with Skylake client with old microcode.

On Cannonlake I did not observe the slow behavior. I don't know if I was using an "old" or "new" microcode as Intel does not publish microcode guidance for Cannonlake (and it isn't clear to me if any Cannonlake microcodes have been released at all as very few chips were ever shipped).

You can look at the results for all the platforms I tested in the [assets directory]({{page.assets}}). The plots are the same as described above for Skylake plus some variants not show but which should be obvious from the title or filename.

## The Source

You can have fun reproducing all these results yourself as my code is available in the store-bench project [on GitHub](https://github.com/travisdowns/store-bench). Documentation is a bit lacking, but it shouldn't be to hard to figure out. Open an issue if anything is unclear or you find a bug, and pull requests gladly accepted.

## Thanks

Thanks to [Daniel Lemire](https://lemire.me/en/) who kindly provided additional hardware on which I was able to test these results. 


---
---
<br>


[^1]: By *real code* I simply mean something that is not a benchmark, not necessarily anything actually useful.

[^2]: Of course, to achieve one-write per cycle, your benchmark has to be otherwise quite efficient: among other things the process by which you generate random addresses needs to have a throughput of one per cycle too, so usually you'll want cheat a bit on the RNG side. I wrote such a test and you can run it with `./bench wrandom1-unroll`. For buffer sizes that fit within L1, it achieves very close to 1 cycle per write (roughly 1.01 cycles per write for most buffer sizes).

[^normal-stores]: Here "normal stores" basically means stores that are to write-back (WB) memory regions and which are not the special non-temporal stores that x86 offers. Almost every store you'll do from a typical program falls into this category.

[^4]: In fact, we can test this - the `wlinear1-sfence` test is a linear write test like `wlinear1` except with an `sfence` instruction between every store. This flushes the store buffer, preventing any overlap in the stores and the observed time per store is in all cases a couple of cycles above the corresponding read latency (probably corresponding to `sfence` overhead).

[^5]: This isn't really the whole story though. If the L1 cache misses explained it, we'd expect performance to approach ~4 cycles (1 cycle L1 + 3 cycle L2) as the size of the region approaches 0, since at some point the smaller region will stay in L2 regardless of interference from other stores. It doesn't happen though: performance flatlines at 6 cycles, the cost of two stores to L2. Perhaps what happens is that the L1 stores in the store buffer reduce the MLP of the interleaved L2 stores because the RFO prefetch mechanism only has a certain horizon it examines. For example, maybe it examines the 10 entries closest to the store buffer head for prefetch candidates, and with the L1-hitting stores in there, there are only half as many L2-hitting stores to fetch.

[^7]: See your microcode version on Linux using `cat /proc/cpuinfo | grep -m1 micro` or `dmesg | grep micro`. The latter option also helps you determine if the microcode was updated during boot by the Linux microcode driver.

[^9]: I used the weasel word "contributes" here rather than "ultimately results in an L1 miss" to cover the case where two stores occur to the same line in short succession and that line is not in L1. In this case, both stores will miss, but there will generally only be one reference to L2 since the fill buffers operate on whole cache lines, so both stores will be satisfied by the same miss. The same effect occurs for loads and can be measured explicitly by the `mem_load_retired.fb_hit` event: those are loads that missed in L1, but subsequently hit the _fill buffer_ (aka miss status handling register) allocated for an earlier access to the same cache line that also missed. 

[^sfence-note]: Actually, this doesn't seem to be strictly true. The results on some CPUs are too good to represent zero overlapping between stores. E.g., the [old microcode results]({{page.assets}}/skl/i-sfence-old.svg)) show the sfenceB results staying under 30 cycles even for main-memory sized regions (and quite close to the no sfence results), which is only possible with a lot of store overlapping. So something remains to be discovered about sfence behavior.

[^11]: I did notice _some_ differences when removing the aliasing: for example, sfenceA and sfenceB converged and finally performed the same as the region size increased, rather than sfenceB crossing over and being several cycles faster than sfenceA.

[^13]: In particular, when the variable sized region is small, we expect the fixed region write to always hit in L1 or L2 (since the total working set fits in L2), with a ratio approaching 1:3 as the variable region goes to zero. When the variable region is large, we expect many fixed region writes to hit in L2 and less frequently L1, but some will miss even in L2 as the working set is larger than L2 and with random writes some fixed region lines will be evicted before they are written again. The cache related performance counters agree with this hand-waving explanation.

[^17]: _Senior stores_ are stores that have retired (the instruction has been completed in the out-of-order engine), but whose value hasn't yet been committed to the memory subsystem and hence are not globally observable.

[^patent-note]: This patent is interesting not least because the title is "Apparatus and method for store address for store address prefetch **and line locking**", but as far as I can tell the latter part about "line locking" is never mentioned again in the body of the patent. One might imagine that line looking involves something like delaying or nacking incoming snoops for a line that is about to be written.

[^wc-note]: It is an open question whether normal writes which miss in L1 simply wait in the store buffer until the RFO request is complete, or whether they instead get stashed in a write combining buffer associated with the cache line, potentially collecting several store misses to the same line. The latter sounds more efficient but any combining of stores out of order with respect to the store buffer is problematic: committing multiple such WC buffers when the line is available in L1 could change the apparent order of stores unless all WC buffers are committed as a unit or some other approach is taken. 

[^wc-stores]: I am not 100% sure this is the mechanism, versus an alternative of say stalling the store buffer with the missing store at the head, until the fill buffer returns, but we have evidence both in wording from the Intel manuals, and [this answer on StackOverflow](https://stackoverflow.com/a/53438221). The main argument in favor of this implementation would be performance: it prevents the store buffer from stalling, allowing more stores to commit or start additional requests to memory and keeping the store buffer smaller to avoid stalling the front-end. The main argument against is that it seems hard to maintain ordering in this scenario: if a stream of stores is coalesced into more than one fill buffer, the relative order between the stores is lost, and it is not in general possible to commit the store buffers to L1 "one at a time" while preserving the original store order, you'd basically have to commit all the fill buffers at once (atomically wrt the outside world), or put limits on what stores can be coalesced.

[^x86-memmodel]: The x86 has a relatively strong memory model: lets call it [x86-TSO](https://www.cl.cam.ac.uk/~pes20/weakmemory/cacm.pdf). In x86-TSO, stores from all CPUs appear in a global total order with stores from each CPU consistent with program order. If a given CPU makes stores A and B in that order, all other CPUs will observe not only a consistent order of stores A and B, but the *same* A-before-B order as the program order. All this store ordering complicates the pipeline. In weaker memory models like ARM and POWER, in the absence of fences, you can simply commit senior stores[^17] in whatever order is convenient. If some store locations are already present in L1, you can commit those, while making RFO requests for other store locations which aren't in L1. An x86 CPU has a to take more conservative strategy. The basic idea is that stores are only made globally observable _in program order_ as they reach the head of the store buffer. The CPU may still try to get parallelism by prefetching upcoming stores, as described for example in Intel's [US patent 7130965](https://patents.google.com/patent/US7130965/en)[^patent-note] - but care must be taken. For example, any snoop request that comes in for any of the lines in flight must get a consistent result: whether the lines are in a write-back buffer being evicted from L1, in a fill buffer making their way to L2, in a write-combining buffer[^wc-note] waiting to commit to L1, and so on.

[^prefetchw]: The `prefetchw` has long been supported by AMD, but on Intel it is only supported on Broadwell and more recent micro-architectures. Earlier Intel chips didn't implement this functionality, but the `prefetchw` opcode was still accepted and executed as a no-op.
