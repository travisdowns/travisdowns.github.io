---
layout: post
title: A Concurrency Cost Hierarchy
category: blog
tags: [performance, c++, concurrency]
assets: /assets/concurrency-costs
image:  /assets/concurrency-costs/avatar.jpg
results: https://github.com/travisdowns/concurrency-hierarchy-bench/tree/master/results
twitter:
  card: summary_large_image
excerpt: Concurrent operations can be grouped relatively neatly into categories based on their cost
content_classes: invert-rotate-img
---

{% include post-boilerplate.liquid %}

{% assign uarches="skl,icl,g1-16,g2-16" %}
{% assign unames="Skylake,Ice Lake,Graviton,Graviton 2" %}
{% assign uresults = uarches | split: "," | join: "/combined.csv," | append: "/combined.csv" %}

## Introduction

Concurrency is hard to get _correct_, at least for those of us unlucky enough to be writing in languages which expose directly the guts of concurrent hardware: threads and shared memory. Getting concurrency correct _and_ fast is hard, too. Your knowledge about single-threaded optimization often won't help you: at a micro (instruction) level we can't simply apply the usual rules of μops, dependency chains, throughput limits, and so on. The rules are different.

If that first paragraph got your hopes up, this second one is here to dash them: I'm not actually going to do a deep dive into the very low level aspects of concurrent performance. There are a lot of things we just don't know about how atomic instructions and fences execute, and we'll save that for another day.

Instead, I'm going to describe a higher level taxonomy that I use to think about concurrent performance. We'll group the performance of concurrent operations into six broad _levels_ running from fast to slow, with each level differing from its neighbors by roughly an order of magnitude in performance.

I often find myself thinking in terms of these categories when I need high performance concurrency: what is the best level I can practically achieve for the given problem? Keeping the levels in mind is useful both during initial design (sometimes a small change in requirements or high level design can allow you to achieve a better level), and also while evaluating existing systems (to better understand existing performance and evaluate the path of least resistance to improvements).

### A "Real World" Example

I don't want this to be totally abstract, so we will use a real-world-if-you-squint[^realworld] running example throughout: safely incrementing an integer counter across threads. By _safely_ I mean without losing increments, producing out-of-thin air values, frying your RAM or making more than a minor rip in space-time.

### Source and Results

