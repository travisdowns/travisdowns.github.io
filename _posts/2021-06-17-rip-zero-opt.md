---
layout: post
title: Your CPU May Have Slowed Down on Wednesday
category: blog
tags: [Intel, x86, uarch]
assets: /assets/rip-zero-opt
tables: rip-zero-opt
image: /assets/rip-zero-opt/og-image.jpg
results: https://github.com/travisdowns/zero-fill-bench/tree/master/results/post3
twitter:
  card: summary_large_image
excerpt: The death of hardware store optimization.
---

{% include post-boilerplate.liquid %}

## A Strange Performance Effect

The plot below shows the throughput of filling a region of the given size (varying on the x-axis) with zeros[^stdfill] on Skylake (and Ice Lake in the second tab).

The two series were generated under apparently identical conditions: the same binary on the same machine. Only the date the benchmark was run varies. That is, on Tuesday (June 7th) filling with zeros is substantially faster than the same benchmark on Wednesday, at least when the region no longer fits in the L2 cache[^whitelie].


{% include carousel-svg-fig-2.html file="fig1" suffixes="skl,icl" names="Skylake,Ice Lake"
    raw="skl-combined/l2-focus.csv,icl-combined/l2-focus.csv"
    alt="Figure 13: A chart of region size (x-axis) versus fill throughput (y-axis) with two series, Tuesday and Wednesday, with the Wednesday series showing worse performance in L3 and RAM" %}

### Hump Day Strikes Back

What's going on here? Are my Skylake and Ice Lake hosts simply work-weary by Wednesday and don't put in as much effort? Is there a new crypto-coin based on who can store the most zeros and this is a countermeasure to avoid ballooning CPU prices in the face of this new workload?

Believe it or not, it is none of the above!

