---
layout: post
title: Hardware Store Elimination
category: blog
tags: [Intel, x86, uarch]
assets: /assets/intel-zero-opt
image: /assets/intel-zero-opt/twitter-card.png
results: https://github.com/travisdowns/zero-fill-bench/tree/master/results
twitter:
  card: summary_large_image
comments: true
---

{% include post-boilerplate.liquid %}

I had no plans to write [another post]({{ site.baseurl }}{% post_url 2020-01-20-zero %}) about zeros, but when life throws you a zero make zeroaid, or something like that. Here we go!

If you want to jump over the winding reveal and just read the summary and advice, [now is your chance](#summary-perma).

When writing simple memory benchmarks I have always taken the position the _value_ written to memory didn't matter. Recently, while running a straightforward benchmark[^ubstore] probing the interaction between AVX-512 stores and [read for ownership](https://en.wikipedia.org/wiki/MESI_protocol#Read_For_Ownership) I ran into a weird performance deviation. This is that story[^story].

[^ubstore]: Specifically, I was running `uarch-bench.sh --test-name=memory/bandwidth/store/*` from uarch-bench.

## Table of Contents

* Table of contents
{:toc}

## Prelude

### Data Dependent Performance

On current mainstream CPUs, the timing of most instructions isn't data-dependent. That is, their performance is the same regardless of the _value_ of the input(s) to the instruction. Unlike you[^assume] or me your CPU takes the same time to add `1 + 2` as it does to add `68040486 + 80866502`.

Now, there are some notable exceptions:

 - Integer division is data-dependent on most x86 CPUs: larger inputs generally take longer although the details vary widely among microarchitectures[^icldiv].
 - BMI2 instructions `pdep` and `pext` have [famously terrible](https://twitter.com/uops_info/status/1202950247900684290) and data-dependent performance on AMD Zen and Zen2 chips.
 - Floating point instructions often have slower performance when [denomral numbers](https://en.wikipedia.org/wiki/Denormal_number#Performance_issues) are encountered, although some rounding modes such as _flush to zero_ may avoid this.

That list is not exhaustive: there are other cases of data-dependent performance, especially when you start digging into complex microcoded instructions such as [`cpuid`](https://www.felixcloutier.com/x86/cpuid). Still, it isn't unreasonable to assume that most simple instructions not listed above execute in constant time. 

How about memory operations, such as loads and stores?

Certainly, the _address_ matters. After all the address determines the caching behavior, and caching can easily account for two orders of magnitude difference in performance[^memperf]. On the other hand, I wouldn't expect the _data values_ loaded or stored to matter. There is not much reason to expect the memory or caching subsystem to care about the value of the bits loaded or stored, outside of scenarios such as hardware-compressed caches not widely deployed[^atall] on x86.

### Source

The full benchmark associated with this post (including some additional benchmarks not mention here) is [available on GitHub](https://github.com/travisdowns/zero-fill-bench).

## Benchmarks

That's enough prelude <img src="{{assetpath}}/prelude.jpg" style="display:inline; height: 1.2em;"> for now. Let's write some benchmarks.

### A Very Simple Loop

Let's start with a very simple task. Write a function that takes an `int` value `val` and fills a buffer of a given size with copies of that value. Just like [`memset`](https://en.cppreference.com/w/c/string/byte/memset), but with an `int` value rather than a `char` one.

The canonical C implementation is probably some type of for loop, like this:

~~~c
void fill_int(int* buf, size_t size, int val) {
  for (size_t i = 0; i < size; ++i) {
    buf[i] = val;
  }
}
~~~

... or maybe this[^otherc]:

~~~c
void fill_int(int* buf, size_t size, int val) {
  for (int* end = buf + size; buf != end; ++buf) {
    *buf = val;
  }
}
~~~

In C++, we don't even need that much: we can simply delegate directly to `std::fill` which does the same thing as a one-liner[^bpurp]:

~~~c++
std::fill(buf, buf + size, val);
~~~

There is nothing magic about `std::fill`, it also [uses a loop](https://github.com/gcc-mirror/gcc/blob/866cd688d1b72b0700a7e001428bdf2fe73fbf64/libstdc%2B%2B-v3/include/bits/stl_algobase.h#L698) just like the C version above. Not surprisingly, gcc and clang compile them to the [same machine code](https://godbolt.org/z/R5bJiE)[^clangv].

With the right compiler arguments (`-march=native -O3 -funroll-loops` in our case), we expect this `std::fill` version (and all the others) to be implemented with with AVX vector instructions, and [it is so](https://godbolt.org/z/SfGVEC). The part which does the heavy lifting work for large fills looks like this:

~~~nasm
.L4:
  vmovdqu YMMWORD PTR [rax +   0], ymm1
  vmovdqu YMMWORD PTR [rax +  32], ymm1
  vmovdqu YMMWORD PTR [rax +  64], ymm1
  vmovdqu YMMWORD PTR [rax +  96], ymm1
  vmovdqu YMMWORD PTR [rax + 128], ymm1
  vmovdqu YMMWORD PTR [rax + 160], ymm1
  vmovdqu YMMWORD PTR [rax + 192], ymm1
  vmovdqu YMMWORD PTR [rax + 224], ymm1
  add     rax, 256
  cmp     rax, r9
  jne     .L4
~~~

It copies 256 bytes of data every iteration using eight 32-byte AVX2 store instructions. The full function is much larger, with a scalar portion for buffers smaller than 32 bytes (and which also handles the odd elements after the vectorized part is done), and a vectorized jump table to handle up to seven 32-byte chunks before the main loop. No effort is made to align the destination, but we'll align everything to 64 bytes in our benchmark so this won't matter.

### Our First Benchmark

Enough foreplay: let's take the C++ version out for a spin, with two different fill values (`val`) selected completely at random: zero (`fill0`) and one (`fill1`). We'll use gcc 9.2.1 and the `-march=native -O3 -funroll-loops` flags mentioned above.

We organize it so that for both tests we call the _same_ non-inlined function: the exact same instructions are executed and only the value differs. That is, the compile isn't making any data-dependent optimizations.

Here's the fill throughput in GB/s for these two values, for region sizes ranging from 100 up to 100,000,000 bytes.

<center><strong>Figure 1</strong></center>
{% include svg-fig.html file="fig1" raw="overall.csv" alt="Figure 1" %}


**About this chart:**\\
At each region size (that is, at each position along the x-axis) 17 semi-transparent samples[^warm] are plotted and although they usually overlap almost completely (resulting in a single circle), you can see cases where there are outliers that don't line up with the rest of this sample. This plot tries to give you an idea of the spread of back-to-back samples without hiding them behind error bars[^errorbars]. Finally, the sizes of the various data caches (32, 256 and 6144 KiB for the L1D, L2 and L3, respectively) are marked for convenience.
{: .info}


#### L1 and L2

Not surprisingly, the performance depends heavily on what level of cache the filled region fits into.

Everything is fairly sane when the buffer fits in the L1 or L2 cache (up to ~256 KiB[^l2]). The relatively poor performance for very small region sizes is explained by the prologue and epilogue of the vectorized implementation: for small sizes a relatively large amount of of time is spent in these int-at-a-time loops: rather than copying up to 32 bytes per cycle, we copy only 4.

This also explains the bumpy performance in the fastest region between ~1,000 and ~30,000 bytes: this is highly reproducible and not noise. It occurs because because some sampled values have a larger remainder mod 32. For example, the sample at 740 bytes runs at ~73 GB/s while the next sample at 988 runs at a slower 64 GB/s. That's because 740 % 32 is 4, while 988 % 32 is 28, so the latter size has 7x more cleanup work to to do than the former[^badvec]. Essentially, we are sampling semi-randomly a sawtooth function and if you plot this region with finer granularity (go for it or just [click here]({{page.assets}}/sawtooth.svg)[^melty]) you can see it quite clearly.


#### Getting Weird in the L3

Unlike the L1 or L2, the performance in the L3 is _weird_.

Weird in that we we see a clear divergence between stores of zero versus ones. Remember that this is the exact same function, the same _machine_ code executing the same stream of instructions, only varying in the value of the `ymm1` register passed to the store instruction. Storing zero is consistently about 17% to 18% faster than storing one, both in the region covered by the L3 (up to 6 MiB on my system), and beyond that where we expect misses to RAM (it looks like the difference narrows in the RAM region, but it's mostly a trick of the eye: the relative performance difference is about the same).

What's going on here? Why does the CPU care _what_ values are being stored, and why is zero special?

We can get some additional insight by measuring the `l2_lines_out.silent` and `l2_lines_out.non_silent` events while we focus on the regions that fit in L2 or L3. These events measure the number of lines evicted from L2 either _silently_ or _non-silently_.

Here are Intel's descriptions of these events:

**l2_lines_out.silent**
> Counts the number of lines that are silently dropped by L2 cache when triggered by an L2 cache fill. These lines are typically in Shared or Exclusive state.

**l2_lines_out.non_silent**
> Counts the number of lines that are evicted by L2 cache when triggered by an L2 cache fill. Those lines are in Modified state. Modified lines are written back to L3.

The second definition is not completely accurate. In particular, it implies that only modified lines trigger the _non-silent_ event. However, [I find](https://stackoverflow.com/q/52565303/149138) that unmodified lines in E state can also trigger this event. Roughly, the behavior for unmodified lines seems to be that lines that miss in L2 _and_ L3 usually get filled into the L2 in a state where they will be evicted _non-silently_, but unmodified lines that miss in L2 and _hit_ in L3 will generally be evicted silently[^silent]. Of course, lines that are modified _must_ be evicted non-silently in order to update the outer levels with the new data.

In summary: silent evictions are associated with unmodified lines in E or S state, while non-silent evictions are associated with M, E or (possibly) S state lines, with the silent vs non-silent choice for E and S being made in some unknown matter.

Let's look at silent vs non-silent evictions for the `fill0` and `fill1` cases:

<center><strong>Figure 2</strong></center>
{% include svg-fig.html file="fig2" raw="l2-focus.csv" alt="Figure 2" %}

**About this chart:**\\
For clarity, I show only the median single sample for each size[^trust]. As before, the left axis is fill speed and on the right axis the two types eviction events are plotted, normalized to the number of cache lines accessed in the benchmark. That is, a value of 1.0 means that for every cache line accessed, the event occurred one time.
{:.info}

[^trust]: You've already seen in Fig. 1 that there is little inter-sample variation, and this keeps the noise down. You can always check the raw data if you want the detailed view.

The _total_ number of evictions (sum of silent and non-silent) is the same for both cases: near zero[^wb] when the region fits in L2, and then quickly increases to ~1 eviction per stored cache line. In the L3, `fill1` also behaves as we'd expect: essentially all of the evictions are non-silent. This makes sense since modified lines _must_ be evicted non-silently to write their modified data to the next layer of the cache subsystem.

[^wb]: This shows that the L2 is a write-back cache, not write-through: modified lines can remain in L2 until they are evicted, rather than immediately being written to the outer levels of the memory hierarchy. This type of design is key for high store throughput, since otherwise the long-term store throughput is limited to the bandwidth of the slowest write-through cache level.

For `fill0`, the story is different. Once the buffer size no longer fits in L2, we see the same _total_ number of evictions from L2, but 63% of these are silent, the rest non-silent. Remember, only unmodified lines even have the hope of a silent eviction. This means that at least 63% of the time, the L2[^orl3] is able to detect that the write is _redundant_: it doesn't change the value of the line, and so the line is evicted silently. That is, it is never written back to the L3. This is presumably what causes the performance boost: the pressure on the L3 is reduced: although all the implied reads[^rfo] still need to go through the L3, only about 1 out of 3 of those lines ends up getting written back.

[^rfo]: Although only stores appear in the source, at the hardware level this benchmark does at least as many reads as stores: every store must do a _read for ownership_ (RFO) to get the current value of the line before storing to it.

[^orl3]: I say the L2 because the behavior is already reflected in the L2 performance counters, but it could be teamwork between the L2 and other components, e.g., the L3 could say "OK, I've got that line you RFO'd and BTW it is all zeros".

Once the test starts to exceed the L3 threshold, all of the evictions become non-silent even in the `fill0` case. This doesn't necessarily mean that the zero optimization stops occurring. As mentioned earlier[^silent], it is a typical pattern even for read-only workloads: once lines arrive in L2 as a result of an L3 miss rather than a hit, their subsequent eviction becomes non-silent, even if never written. So we can assume that the lines are probably still detected as not modified, although we lose our visibility into the effect at least as far as the `l2_lines_out` events go. That is, although all evictions are non-silent, some fraction of the evictions are still indicating that the outgoing data is unmodified.

#### RAM: Still Weird

In fact, we can confirm that this apparent optimization still happens as move into RAM using a different set of events. There are several to choose from – and all of those that I tried tell the same story. We'll focus on `unc_arb_trk_requests.writes`, [documented](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/6th-gen-core-family-uncore-performance-monitoring-manual.pdf) as follows:

> Number of writes allocated including any write transaction including full, partials and evictions.

Important to note that the "uncore tracker" these events monitor is used by data flowing between L3 and memory, not between L2 and L3. So _writes_ here generally refers to writes that will reach memory.

Here's how this event scales for the same test we've been running this whole time (the size range has been shifted for focus on the area of interest)[^sneaky]:

[^sneaky]: Eagle-eyed readers, all two of them, might notice that the performance in the L3 region is different than the previous figure: here the performance slopes up gradually across most of the L3 range, while in the previous test it was very flat. Absolute performance is also somewhat lower. This is a testing artifact: reading the uncore performance counters necessarily involves a kernel call, taking over 1,000 cycles versus the < 100 cycles required for `rdpmc` to measure the CPU performance counters needed for the prior figure. Due to "flaws" (laziness) in the benchmark, this overhead is captured in the shown performance, and larger regions take longer, meaning that this fixed measurement overhead has a smaller relative impact, so you get this `measured = actual - overhead/size` type effect. It can be fixed, but I have to reboot my host into single-user mode to capture clean numbers, and I am feeling too lazy to do that right now, although as I look back at the size of the footnote I needed to explain it I am questioning my judgement.

<center><strong>Figure 3</strong></center>
{% include svg-fig.html file="fig3" raw="l3-focus.csv" alt="Figure 3" %}

The number of writes for well-behaved `fill1` approaches one write per cache line as the buffer exceeds the size of L3 – again, this is as expected. For the more rebellious `fill0`, it is almost exactly half that amount. For every two lines written by the benchmark, we only write one back to memory! This same 2:1 ratio is reflected also if we measure memory writes at the integrated memory controller[^imcevent]: writing zeros results in only half the number of writes at the memory controller.

### Wild, Irresponsible Speculation and Miscellanous Musings

This is all fairly strange. It's not weird that there would be a "redundant writes" optimization to avoid writing back identical values: this seems like it could benefit some common write patterns.

It is perhaps a bit unusual that it only apparently applies to all-zero values. Maybe this is because zeros overwriting zeros is one of the most common redundant write cases, and detecting zero values can done more cheaply than a full compare. Also, the "is zero?" state can be communicated and stored as a single bit, which might be useful. For example, if the L2 is involved in the duplicate detection (and the `l2_lines_out` results suggest it is), perhaps the detection happens when the line is evicted, at which point you want to compare to the line in L3, but you certainly can't store the entire old value in or near the L2 (that would require storage as large as the L2 itself). You could store an indicator that the line was zero, however, in a single bit and compare the existing line as part of the eviction process.

#### Predicting a New Predictor

What is the weirdest of all, however, is that the optimization doesn't kick in 100% of the time but only for 40% to 60% of the lines, depending on various parameters[^params]. What would lead to that effect? One could imagine that there could be some type of predictor which determines whether to apply this optimization or not, depending on e.g., whether the optimization has recently been effective – that is, whether redundant stores have been common recently. Perhaps this predictor also considers factors such as the occupancy of outbound queues[^obbus]: when the bus is near capacity, searching for eliminating redundant writes might be more worth the power or latency penalty compared to the case when there is little apparent pressure on the bus.

In this benchmark, any predictor would find that the optimization is 100% effective: _every_ write is redundant! So we might guess that the second condition (queue occupancy) results in a behavior where only some stores are eliminated: as more stores are eliminated, the load on the bus becomes lower and so at some point the predictor no long thinks it is worth it to eliminate stores and you reach a kind of stable state where only a fraction of stores are eliminated based on the predictor threshold.

#### Predictor Test

We can kind of test that theory: in this model, any store is _capable_ of being eliminated, but the ratio of eliminated stores is bounded above by the predictor behavior. So if we find that a benchmark of _pure_ redundant zero stores is eliminated at a 60% rate, we might expect that any benchmark with at least 60% redundant stores can reach the 60% rate, and with lower rates, you'd see full elimination of all redundant stores (since now the bus always stays active enough to trigger the predictor).

Apparently analogies are helpful, so an analogy here would be a person controlling the length of a line by redirecting some incoming people. For example, in an airport security line the handler tries to keep the line at a certain maximum length by redirecting (redirecting -> store elimination) people to the priority line if they are eligible and the main line is at or above its limit. Eligible people are those without carry-on luggage (eligible people -> zero-over-zero stores).\\
\\
If everyone is eligible (-> 100% zero stores), this control will always be successful and the fraction of people redirected will depend on the relative rate of ingress and egress through security. If security only has a throughput of 40% of the ingress rate, 60% of people will redirected in the steady state. Now, consider what happens if not everyone is eligible: if the eligible fraction is at least 60%, nothing changes. You still redirect 60% of people. Only if the eligible rate drops below 60% is there a problem: now you'll be redirecting 100% of eligible people, but the primary line will grow beyond your limit.\\
\\
Whew! Not sure if that was helpful after all?
{: .info}


Let's try a benchmark which adds a new implementation, `alt01` which alternates between writing a cache line of zeros and a cache line of ones. All the writes are redundant, but only 50% are zeros, so under the theory that a predictor is involved we expect that maybe 50% of the stores will be eliminated (i.e., 100% of the redundant stores are eliminated and they make up 50% of the total).

Here we focus on the L3, similar to Fig. 2 above, showing silent evictions (the non-silent ones make up the rest, adding up to 1 total as before):

<center><strong>Figure 4</strong></center>
{% include svg-fig.html file="fig4" raw="l2-focus.csv" alt="Figure 4" %}

We don't see 50% elimination. Rather we see less than half the elimination of the all-zeros case: 27% versus 63%. Performance is better in the L3 region than the all ones case, but only slightly so! So this doesn't support the theory of a predictor capable of eliminating on any store and operating primarily on outbound queue occupancy.

Similarly, we can examine the region where the buffer fits only in RAM, similar to Fig. 3 above:

<center><strong>Figure 5</strong></center>
{% include svg-fig.html file="fig5" raw="l3-focus.csv" alt="Figure 5" %}

Recall that the lines show the number of writes reaching the memory subsystem. Here we see that `alt01` again splits the difference between the zero and ones case: about 75% of the writes reach memory, versus 48% in the all-zeros case, so the elimination is again roughly half as effective. In this case, the performance also splits the difference between all zeros and all ones: it falls almost exactly half-way between the two other cases.

So I don't know what's going on exactly. It seems like maybe only some fraction are of lines are eligible for elimination due to some unknown internal mechanism in the uarch.

### Hardware Survey

Finally, here are the performance results (same as **Figure 1**) on a variety of other Intel and AMD x86 architectures, as well as IBM's POWER9 and Amazon's Graviton 2 ARM processor, one per tab.

{% assign uarches="snb,hsw,skl,skx,cnl,zen2,power9,gra2" %}
{% assign uresults = uarches | split: "," | join: "/remote.csv," | append: "/remote.csv" %}
<!-- uresults: {{uresults}} -->

{% include carousel-svg-fig.html file="fig6"
suffixes=uarches
names="Sandy Bridge,Haswell,Skylake-S,Skylake-X,Cannon Lake,Zen2,POWER9,Graviton 2"
raw=uresults %}

Some observations on these results:

 - The redundant write optimization isn't evident in the performance profile for _any_ of the other non-SKL hardware tested. Not even closely related Intel hardware like Haswell or Skylake-X. I also did a few spot tests with performance counters, and didn't see any evidence of a reduction in writes. So for now this might a Skylake client only thing (of course, Skylake client is perhaps the most widely deployed Intel uarch even due to the many identical-uarch-except-in-name variants: Kaby Lake, Coffee Lake, etc, etc). Note that the Skylake-S result here is for a different (desktop i7-6700) chip than the rest of this post, so we can at least confirm this occurs on two different chips.
 - Except in the RAM region, Sandy Bridge throughput is half of its successors: a consequence of having only a 16-byte load/store path in the core, despite supporting 32-byte AVX instructions.
 - AMD Zen2 has _excellent_ write performance in the L2 and L3 regions. All of the Intel chips drop to about half throughput for writes in the L2: slightly above 16 bytes per cycle (around 50 GB/s for most of these chips). Zen2 maintains its L1 throughput and in fact has its highest results in L2: over 100 GB/s. Zen2 also manages more than 70 GB/s in the L3, much better than the Intel chips, in this test.
 - Both Cannon Lake and Skylake-X exhibit a fair amount of inter-sample variance in the L2 resident region. My theory here would be prefetcher interference which behaves differently than earlier chips, but I am not sure.
 - Skylake-X, with a different L3 design than the other chips, has quite poor L3 fill throughput, about half of contemporary Intel chips, and less than a third of Zen2.
 - The POWER9 performance is neither terrible nor great. The most interesting part is probably the high L3 fill throughput: L3 throughput is as high or higher than L1 or L2 throughput, but still not in Zen2 territory.
 - Amazon's new Graviton processor is very interesting. It seems to be limited to one 16-byte store per cycle[^armcompile], giving it a peak possible store throughput of 40 GB/s, so it doesn't do well in the L1 region versus competitors that can hit 100 GB/s or more (they have both higher frequency and 32 byte stores), but it sustains the 40 GB/s all the way to RAM sizes, with a RAM result flat enough to serve drinks on, and this on a shared 64-CPU host where I paid for only a single core[^g2ga]! The RAM performance is the highest out of all hardware tested.

[^armcompile]: The Graviton 2 uses the Cortex A76 uarch, which can _execute_ 2 stores per cycle, but the L1 cache write ports limits sustained execution to only one 128-bit store per cycle. 

<a id="summary-perma"></a>

## Wrapping Up

### Findings

Here's a brief summary of what we found. This will be a bit redundant if you've just read the whole thing, but we need to accommodate everyone who just skipped down to this part, right?

 - Intel chips can apparently eliminate some redundant stores when an all-zero cache line is written to a cache line that was already all-zero.
 - This optimization applies at least as early as L2 writeback to L3, so would apply to the extend that working sets don't fit in L2.
 - The effect eliminates both write accesses to L3, and writes to memory depending on the working set size.
 - For the pure store benchmark discussed here effect of this optimization is a reduction in the number of writes of ~63% (to L3) and ~50% (to memory), with a runtime reduction of between 15% and 20%.
 - It is unclear why not all redundant zero-over-zero stores are eliminated.

### Tuning "Advice"

So is any of actually useful? Can we use this finding to quadruple the speed of the things that really matter in computation: tasks like bitcoin mining, high-frequency trading and targeting ads in real time?

Nothing like that, no – but it might provide a small boost for some cases.

Many of those cases are probably getting the benefit without any special effort. After all, zero is already a special value: it's how memory arrives comes from the operating system, and at the language allocation level for some languages. So a lot of cases that could get this benefit, probably already are.

Redundant zero-over-zero probably isn't as rare as you might think either: consider that in low level languages, memory is often cleared after receiving it from the allocator, but in many cases this memory came directly from the OS so it is already zero[^calloc].

If you are making a ton of redundant writes, the first thing you might want to do is look for a way to stop doing that. Beyond that, we can list some ways you _might_ be able to take advantage of this new behavior:

 - In the case you are likely to have redundant writes, prefer zero as the special value that is likely to be redundantly overwritten. For example if you are doing some blind writes, something like [card marking](https://richardstartin.github.io/posts/garbage-collector-code-artifacts-card-marking) where you don't know if your write is redundant, you might consider writing zeros, rather than writing non-zeros, since in the case that some region of card marks gets repeatedly written, it will be all-zero and the optimization can apply. Of course, this cuts the wrong way when you go to clear the marked region: now you have to write non-zero so you don't get the optimization during clearing (but maybe this happens out of line with the user code that matters). What ends up better depends on the actual write pattern.
 - In case you might have redundant zero-over-zero writes, pay a bit more attention to 64-byte alignment than you normally would because this optimization only kicks in when a full cache line is zero. So if you have some 64-byte structures that might often be all zero (but with non-zero neighbors), a forced 64-byte alignment will be useful since it would activate the optimization more frequently.
 - Probably the most practical advice of all: just keep this effect in mind because it can mess up your benchmarks and make you distrust performance counters. I found this when I noticed that the scalar version of a benchmark was writing 2x as much memory as the AVX version, despite them doing the same thing other than the choice of registers. As it happens, the dummy value in vector register I was storing was zero, while in the scalar case it wasn't: so there was a large difference that had nothing to do with scalar vs vector, but non-zero vs zero instead. Prefer non-zero values in store microbenchmarks, unless you really expect them to be zero in real life!
  - Keep an eye for a more general version of this optimization: maybe one day we'll see this effect apply to redundant writes that aren't zero-over-zero.

Of course, the fact that this seems to currently only apply on Skylake client hardware makes specifically targeting this quite dubious indeed.

### Thanks

Thanks to Daniel Lemire who provided access to the hardware used in the [Hardware Survey](#hardware-survey) part of this post.

Thanks Alex Blewitt and Zach Wegner who pointed out the CSS tab technique (I used the one linked in the [comments of this post](https://twitter.com/zwegner/status/1223701307078402048)) and others who replied to [this tweet](https://twitter.com/trav_downs/status/1223690150175236102) about image carousels.

### Discussion and Feedback

Leave a comment below if you'd like.

Feedback is also warmly welcomed by comment, [email](mailto:travis.downs@gmail.com) or as [a GitHub issue](https://github.com/travisdowns/travisdowns.github.io/issues).

[^g2ga]: It was the first full day of general availability for Graviton, so perhaps these hosts are very lightly used at the moment because it certainly felt like I had the whole thing to myself.

[^calloc]: This phenomenon is why `calloc` is sometimes considerably faster than `malloc + memset`. With `calloc` the zeroing happens within the allocator, and the allocator can track whether the memory it is about to return is _known zero_ (usually because it the block is fresh from the OS, which always zeros memory before handing it out to userspace), and in the case of `calloc` it can avoid the zeroing entirely (so `calloc` runs as fast as `malloc` in that case). The client code calling `malloc` doesn't receive this information and can't make the same optimization. If you stretch the analogy almost to the breaking point, one can see what Intel is doing here as "similar, but in hardware".

[^params]: I tried a bunch of other stuff that I didn't write up in detail. Many of them affect the behavior: we still see the optimization but with different levels of effectiveness. For example, with L2 prefetching off, only about 40% of the L2 evictions are eliminated (versus > 60% with prefetch on), and the performance difference between is close to zero despite the large number of eliminations. I tried other sizes of writes, and with narrow writes the effect is reduced until it is eliminated at 4-byte writes. I don't think the write size _directly_ affects the optimization, but rather narrower writes slows down the maximum possible performance which interacts in some way with the hardware mechanisms that support this to reduce of often it occurs (a similar observation could apply to prefetching).

[^clangv]: Admittedly I didn't go line-by-line though the long vectorized version produced by clang but the line count is identical and if you squint so the assembly is just a big green and yellow blur they look the same...

[^bpurp]: For benchmarking purposes, we wrap this in another function (TODO: link code) so we can slap a `noinline` attribute on this function to ensure that we have a single non-inlined version to call for different values. If we just called `std::fill` with a literal `int` value, it highly likely to get inlined at the call site and we'd have code with different alignment (and possibly other differences) for each value.

[^story]: Like many posts on this blog, what follows is essentially a _reconstruction_. I encountered the effect originally in a benchmark, as described, and then worked backwards from there to understand the underlying effect. Then, I wrote this post the other way around: building up a new benchmark to display the effect ... but at that point I already knew what we'd find. So please don't think I just started writing the benchmark you find on GitHub and then ran into this issue coincidentally: the arrow of causality points the other way.

[^obbus]: By _outbound bus_ I mean the bus to the outer layers of the memory hierarchy. So for the L2, the outbound bus is the so-called _superqueue_ that connects the L2 to the uncore and the L3 cache.

[^imcevent]: On SKL client CPUs we can do this with the `uncore_imc/data_writes/` events, which polls internal counters in the memory controller itself. This is a socket-wide event, so it is important to do this measurement on as quiet a machine as possible.

[^assume]: Probably? I don't like to assume too much about the reader, but this seems like a fair bet.

[^icldiv]: Starting with Ice Lake, it seems like Intel has implemented a constant-time integer divide unit.

[^memperf]: Latency-wise, something like 4-5 cycles for an L1 hit, versus 200-500 cycles for a typical miss to DRAM. Throughput wise there is also a very large gap (256 GB/s L1 throughput _per core_ on a 512-bit wide machine versus usually less than < 100 GB/s _per socket_ on recent Intel).

[^atall]: Is it deployed anywhere at all on x86? Ping me if you know.

[^otherc]: It's hard to say which is faster if they are compiled as written: x86 has indexed addressing modes that make the indexing more or less free, at least for arrays of element size 1, 2, 4 or 8, so the usual arguments againt indexed access mostly don't apply. Probably, it doesn't matter: this detail might have made a big difference 20 years ago, but it is unlikely to make a difference on a decent compiler today, which can transform one into the other, depending on the target hardware. 

[^l2]: The ~ is there in ~256 KiB because unless you use huge pages, you might start to see L2 misses even before 256 KiB since only a 256 KiB _virtually contiguous_ buffer is not necessarily well behaved in terms of evictions: it depends how those 4k pages are mapped to physical pages. As soon as you get too many 4k pages mapping to the same group of sets, you'll see evictions even before 256 KiB.

[^silent]: This behavior is interesting and a bit puzzling. There are several reasons why you might want to do a non-silent eviction. (1a) would be to keep the L3 snoop filter up to date: if the L3 knows a core no longer has a copy of the line, later requests for that line can avoid snooping the core and are some 30 cycles faster. (1b) Similarly, if the L3 wants to evict this line, this is faster if it knows it can do it without writing back, versus snooping the owning core for a possibly modified line. (2) Keeping the L3 LRU more up to date: the L3 LRU wants to know which lines are hot, but most of the accesses are filtered through the L1 and L2, so the L3 doesn't get much information – a non-silent eviction can provide some of the missing info (3) If the L3 serves as a victim cache, the L2 needs to write back the line for it to be stored in L3 at all. SKX L3 actually works this way, but despite being a very similar uarch, SKL apparently doesn't. However, one can imagine that on a miss to DRAM it may be advantageous to send the line directly to the L2, updating the L3 tags (snoop filter) only, without writing the data into L3. The data only gets written when the line is subsequently evicted from the owning L2. When lines are frequency modified, this cuts the number of writes to L3 in half. This behavior warrants further investigation.

[^melty]: Those melty bits where the pattern gets all weird, in the middle and near the right side are not random artifacts: they are consistently reproducible. I suspect a collision in the branch predictor history.

[^badvec]: It is worth noting[^nested] his performance deviation isn't exactly inescapable, just a consequence of poor remainder handling in the compiler's autovectorizer. An approach that would be much faster and generate much less code to handle the remaining elements would be to do a final full-width vector store but aligned to the 

[^nested]: Ha! To me, everything is "worth noting" if it means another footnote.

So while there are some interesting effects on the left half, they are fairly easy to explain and, more to the point, performance for the zero and one cases are identical: the samples are all concentric. As soon as we dip our toes into the L3, however, things start to get _weird_.

[^warm]: There are 27 samples total at each size: the first 10 are discarded as warmup and the remaining 17 are plotted.

[^errorbars]: The main problem with error bars are that most perforamnce profiling results, and especially microbenchmarks, are mightly non-normal in their distribution, so displaying an error bar based a statistic like the variance is often highly misleading.

---
<br>

{% include glossary.md %}
