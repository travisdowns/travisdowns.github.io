---
layout: post
title: A Concurrency Cost Hierarchy
category: blog
tags: [performance, c++, concurrency]
assets: /assets/concurrency-costs
image:  /assets/concurrency-costs/avatar.png
twitter:
  card: summary_large_image
---

We'll start the middle of the hierarcy.

The most elementary way to safely modify any concurrently shared object is to use a lock. It mostly _just works_ for any type of object, no matter its structure or the nature of the modifications. Almost any hardware from the last thirty years supports some type of atomic locking[^parisc] userspace instruction.

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

On my 4 CPU Skylake-S box, when I use the vanilla `std::mutex` I get the following results for 2 to 4 threads:

{% include svg-fig.html file="mutex" alt="std::mutex as lock" %}

This shows that the baseline contended cost to modify an integer protected by a lock starts at about 120 nanoseconds for two threads, and grows somewhat with increasing thread count.

I can already hear someone saying: _If you are just modifying a single 64-bit integer, skip the lock and just directly use the atomic operations that most ISAs support!_

Sure, let's add a couple of variants. The `std::atomic<T>` template makes this easy: we can wrap any type meeting some basic requirements and then manipulate it atomically. The easiest of all is to use `std::atomic<uint64>::operator++()`[^post]:

[^post]: We could actually use either the pre or post-increment version of the operator here. The usual advice is to prefer the pre-increment form `++c` as it can be faster as it can return the mutated value, rather than making a copy to return after the mutation. Now this advice rarely applies to primitive values, but atomic increment is actually an interesting case which turns it on its head: the post-increment version is probably better (at least, never slower) since the underlying hardware operation returns the previous value. So it's [at least one extra operation](https://godbolt.org/z/p4TDjX) to calculate the pre-increment value (or much worse, apparently, if icc gets involved).

~~~c++
std::atomic<uint64_t> atomic_counter{};

void atomic_add(size_t iters) {
    while (iters--) {
        atomic_counter++;
    }
}
~~~

