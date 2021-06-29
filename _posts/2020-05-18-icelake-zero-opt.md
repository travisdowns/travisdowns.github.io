---
layout: post
title: Ice Lake Store Elimination
category: blog
tags: [Intel, x86, uarch, icelake]
assets: /assets/intel-zero-opt
tables: /intel-zero-opt
image: /assets/intel-zero-opt/twitter-card-post2.png
results: https://github.com/travisdowns/zero-fill-bench/tree/master/results
twitter:
  card: summary_large_image
excerpt: We look at the zero store optimization as it applies to Intel's newest micro-architecture.
---

{% include post-boilerplate.liquid %}

## Introduction

If you made it down to the [hardware survey]({% post_url 2020-05-13-intel-zero-opt %}#hardware-survey) on the last post, you might have [wondered](https://twitter.com/tarlinian/status/1260629853000265728) where Intel's newest mainstream architecture was. _Ice Lake was missing!_

Well good news: it's here... and it's interesting. We'll jump right into the same analysis we did last time for Skylake client. If you haven't read the [first article]({% post_url 2020-05-13-intel-zero-opt %}) you'll probably want to start there, because we'll refer to concepts introduced there without reexplaining them here.

As usual, you can skip to the [summary](#summary) for the bite sized version of the findings.

## ICL Results

### The Compiler Has an Opinion

Let's first take a look at the overall performance: facing off `fill0` vs `fill1` as we've been doing for every microarchitecture. Remember, `fill0` fills a region with zeros, while `fill1` fills a region with the value one (as a 4-byte `int`).

All of these tests run at 3.5 GHz. The max single-core turbo for this chip is at 3.7 GHz, but is difficult to run in a sustained manner at this frequency, because of AVX-512 clocking effects and because other cores occasionally activate. 3.5 GHz is a good compromise that keeps the chip running at the same frequency, while remaining close to the ideal turbo. Disabling turbo is not a good option, because this chip runs at 1.1 GHz without turbo, which would introduce a large distortion when exercising the uncore and RAM.
{: .warning}

<center><strong>Figure 7a</strong></center>
{% include svg-fig.html file="fig7a" raw="icl512/overall-warm.csv" alt="Figure 7a" %}

Actually, I lied. *This* is the right plot for Ice Lake:

<center><strong>Figure 7b</strong></center>
{% include svg-fig.html file="fig7b" raw="icl/overall-warm.csv" alt="Figure 7b" %}

Well, which is it?

Those two have a couple of key differences. The first is this weird thing that **Figure 7a** has going on in the right half of the L1 region: there are two obvious and distinct performance levels visible, each with roughly half the samples.

<!-- https://stackoverflow.com/questions/43806515/position-svg-elements-over-an-image -->
<style>
.img-overlay-wrap {
  position: relative;
  display: block; /* <= shrinks container to image size */
}

.img-overlay-wrap svg {
  position: absolute;
  top: 0;
  left: 0;
}
</style>

<div class="img-overlay-wrap">
  <img class="figimg" src="{{assetpath}}/fig7a.svg" alt="Figure 7a Annotated">
  <svg viewBox="0 0 90 60">
    <g stroke-width=".5" fill="none" opacity="0.5">
      <ellipse transform="rotate(-25 34 10)" cx="34" cy="10" rx="12" ry="5" stroke="green" />
      <ellipse transform="rotate(-25 34 34.5)" cx="34" cy="34.5" rx="12" ry="5" stroke="red" />
    </g>
  </svg>
</div>

The second thing is that while both of the plots show _some_ of the zero optimization effect in the L3 and RAM regions, the effect is _much larger_ in **Figure 7b**:

<div class="img-overlay-wrap">
  <img class="figimg" src="{{assetpath}}/fig7b.svg" alt="Figure 7a Annotated">
  <svg viewBox="0 0 90 60">
    <g stroke-width=".5" fill="none" opacity="0.5">
      <ellipse cx="63" cy="40" rx="10" ry="8" stroke="blue" />
    </g>
  </svg>
</div>

So what's the difference between these two plots? The top one was compiled with `-march=native`, the second with `-march=icelake-client`.

Since I'm compiling this _on_ the Ice Lake client system, I would expect these to do the same thing, but for [some reason they don't](https://twitter.com/stdlib/status/1261038662751522826). The primary difference is that `-march=native` [generates](https://godbolt.org/z/gm3vRa) 512-bit instructions like so (for the main loop):

~~~nasm
.L4:
    vmovdqu32   [rax], zmm0
    add         rax, 512
    vmovdqu32   [rax-448], zmm0
    vmovdqu32   [rax-384], zmm0
    vmovdqu32   [rax-320], zmm0
    vmovdqu32   [rax-256], zmm0
    vmovdqu32   [rax-192], zmm0
    vmovdqu32   [rax-128], zmm0
    vmovdqu32   [rax-64],  zmm0
    cmp     rax, r9
    jne     .L4
~~~

Using `-march=icelake-client` uses 256-bit instructions[^still512]:

~~~nasm
.L4:
    vmovdqu32   [rax], ymm0
    vmovdqu32   [rax+32], ymm0
    vmovdqu32   [rax+64], ymm0
    vmovdqu32   [rax+96], ymm0
    vmovdqu32   [rax+128], ymm0
    vmovdqu32   [rax+160], ymm0
    vmovdqu32   [rax+192], ymm0
    vmovdqu32   [rax+224], ymm0
    add     rax, 256
    cmp     rax, r9
    jne     .L4
~~~

Most compilers use 256-bit instructions by default even for targets that support AVX-512 (reason: [downclocking](https://reviews.llvm.org/D67259), so the `-march=native` version is the weird one here. All of the earlier x86 tests used 256-bit instructions.

The observation that **Figure 7a** results from running 512-bit instructions, combined with a peek at the data lets us immediately resolve the mystery of the bi-modal behavior.

Here's the raw data for the 17 samples at a buffer size of 9864:

<table border="1" class="dataframe" style="max-width:500px; font-size:80%;">
  <thead>
    <tr>
      <th></th>
      <th></th>
      <th colspan="2" halign="left">GB/s</th>
    </tr>
    <tr>
      <th>Size</th>
      <th>Trial</th>
      <th>fill0</th>
      <th>fill1</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th rowspan="17" valign="top">9864</th>
      <th>0</th>
      <td>92.3</td>
      <td>92.0</td>
    </tr>
    <tr>
      <th>1</th>
      <td>91.9</td>
      <td>91.9</td>
    </tr>
    <tr>
      <th>2</th>
      <td>91.9</td>
      <td>91.9</td>
    </tr>
    <tr>
      <th>3</th>
      <td>92.4</td>
      <td>92.2</td>
    </tr>
    <tr>
      <th>4</th>
      <td>92.0</td>
      <td>92.3</td>
    </tr>
    <tr>
      <th>5</th>
      <td>92.1</td>
      <td>92.1</td>
    </tr>
    <tr>
      <th>6</th>
      <td>92.0</td>
      <td>92.0</td>
    </tr>
    <tr>
      <th>7</th>
      <td>92.3</td>
      <td>92.1</td>
    </tr>
    <tr>
      <th>8</th>
      <td>92.2</td>
      <td>92.0</td>
    </tr>
    <tr>
      <th>9</th>
      <td>92.0</td>
      <td>92.1</td>
    </tr>
    <tr>
      <th>10</th>
      <td>183.3</td>
      <td>93.9</td>
    </tr>
    <tr>
      <th>11</th>
      <td>197.3</td>
      <td>196.9</td>
    </tr>
    <tr>
      <th>12</th>
      <td>197.3</td>
      <td>196.6</td>
    </tr>
    <tr>
      <th>13</th>
      <td>196.6</td>
      <td>197.3</td>
    </tr>
    <tr>
      <th>14</th>
      <td>197.3</td>
      <td>196.6</td>
    </tr>
    <tr>
      <th>15</th>
      <td>196.6</td>
      <td>197.3</td>
    </tr>
    <tr>
      <th>16</th>
      <td>196.6</td>
      <td>196.6</td>
    </tr>
  </tbody>
</table>

The performance follows a specific pattern with respect to the trials for both `fill0` and `fill1`: it starts out slow (about 90 GB/s) for the first 9-10 samples then suddenly jumps up the higher performance level (close to 200 GB/s). It turns out this is just [voltage and frequency management]({% post_url 2020-01-17-avxfreq1 %}) biting us again. In this case there is no frequency change: the [raw data](https://github.com/travisdowns/zero-fill-bench/blob/post2/results/icl512/overall-warm.csv#L546) has a frequency column that shows the trials always run at 3.5 GHz. There is only a voltage change, and while the voltage is changing, the CPU runs with reduced dispatch throughput[^iclbetter].

The reason this effect repeats for every new set of trials (new buffer size value) is that each new set of trials is preceded by a 100 ms spin wait: this spin wait doesn't run any AVX-512 instructions, so the CPU drops back to the lower voltage level and this process repeats. The effect stops when the benchmark moves into the L2 region, because there it is slow enough that the 10 discarded warmup trials are enough to absorb the time to switch to the higher voltage level.

We can avoid this problem simply by removing the 100 ms warmup (passing `--warmup-ms=0` to the benchmark), and for the rest of this post we'll discuss the no-warmup version (we keep the 10 warmup _trials_ and they should be enough).

## Elimination in Ice Lake

So we're left with the second effect, which is that the 256-bit store version shows _very_ effective elimination, as opposed to the 512-bit version. For now let's stop picking favorites between 256 and 512 (push that on your stack, we'll get back to it), and just focus on the elimination behavior for 256-bit stores.

Here's the closeup of the L3 region for the 256-bit store version, showing also the L2 eviction type, as discussed in the previous post:

<center><strong>Figure 8</strong></center>
{% include svg-fig.html file="fig8" raw="icl/l2-focus.csv" alt="Figure 8" %}

We finally have the elusive (near) 100% elimination of redundant zero stores! The `fill0` case peaks at 96% silent (eliminated[^stricly]) evictions. Typical L3 bandwidth is ~59 GB/s with elimination and ~42 GB/s without, for a better than 40% speedup! So this is a potentially a big deal on Ice Lake.

Like last time, we can also check the uncore tracker performance counters, to see what happens for larger buffers which would normally write back to memory.

<center><strong>Figure 9</strong></center>
{% include svg-fig.html file="fig9" raw="icl/l3-focus.csv" alt="Figure 9" %}

**Note:** the way to interpret the events in this plot is the reverse of the above: more uncore tracker writes means _less_ elimination, while in the earlier chart more silent writebacks means _more_ elimination (since every silent writeback replaces a non-silent one).
{: .info}

As with the L3 case, we see that the store elimination appears 96% effective: the number of uncore to memory writebacks flatlines at 4% for the `fill0` case. Compare this to [**Figure 3**]({{assetpath}}/fig3.svg), which is the same benchmark running on Skylake-S, and note that only half the writes to RAM are eliminated.

This chart also includes results for the `alt01` benchmark. Recall that this benchmark writes 64 bytes of zeros alternating with 64 bytes of ones. This means that, at best, only half the lines can be eliminated by zero-over-zero elimination. On Skylake-S, only about 50% of eligible (zero) lines were eliminated, but here we again get to 96% elimination! That is, in the `alt01` case, 48% of all writes were eliminated, half of which are all-ones and not eligible.

The asymptotic speedup for the all zero case for the RAM region is less than the L3 region, at about 23% but that's still not exactly something to sneeze at. The speedup for the alternating case is 10%, somewhat less than half the benefit of the all zero case[^altwrites]. In the L3 region, we also note that the benefit of elimination for `alt01` is only about 7%, much smaller than the ~20% benefit you'd expect if you cut the 40% benefit the all-zeros case sees. We saw a similar effect in Skylake-S.

Finally it's worth noting this little uptick in uncore writes in the `fill0` case:

![Little Uptick]({{assetpath}}/little-uptick.png)

This happens right around the transition from L3 to RAM, and this, the writes flatline down to 0.04 per line, but this uptick is fairly consistently reproducible. So there's some interesting effect there, probably, perhaps related to the adaptive nature of the L3 caching[^l3adapt].

[^l3adapt]: The L3 is capable of determining if the current access pattern would be better served by something like an MRU eviction strategy, for example when a stream of data is being accessed without reuse, it would be better to kick that data out of the cache quickly, rather than evicting other data that may be useful.


### 512-bit Stores

If we rewind time, time to pop the mental stack and return to something we noticed earlier: that 256-bit stores seemed to get superior performance for the L3 region compared to 512-bit ones.

Remember that we ended up with 256-bit and 512-bit versions due to unexpected behavior in the `-march` flag. Rather they _relying_ on this weirdness[^gccfix], let's just write slighly lazy[^lazy] [methods](https://github.com/travisdowns/zero-fill-bench/blob/master/algos.cpp#L151) that explicitly use 256-bit and 512-bit stores but are otherwise identical. `fill256_0` uses 256-bit stores and writes zeros, and I'll let you pattern match the rest of the names.

Here's how they perform on my ICL hardware:

<center><strong>Figure 10</strong></center>
{% include svg-fig.html file="fig10" raw="icl/256-512.csv" alt="Figure 10" %}

This chart shows only the the median of 17 trials. You can look at the raw data for an idea of the trial variance, but it is generally low.
{: .warning}

In the L1 region, the 512-bit approach usually wins and there is no apparent difference between writing 0 or 1 (the two halves of the moon mostly line up). Still, 256-bit stores are roughly _competitive_ with 512-bit: they aren't running at half the throughput. That's thanks to the second store port on Ice Lake. Without that feature, you'd be limited to 112 GB/s at 3.5 GHz, but here we handily reach ~190 GB/s with 256-bit stores, and ~195 GB/s with 512-bit stores. 512-bit stores probably have a slight advantage just because of fewer total instructions executed (about half of the 256-bit case) and associated second order effects.

Ice Lake has two _store ports_ which lets it execute two stores per cycle, but only a single cache line can be written per cycle. However, if two consecutive stores fall into the _same_ cache line, they will generally both be written in the same cycle. So the maximum sustained throughput is up to two stores per cycle, _if_ they fall in the same line[^l1port].
{: .info}


In the L2 region, however, the 256-bit approaches seem to pull ahead. This is a bit like the Buffalo Bills winning the Super Bowl: it just isn't supposed to happen.

Let's zoom in:

<center><strong>Figure 11</strong></center>
{% include svg-fig.html file="fig11" raw="icl/256-512-l2-l3.csv" alt="Figure 11" %}

The 256-bit benchmarks start roughly tied with their 512 bit cousins, but then steadily pull away as the region approaches the full size of the L2. By the end of the L2 region, they have nearly a ~13% edge. This applies to _both_ `fill256` versions -- the zeros-writing and ones-writing flavors. So this effect doesn't seem explicable by store elimination: we already know ones are not eliminated and, also, elimination only starts to play an obvious role when the region is L3-sized.

In the L3, the situation changes: now the 256-bit version really pulls ahead, _but only the version that writes zeros_. The 256-bit and 512-bit one-fill versions fall down in throughput, nearly to the same level (but the 256-bit version still seems _slightly but measurably ahead_ at ~2% faster). The 256-bit zero fill version is now ahead by roughly 45%!

Let's concentrate only on the two benchmarks that write zero: `fill256_0` and `fill512_0`, and turn on the L2 eviction counters (you probably saw that one coming by now):

{% include svg-fig.html file="fig12" raw="icl/256-512-l2-l3.csv" alt="Figure 12" %}

Only the _L2 Lines Out Silent_ event is shown -- the balance of the evictions are _non-silent_ as usual.
{: .warning}

Despite the fact that I had to leave the right axis legend just kind floating around in the middle of the plot, I hope the story is clear: 256-bit stores get eliminated at the usual 96% rate, but 512-bit stores are hovering at a decidedly Skylake-like ~56%. I can't be sure, but I expect this difference in store elimination largely explains the performance difference.

I checked also the behavior with prefetching off, but the pattern is very similar, except with both approaches having reduced performance in L3 (you can [see for yourself]({{assetpath}}/fig12-nopf.svg)). It is interesting to note that for zero-over-zero stores, the 256-bit store performance _in L3_ is almost the same as the 512-bit store performance _in L2!_ It buys you almost a whole level in the cache hierarchy, performance-wise (in this benchmark).

Normally I'd take a shot at guessing what's going on here, but this time I'm not going to do it. I just don't know[^lied]. The whole thing is very puzzling, because everything after the L1 operates on a cache-line basis: we expect the fine-grained pattern of stores made by the core, _within a line_ to basically be invisible to the rest of the caching system which sees only full lines. Yet there is some large effect in the L3 and even in RAM[^RAM] related to whether the core is writing a cache line in two 256-bit chunks or a single 512-bit chunk.

## Summary

We have found that the store elimination optimization originally uncovered on Skylake client is still present in Ice Lake and is roughly twice as effective in our fill benchmarks. Elimination of 96% L2 writebacks (to L3) and L3 writebacks (to RAM) was observed, compared to 50% to 60% on Skylake. We found speedups of up to 45% in the L3 region and speedups of about 25% in RAM, compared to improvements of less than 20% in Skylake.

We find that when zero-filling writes occur to a region sized for the L2 cache or larger, 256-bit writes are often significantly _faster_ than 512-bit writes. The effect is largest for the L2, where 256-bit zero-over-zero writes are up to _45% faster_ than 512-bit writes. We find a similar effect even for non-zeroing writes, but only in the L2.

## Future

It is an interesting open question whether the as-yet-unreleased Sunny Cove server chips will exhibit this same optimization.

## Advice

Unless you are developing only for your own laptop, as of May 2020 Ice Lake is deployed on a microscopic fraction of total hosts you would care about, so the headline advice in the previous post applies: this optimization doesn't apply to enough hardware for you to target it specifically. This might change in the future as Ice Lake and sequels roll out in force. In that case, the magnitude of the effect might make it worth optimizing for in some cases.

For fine-grained advice, see the [list in the previous post]({% post_url 2020-05-13-intel-zero-opt %}#tuning-advice).

## Thanks

Vijay and Zach Wegner for pointing out typos.

Ice Lake photo by [Marcus Löfvenberg](https://unsplash.com/@marcuslofvenberg) on Unsplash.

Saagar Jha for helping me track down and fix a WebKit rendering [issue](https://github.com/travisdowns/travisdowns.github.io/issues/102).

## Discussion and Feedback

If you have something to say, leave a comment below. There are also discussions on [Twitter](https://twitter.com/trav_downs/status/1262428350511022081) and [Hacker News](https://news.ycombinator.com/item?id=23225260).

Feedback is also warmly welcomed by [email](mailto:travis.downs@gmail.com) or as [a GitHub issue](https://github.com/travisdowns/travisdowns.github.io/issues).


---
<br>

{% include glossary.md %}

[^RAM]: We didn't take a close look at the effect in RAM but it persists, albeit at a lower magnitude. 256-bit zero-over-zero writes are about 10% faster than 512-bit writes of the same type.

[^lied]: Well I lied. I at least have some ideas. It may be that the CPU power budget is dynamically partitioned between the core and uncore, and with 512-bit stores triggering the AVX-512 power budget, there is less power for the uncore and it runs at a lower frequency (that could be checked). This seems unlikely given that it should not obviously affect the elimination chance.

[^still512]: It's actually still using the EVEX-encoded AVX-512 instruction `vmovdqu32`, which is somewhat more efficient here because AVX-512 has more compact encoding of offsets that are a multiple of the vector size (as they usually are).

[^stricly]: Strictly speaking, a silent writeback is a _sufficient_, but not a _necessary_ condition for elimination, so it is a lower bound on the number of eliminated stores. For all I know, 100% of stores are eliminated, but out of those 4% are written back not-silently (but not in a modified state).

[^altwrites]: One reason could be that writing only alternating lines is somewhat more expensive than writing half the data but contiguously. Of course this is obviously true closer to the core, since you touch half the number of the pages in the contiguous case, need half the number of page walks, prefetching is more effective since you cross half as many 4K boundaries (prefetch stops at 4K boundaries) and so on. Even at the memory interface, alternating line writes might be less efficient because you get less benefit from opening each DRAM page, can't do longer than 64-byte bursts, etc. In a pathological case, alternating lines could be _half_ the bandwidth if the controller maps alternating lines to alternating channels, since you'll only be accessing a single channel. We could try to isolate this effect by trying more coarse grained interleaving.

[^l1port]: Most likely, the L1 has a single 64 byte wide write port, like SKX, and the commit logic at the head of the store buffer can look ahead one store to see if it is in the same line in order to dequeue two stores in a single cycle. Without this feature, you could _execute_ two stores per cycle, but only commit one, so the long-run store throughput would be limited to one per cycle.

[^iclbetter]: In this case, the throughput is only halved, versus the 1/4 throughput when we looked at dispatch throttling on SKX, so based on this very preliminary result it seems like the dispatch throttling might be less severe in Ice Lake (this needs a deeper look: we never used stores to test on SKX).

[^gccfix]: After all, there's a good chance it will be fixed in a later version of gcc.

[^lazy]: These are lazy in the sense that I don't do any scalar head or tail handling: the final iteration just does a full width SIMD store even if there aren't 64 bytes left: we overwrite the buffer by up to 63 bytes. We account for this when we allocate the buffer by ensuring the allocation is oversized by at least that amount. This doesn't matter for larger buffers, but it means this version will get a boost for very small buffers versus approaches that do the fill exactly. In any case, we are interested in large buffers here.