The source for every benchmark here is [available](https://github.com/travisdowns/concurrency-hierarchy-bench), so you can follow along and even reproduce the results or run the benchmarks on your own hardware. All of the results discussed here (and more) are available in the same repository, and each plot includes a `[data table]` link to the specific subset used to generate the plot.

### Hardware

All of the performance results are provided for several different hardware platforms: Intel Skylake, Ice Lake, Amazon Graviton and Graviton 2. However except when I explicitly mention other hardware, the prose refers to the results on Skylake. Although the specific numbers vary, most of the qualitative relationships hold for the hardware too, but _not always_. Not only does the hardware vary, but the OS and library implementations will vary as well.

It's almost inevitable that this will be used to compare across hardware ("wow, Graviton 2 sure kicks Graviton 1's ass"), but that's not my goal here. The benchmarks are written primarily to tease apart the characteristics of the different levels, and _not_ as a hardware shootout.

Find below the details of the hardware used:

| Micro-architecture | ISA | Model | Tested Frequency | Cores | OS | Instance Type |
| -- | --| -- | -- | -- |
| Skylake | x86 | i7-6700HQ | 2.6 GHz | 4 | Ubuntu 20.04 | |
| Ice Lake | x86 | i5-1035G4 | 3.3 GHz | 4 | Ubuntu 19.10 | |
| Graviton | AArch64 | Cortex-A72 | 2.3 GHz | 16 | Ubuntu 20.04 | a1.4xlarge |
| Graviton 2 | AArch64 | Neoverse N1 | 2.5 GHz | 16[^g2cores] | Ubuntu 20.04 | c6g.4xlarge |


[^g2cores]: The Graviton 2 bare metal hardware has 64 cores, but this instance size makes 16 of them available. This means that in principle the results can be affected by the coherency traffic of other tenants on the same hardware, but the relatively stable results seem to indicate it doesn't affect the results much.

## Level 2: Contended Atomics

You'd probably expect this hierarchy to be introduced from fast to slow, or vice-versa, but we're all about defying expectations here and we are going to start in the _middle_ and work our way outwards. The middle (rounding down) turns out to be _level 2_ and that's where we will jump in.

The most elementary way to safely modify any shared object is to use a lock. It mostly _just works_ for any type of object, no matter its structure or the nature of the modifications. Almost any mainstream CPU from the last thirty years has some type of locking[^parisc] instruction accessible to userspace.

So our baseline increment implementation will use a simple mutex of type `T` to protect a plain integer variable:

~~~c++
T lock;
uint64_t counter;

void bench(size_t iters) {
    while (iters--) {
        std::lock_guard<T> holder(lock);
        counter++;
    }
}
~~~

*[mutex add]: Uses a std::mutex and std::lock_guard to protect a plain integer counter.

We'll call this implementation _mutex add_, and on my 4 CPU Skylake-S i7-6700HQ machine, when I use the vanilla `std::mutex` I get the following results for 2 to 4 threads:

{% include carousel-svg-fig-2.html file="mutex" suffixes=uarches names=unames raw=uresults alt="Mutex" %}

The reported value is the median of all trials, and the vertical black error lines at the top of each bar indicate the _interdecile range_, i.e., the values at the 10th and 90th percentile. Where the error bars don't show up, it means there is no difference between the p10 and p90 values at all, at least within the limits of the reporting resolution (100 picoseconds).
{: .info}

This shows that the baseline contended cost to modify an integer protected by a lock starts at about 125 nanoseconds for two threads, and grows somewhat with increasing thread count.

I can already hear someone saying: _If you are just modifying a single 64-bit integer, skip the lock and just directly use the atomic operations that most ISAs support!_

Sure, let's add a couple of variants that do that. The `std::atomic<T>` template makes this easy: we can wrap any type meeting some basic requirements and then manipulate it atomically. The easiest of all is to use `std::atomic<uint64>::operator++()`[^post] and this gives us _atomic add_:

*[atomic add]: Uses an atomic increment on a single shared counter.

~~~c++
std::atomic<uint64_t> atomic_counter{};

void atomic_add(size_t iters) {
    while (iters--) {
        atomic_counter++;
    }
}
~~~

The other common approach would be to use [compare and swap (CAS)](https://en.wikipedia.org/wiki/Compare-and-swap) to load the existing value, add one and then CAS it back if it hasn't changed. If it _has_ changed, the increment raced with another thread and we try again.

Note that even if you use increment at the source level, the assembly might actually end up using CAS if your hardware doesn't support atomic increment[^atomicsup], or if your compiler or runtime just don't take advantage of atomic operations even though they are available (e.g., see what even the newest version of [icc does](https://godbolt.org/z/5h4K7y) for atomic increment, and what Java did for years[^java]). This caveat doesn't apply to any of our tested platforms, however.

Let's add a counter implementation that uses CAS as described above, and we'll call it _cas add_:

*[cas add]: Uses a CAS loop to increment a single shared counter.

~~~c++
std::atomic<uint64_t> cas_counter;

void cas_add(size_t iters) {
    while (iters--) {
        uint64_t v = cas_counter.load();
        while (!cas_counter.compare_exchange_weak(v, v + 1))
            ;
    }
}
~~~

Here's what these look like alongside our existing `std::mutex` benchmark:

{% include carousel-svg-fig-2.html file="atomic-inc" suffixes=uarches names=unames raw=uresults alt="Atomic increment" %}

The first takeaway is that, at least in this _unrealistic maximum contention_ benchmark, using atomic add ([`lock xadd`](https://www.felixcloutier.com/x86/xadd) at the hardware level) is significantly better than CAS. The second would be that `std::mutex` doesn't come out looking all that bad on Skylake. It is only slightly worse than the CAS approach at 2 cores and beats it at 3 and 4 cores. It is slower than the atomic increment approach, but less than three times as slow and seems to be scaling in a reasonable way.

All of these operations are belong to _level 2_ in the hierarchy. The primary characteristic of level 2 is that they make a _contended access_ to a shared variable. This means that at a minimum, the line containing the data needs to move out to the caching agent that manages coherency[^l3], and then back up to the core that will receive ownership next. That's about 70 cycles minimum just for that operation[^inter].

Can it get slower? You bet it can. _Way_ slower.

### Level 3: System Calls

The next level up ("up" is not good here...) is level 3. The key characteristic of implementations at this level is that they make a _system call on almost every operation_.

It is easy to write concurrency primitives that make a system call _unconditionally_ (e.g., a lock which always tries to wake waiters via a `futex(2)` call, even if there aren't any), but we won't look at those here. Rather we'll take a look at a case where the fast path is written to avoid a system call, but the design or way it is used implies that such a call usually happens anyway.

Specifically, we are going to look at some _fair locks_. Fair locks allow threads into the critical section in the same order they began waiting. That is, when the critical section becomes available, the thread that has been waiting the longest is given the chance to take it.

Sounds like a good idea, right? Sometimes yes, but as we will see it can have significant performance implications.

On the menu are three different fair locks.

The first is a [ticket lock](https://en.wikipedia.org/wiki/Ticket_lock) with a `sched_yield` in the spin loop. The idea of the yield is to give other threads which may hold the lock time to run. This `yield()` approach is publicly frowned upon by concurrency experts[^notwhat], who then sometimes go right ahead and use it anyway.

We will call it ticket yield and it looks like this:

*[ticket yield]: A ticket lock that calls sched_yield in a spin loop while waiting for its turn.

<a id="ys-lock"></a>

~~~c++
/**
 * A ticket lock which uses sched_yield() while waiting
 * for the ticket to be served.
 */
class ticket_yield {
    std::atomic<size_t> dispenser{}, serving{};

public:
    void lock() {
        auto ticket = dispenser.fetch_add(1, std::memory_order_relaxed);

        while (ticket != serving.load(std::memory_order_acquire))
            sched_yield();
    }

    void unlock() {
        serving.store(serving.load() + 1, std::memory_order_release);
    }
};
~~~

Let's plot the performance results for this lock alongside the existing approaches:

{% include carousel-svg-fig-2.html file="fair-yield" alt="Increment Cost: Fair Yield"
suffixes=uarches names=unames raw=uresults %}

This is level 3 visualized: it is an order of magnitude slower than the level 2 approaches. The slowdown comes from the `sched_yield` call: this is a system call and these are generally on the order of 100s of nanoseconds[^spectre], and it shows in the results.

This lock _does_ have a fast path where `sched_yield` isn't called: if the lock is available, no spinning occurs and `sched_yield` is never called. However, the combination of being a _fair_ lock and the high contention in this test means that a lock convoy quickly forms (we'll describe this in more detail later) and so the spin loop is entered basically every time `lock()` is called.

So have we _now_ fully plumbed the depths of slow concurrency constructs? Not even close. We are only now just about to cross the River Styx.

#### Revisiting std::mutex

Before we proceed, let's quickly revisit the `std::mutex` implementation discussed in level 2 in light of our definition of level 3 as requiring a system call. Doesn't `std::mutex` _also_ make system calls? If a thread tries to lock a `std::mutex` object which is already locked, we expect that thread to block using OS-provided primitives. So why isn't it level 3 and slow like ticket yield?

The primary reason is that it makes _few_ system calls in practice. Through a combination of spinning and unfairness I measure only about 0.18 system calls per increment, with three threads on my Skylake box. So _most_ increments happen without a system call. On the other hand, ticket yield makes about 2.4 system calls per increment, more than an order of magnitude more, and so it suffers a corresponding decrease in performance.

That out of way, let's get even slower.

### Level 4: Implied Context Switch

The next level is when the implementation forces a significant number of concurrent operations to cause a _context switch_.

The yielding lock wasn't resulting in many context switches, since we are not running more threads than there are cores, and so there usually is no other runnable process (except for the occasional background process). Therefore, the current thread stays on the CPU when we call `sched_yield`. Of course, this burns a lot of CPU.

As the experts recommend whenever one suggests _yielding_ in a spin loop, let us try a _blocking lock_ instead.

**Blocking Locks**\\
\\
A more resource friendly design, and one that will often perform better is a _blocking_ lock.<br/><br/>Rather than busy waiting, these locks ask the OS to put the current thread to sleep until the lock becomes available. On Linux, the [`futex(3)`](http://man7.org/linux/man-pages/man2/futex.2.html) system call is the preferred way to accomplish this, while on Windows you have the [`WaitFor*Object`](https://docs.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject) API family. Above the OS interfaces, things like C++'s `std::condition_variable` provide a general purpose mechanism to wait until an arbitrary condition is true.
{: .info}

Our first blocking lock is again a ticket-based design, except this time it uses a condition variable to block when it detects that it isn't first in line to be served (i.e., that the lock was held by another thread). We'll name it ticket blocking and it looks like this:

*[ticket blocking]: A ticket lock which blocks if it cannot immediately acquire the lock.

~~~c++
void blocking_ticket::lock() {
    auto ticket = dispenser.fetch_add(1, std::memory_order_relaxed);

    if (ticket == serving.load(std::memory_order_acquire))
        return; // uncontended case

    std::unique_lock<std::mutex> lock(mutex);
    while (ticket != serving.load(std::memory_order_acquire)) {
        cvar.wait(lock);
    }
}

void blocking_ticket::unlock() {
    std::unique_lock<std::mutex> lock(mutex);
    auto s = serving.load(std::memory_order_relaxed) + 1;
    serving.store(s, std::memory_order_release);
    auto d = dispenser.load(std::memory_order_relaxed);
    assert(s <= d);
    if (s < d) {
        // wake all waiters
        cvar.notify_all();
    }
}
~~~

The main difference with the earlier implementation occurs in the case where we don't acquire the lock immediately (we don't return at the location marked `// uncontended case`). Instead of yielding in a loop, we take the mutex associated with the condition variable and wait until notified. Every time we are notified we check if it is our turn.

Even without spurious wakeups we might get woken many times, because this lock suffers from the _thundering herd_ problem where every waiter is woken on `unlock()` even though only one will ultimately be able to get the lock.

*[spurious wakeups]: When a waiter on a condition variable is woken up even though no other thread notified it.

We'll try a second design too, that doesn't suffer from thundering herd. This is a queued lock, where each lock waits on its own private node in a queue of waiters, so only a single waiter (the new lock owner) is woken up on unlock. We will call it queued fifo and if you're interested in the implementation you can find it [here](https://github.com/travisdowns/concurrency-hierarchy-bench/blob/9b8e0e0dfec7d38036d114038c6a9ed020b5b775/fairlocks.cpp#L61).

*[queued fifo]: A blocking ticket lock where each waiter waits on a unique condition variable.

Here's how our new locks perform against the existing crowd:

{% include carousel-svg-fig-2.html file="more-fair" alt="Increment Cost: Fair Blocking"
suffixes=uarches names=unames raw=uresults %}

You're probably seeing the pattern now: performance is again a new level of terrible compared to the previous contenders. About an order of magnitude slower than the yielding approach, which was already slower than the earlier approaches, which are now just slivers a few pixels high on the plots. The queued version of the lock does slightly better at increasing thread counts (_especially_ on Graviton 2), as might be expected from the lack of the thundering herd effect, but is still very slow because the primary problem isn't thundering herd, but rather a [_lock convoy_](https://en.wikipedia.org/wiki/Lock_convoy).


**Lock Convoy**\\
\\
Unlike unfair locks, fair locks can result in sustained convoys involving only a single lock, once the contention reaches a certain point[^hyst].\\
\\
Consider what happens when two threads, `A` and `B`, try to acquire the lock repeatedly. Let's say `A` gets ticket 1 and `B` ticket 2. So `A` gets to go first and `B` has to wait, and for these implementations that means blocking (we can say the thread is _parked_ by the OS). Now, `A` unlocks the lock and sees `B` waiting and wakes it. `A` is still running and soon tries to get the lock again, receiving ticket 3, but it cannot acquire the lock immediately because the lock is _fair_: `A` can't jump the queue and acquire the lock with ticket 3 before `B`, holding ticket 2, gets its chance to enter the lock.\\
\\
Of course, `B` is going to be a while: it needs to be woken by the scheduler and this takes a microsecond or two, at least. Now `B` wakes and gets the lock, and the same scenario repeats itself with the roles reversed. The upshot is that there is a full context switch for each acquisition of the lock.\\
\\
Unfair locks avoid this problem because they allow queue jumping: in the scenario above, `A` (or any other thread) could re-acquire the lock after unlocking it, before `B` got its chance. So the use of the shared resource doesn't grind to a halt while `B` wakes up.
{: .info}

So, are you tired of seeing mostly-white plots where the newly introduced algorithm relegates the rest of the pack to little chunks of color near the x-axis, yet?

I've just got one more left on the slow end of the scale. Unlike the other examples, I haven't actually diagnosed something _this_ bad in real life, but examples are out there.

### Level 5: Catastrophe

Here's a ticket lock which is identical to the [first ticket lock we saw](#ys-lock), except that the `sched_yield();` is replaced by `;`. That is, it busy waits instead of yielding (look [here](https://github.com/travisdowns/concurrency-hierarchy-bench/blob/9b8e0e0dfec7d38036d114038c6a9ed020b5b775/fairlocks.cpp#L31) for the spin flavors which specialize on a shared ticket lock template). You could also replace this by a CPU-specific "relax" instruction like [`pause`](https://www.felixcloutier.com/x86/pause), but it won't change the outcome (see [here](https://github.com/travisdowns/concurrency-hierarchy-bench/blob/9b8e0e0dfec7d38036d114038c6a9ed020b5b775/fairlocks.hpp#L26)). We call it ticket spin, and here's how it performs compared to the existing candidates:

*[ticket spin]: A traditional spin-based ticket lock that does a hot spin while waiting for its ticket to be next.

{% include carousel-svg-fig-2.html file="ts-4" alt="Increment Cost: Ticket Spin"
suffixes=uarches names=unames raw=uresults %}

What? That doesn't look too bad at all. In fact, it is only slightly worse than the level 2 crew, the fastest we've seen so far[^huh].

The picture changes if we show the results for up to 6 threads, rather than just 4. Since I have 4 available cores[^noht], this means that not all the test threads will be able to run at once:

{% include carousel-svg-fig-2.html file="ts-6" alt="Increment Cost: Ticket Spin (Oversubscribed)"
suffixes=uarches names=unames raw=uresults %}


Now it becomes clear why this level is called _catastrophic_. As soon as we oversubscribe the number of available cores, performance gets about _five hundred times worse_. We go from 100s of nanoseconds to 100s of microseconds. I don't show more threads, but it only gets worse as you add more.

We are also about an order of magnitude slower than the best solution (queued fifo) of the previous level, although it varies a lot by hardware: on Ice Lake the difference is more like _forty_ times, while on Graviton this solution is actually slightly faster than ticket blocking (also level 4) at 17 threads. Note also the huge error bars. This is the least consistent benchmark of the bunch and exhibits a lot of variance and the slowest and fastest runs might vary by a factor of 100.

#### Lock Convoy on Steroids

So what happens here?

It's similar to the lock convoy described above: all the threads queue on the lock and acquire it in a round-robin order due to the fair design. The difference is that threads don't block when they can't acquire the lock. This works out great when the cores are not oversubscribed, but falls off a cliff otherwise.

Imagine 5 threads, `T1`, `T2`, ..., `T5`, where `T5` is the one not currently running. As soon as `T5` is the thread that needs the acquire the lock next (i.e., `T5`'s saved ticket value is equal to `dispensing`), nothing will happen because `T1` through `T4` are busily spinning away waiting for their turn. The OS scheduler sees no reason to interrupt them until their time slice expires. Time slices are usually measured in milliseconds. Once one thread is preempted, say `T1`, `T5` will get the chance to run, but at most 4 total acquisitions can happen (`T5`, plus any of `T2`, `T3`, `T4`), before it's `T1`'s turn. `T1` is waiting for their chance to run again, but since everyone is spinning this won't occur until another time slice expires.

So the lock can only be acquired a few times (at most `$(nproc)` times), or as little as once[^once], every time slice. Modern Linux using [CFS](https://en.wikipedia.org/wiki/Completely_Fair_Scheduler) doesn't have a fixed timeslice, but on my system, `sched_latency_ns` is 18,000,000 which means that we expect two threads competing for one core to get a typical timeslice of 9 ms. The measured numbers are roughly consistent with a timeslice of single-digit milliseconds.

If I was good at diagrams, there would be a diagram here.

Another way of thinking about this is that in this over-subscription scenario, the ticket spin lock implies roughly the same number of context switches as the blocking ticket lock[^perf], but in the former case each context switch comes with a giant delay caused by the need to exhaust the timeslice, while in the blocking case we are only limited by how fast a context switch can occur.

Interestingly, although this benchmark uses 100% CPU on every core, the performance of the benchmark in the oversubscribed case almost doesn't depend on your CPU speed! Performance is approximately the same if I throttle my CPU to 1 GHz, or enable turbo up to 3.5 GHz. All of other implementations scale almost proportionally with CPU frequency. The benchmark does scale strongly with adjustment to `sched_latency_ns` (and `sched_min_granularity_ns` if the former is set low enough): lower scheduling latency values gives proportionally better performance as the time slices shrink, helping to confirm our theory of how this works.

This behavior also explains the large amount of variance once the available cores are oversubscribed: by definition, not all threads will be running at once, so the test becomes very sensitive to exactly where the not-running threads took their context switch. At the beginning of the test, only 4 of 6 threads will be running, and the two will be switched out, still waiting on the the [barrier](https://github.com/travisdowns/concurrency-hierarchy-bench/blob/master/cyclic-barrier.hpp) that synchronizes the test start. Since the two switched out threads haven't tried to get the lock yet, the four running threads will be able to quickly share the lock between themselves, since the six-thread convoy hasn't been set up.

This runs up the "iteration count" (work done) during an initial period which varies randomly, until the first context switch lets the fifth thread join the competition and then the convoy gets set up[^csdepend]. That's when the catastrophe starts. This makes the results very noisy: for example, if you set a too-short time period for a trial, the _entire test_ is composed of this initial phase and the results are artificially "good".

We can probably invent something even worse, but that's enough for now. Let's move on to scenarios that are _faster_ than the use of vanilla atomic add.

### Level 1: Uncontended Atomics

Recall that we started at level 2: contended atomics. The name gives it away: the next faster level is when atomic operations are used but there is no contention, either by design or by luck. You might have noticed that so far we've only shown results for at least two threads. That's because the single threaded case involves no contention, and so every implementation so far is level 1 if run on a single thread[^notexx].

Here are the results for all the implementations we've looked at so far, for a single thread:

{% include carousel-svg-fig-2.html file="single" alt="Increment Cost: Single Threaded"
suffixes=uarches names=unames raw=uresults %}

The fastest implementations run in about 10 nanoseconds, which is 5x faster than the fastest solution for 2 or more threads. The _slowest_ implementation (queued fifo) for one thread ties the _fastest_ implementation (atomic add) at two threads, and beats it handily at three or four.

The number overlaid on each bar is the number of atomic operations[^atomhow] each implementation makes per increment. It is obvious that the performance is almost directly proportional to the number of atomic instructions. On the other hand, performance does _not_ have much of a relationship with the total number of instructions of any type, which vary a lot even between algorithms with the same performance as the following table shows:

| Algorithm        | Atomics | Instructions   | Performance |
| ---------------- | -------:| -------------: | -----------:|
| mutex add        |     2   |  64            |      ~21 ns |
| atomic add       |     1   |   4            |      ~7 ns |
| cas add          |     1   |   7            |      ~12 ns |
| ticket yield     |     1   |  13            |      ~10 ns |
| ticket blocking  |     3   | 107            |      ~32 ns |
| queued fifo      |     4   | 167            |      ~45 ns |
| ticket spin      |     1   |  13            |      ~10 ns |
| mutex3           |     2   |  17            |      ~20 ns |

*[mutex3]: A simple mutex from "Futexes Are Tricky".

In particular, note that mutex add has more than 9x the number of instructions compared to cas add yet still runs at half the speed, in line with the 2:1 ratio of atomics. Similarly, ticket yield and ticket spin have slightly _better_ performance than cas add despite having about twice the number of instructions, in line with them all having a single atomic operation[^casworse].

The last row in the table shows the performance of mutex3, an implementation we haven't discussed. It is a basic mutex offering similar functionality to `std::mutex` and whose implementation is described in [Futexes Are Tricky](https://akkadia.org/drepper/futex.pdf). Because it doesn't need to pass through two layers of abstraction[^twolayer], it has only about one third the instruction count of `std::mutex`, yet performance is almost exactly the same, differing by less than 10%.

So the idea that you can almost ignore things that are in a lower cost tier seems to hold here. Don't take this too far: if you design a lock with a single atomic operation but 1,000 other instructions, it is not going to be fast. There are also reasons to keep your instruction count low other than microbenchmark performance: smaller instruction cache footprint, less space occupied in various out-of-order execution buffers, more favorable inlining tradeoffs, etc.

Here it is important to note that the change in level of our various functions didn't require a change in implementation. These are exactly the same few implementations we discussed in the slower levels. Instead, we simply changed (by fiat, i.e., adjusting the benchmark parameters) the contention level from "very high" to "zero". So in this case the  level doesn't depend only on the code, but also this external factor. Of course, just saying that we are going to get to level 1 by only running one thread is not very useful in real life: we often can't simply ban multi-threaded operation.

So can we get to level 1 even under concurrent calls from multiple threads? For this particular problem, we can.

#### Adaptive Multi-Counter

One option is to use multiple counters to represent the counter value. We try to organize it so that that threads running concurrently on different CPUs will increment different counters. Thus the _logical_ counter value is split across all of these internal _physical_ counters, and so a read of the logical counter value now needs to add together all the physical counter values.

Here's an implementation:

*[cas multi]: Uses a CAS on an adatively per-CPU counter.
*[tls]: Uses a vanilla increment on a write-private thread-local counter.

~~~c++
class cas_multi_counter {
    static constexpr size_t NUM_COUNTERS = 64;

    static thread_local size_t idx;
    multi_holder array[NUM_COUNTERS];

public:

    /** increment the logical counter value */
    uint64_t operator++(int) {
        while (true) {
            auto& counter = array[idx].counter;

            auto cur = counter.load();
            if (counter.compare_exchange_strong(cur, cur + 1)) {
                return cur;
            }

            // CAS failure indicates contention,
            // so try again at a different index
            idx = (idx + 1) % NUM_COUNTERS;
        }
    }

    uint64_t read() {
        uint64_t sum = 0;
        for (auto& h : array) {
            sum += h.counter.load();
        }
        return sum;
    }
};
~~~

We'll call this cas multi, and the approach is relatively straightforward.

There are 64 padded[^padded] physical counters whose sum makes up the logical counter value. There is a thread-local `idx` value, initially zero for every thread, that points to the physical counter that each thread should increment. When `operator++` is called, we attempt to increment the counter pointed to by `idx` using CAS.

If this fails, however, we don't simply retry. Failure indicates contention[^notallfailure] (this is the only way the _strong_ variant of `compare_exchange` can fail), so we add one to `idx` to try another counter on the next attempt.

In a high-contention scenario like our benchmark, every CPU quickly ends up pointing to a different index value. If there is low contention, it is possible that only the first physical counter will be used.

Let's compare this to the `atomic add` version we looked at above, which was the fastest of the level 2 approaches. Recall that it uses an atomic add on a single counter.

{% include carousel-svg-fig-2.html file="cas-multi" alt="Increment Cost: Contention Adaptive Multi-Counter"
suffixes=uarches names=unames raw=uresults %}

For 1 active core, the results are the same as we saw earlier: the CAS approach performs the same as the cas add algorithm[^perfsame], which is somewhat slower than atomic add, due to the need for an additional load (i.e., the line with `counter.load()`) to set up the CAS.

For 2 to 4 cores, the situation changes dramatically. The multiple counter approach performs the _same_ regardless of the number of active cores. That is, it exhibits perfect scaling with multiple cores -- in contrast to the single-counter approach which scales poorly. At four cores, the relative speedup of the multi-counter approach is about 9x. On Amazon's Graviton ARM processor the speedup approaches _eighty_ times at 16 threads.

This improvement in increment performance comes at a cost, however:

 - 64 counters ought to be enough for anyone, but they take 4096 (!!) bytes of memory to store what takes only 8 bytes in the atomic add approach[^eightbyte].
 - The `read()` method is much slower: it needs to iterate over and add all 64 values, versus a single load for the earlier approaches.
 - The implementation compiles to much larger code: 113 bytes versus 15 bytes for the single counter CAS approach or 7 bytes for the atomic add approach.
 - The concurrent behavior is considerably harder to reason about and document. For example, it is harder to explain the consistency condition provided by `read()` since it is no longer a single atomic read[^read].
 - There is a single thread-local `idx` variable. So while different `cas_multi_counter` instances are logically independent, the shared `idx` variable means that things that happen in one counter can affect the non-functional behavior of the others[^sharedidx].

Some of these downsides can be partly mitigated:

- A much smaller number of counters would probably be better for most practical uses. We could also set the array size dynamically based on the detected number of logical CPUs since a larger array should not provide much of a performance increase. Better yet, we might make the size even more dynamic, based on contention: start with a single element and grow it only when contention is detected. This means that even on systems with many CPUs, the size will remain small if contention is never seen in practice. This has a runtime cost[^rtcost], however.
- We could optimize the `read()` method by stopping when we see a zero counter. I believe a careful analysis shows that the non-zero counter values for any instance of this class are all in a contiguous region starting from the beginning of the counter array[^subtle].
- We could mitigate some of the code footprint by carefully carving the "less hot"[^lesshot] slow path out into a another function, and use our [magic powers](https://xania.org/201209/forcing-code-out-of-line-in-gcc) to encourage the small fast path (the first CAS) to be inlined while the fallback remains not inlined.
- We could make the thread-local `idx` per instance specific to solve the "shared `idx` across all instances" problem. This does require some non-negligible amount of work to implement a dynamic TLS system which can create as many thread local keys as you want[^dynamictls], and it is slower.

So while we got a good looking chart, this solution doesn't exactly dominate the simpler ones. You pay a price along several axes for the lack of contention and you shouldn't blindly replace the simpler solutions with this one -- it needs to be a carefully considered and use-case dependent decision.

Is it over yet? Can I close this browser tab and reclaim all that memory? Almost. Just one level to go.

### Level 0: Vanilla

The last and fastest level is achieved when only vanilla instructions are used (and without contention). By _vanilla instructions_ I mean things like regular loads and stores which don't imply additional synchronization above what the hardware memory model offers by default[^noatomic].

How can we increment a counter atomically while allowing it to be read from any thread? By ensuring there is only one writer for any given physical counter. If we keep a counter _per thread_ and only allow the owning thread to write to it, there is no need for an atomic increment.

The obvious way to keep a per-thread counter is use thread-local storage. Something like this:

~~~c++
/**
 * Keeps a counter per thread, readers need to sum
 * the counters from all active threads and add the
 * accumulated value from dead threads.
 */
class tls_counter {
    std::atomic<uint64_t> counter{0};

    /* protects all_counters and accumulator */
    static std::mutex lock;
    /* list of all active counters */
    static std::vector<tls_counter *> all_counters;
    /* accumulated value of counters from dead threads */
    static uint64_t accumulator;
    /* per-thread tls_counter object */
    static thread_local tls_counter tls;

    /** add ourselves to the counter list */
    tls_counter() {
        std::lock_guard<std::mutex> g(lock);
        all_counters.push_back(this);
    }

    /**
     * destruction means the thread is going away, so
     * we stash the current value in the accumulator and
     * remove ourselves from the array
     */
    ~tls_counter() {
        std::lock_guard<std::mutex> g(lock);
        accumulator += counter.load(std::memory_order_relaxed);
        all_counters.erase(std::remove(all_counters.begin(), all_counters.end(), this), all_counters.end());
    }

    void incr() {
        auto cur = counter.load(std::memory_order_relaxed);
        counter.store(cur + 1, std::memory_order_relaxed);
    }

public:

    static uint64_t read() {
        std::lock_guard<std::mutex> g(lock);
        uint64_t sum = 0, count = 0;
        for (auto h : all_counters) {
            sum += h->counter.load(std::memory_order_relaxed);
            count++;
        }
        return sum + accumulator;
    }

    static void increment() {
        tls.incr();
    }
};
~~~

The approach is the similar to the per-CPU counter, except that we keep one counter per thread, using `thread_local`. Unlike earlier implementations, you don't create instances of this class: there is only one counter and you increment it by calling the static method `tls_counter::increment()`.

Let's focus a moment on the actual increment inside the thread-local counter instance:

~~~c++
void incr() {
    auto cur = counter.load(std::memory_order_relaxed);
    counter.store(cur + 1, std::memory_order_relaxed);
}
~~~

This is just a verbose way of saying "add 1 to this `std::atomic<uint64_t>` but it doesn't have to be atomic". We don't need an atomic increment as there is only one writer[^whyatomic]. Using the _relaxed_ memory order means that no barriers are inserted[^barrier]. We still need a way to read all the thread-local counters, and the rest of the code deals with that: there is a global vector of pointers to all the active `tls_counter` objects, and `read()` iterates over this. All access to this vector is protected by a `std::mutex`, since it will be accessed concurrently. When threads die, we remove their entry from the array, and add their final value to `tls_counter::accumulator` which is added to the sum of active counters in `read()`.

Whew.

So how does this tls add implementation benchmark?

*[tls add]: Uses thread-local storage for a counter per thread.

{% include carousel-svg-fig-2.html file="tls" alt="Increment Cost: Thread Local Storage"
suffixes=uarches names=unames raw=uresults %}

That's two nanoseconds per increment, regardless of the number of active cores. This turns out to be exactly as fast as just incrementing a variable in memory with a single instruction like `inc [eax]` or `add [eax], 1`, so it's somehow as fast as possible for any solution which ends up incrementing something in memory[^whitelie].

Let's take a look at the number of atomics, total instructions and performance for the three implementations in the last plot, for four threads:

| Algorithm        | Atomics | Instructions   | Performance |
| ---------------- | -------:| -------------: | -----------:|
| atomic add       |     1   |   4            |    ~ 110 ns |
| cas multi        |     1   |   7            |     ~ 12 ns |
| tls add          |     0   |   12           |      ~ 2 ns |

This is a clear indication that the difference in performance has very little to do with the number of instructions: the ranking by instruction count is exactly the reverse of the ranking by performance! tls add has three times the number of instructions, yet is more than _fifty times_ faster (so the IPC varies by a factor of more than 150x).

As we saw at the last 1, this improvement in performance doesn't come for free:

- The total code size is considerably larger than the per-CPU approach, although most of it is related to creation of the initial object on each thread, and not on the hot path.
- We have one object per thread, instead of per CPU. For an application with many threads using the counter, this may mean the creation of many individual counters which use both more memory[^tlsmem] and result in a slower `read()` function.
- This implementation only supports _one_ counter: the key methods in `tls_counter` are static. This boils down to the need for a `thread_local` object for the physical counter, which must be static by the rules of C++. A template parameter could be added to allow multiple counters based on dummy types used as tags, but this is still more awkward to use than instances of a class (and some platforms [have limits](https://docs.microsoft.com/en-us/windows/win32/procthread/thread-local-storage) on the number of `thread_local` variables). This limitation could be removed in the same way as discussed earlier for the cas multi `idx` variable, but at a cost in performance and complexity.
- A lock was introduced to protect the array of all counters. Although the important increment operation is still lock-free, things like the `read()` call, the first counter access on a given thread and thread destruction all compete for the same lock. This could be eased with a read-write lock or a concurrent data structure, but at a cost as always.

## The Table

<style>
.yesno {
    display: inline-block;
    border-radius: 3px;
    min-width: 25px;
    text-align: center;
}
.yes {
    background-color: #070;
    padding: 3px;
}
.no {
    background-color: orangered;
    padding: 3px 5px;
}
</style>

Let's summarize all the levels in this table.

The _~Cost_ column is a _very_ approximate estimate of the cost of each "occurrence" of the expensive operation associated with the level. It should be taken as a very rough ballpark for current Intel and AMD hardware, but especially the later levels can vary a lot.

The _Perf Event_ column lists a Linux `perf` event that you can use to count the number of times the operation associated with this level occurs, i.e., the thing that is slow. For example, in level 1, you count atomic operations using the `mem_inst_retired.lock_loads` counter, and if you get three counts per high level operation, you can expect roughly 3 x 10 ns = 30 ns cost. Of course, you don't necessarily need perf in this case: you can inspect the assembly too.

The _Local_ column records whether the behavior of this level is _core local_. If yes, it means that operations on different cores complete independently and don't compete and so the performance scales with the number of cores. If not, there is contention or serialization, so the throughput of the entire system is often limited, regardless of how many cores are involved. For example, only one core at a time performs an atomic operation on a cache line, so the throughput of the whole system is fixed and the throughput per core decreases as more cores become involved.

The _Key Characteristic_ tries to get across the idea of the level in one bit-sized chunk.

| Level |  Name | ~Cost (ns) | Perf Event | Local | Key Characteristic |
| ---   | ------| -------------:|:----------------:|:----:| -- |
| 0 | Vanilla | low | depends | **Yes**{:.yes.yesno} | No atomic instructions or contended accesses at all |
| 1 | Uncontended Atomic | 10 | `mem_inst_retired.` `lock_loads` | **Yes**{:.yes.yesno} | Atomic instructions without contention |
| 2 | True Sharing | 40 - 400 | `mem_load_l3_hit_retired.` `xsnp_hitm` | **No**{:.no.yesno} | Contended atomics or locks |
| 3 | Syscall | 1,000 | `raw_syscalls:sys_enter` | **No**{:.no.yesno} | System call |
| 4 | Context Switch | 10,000 | `context-switches` | **No**{:.no.yesno} | Forced context switch |
| 5 | Catastrophe | huge | depends | **No**{:.no.yesno} | Stalls until quantum exhausted, or other sadness |

## So What?

What's the point of all this?

Primarily, I use the hierarchy as a simplification mechanism when thinking about concurrency and performance. As a first order approximation _you mostly only need to care about the operations related to the current level_. That is, if you are focusing on something which has contended atomic operations (level 2), you don't need to worry too much about uncontended atomics or instruction counts: just focus on reducing contention. Similarly, if you are at level 1 (uncontended atomics) it is often worth using _more_ instructions to reduce the number of atomics.

This guideline only goes so far: if you have to add 100 instructions to remove one atomic, it is probably not worth it.

Second, when optimizing a concurrent system I always try to consider how I can get to a (numerically) lower level. Can I remove the last atomic? Can I avoid contention? Successfully moving to a lower level can often provide an order-of-magnitude boost to performance, so it should be attempted first, before finer-grained optimizations within the current level. Don't spend forever optimizing your contended lock, if there's some way to get rid of the contention entirely.

Of course, this is not always possible, or not possible without tradeoffs you are unwilling to make.

### Getting There

Here's a quick look at some usual and unusual ways of achieving levels lower on the hierarchy.

#### Level 4

You probably don't want to really be in level 4 but it's certainly better than level 5. So, if you still have your job and your users haven't all abandoned you, it's usually pretty easy to get out of level 5. More than half the battle is just recognizing what's going on and from there the solution is often clear. Many times, you've simply violated some rule like "don't use pure spinlocks in userspace" or "you built a spinlock by accident" or "so-and-so accidentally held that core lock during IO". There's almost never any inherent reason you'd need to stay in level 5 and you can usually find an almost tradeoff-free fix.

A better approach than targeting level 4 is just to skip to level 2, since that's usually not too difficult.

#### Level 3

Getting to level 3 just means solving the underlying reason for so many context switches. In the example used in this post, it means giving up fairness. Other approaches include not using threads for small work units, using smarter thread pools, not oversubscribing cores, and keeping locked regions short.

You don't usually really want to be in level 3 though: just skip right to level 2.

#### Level 2

Level 3 isn't a _terrible_ place to be, but you'll always have that gnawing in your stomach that you're leaving a 10x speedup on the table. You just need to get rid of that system call or context switch, bringing you to level 2.

Most library provided concurrency primitives already avoid system calls on the happy path. E.g., pthreads mutex, `std::mutex`, Windows `CRITICAL_SECTION` will avoid a system call while acquiring and releasing an uncontended lock. There are, however, some notable exceptions: if you are using a [Win32 mutex object](https://docs.microsoft.com/en-us/windows/win32/sync/mutex-objects) or [System V semaphore](https://man7.org/linux/man-pages/man2/semop.2.html) object, you are paying a system call on every operation. Double check if you can use an in-process alternative in this case.

For more general synchronization purposes which don't fit the lock-unlock pattern, a condition variable often fits the bill and a quality implementation generally avoids system calls on the fast path. A relatively unknown and higher performance alternative to condition variables, especially suitable for coordinating blocking for otherwise lock-free structures, is an [_event count_](http://pvk.ca/Blog/2019/01/09/preemption-is-gc-for-memory-reordering/#event-counts-with-x86-tso-and-futexes). Paul's implementation is [available in concurrency kit](https://github.com/concurrencykit/ck/blob/master/include/ck_ec.h) and we'll mention it again at Level 0.

System calls often creep in when home-grown synchronization solutions are used, e.g., using Windows events to build your own read-write lock or striped lock or whatever the flavor of the day is. You can often remove the call in the fast path by making a check in user-space to see if a system call is necessary. For example, rather than unconditionally unblocking any waiters when releasing some exclusive object, _check_ to see if there are waiters[^tricky] in userspace and skip the system call if there are none.

If a lock is generally held for a short period, you can avoid unnecessary system calls and context switches with a hybrid lock that spins for an appropriate[^spin] amount of time before blocking. This can trade tens of nanoseconds of spinning for hundreds or thousands of nanoseconds of system calls.

Ensure your use of threads is "right sized" as much as possible. A lot of unnecessary context switches occur when many more threads are running than there are CPUs, and this increases the chance of a lock being held during a context switch (and makes it worse when it does happen: it takes longer for the holding thread to run again as the scheduler probably cycles through all the other runnable threads first).

#### Level 1

A lot of code that does the work to get to level 2 actually ends up in level 1. Recall that the primary difference between level 1 and 2 is the lack of contention in level 1. So if your process naturally or by design has low contention, simply using existing off-the-shelf synchronization like `std::mutex` can get you to level 1.

I can't give a step-by-step recipe for reducing contention, but here's a laundry list of things to consider:

- Keep your critical sections as short as possible. Ensure you do any heavy work that doesn't directly involve a shared resource outside of the critical section. Sometimes this means making a copy of the shared data to work on it "outside" of the lock, which might increase the total amount of work done, but reduce contention.
- For things like atomic counters, try to batch your updates: e.g., if you update the counter multiple times during some operation, update a local on the stack rather than the global counter and only "upload" the entire value once at the end.
- Consider using structures that use fine-grained locks, striped locks or similar mechanisms that reduce contention by locking only portions of a container.
- Consider per-CPU structures, as in the examples above, or some approximation of them (e.g., hashing the current thread ID into an array of structures). This post used an atomic counter as a simple example, but it applies more generally to any case where the mutations can be done independently and aggregated later.

For all of the advice above, when I say _consider doing X_ I really mean _consider finding and using an existing off-the shelf component that does X_. Writing concurrent structures yourself should be considered a last resort -- despite what you think, your use case is probably not all that unique.

Level 1 is where a lot of well written, straightforward and high-performing concurrent code lives. There is nothing wrong with this level -- it is a happy place.

#### Level 0

It is not always easy or possible to remove the last atomic access from your fast paths, but if you just can't live with the extra ~10 ns, here are some options:

- The general approach of using thread local storage, as discussed above, can also be extended to structures more complicated than counters.
- You may be able to achieve fewer than one expensive atomic instruction per logical operation by _batching:_ saving up multiple operations and then committing them at all once with a small fixed number of atomic operations. Some containers or concurrent structures may have a batched API which does this for you, but even if not you can sometimes add batching yourself, e.g., by inserting collections of elements rather than a single element[^hiddenbatch].
- Many lock-free structures offer atomic-free _read_ paths, notably concurrent containers in garbage collected languages, such as `ConcurrentHashMap` in Java. Languages without garbage collection have fewer straightforward options, mostly because safe memory reclamation is a [hard problem](http://concurrencyfreaks.blogspot.com/2017/08/why-is-memory-reclamation-so-important.html), but there are still [some](http://concurrencykit.org/) [good](https://software.intel.com/content/www/us/en/develop/documentation/tbb-documentation/top/intel-threading-building-blocks-developer-guide/containers.html) [options](https://github.com/facebook/folly/tree/master/folly/concurrency) out there.
- I find that [RCU](https://liburcu.org/) is especially powerful and fairly general if you are using a garbage collected language, or can satisfy the requirements for an efficient reclamation method in a non-GC language.
- The [seqlock](https://en.wikipedia.org/wiki/Seqlock)[^despite] is an underrated and little known alternative to RCU without reclaim problems, although not as general. Concurrencykit has [an implementation](http://concurrencykit.org/doc/ck_sequence.html). It has an atomic-free read path for readers. Unfortunately, seqlocks don't integrate cleanly with either the Java[^stampedlock] or [C++](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2019/p1478r1.html) memory models.
- It is also possible in some cases to do a per-CPU rather than a per-thread approach using only vanilla instructions, although the possibility of interruption at any point makes this tricky. [Restartable sequences (rseq)](https://www.efficios.com/blog/2019/02/08/linux-restartable-sequences/) can help, and there are other tricks lurking out there.
- Event counts, mentioned earlier, [can even be level 0](https://pvk.ca/Blog/2019/01/09/preemption-is-gc-for-memory-reordering/#event-counts-with-x86-tso-and-futexes:~:text=However%2C%20if%20we%20go) in a single writer scenario, as Paul shows.
- This is the last point, but it should be the first: you can probably often redesign your algorithm or application to avoid sharing data in the first place, or to share much less. For example, rather than constantly updating a shared collection with intermediate results, do as much private computation as possible before only merging the final results.


### Summary

We looked at the six different levels that make up this concurrency cost hierarchy. The slow half (3, 4 and 5) are all basically performance bugs. You should be able to achieve level 2 or level 1 (if you naturally have low contention) for most designs fairly easily and those are probably what you should target by default. Level 1 in a contended scenario and level 0 are harder to achieve and often come with difficult tradeoffs, but the performance boost can be significant: often one or more orders of magnitude.

### Thanks

Thanks to Paul Khuong who [showed me something](https://pvk.ca/Blog/2020/07/07/flatter-wait-free-hazard-pointers) that made me reconsider in what scenarios level 0 is achievable and typo fixes.

Thanks to [@never_released](https://twitter.com/never_released) for help on a problem I had bringing up an EC2 bare-metal instance (tip: just wait).

Special thanks to [matt_dz](https://twitter.com/matt_dz) and Zach Wenger for helping fix about _sixty_ typos between them.

Thanks to Alexander Monakov, Dave Andersen, Laurent and Kriau for reporting typos, and Aaron Jacobs for suggesting clarifications to the level 0 definition.

Traffic light photo by <a href="https://unsplash.com/@harshaldesai">Harshal Desai</a> on <a href="https://unsplash.com/s/photos/traffic-light">Unsplash</a>.

### Discussion and Feedback

You can leave a [comment below](#comment-section) or discuss on [Hacker News](https://news.ycombinator.com/item?id=23749172), [r/programming](https://www.reddit.com/r/programming/comments/hma5y1/a_concurrency_cost_hierarchy/) or [r/cpp](https://www.reddit.com/r/cpp/comments/hmaocb/a_concurrency_cost_hierarchy/).

{% include other-posts.md %}

---
---
<br>

[^hiddenbatch]: An interesting design point is a data type that implements batching internally behind an API offering single-element operations. For example, a queue might decide that added elements won't be immediately consumed (because there are already some elements in the queue), and hold them in a local staging area until several can be added as a batch, or until their absence would be noticed.

[^realworld]: Well, this is quite real world: such atomic counters are used widely for a variety of purposes. I throw the _if you squint_ in there because, after all, we are using microbenchmarks which simulate a probably-unrealistic density of increments to this counter, and it is a _bit_ of a stretch to make this one example span all five levels -- but I tried!

[^stampedlock]: Java does provide [StampedLock](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/concurrent/locks/StampedLock.html) which offers seqlock functionality.

[^spin]: An "appropriate" time is probably something like the typical runtime of the locked region. Basically you want to spin in any case where the lock is held by a currently running thread, which will release it soon. As soon as you've been spinning for more than the typical hold time of the lock, it becomes much more likely you are simply waiting for a lock held by a thread that is _not_ running (e.g., it was unlucky enough to incur a context switch while it held the lock). In that case, you are better off sleeping.

[^tricky]: It's easy to introduce a missed wakeup problem if this isn't done correctly. The usual cause is a race condition between some waiter arriving at a lock-like thing, seeing that it's locked and then indicating interest, but in the critical region of that check-then-act the owning thread left the lock and didn't see any waiters. The waiter blocks but there is nobody to unblock them. These bugs often go undetected since the situation resolves itself as soon as another thread arrives, so in a busy system you might not notice the temporarily hung threads. The `futex` system call is basically designed to make solving this easy, while the Event stuff in Windows requires a bit more work (usually based on a compare-and-swap).

[^barrier]: If you use the default `std::memory_order_seq_cst`, on x86 gcc inserts an `mfence` which makes this _even slower than an atomic increment_ since `mfence` is generally slower than instructions with a lock prefix (it has slightly stronger barrier semantics).

[^whyatomic]: The only reason we even need `std::atomic<uint64_t>` at all is because it is _undefined behavior_ to have concurrent access to any variable if at least one access is a write. Since the owning thread is making writes, this would _technically_ be a violation of the standard if there was a concurrent `tls_counter::read()` call. Most actual hardware has no problem with concurrent reads and writes like this, but it's better to stay on the right side of the law. Some hardware could also exhibit _tearing_ of the writes, and `std::atomic` guarantees this doesn't happen. That is, the read and write are still _individually_ atomic.

[^dynamictls]: A sketch of an implementation would be to use something like a single static `thread_local` pointer to an array or map, which maps an ID contained in the dynamic TLS key to the object data. Lookup speed is important, which favors an array, but you also need to be able to remove elements, which can favor some type of hash map. All of this is probably at least twice as slow as a plain `thread_local` access ... or just use [folly](https://github.com/facebook/folly/blob/master/folly/docs/ThreadLocal.md) or [boost](https://www.boost.org/doc/libs/1_73_0/doc/html/thread/thread_local_storage.html).

[^lesshot]: I'm not sure if "less hot" means `__attribute__((cold))` necessarily, that might be _too_ cold. We mostly just want to separate the first-cas-succeeds case and the rest of the logic so we don't pay the dynamic code size impact except when the fallback path is taken.

[^subtle]: The intuition is later counter positions only get written when an earlier position failed a compare and swap, which necessarily implies it was written to by some other thread and hence non-zero. There is some subtlety here: this wouldn't hold if `compare_exchange_weak` was used instead of `compare_exchange_strong`, and it more obviously wouldn't apply if we allowed decrements or wanted to change the "probe" strategy.

[^rtcost]: At least, an extra indirection to access the array which is no longer embedded in the object[^soa], and checks to ensure the array is large enough. Furthermore, we have another decision to make: when to expand the array. How much contention should we suffer before we decide the array is too small?

[^soa]: Of course, we could go even _one step further_ and embed a small array of 1 or 2 elements in the counter object, in the hope that this is enough and only use a dynamically allocated array and suffer the additional indirection if we observe contention.

[^sharedidx]: In particular, if contention is seen on one object, the per-thread index will change to avoid it, which changes the index of all other objects as well, even if they have not seen any contention. This doesn't seem like much of a problem for this simple implementation (which index we write to doesn't matter much), but it could make some other optimizations more difficult: e.g., if we size the counter array dynamically, we don't want to unnecessarily change the `idx` for uncontended objects, since it requires a larger counter array, unnecessarily.

[^read]: In this limited case, I _think_ `read()` provides the same guarantees as the single-counter case. Informally, `read()` returns some value that the counter had at some point between the start and end of the `read()` call. Formally, there is a _linearization point_ within `read()` although this point can only be determined in retrospect by examining the returned value (unlike the single-counter approaches, where the linearization is clear regardless of the value). However, _this is only true because the only mutating operation is `increment()`_. If we also offered a `decrement()` method, this would no longer be true: you could read values that the logical counter never had based on the sequence of increments and decrements. Specifically, if you execute `increment(); decrement(); increment()` and even if you know these operations are strictly ordered (e.g., via locking), a concurrent call to `read()` could return _2_, even though the counter never logically exceeded 1.

[^eightbyte]: Here I'm assuming that `sizeof(std::atomic<uint64_t>)` is 8, and this is the case on all current mainstream platforms. Also, you may or may not want to pad out the single-counter version to 64 bytes as well, to avoid some _potential_ false sharing with nearby values, but this is different than the multi-counter case where padding is obligatory to avoid guaranteed false sharing.

[^padded]: _Padded_ means that the counters are aligned such that each falls into its own 64 byte cache line, to avoid [_false sharing_](https://en.wikipedia.org/wiki/False_sharing). This means that even though each counter only has 8 bytes of logical payload, it requires 64 bytes of storage. Some people claim that you need to pad out to 128 bytes, not 64, to avoid the effect of the _adjacent line prefetcher_ which fetches the 64-byte that completes an aligned 128-byte pair of lines. However, I have not observed this effect often on modern CPUs. Maybe the prefetcher is conservative and doesn't trigger unless past behavior indicates the fetches are likely to be used, or the prefetch logic can detect and avoid cases of false sharing (e.g., by noticing when prefetched lines are subsequently invalidated by a snoop).

[^perfsame]: Not surprising, since there is no contention and the fast path looks the same for either algorithm: a single CAS that always succeeds.

[^twolayer]: Actually three layers, [libstdc++](https://github.com/gcc-mirror/gcc/blob/4ff685a8705e8ee55fa86e75afb769ffb0975aea/libstdc%2B%2B-v3/include/bits/std_mutex.h#L98), then [libgcc](https://github.com/gcc-mirror/gcc/blob/4ff685a8705e8ee55fa86e75afb769ffb0975aea/libgcc/gthr-posix.h#L775) and then finally pthreads. I'll count the first two as one though because those can all inline into the caller. Based on a rough accounting, probably 75% of the instruction count comes from pthreads, the rest from the other two layers. The pthreads mutexes are more general purpose than what `std::mutex` offers (e.g., they support recursion), and the features are configured at runtime on a per-mutex basis, so that explains a lot of the additional work these functions are doing. It's only due to cost of atomic operations that `std::mutex` doesn't take a significant penalty compared to a more svelte design.

[^atomhow]: On Intel hardware you can use [details.sh](https://github.com/travisdowns/concurrency-hierarchy-bench/blob/master/scripts/details.sh) to collect the atomic instruction count easily, taking advantage of the `mem_inst_retired.lock_loads` performance counter.

[^notexx]: This won't always _necessarily_ be the case. You could write a primitive that always makes a system call, putting it at level 3, even if there is no contention, but here I've made sure to always have a no-syscall fast path for the no-contention case.

[^perf]: In fact, you can measure this with `perf` and see that the total number of context switches is usually within a factor of 2 for both tests, when oversubscribed.

[^once]: In fact, the _once_ scenario is the most likely, since one would assume with homogeneous threads the scheduler will approximate something like round-robin scheduling. So the thread that is descheduled is most likely the one that is also closest to the head of the lock queue, because it had been spinning the longest.

[^huh]: Actually I find it remarkable that this performs about as well as the CAS-based atomic add, since the fairness necessarily implies that the lock is acquired in a round-robin order, so the cache line with the lock must at a minimum move around to each acquiring thread. This is a real stress test of the arbitrary coherency mechanisms offered by the CPU.

[^hyst]: An interesting thing about convoys is that they exhibit hysteresis: once you start having a convoy, they become self-sustaining, even if the conditions that started it are removed. Imagine two threads that lock a common lock for 1 nanosecond every 10,000 nanoseconds. Contention is low: the chance of any particular lock acquisition being contended is 0.01%. However, as soon as a contended acquisition occurs, the lock effectively becomes held for the amount of time it takes to do a full context switch (for the losing thread to block, and then to wake up). If that's longer than 10,000 nanoseconds, the convoy will sustain itself indefinitely, until something happens to break the loop (e.g., one thread deciding to work on something else). A restart also "fixes" it, which is one of many possible explanations for processes that suddenly shoot to 100% CPU (but are still making progress), but can be fixed by a restart. Everything becomes worse with more than two threads, too.

[^parisc]: Some hardware supports very limited atomic operations, which may be mostly useful _only_ for locking, although you can [get tricky](https://parisc.wiki.kernel.org/index.php/FutexImplementation).

[^atomicsup]: Many ISAs, including POWER and ARM, traditionally only included support for a CAS-like or [LL/SC](https://en.wikipedia.org/wiki/Load-link/store-conditional) operation, without specific support for more specific atomic arithmetic operations. The idea, I think, was that you could build any operation you want on top of of these primitives, at the cost of "only" a small retry loop and that's more RISC-y, right? This seems to be changing as ARMv8.1 got a bunch of atomic operations.

[^java]: From its introduction through Java 7, the `AtomicInteger` and related classes in Java implemented all their atomic operations on top of a CAS loop, as CAS was the only primitive implemented as an intrinsic. In Java 8, almost exactly a decade later, these were finally replaced with dedicated atomic RMWs where possible, with [good results](http://ashkrit.blogspot.com/2014/02/atomicinteger-java-7-vs-java-8.html).

[^l3]: On my system and most (all?) modern Intel systems this is essentially the L3 cache, as the caching home agent (CHA) lives in or adjacent to the L3 cache.

[^inter]: This doesn't imply that each atomic operation needs to take 70 cycles under contention: a single core could do _multiple_ operations on the cache line after it gains exclusive ownership, so the cost of obtaining the line could be amortized over all of these operations. How much of this occurs is a measure of fairness: a very fair CPU will not let any core monopolize the line for long, but this makes highly concurrent benchmarks like this slower. Recent Intel CPUs seem quite fair in this sense.

[^post]: We could actually use either the pre or post-increment version of the operator here. The usual advice is to prefer the pre-increment form `++c` as it can be faster as it can return the mutated value, rather than making a copy to return after the mutation. Now this advice rarely applies to primitive values, but atomic increment is actually an interesting case which turns it on its head: the post-increment version is probably better (at least, never slower) since the underlying hardware operation returns the previous value. So it's [at least one extra operation](https://godbolt.org/z/p4TDjX) to calculate the pre-increment value (or much worse, apparently, if icc gets involved).

[^notwhat]: It also might not [work how you think](https://www.realworldtech.com/forum/?threadid=189711&curpostid=189752), depending on details of the OS scheduler.

[^spectre]: They used to be cheaper: based on my measurements the cost of system calls has more than doubled, on most Intel hardware, after the Spectre and Meltdown mitigations have been applied.

[^notallfailure]: Actually, not _all_ failure indicates contention: there is a small chance also that a context switch exactly splits the load and the subsequent CAS, and in this case the CAS would fail when the thread was scheduled again if any thread that ran in the meantime updated the same counter. Treating this as contention doesn't really cause any serious problems.

[^tlsmem]: On the other hand, the TLS approach doesn't need padding since the counters will generally appear next to other thread-local data, and not subject to false sharing, which means an 8x reduction (from 64 to 8 bytes) in the per-counter size, so if your process has a number of threads roughly equal to the number of cores, you will probably _save_ memory over the per-CPU approach.

[^noht]: And no SMT enabled, so there are 4 logical processors from the point of view of the OS.

[^csdepend]: There is another level of complication here: the convoy only gets set up when the fifth thread joins the fun _if_ the thread that gets switched out had expressed interest in the lock before it lost the CPU. That is, after a thread unlocks the lock, there is a period before it gets a new ticket as it tries to obtain the lock again. Before it gets that ticket, it is essentially invisible to the other threads, and if it gets context switched out, the catastrophic convoy won't be set up (because the new set of four threads will be able to efficiently share the lock among themselves).

[^casworse]: The cas add implementation comes off looking slightly worse than the other single-atomic implementations here because the load required to set up the CAS value effectively adds to the dependency chain involving the atomic operation, which explains the 5-cycle difference with atomic add. This goes away if you can do a _blind CAS_ (e.g., in locks' acquire paths), but that's not possible here.

[^whitelie]: This is a very small white lie. I'll explain more elsewhere.

[^despite]: Despite the current claim in wikipedia that seqlocks are somehow a Linux-specific construct involving the kernel, they work great in userspace only and are not tied to Linux. It is likely they were not invented for use in Linux but [pre-dated](https://twitter.com/davidtgoldblatt/status/1280189008803278848) the OS, although maybe the use in Linux was where the name _seqlock_ first appeared?

[^noatomic]: On x86, what's vanilla and what isn't is fairly cut and dried: regular memory accesses and read-modify-write instructions are _vanilla_ while LOCKed RMW instructions, whether explicit like `lock inc` or implicit like [`xchg [mem], reg`](https://www.felixcloutier.com/x86/xchg), are not and are an order of magnitude slower. Out of the fences, `mfence` is also a slow non-vanilla instruction, comparable in cost to a LOCKed instruction. On other platforms like ARM or POWER, there may be shades of grey: you still have vanilla accesses on one end, and expensive full barriers like `dmb` on ARM or `sync` on POWER at the other, but you also have things in the middle with some additional ordering guarantees but still short of sequential consistency. This includes things like `LDAR` and `LDAPR` on ARM which implement sort of a sliding scale of load ordering and performance. Still, on any given hardware, you might find that instructions generally fall into a "cheap" (vanilla) and "expensive" (non-vanilla) bucket.