The other common approach would be to use [compare and swap (CAS)](https://en.wikipedia.org/wiki/Compare-and-swap) to load the existing value, add one and then to CAS it back if it hasn't changed. Even if you use increment at the source level, the assembly might actually end up using CAS if your hardware doesn't support atomic increment[^atomicsup], or if your compiler or runtime just doesn't take advantage of atomic operations even though they are available (e.g., see what even the newest version of [icc does](https://godbolt.org/z/5h4K7y) for atomic increment, and what Java did for years[^java]). So let's add one of those:

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

{% include svg-fig.html file="atomic-inc" alt="atomic-increment" %}

The first takeaway is that, at least in this _unrealistic maximum contention_ benchmark, using atomic add (`lock xadd` at the hardware level) is significantly better than CAS. The second would be that `std::mutex` doesn't come look all that bad. It ties with the CAS approach at 2 cores and beats it at 3 and 4 cores. It's slower than the atomic increment approach, but less than twice as slow at 3 and 4 cores and seems to scale fine.

All of these operations are belong to performance level TODO. The primary characteristic is that they make a _contended_ access to a shared variable. This means that at a minimum, the line containing the data needs to move down to the caching agent that manages coherency[^l3], and then back up to the core that will receive ownership next. That's about 70 cycles minimum just for that operation[^inter].

Can it get slower? Yes, it can get _way_ slower. 

The next level up ("up" is not good here...) is level TODO. This is occupied by scenarios where most or all operations make a _system call_. It is easy to write concurrency primitives that do this (e.g,. a lock which always tries to wake waiters via a `futex(2)` call, even if there aren't any), but we don't show these here. Rather we'll take a look at some _fair_ locks. Fair locks allow threads into the critical section into the order they began waiting. That is, when the critical section becomes available, the thread that has been waiting the longest is given the chance to take it.

Sounds like a good idea, right? Well it can have significant performance implications.

We'll try three different fair locks. The first is a ticket lock with a `sched_yield` in the spin loop. The idea of the yield is to give other threads which may hold the lock time to run. It looks like this:

<a id="ys-lock"></a>
~~~c++
class yielding_spin {
    std::atomic<size_t> dispenser{}, serving{};

public:
    void lock() {
        auto ticket = dispenser++;

        while (ticket != serving.load(std::memory_order_acquire))
            sched_yield();
    }

    void unlock() {
        serving.store(serving.load() + 1, std::memory_order_release);
    }
};
~~~

Let's plot the result for this lock alongside the existing approaches:

{% include svg-fig.html file="fair-yield" alt="Increment Costs: Fair Yield" %}

It is an order of magnitude slower than the existing approaches. This is level TODO. The key characteristic is that a system call is made, but that it doesn't usually force a context switch. System calls are generally on the order of 100s of nanoseconds or more, and it shows in the results.

There are more still more levels. That is, it can still get worse.

The next level is when the concurrent operations cause a _context switch_. The yielding lock wasn't resulting in many actual context switches, since the CPUs are not oversubscribed and so there usually is no other runnable process (except for the occasional background process), so the current thread stays on the CPU. However, this burns a lot of CPU. Let's try a _blocking lock_ instead.

**Blocking locks:**  
A more resource friendly design, and one that will often perform better is a _blocking_ lock. Rather than busy waiting, these locks as the OS to remove them from the scheduling queue until the lock becomes available. On Linux, the [`futex(3)`](http://man7.org/linux/man-pages/man2/futex.2.html) system call is the preferred way to accomplish this, while on Windows you have the [`WaitFor*Object`](https://docs.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject) API family. Above the OS interfaces, things like C++'s `std::condition_varibale` provide a general purpose mechanism to wait until a condition is true.
{: .info}

Our first blocking lock is a ticket based design similar to the earlier tick lock, except that it uses a condition variable to block when it detects that it isn't going to get served right away:

~~~c++
void blocking_ticket::lock() {
    auto ticket = dispenser++;
    
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

The main difference with the earlier lock is that when we don't acquire the lock immediately (we don't return at the location marked `// uncontended case`), take the mutex associated with the condition variable and every time we are worken, we check if it is our turn. We might get woken many times, because this lock suffers from the _thundering herd_ problem where every waiter is woken on `unlock()` even though only one will ultimately be able to get the lock.

We'll try a second design too, that doesn't suffer from thundering herd. This is a queued lock, where each lock waits it's own node in a queue of waiters, so only the new lock owner is woken up in unlock. If you're interested in the implementation you can find it here [TODO include code].

Here's how our new locks perform against the existing crowd:

{% include svg-fig.html file="more-fair" alt="Increment Costs: Fair Blocking" %}

You're probably seeing the pattern now: performance is terrible. About an order of magniute slower than the yielding approach, which was already slower than the earlier approaches, which are themselves slivers a few pixels high on the plots. The queued version of the lock does slightly better at increasing thread counts, as might be expected from the hack of the thundering herd effect, but is still very slow because the primary problem isn't thundering herd, but rather a [_lock convoy_](https://en.wikipedia.org/wiki/Lock_convoy).

Unlike unfair locks, fair locks result can result in sustained convoys involving only a single lock, once the contention reaches a certain point[^hyst]. Consider what happens when two threads, A and B, try to acquire the lock repeatedly. Let's say A wins the first time, and so B has to wait, and so blocks (and is descheduled by the OS). Now, A unlocks the lock and sees B waiting and wakes it. A is still running and soon tries to get the lock again, but it can't because the lock is _fair_: A can't jump the queue and acquire the lock before B goes. Of course, B is going to be a while: it needs to be woken by the scheduler and this takes 1,000s of nanoseconds. Now B wakes and gets the lock, and the same scenario repeats itself with the roles reversed. The upshot is that there is a full context switch for each acquisition of the lock.

Unfair locks avoid this problem because they all queue jumping: in the scenario above, A (or any other thread) could re-acquire the lock after unlocked it, before B got its chance. So the use of the shared resource doesn't grind to a halt while B wakes up.

So, are you tired of seeing mostly-white plots where the newly introduced algorithm relegates the rest of the pack to little chunks of color near the x-axis, yet?

I've just got one more left on the slow end of the scale. Unlike the other examples, I haven't seen something _this_ bad in real life, but I'm sure something similar is out there _somewhere_. Here's a ticket lock which is identical to the [first ticket lock we saw](#ys-lock), except that the `sched_yield();` is replaced by `;`. That is, it busy waits instead of yielding (TODO: source). Here's how this one performs (TODO: color, name):

{% include svg-fig.html file="ts-4" alt="Increment Costs: Ticket Spin" %}

What? That doesn't look too bad at all. In fact, it's in line with the level TODO crew, the fastest we've seen so far[^huh].

The picture changes if we show the results for up to 6 threads, rather than just 4. Since I have 4 available logical processors, this means that not all the test threads will be ale to run at once:

{% include svg-fig.html file="ts-6" alt="Increment Costs: Ticket Spin (6 threads)" %}

Now it becomes clear why this level is called _catastrophic_. We aren't just one order of magnitude slower, but two orders slower than the second slowest solution. We are about _eighty thousand times_ slower than the fastest solution seen so far[^fastest]. Since it performed fine with fewer threads, this kind of thing could easily escape notice until it takes down your service under load.

What happens here? It's similar to the lock convoy described above: all the threads queue on the lock and acquire it in a round-robin order due to the fair design. The difference is that threads don't block when they can't acquire the lock. Imagine 5 threads, `T1`, `T2`, ..., `T5`, where `T5` is the one not currently running. As soon as `T5` is the thread that needs the acquire the lock next (i.e., `T5`'s saved ticket value is equal to `dispensing`), nothing will happen because `T1` through `T4` are busily spinning away. The OS scheduler sees no reason to interrupt them until their time slice expires. Time slices are usually measured in millseconds. Once one thread is preempted, say `T1`, `T5` will get the chance to run, but at most 4 total acquisitions can happen (`T5`, plus any of `T2`, `T3`, `T4`), before it's `T1`'s turn. `T1` is waiting for their chance to run again, but since everyone is spinning this won't occur until another time slice expires.

So the lock can only be acquired a few times (at most `$(nproc)` times), or as little as once[^once], every time slice. Modern Linux using [CFS](https://en.wikipedia.org/wiki/Completely_Fair_Scheduler) doesn't have a fixed timeslice, but on my system, `sched_latency_ns` is 18,000,000 which means that we expect two threads competing for one core to get a typical timeslice of 9 ms. The measured numbers are roughly consistent with a timeslice of single-digit milliseconds.

Another way of thinking about this is that in this over-subscription scenario, the ticket spin lock implies roughly the same number of context switches as the blocking ticket lock[^perf], but in the former case each context switch comes with a giant delay caused by the need to exhaust the timeslice, while in the blocking case we are only limited by how fast a context switch can occur. Interestingly, although this benchmark uses 100% CPU on every core, the performance of in the oversubscribed case doesn't almost depend on your CPU speed! Performance is approximately the same if I throttle my CPU to 1 GHz, or enable turbo up to 3.5 GHz. On the other the benchmark performance scales strong with adjustment to `sched_latency_ns` (and `sched_min_granularity_ns` if the former is set low enough): lower scheduling latency values gives proportionally better performance as the timeslices shrink.

Let's move on to scenarios that are _faster_ than the use of vanilla atomic add.

The next level down, is when atomics operations are used but there is no contention, either by design or by luck. You might have noticed that so far I've only shown results for at least two threads. That's because the 1 thread case involves no contention, and so every implementation so far is level TODO if run on a single thread[^notexx].

Here's the results for all the implementations we've look at so far, for a single thread:

{% include svg-fig.html file="single" alt="Increment Costs: Single Threaded" %}

The fastest implementations run in about 10 nanoseconds, which is 5x faster than the fastest solution at for 2 or more threads. The number overlaid on each bar is the number of atomic operations[^atomhow] the implementation makes per increment. It is obvious that the performance is almost directly proportional to the number of atomic instructions.

Performance does not have much of a relationship with the total number of instructions of any type, which vary a lot even between algorithms with the same performance as the following table shows:

| Algorithm        | Atomics | Instructions   | Performance |
| ---------------- | -------:| -------------: | -----------:|
| mutex add        |     2   |  64            |      ~21 ns |
| atomic add       |     1   |   4            |      ~10 ns |
| cas add          |     1   |   7            |      ~10 ns |
| ticket yield     |     1   |  13            |      ~10 ns |
| ticket blocking  |     3   | 107            |      ~32 ns |
| queued fifo      |     4   | 167            |      ~45 ns |
| ticket spin      |     1   |  13            |      ~10 ns |
| mutex3           |     2   |  17            |      ~20 ns |

TODO redo the prose with the final instruction numbers

In particular, note that "mutex add" has 6.5x the number of instructions compared to "CAS add" yet is runs at half the speed, in line with the 2:1 ratio of atomics. Similarly, "ticket yield" and "ticket spin" have the same performance as "atomic add" and "cas add" despite having 2x the number of instructions, in line with them all having a single atomic operation.

The last row in the table shows the performance of `mutex3`, an implementation we haven't discussed. It is a blocking mutex offering similar functionality to `std::mutex`, described in [Futexes Are Tricky](https://akkadia.org/drepper/futex.pdf). Because of it doesn't need to pass through two layers of abstraction[^twolayer], has only about one third the instruction count of `std::mutex`, yet performance is almost exactly the same, differing by less than 10%. So the idea that you can almost ignore things that are in a lower cost tier seems to hold here. Don't take this too far: if you design a lock with a single atomic operation but 1,000 other instructions, it is not going to be fast.

Here it is important to note that the change in level of our various functions didn't require a change in implementation. Rather we simply changed (by fiat) the contention level from "very high" to "zero". So the level doesn't depend only on the code, but also this external factor. Of course, that's not very satisfying: we can't simply ban multi-threaded operations in practice.

So can we drop to this level TODO even under concurrent calls from multiple threads? Sure.


 
{% include other-posts.md %}

---
---
<br>

{% include glossary.md %}

[^twolayer]: Actually three layers, [libstc++](https://github.com/gcc-mirror/gcc/blob/4ff685a8705e8ee55fa86e75afb769ffb0975aea/libstdc%2B%2B-v3/include/bits/std_mutex.h#L98), then [libgcc](https://github.com/gcc-mirror/gcc/blob/4ff685a8705e8ee55fa86e75afb769ffb0975aea/libgcc/gthr-posix.h#L775) and then finally pthreads. I'll count the first two as one though because those can all inline into the caller. Based on a rough accounting, probably 75% of the instruction count comes from pthreads, the rest from the other two layers. The pthreads mutexes are more general purpose than what `std::mutex` alone (e.g., they support recursion), and the features are configured at runtime on a per-mutex basis, so that explains a lot of the additional work these functions are doing. It's only due to cost of atomic operations that `std::mutex` doesn't take a significant penalty compared to a more svelte design.

[^atomhow]: On Intel hardware you can use details.sh TODO:link to collect the atomic instruction count easily, take advantage of the `mem_inst_retired.lock_loads` performance counter.

[^notexx]: This won't always _necessarily_ be the case. You could write a primitive that always makes a system call, putting it level TODO, even if there is no contention, but here I've made to always fast-path the no-contention case.

[^perf]: In fact, you can measure this with `perf` and see that the total number of context switches is usually within a factor of 2 for both tests, when oversubscribed.

[^fastest]: That's for six threads, where the atomic add runs in about 100 ns and this lock takes more than 8,000,000 ns (more than 8 milliseconds).

[^once]: In fact, the _once_ scenario is the most likely, since one would assume with homogenous threads the scheduler will approximate something like round-robin scheduling. So the thread that is descheduled is most likely the one that is also closest to the head of the lock queue, because it had been spinning the longest.

[^huh]: Actually I find it remarkable that this performs about as well as the CAS-based atomic add, since the fairness necessarily implies that the lock is acquired in a round-robin order, so the cache line with the lock must at a minimum move to around to each acquiring thread. This is a real stress test of the arbitrary and coherency mechanisms offered by the CPU.

[^hyst]: An interesting thing about convoys is that they exhibit hysterisis: once you start having a convoy, they become self-sustaining, even if the conditions that started it are removed. Imagine two threads that lock a common lock for 1 nanosecond every 10,000 nanoseconds. Contention is low: the chance of any particular lock acquisition being contended is 0.01%. However, as soon as a contended acquisition occurs, the lock effectively becomes held for the amount of time it takes to do a full context switch (for the losing thread to block, and then to wake up). If that's longer than 10,000 nanoseconds, the convoy will sustain itself indefinitely, until something happens to break the loop (e.g., one thread doing deciding to work on something else). A restart also "fixes" it, which is one of many possible exlanations for processes that suddenly shoot to 100% CPU (but are still making progress), but can be fixed by a restart. Everything becomes worse with more than two threads, too.

[^parisc]: Some hardware supports very limited atomic operations, which may be mostly useful _only_ for locking, although you can [get tricky](https://parisc.wiki.kernel.org/index.php/FutexImplementation).

[^atomicsup]: Many ISAs, including POWER and ARM, traditionally only included support for a CAS-like or [LL/SC](https://en.wikipedia.org/wiki/Load-link/store-conditional) operation, without specific support for more specific atomic arithmetic operations. The idea, I think, was that you could build any operation you want on top of of these primitives, at the cost of "only" a small retry loop and that's more RISC-y, right? This seems to be changing as ARMv8.1 got a bunch of atomic operations.

[^java]: From it's introduction through Java 7, the `AtomicInteger` and related classes in Java implemented all their atomic operations on top of a CAS loop, as CAS was the only primitive implemented as an intrinsic. In Java 8, almost exactly a decade later, these were finally replaced with dedicated atomic RMWs where possible, with [good results](http://ashkrit.blogspot.com/2014/02/atomicinteger-java-7-vs-java-8.html).

[^l3]: On my system and most (all?) modern Intel systems this is essentially the L3 cache, as the caching home agent (CHA) lives in or adjacent to the L3 cache.

[^inter]: This doesn't imply that each atomic operation needs to take 70 cycles under contention: a single core could do _multiple_ operations on the cache line after it gains exclusive ownership, so the cost of obtained the line could be amortized over all of these operations. How much of this occurs is a measure of fairness: a very CPU will not let any core monopolize the line for long, but this makes high concurrent benchmarks like this slower. Recent Intel CPUs seem quite fair in this sense.