These hosts run Ubuntu 20.04 and on Wednesday June 8th an update to the [intel-microcode](https://launchpad.net/ubuntu/+source/intel-microcode) OS package was released. After a reboot[^reboot], this loads the CPU with new _microcode_ that causes the behavior shown above. Specifically, this microcode[^versions] disables the [hardware zero store]({{ site.baseurl }}{% post_url 2020-05-13-intel-zero-opt %}) optimization we discussed in a previous post. It was disabled to mitigate [CVE-2020-24512](http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2020-24512) further described[^barely] in Intel security advisory [INTEL-SA-00464](https://www.intel.com/content/www/us/en/security-center/advisory/intel-sa-00464.html).

To be clear, I don't know _for sure_ that the microcode disables the zero store optimization -- but the evidence is rather overwhelming. After the update, performance is the same when filling zeros as for any other value, and the performance counters tracking L2 evictions suggestion that substantially all evictions are now non-silent (recall from the previous posts that silent evictions were a hallmark of the optimization).

Although I suspect the performance impact will be minuscule on average[^impact], this surprise still serves as a reminder that raw CPU performance can _silently_ change due to microcode updates and most Linux distributions and modern Windows have these updates enabled by default. We've [seen this before]({{ site.baseurl }}{% post_url 2019-03-19-random-writes-and-microcode-oh-my %}). If you are trying to run reproducible benchmarks, you should always re-run your _entire_ suite in order to make accurate comparisons, even on the same hardware, rather than just running the stuff you think has changed.

### Mea Culpa and an Unsustainable Path

In writing the earlier blog entries on this topic, I was interested in the _performance_ aspects of this optimization, not its potential as an attack vector. However, merely by observing (and publishing) the results, the optimization was affected: [the system under measurement changed as a result of the observation](https://en.wikipedia.org/wiki/Measurement_problem). I can't be sure that the optimization wouldn't have eventually been disabled anyway, but it does seem that the proximate cause this change to the microcode was my earlier post.

I am not convinced that removing any optimization which can be used in a timing-based side channel is sustainable. I am not sure this is a thread you want to keep pulling on: practically _every_ aspect of a modern CPU can vary in performance and timing based on internal state[^power]. Trying to draw the security boundaries tightly around co-located entities (e.g., processes on the same CPU, especially on the same core), without allowing any leaks seems destined to fail without a complete overhaul of CPU design, likely at the cost of a large amount of performance. There are just too many holes to plug.

I hope that once the wave of vulnerabilities and disclosures that started with Meltdown and Spectre beings to recede, we can start to work on a measured approach to classifying and mitigating timing and other side-channel attacks. This could start by enumerating which performance characteristics are reasonable guaranteed to hold, and which aren't. For example, it could be specified whether memory access timing may vary based on the _value_ accessed. If it is allowed to vary, the zero store optimization would be allowed.

In any case, I still plan to write about performance-related microarchitectural details. I just hope this outcome does not repeat itself.

### Thanks

Stone photo by <a href="https://unsplash.com/@imagefactory">Colin Watts</a> on Unsplash.

### Discussion and Feedback

You can join the discussion on [Twitter](https://twitter.com/trav_downs/status/1407110595761950720) or [Hacker News](https://news.ycombinator.com/item?id=27588258).

If you have a question or any type of feedback, you can leave a [comment below](#comment-section).

{% include other-posts.md %}

---
<br>

[^barely]: _barely_

[^versions]: The new June 8th microcode versions are `0xea` for Skylake (versus `0xe2` previously) and `0xa6` for Ice Lake (versus `0xa0` previously). 

[^reboot]: To be clear, the microcode is not persistent, so it needs to be loaded on _every_ boot. If you remove or downgrade the `intel-microcode` package, you'll be back to an older microcode after the next boot. That is, unless you also update your BIOS which can _also_ come with a microcode update: this will be persistent unless you downgrade your BIOS.

[^stdfill]:
    Specifically, it uses [`std::fill`](https://en.cppreference.com/w/cpp/algorithm/fill) with a zero argument, with some inlining prevention, which ultimately results in a fill which uses a series of 32-byte vector loads and stores to store 256 bytes per unrolled iteration, with a loop body like this:
    ~~~nasm
    vmovdqu YMMWORD PTR [rax],ymm1
    vmovdqu YMMWORD PTR [rax+0x20],ymm1
    vmovdqu YMMWORD PTR [rax+0x40],ymm1
    vmovdqu YMMWORD PTR [rax+0x60],ymm1
    vmovdqu YMMWORD PTR [rax+0x80],ymm1
    vmovdqu YMMWORD PTR [rax+0xa0],ymm1
    vmovdqu YMMWORD PTR [rax+0xc0],ymm1
    vmovdqu YMMWORD PTR [rax+0xe0],ymm1
    ~~~
    So the compiler does a good job: you can't ask for much better than that.

[^power]: This observation becomes almost universal once you consider that the _values_ involved in any operation affect power use (see e.g. [Schöne et al](https://arxiv.org/pdf/1905.12468.pdf) or [Cornebize and Legrand](https://hal.inria.fr/hal-02401760/document)). Since power use can be directly (e.g., RAPL or external measurements) or indirectly (e.g., because of heat-dependent frequency changes) observed, it means that in theory _any_ operation, even those widely considered to be constant-time, may leak information.

[^whitelie]: I'm doing a bit of a retcon here. The effect is present as described based on the date, and I observed and benchmarked it "on Wednesday", but the specific data series used for the plot were generated a week later when I had time to collect the data properly in a relatively noise free environment. So the two series were collected back-to-back on the same day, varying only the hidden parameter you'll learn about two paragraphs from now.

[^impact]: The performance regression shown in the plots is close to a worst case: the benchmark only fills zeros and nothing else. Real code doesn't spend _that much_ time filling zeros, although zero *is* no doubt the dominant value in large block fills, at least because the OS must zero pages before returning them to user processes and memory-safe languages like Java will zero some objects and array types in bulk.