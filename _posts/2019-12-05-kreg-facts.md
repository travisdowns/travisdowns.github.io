---
layout: post
title: A note on mask registers
category: blog
date: 2019-12-05 11:30:00 -500
tags: [performance, c++, Intel, uarch]
assets: /assets/kreg
assetsmin: /assets/kreg/min
image:  /assets/kreg/specialk.jpg
twitter:
  card: summary_large_image
description: A look into some low level hardware details of the mask registers introduced in AVX-512
---

If you are in a rush, you can [skip to the summary](#summary), but you'll miss out on the journey.
{: .warning}

AVX-512 introduced eight so-called _mask registers_, `k0`[^k0note] through `k7`, which apply to most ALU operations and allow you to apply a zero-masking or merging[^maskmerge] operation on a per-element basis, speeding up code that would otherwise require extra blending operations in AVX2 and earlier.

If that single sentence doesn't immediately indoctrinate you into the mask register religion, here's a copy and paste from [Wikipedia](https://en.wikipedia.org/wiki/AVX-512#Opmask_registers) that should fill in the gaps and close the deal:

> Most AVX-512 instructions may indicate one of 8 opmask registers (k0–k7). For instructions which use a mask register as an opmask, register `k0` is special: a hardcoded constant used to indicate unmasked operations. For other operations, such as those that write to an opmask register or perform arithmetic or logical operations, `k0` is a functioning, valid register. In most instructions, the opmask is used to control which values are written to the destination. A flag controls the opmask behavior, which can either be "zero", which zeros everything not selected by the mask, or "merge", which leaves everything not selected untouched. The merge behavior is identical to the blend instructions.

So mask registers[^kreg] are important, but are not household names unlike say general purpose registers (`eax`, `rsi` and friends) or SIMD registers (`xmm0`, `ymm5`, etc). They certainly aren't going to show up on Intel slides disclosing the size of uarch resources, like these:

![Intel Slide]({{page.assets}}/intel-skx-slide.png)

<br>

In particular, I don't think the size of the mask register physical register file (PRF) has ever been reported. Let's fix that today.

We use an updated version of the ROB size [probing tool](https://github.com/travisdowns/robsize) originally authored and [described by Henry Wong](http://blog.stuffedcow.net/2013/05/measuring-rob-capacity/)[^hcite] (hereafter simply _Henry_), who used it to probe the size of various documented and undocumented out-of-order structures on earlier architecture. If you haven't already read that post, stop now and do it. This post will be here when you get back. 

You've already read Henry's blog for a full description (right?), but for the naughty among you here's the fast food version:

#### Fast Food Method of Operation

We separate two cache miss load instructions[^misstime] by a variable number of _filler instructions_ which vary based on the CPU resource we are probing. When the number of filler instructions is small enough, the two cache misses execute in parallel and their latencies are overlapped so the total execution time is roughly[^roughly] as long as a single miss.

However, once the number of filler instructions reaches a critical threshold, all of the targeted resource are consumed and instruction allocation stalls before the second miss is issued and so the cache misses can no longer run in parallel. This causes the runtime to spike to about twice the baseline cache miss latency.

Finally, we ensure that each filler instruction consumes exactly one of the resource we are interested in, so that the location of the spike indicates the size of the underlying resource. For example, regular GP instructions usually consume one physical register from the GP PRF so are a good choice to measure the size of that resource.

#### Mask Register PRF Size

Here, we use instructions that write a mask register, so can measure the size of the mask register PRF.

To start, we use a series of `kaddd k1, k2, k3` instructions, as such (shown for 16 filler instructions):

~~~nasm
mov    rcx,QWORD PTR [rcx]  ; first cache miss load
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
kaddd  k1,k2,k3
mov    rdx,QWORD PTR [rdx]  ; second cache miss load
lfence                      ; stop issue until the above block completes
; this block is repeated 16 more times
~~~

Each `kaddd` instruction consumes one physical mask register. If number of filler instructions is equal to or less than the number of mask registers, we expect the misses to happen in parallel, otherwise the misses will be resolved serially. So we expect at that point to see a large spike in the running time.

That's exactly what we see:

![Test 27 kaddd instructions]({{page.assetsmin}}/skx-27.svg)

Let's zoom in on the critical region, where the spike occurs:

![Test 27 zoomed]({{page.assetsmin}}/skx-27-zoomed.svg)

Here we clearly see that the transition isn't _sharp_ -- when the filler instruction count is between 130 and 134, we the runtime is intermediate: falling between the low and high levels. Henry calls this _non ideal_ behavior and I have seen it repeatedly across many but not all of these resource size tests. The idea is that the hardware implementation doesn't always allow all of the resources to be used as you approach the limit[^nonideal] - sometimes you get to use every last resource, but in other cases you may hit the limit a few filler instructions before the theoretical limit.

Under this assumption, we want to look at the last (rightmost) point which is still faster than the slow performance level, since it indicates that _sometimes_ that many resources are available, implying that at least that many are physically present. Here, we see that final point occurs at 134 filler instructions.

So we conclude that _SKX has 134 physical registers available to hold speculative mask register values_. As Henry indicates on the original post, it is likely that there are 8 physical registers dedicated to holding the non-speculative architectural state of the 8 mask registers, so our best guess at the total size of the mask register PRF is 142. That's somewhat smaller than the GP PRF (180 entires) or the SIMD PRF (168 entries), but still quite large (see [this table of out of order resource sizes]({{ site.baseurl }}{% post_url 2019-06-11-speed-limits %}#ooo-table) for sizes on other platforms).

In particular, it is definitely large enough that you aren't likely to run into this limit in practical code: it's hard to imagine non-contrived code where almost 60%[^twothirds] of the instructions _write_[^write] to mask registers, because that's what you'd need to hit this limit.


#### Are They Distinct PRFs?

You may have noticed that so far I'm simply _assuming_ that the mask register PRF is distinct from the others. I think this is highly likely, given the way mask registers are used and since they are part of a disjoint renaming domain[^rename]. It is also supported by the fact that that apparent mask register PFR size doesn't match either the GP or SIMD PRF sizes, but we can go further and actually test it!

To do that, we use a similar test to the above, but with the filler instructions alternating between the same `kaddd` instruction as the original test and an instruction that uses either a GP or SIMD register. If the register file is shared, we expect to hit a limit at size of the PRF. If the PRFs are not shared, we expect that neither PRF limit will be hit, and we will instead hit a different limit such as the ROB size.

[Test 29](https://github.com/travisdowns/robsize/blob/fb039f212f1364e2e65b8cb2a0c3f8023c85777f/asm-gold/asm-29.asm) alternates `kaddd` and scalar `add` instructions, like this:

~~~nasm
mov    rcx,QWORD PTR [rcx]
add    ebx,ebx
kaddd  k1,k2,k3
add    esi,esi
kaddd  k1,k2,k3
add    ebx,ebx
kaddd  k1,k2,k3
add    esi,esi
kaddd  k1,k2,k3
add    ebx,ebx
kaddd  k1,k2,k3
add    esi,esi
kaddd  k1,k2,k3
add    ebx,ebx
kaddd  k1,k2,k3
mov    rdx,QWORD PTR [rdx]
lfence 
~~~

Here's the chart:

![Test 29: alternating kaddd and scalar add]({{page.assetsmin}}/skx-29.svg)

We see that the spike is at a filler count larger than the GP and PRF sizes. So we can conclude that the mask and GP PRFs are not shared.

Maybe the mask register is shared with the SIMD PRF? After all, mask registers are more closely associated with SIMD instructions than general purpose ones, so maybe there is some synergy there.

To check, here's [Test 35](https://github.com/travisdowns/robsize/blob/fb039f212f1364e2e65b8cb2a0c3f8023c85777f/asm-gold/asm-35.asm), which is similar to 29 except that it alternates between `kaddd` and `vxorps`, like so:

~~~nasm
mov    rcx,QWORD PTR [rcx]
vxorps ymm0,ymm0,ymm1
kaddd  k1,k2,k3
vxorps ymm2,ymm2,ymm3
kaddd  k1,k2,k3
vxorps ymm4,ymm4,ymm5
kaddd  k1,k2,k3
vxorps ymm6,ymm6,ymm7
kaddd  k1,k2,k3
vxorps ymm0,ymm0,ymm1
kaddd  k1,k2,k3
vxorps ymm2,ymm2,ymm3
kaddd  k1,k2,k3
vxorps ymm4,ymm4,ymm5
kaddd  k1,k2,k3
mov    rdx,QWORD PTR [rdx]
lfence 
~~~

Here's the corresponding chart:

![Test 35: alternating kaddd and SIMD xor]({{page.assetsmin}}/skx-35.svg)

The behavior is basically identical to the prior test, so we conclude that there is no direct sharing between the mask register and SIMD PRFs either.

#### An Unresolved Puzzle

Something we notice in both of the above tests, however, is that the spike seems to finish around 212 filler instructions. However, the ROB size for this microarchtiecture is 224. Is this just _non ideal behavior_ as we saw earlier? Well we can test this by comparing against Test 4, which just uses `nop` instructions as the filler: these shouldn't consume almost any resources beyond ROB entries. Here's Test 4 (`nop` filer) versus Test 29 (alternating `kaddd` and scalar `add`):

![Test 4 vs 29]({{page.assetsmin}}/skx-4-29.svg)

The `nop`-using [Test 4](https://github.com/travisdowns/robsize/blob/fb039f212f1364e2e65b8cb2a0c3f8023c85777f/asm-gold/asm-4.asm) _nails_ the ROB size at exactly 224 (these charts are SVG so feel free to "View Image" and zoom in confirm). So it seems that we hit some other limit around 212 when we mix mask and GP registers, or when we mix mask and SIMD registers. In fact the same limit applies even between GP and SIMD registers, if we compare Test 4 and [Test 21](https://github.com/travisdowns/robsize/blob/fb039f212f1364e2e65b8cb2a0c3f8023c85777f/asm-gold/asm-21.asm) (which mixes GP adds with SIMD `vxorps`):

![Test 4 vs 21]({{page.assetsmin}}/skx-4-21.svg)

Henry mentions a more extreme version of the same thing in the original [blog entry](http://blog.stuffedcow.net/2013/05/measuring-rob-capacity/), in the section also headed **Unresolved Puzzle**:

> Sandy Bridge AVX or SSE interleaved with integer instructions seems to be limited to looking ahead ~147 instructions by something other than the ROB. Having tried other combinations (e.g., varying the ordering and proportion of AVX vs. integer instructions, inserting some NOPs into the mix), it seems as though both SSE/AVX and integer instructions consume registers from some form of shared pool, as the instruction window is always limited to around 147 regardless of how many of each type of instruction are used, as long as neither type exhausts its own PRF supply on its own.

Read the full section for all the details. The effect is similar here but smaller: we at least get 95% of the way to the ROB size, but still stop before it.  It is possible the shared resource is related to register reclamation, e.g., the PRRT[^prrt] - a table which keeps track of which registers can be reclaimed when a given instruction retires.

Finally, we finish this party off with a few miscellaneous notes on mask registers, checking for parity with some features available to GP and SIMD registers.

### Move Elimination

Both GP and SIMD registers are eligible for so-called _move elimination_. This means that a register to register move like `mov eax, edx` or `vmovdqu ymm1, ymm2` can be eliminated at rename by "simply"[^simply] pointing the destination register entry in the RAT to the same physical register as the source, without involving the ALU.

Let's check if something like `kmov k1, k2` also qualifies for move elimination. First, we check the chart for [Test 28](https://github.com/travisdowns/robsize/blob/fb039f212f1364e2e65b8cb2a0c3f8023c85777f/asm-gold/asm-28.asm), where the filler instruction is `kmovd k1, k2`:

![Test 28]({{page.assetsmin}}/skx-28.svg)

It looks exactly like Test 27 we saw earlier with `kaddd`. So we would suspect that physical registers are being consumed, unless we have happened to hit a different move-elimination related limit with exactly the same size and limiting behavior[^moves].

Additional confirmation comes from uops.info which [shows that](https://uops.info/table.html?search=kmov%20(K%2C%20K)&cb_lat=on&cb_tp=on&cb_uops=on&cb_ports=on&cb_SKX=on&cb_measurements=on&cb_avx512=on) all variants of mask to mask register `kmov` take one uop dispatched to p0. If the move is eliminated, we wouldn't see any dispatched uops.

Therefore I conclude that register to register[^regreg] moves involving mask registers are not eliminated.

### Dependency Breaking Idioms

The [best way](https://stackoverflow.com/a/33668295/149138) to set a GP register to zero in x86 is via the xor zeroing idiom: `xor reg, reg`. This works because any value xored with itself is zero. This is smaller (fewer instruction bytes) than the more obvious `mov eax, 0`, and also faster since the processor recognizes it as a _zeroing idiom_ and performs the necessary work at rename[^zero], so no ALU is involved and no uop is dispatched.

Furthermore, the idiom is _dependency breaking:_ although `xor reg1, reg2` in general depends on the value of both `reg1` and `reg2`, in the special case that `reg1` and `reg2` are the same, there is no dependency as the result is zero regardless of the inputs. All modern x86 CPUs recognize this[^otherzero] special case for `xor`. The same applies to SIMD versions of xor such as integer [`vpxor`](https://www.felixcloutier.com/x86/pxor) and floating point [`vxorps`](https://www.felixcloutier.com/x86/xorps) and [`vxorpd`](https://www.felixcloutier.com/x86/xorpd).

That background out of the way, a curious person might wonder if the `kxor` [variants](https://www.felixcloutier.com/x86/kxorw:kxorb:kxorq:kxord) are treated the same way. Is `kxorb k1, k1, k1`[^notall] treated as a zeroing idiom?

This is actually two separate questions, since there are two aspects to zeroing idioms:
 - Zero latency execution with no execution unit (elimination)
 - Dependency breaking

Let's look at each in turn.

#### Execution Elimination

So are zeroing xors like `kxorb k1, k1, k1` executed at rename without latency and without needing an execution unit?

No.

Here, I don't even have to do any work: uops.info has our back because they've performed [this exact test](https://uops.info/html-tp/SKX/KXORD_K_K_K-Measurements.html#sameReg) and report a latency of 1 cycle and one p0 uop used. So we can conclude that zeroing xors of mask registers are not eliminated.

#### Dependency Breaking

Well maybe zeroing kxors are dependency breaking, even though they require an execution unit?

In this case, we can't simply check uops.info. `kxor` is a one cycle latency instruction that runs only on a single execution port (p0), so we hit the interesting (?) case where a chain of `kxor` runs at the same speed regardless of whether the are dependent or independent: the throughput bottleneck of 1/cycle is the same as the latency bottleneck of 1/cycle!

Don't worry, we've got other tricks up our sleeve. We can test this by constructing a tests which involve a `kxor` in a carried dependency chain with enough total latency so that the chain latency is the bottleneck. If the `kxor` carries a dependency, the runtime will be equal to the sum of the latencies in the chain. If the instruction is dependency breaking, the chain is broken and the different disconnected chains can overlap and performance will likely be limited by some throughput restriction (e.g., [port contention]({{ site.baseurl }}{% post_url 2019-06-11-speed-limits %}#portexecution-unit-limits)). This could use a good diagram, but I'm not good at diagrams.

All the tests are in [uarch bench](https://github.com/travisdowns/uarch-bench/blob/ccbebbec39ab02d6460a1837857d052e120c0946/x86_avx512.asm#L20), but I'll show the key parts here.

First we get a baseline measurement for the latency of moving from a mask register to a GP register and back:

~~~nasm
kmovb k0, eax
kmovb eax, k0
; repeated 127 more times
~~~

This pair clocks in[^runit] at 4 cycles. It's hard to know how to partition the latency between the two instructions: are they both 2 cycles or is there a 3-1 split one way or the other[^fyiuops], but for our purposes it doesn't matter because we just care about the latency of the round-trip. Importantly, the post-based throughput limit of this sequence is 1/cycle, 4x faster than the latency limit, because each instruction goes to a different port (p5 and p0, respectively). This means we will be able to tease out latency effects independent of throughput.

Next, we throw a `kxor` into the chain that we know is _not_ zeroing:

~~~nasm
kmovb k0, eax
kxorb k0, k0, k1
kmovb eax, k0
; repeated 127 more times
~~~

Since [we know](https://uops.info/table.html?search=kxorb&cb_lat=on&cb_tp=on&cb_uops=on&cb_ports=on&cb_SKX=on&cb_measurements=on&cb_avx512=on) `kxorb` has 1 cycle of latency, we expect to increase the latency to 5 cycles and that's exactly what we measure (the first two tests shown):

<pre>
** Running group avx512 : AVX512 stuff **
                               Benchmark    Cycles     Nanos
                kreg-GP rountrip latency      4.00      1.25
    kreg-GP roundtrip + nonzeroing kxorb      5.00      1.57
</pre>

Finally, the key test:

~~~nasm
kmovb k0, eax
kxorb k0, k0, k0
kmovb eax, k0
; repeated 127 more times
~~~

This has a zeroing `kxorb k0, k0, k0`. If it breaks the dependency on k0, it would mean that the `kmovb eax, k0` no longer depends on the earlier `kmovb k0, eax`, and the carried chain is broken and we'd see a lower cycle time.

Drumroll...

We measure this at the exact same 5.0 cycles as the prior example:

<pre>
** Running group avx512 : AVX512 stuff **
                               Benchmark    Cycles     Nanos
                kreg-GP rountrip latency      4.00      1.25
    kreg-GP roundtrip + nonzeroing kxorb      5.00      1.57
<span style="background: green;">       kreg-GP roundtrip + zeroing kxorb      5.00      1.57</span>
</pre>

So we tentatively conclude that zeroing idioms aren't recognized at all when they involve mask registers.

Finally, as a check on our logic, we use the following test which replaces the `kxor` with a `kmov` which we know is _always_ dependency breaking:

~~~nasm
kmovb k0, eax
kmovb k0, ecx
kmovb eax, k0
; repeated 127 more times
~~~

This is the final result shown in the output above, and it runs much more quickly at 2 cycles, bottlenecked on p5 (the two `kmov k, r32` instructions both go only to p5):

<pre>
** Running group avx512 : AVX512 stuff **
                               Benchmark    Cycles     Nanos
                kreg-GP rountrip latency      4.00      1.25
    kreg-GP roundtrip + nonzeroing kxorb      5.00      1.57
       kreg-GP roundtrip + zeroing kxorb      5.00      1.57
<span style="background: green;">         kreg-GP roundtrip + mov from GP      2.00      0.63</span>
</pre>

So our experiment seems to check out. 

### Summary

 - SKX has a separate PRF for mask registers with a speculative size of 134 and an estimated total size of 142
 - This is large enough compared to the other PRF size and the ROB to make it unlikely to be a bottleneck
 - Mask registers are not eligible for move elimination
 - Zeroing idioms[^tech] in mask registers are not recognized for execution elimination or dependency breaking

### Comments

Discussion on [Hacker News](https://news.ycombinator.com/item?id=21714390), Reddit ([r/asm](https://www.reddit.com/r/asm/comments/e6kokb/x86_avx512_a_note_on_mask_registers/) and [r/programming](https://www.reddit.com/r/programming/comments/e6ko7i/a_note_on_mask_registers_avx512/)) or [Twitter](https://twitter.com/trav_downs/status/1202637229606264833).

Direct feedback also welcomed by [email](mailto:travis.downs@gmail.com) or as [a GitHub issue](https://github.com/travisdowns/travisdowns.github.io/issues).
 
### Thanks

[Daniel Lemire](https://lemire.me) who provided access to the AVX-512 system I used for testing.

[Henry Wong](http://www.stuffedcow.net/) who wrote the [original article](http://blog.stuffedcow.net/2013/05/measuring-rob-capacity/) which introduced me to this technique and graciously shared the code for his tool, which I now [host on github](https://github.com/travisdowns/robsize).

[Jeff Baker](https://twitter.com/Jeffinatorator/status/1202642436406669314), [Wojciech Muła](http://0x80.pl) for reporting typos.

Image credit: [Kellogg's Special K](https://www.flickr.com/photos/like_the_grand_canyon/31064064387) by [Like_the_Grand_Canyon](https://www.flickr.com/photos/like_the_grand_canyon/) is licensed under [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/).

---
---
<br>

[^hcite]: H. Wong, _Measuring Reorder Buffer Capacity_, May, 2013. \[Online\]. Available: http://blog.stuffedcow.net/2013/05/measuring-rob-capacity/

[^k0note]: There is sometimes a misconception (until recently even on the AVX-512 wikipedia article) that `k0` is not a normal mask register, but just a hardcoded indicator that no masking should be used. That's not true: `k0` is a valid mask register and you can read and write to it with the `k`-prefixed instructions and SIMD instructions that write mask registers (e.g., any AVX-512 [comparison](https://www.felixcloutier.com/x86/pcmpeqb:pcmpeqw:pcmpeqd). However, the encoding that would normally be used for `k0` as a writemask register in a SIMD operation indicates instead "no masking", so the contents of `k0` cannot be used for that purpose.

[^maskmerge]: The distinction being that a zero-masking operation results in zeroed destination elements at positions not selected by the mask, while merging leaves the existing elements in the destination register unchanged at those positions. As as side-effect this means that with merging, the destination register becomes a type of destructive source-destination register and there is an input dependency on this register.

[^kreg]: I'll try to use the full term _mask register_ here, but I may also use _kreg_ a common nickname based on the labels `k0`, `k1`, etc. So just mentally swap _kreg_ for _mask register_ if and when you see it (or vice-versa).

[^misstime]: Generally taking 100 to 300 cycles each (latency-wise). The wide range is because the cache miss wall clock time varies by a factor of about 2x, generally between 50 and 100 naneseconds, depending on platform and uarch details, and the CPU frequency varies by a factor of about 2.5x (say from 2 GHz to 5 GHz). However, on a given host, with equivalent TLB miss/hit behavior, we expect the time to be roughly constant.

[^nonideal]: For example, a given rename slot may only be able to write a subset of all the RAT entries, and uses the first available. When the RAT is almost full, it is possible that none of the allowed entries are empty, so it is as if the structure is full even though some free entries remain, but accessible only to other uops. Since the allowed entries may be essentially random across iterations, this ends up with a more-or-less linear ramp between the low and high performance levels in the non-ideal region.

[^twothirds]: The "60 percent" comes from 134 / 224, i.e., the speculative mask register PRF size, divided by the ROB size. The idea is that if you'll hit the ROB size limit no matter what once you have 224 instructions in flight, so you'd need to have 60% of those instructions be mask register writes[^write] in order to hit the 134 limit first. Of course, you might also hit some _other_ limit first, so even 60% might not be enough, but the ROB size puts a lower bound on this figure since it _always_ applies.

[^simply]: Of course, it is not actually so simple. For one, you now need to track these "move elimination sets" (sets of registers all pointing to the same physical register) in order to know when the physical register can be released (once the set is empty), and these sets are themselves a limited resource which must be tracked. Flags introduce another complication since flags are apparently stored along with the destination register, so the presence and liveness of the flags must be tracked as well.

[^moves]: In particular, in the corresponding test for GP registers (Test 7), the chart looks very different as move elimination reduce the PRF demand down to almost zero and we get to the ROB limit.

[^regreg]: Note that I am not restricting my statement to moves between two mask registers only, but any registers. That is, moves between a GP registers and a mask registers are also not eliminated (the latter fact is obvious if consider than they use distinct register files, so move elimination seems impossible).

[^zero]: Probably by pointing the entry in the RAT to a fixed, shared zero register, or setting a flag in the RAT that indicates it is zero.

[^otherzero]: Although `xor` is the most reliable, other idioms may be recognized as zeroing or dependency breaking idioms by some CPUs as well, e.g., `sub reg,reg` and even `sbb reg, reg` which is not a zeroing idiom, but rather sets the value of `reg` to zero or -1 (all bits set) depending on the value of the carry flag. This doesn't depend on the value of `reg` but only the carry flag, and some CPUs recognize that and break the dependency. Agner's [microarchitecture guide](https://www.agner.org/optimize/#manual_microarch) covers the uarch-dependent support for these idioms very well.

[^prrt]: This is either the _Physical Register Reclaim Table_ or _Post Retirement Reclaim Table_ depending on who you ask.

[^write]: Importantly, only instructions which write a mask register consume a physical register. Instructions that simply read a mask register (e.g,. SIMD instructions using a writemask) do not consume a new physical mask register.

[^rename]: More renaming domains makes things easier on the renamer for a given number of input registers. That is, it is easier to rename 2 GP and 2 SIMD input registers (separate domains) than 4 GP registers.

[^notall]: Note that only the two source registers really need to be the same: if `kxorb k1, k1, k1` is treated as zeroing, I would expect the same for `kxorb k1, k2, k2`.

[^runit]: Run all the tests in this section using `./uarch-bench.sh --test-name=avx512/*`.

[^fyiuops]: This is why uops.info reports the latency for both `kmov r32, k` and `kmov k, 32` as `<= 3`. They know the pair takes 4 cycles in total and under the assumption that each instruction must take _at least_ one cycle the only thing you can really say is that each instruction takes at most 3 cycles.

[^tech]: Technically, I only tested the xor zeroing idiom, but since that's the groud-zero, most basic idiom we can pretty sure nothing else will be recognized as zeroing. I'm open to being proven wrong: the code is public and easy to modify to test whatever idiom you want.

[^roughly]: The reason I have to add _roughly_ as a weasel word here is itself interesting. A glance at the charts shows that they are certainly not totally flat in either the fast or slow regions surrounding the spike. Rather there are various noticeable regions with distinct behavior and other artifacts: e.g., in Test 29 a very flat region up to about 104 filler instructions, followed by a bump and then a linearly ramping region up to the spike somewhat after 200 instructions. Some of those features are explicable by mentally (or [actually](https://godbolt.org/z/eAGxhH)) simulating the pipeline, which reveals that at some point the filler instructions will contribute (although only a cycle or so) to the runtime, but some features are still unexplained (for now).

{% include glossary.md %}
