---
layout: post
title:  "Where do interrupts happen?"
category: blog
tags: [performance, benchmarking]
assets: /assets/interrupts
image:  /assets/interrupts/Intel_8259.png
twitter:
  card: summary
---

<style>
.perf-annotate {
  white-space: pre-wrap;
  word-wrap: break-word;
  font-family: monospace;
  background-color: Gainsboro;
  margin-bottom: 20px;
}
</style>

On Twitter, Paul Khuong [asks](https://twitter.com/pkhuong/status/1162832557030948864): _Has anyone done a study on the distribution of interrupt points in OOO processors?_

Personally, I'm not aware of any such study for modern x86, and I have also wondered the same thing. In particular, when a CPU receives an externally triggered[^triggered] interrupt, at what point in the instruction stream is the CPU interrupted?

For a simple 1-wide in-order, non-pipelined CPU the answer might be as simple as: the CPU is interrupted either before or after instruction that is currently running[^twoc]. For anything more complicated it's not going to be easy. On a modern out-of-order processor there may be hundreds of instructions in-flight at any time, some waiting to execute, a dozen or more currently executing, and others waiting to retire. From all these choices, which instruction will be chosen as the victim?

Among other reasons, the answer is interesting because it helps us understand how useful the exact interrupt position is when profiling via interrupt: can we extract useful information from the instruction position, or should we only trust it at a higher level (e.g., over regions of say 100s of instructions).

So let's go figure out how interruption works, at least on my Skylake i7-6700HQ, by compiling a bunch of small pure-asm programs and running them. The source for all the tests is available in the associated [git repo](https://github.com/travisdowns/interrupt-test) so you can follow along or write your own tests. All the tests are written in assembly because we want full control over the instructions and because they are all short and simple. In any case, we can't avoid assembly-level analysis when talking about what instructions get interrupted.

First, let's take a look at some asm that doesn't have any instruction that sticks out in any way at all, just a bunch of `mov` instructions[^whymov]. The key part of the [source](https://github.com/travisdowns/interrupt-test/blob/master/indep-mov.asm) looks like this[^srcnotes]:

~~~nasm
.loop:

%rep 10
	mov  eax, 1
	mov  ebx, 2
	mov  edi, 3
	mov  edx, 4
	mov  r8d, 5
	mov  r9d, 6
	mov r10d, 7
	mov r11d, 8
%endrep

	dec rcx
	jne .loop
~~~

Just constant moves into registers, 8 of them repeated 10 times. This code executes with an expected and measured[^ipc] IPC of 4.

Next, we get to the meat of the investigation. We run the binary using `perf record -e task-clock ./indep-mov`, which will periodically interrupt the process and record the IP. Next, we examine the interrupted locations with `perf report`[^acommand]. Here's the output (hereafter, I'm going to cut out the header and just show the samples):

<div class="perf-annotate">
 Samples |	Source code &amp; Disassembly of indep-mov for task-clock (1769 samples, percent: local period)
-----------------------------------------------------------------------------------------------------------
         :
         :            Disassembly of section .text:
         :
         :            00000000004000ae &lt;_start.loop&gt;:
         :            _start.loop():
         :            indep-mov.asm:15
<span style="color:green;">      16</span> : <span style="color:purple;">  4000ae:</span><span style="color:blue;">       mov    eax,0x1</span>
<span style="color:green;">      15</span> : <span style="color:purple;">  4000b3:</span><span style="color:blue;">       mov    ebx,0x2</span>
<span style="color:green;">      22</span> : <span style="color:purple;">  4000b8:</span><span style="color:blue;">       mov    edi,0x3</span>
<span style="color:green;">      25</span> : <span style="color:purple;">  4000bd:</span><span style="color:blue;">       mov    edx,0x4</span>
<span style="color:green;">      14</span> : <span style="color:purple;">  4000c2:</span><span style="color:blue;">       mov    r8d,0x5</span>
<span style="color:green;">      19</span> : <span style="color:purple;">  4000c8:</span><span style="color:blue;">       mov    r9d,0x6</span>
<span style="color:green;">      25</span> : <span style="color:purple;">  4000ce:</span><span style="color:blue;">       mov    r10d,0x7</span>
<span style="color:green;">      18</span> : <span style="color:purple;">  4000d4:</span><span style="color:blue;">       mov    r11d,0x8</span>
<span style="color:green;">      22</span> : <span style="color:purple;">  4000da:</span><span style="color:blue;">       mov    eax,0x1</span>
<span style="color:green;">      24</span> : <span style="color:purple;">  4000df:</span><span style="color:blue;">       mov    ebx,0x2</span>
<span style="color:green;">      20</span> : <span style="color:purple;">  4000e4:</span><span style="color:blue;">       mov    edi,0x3</span>
<span style="color:green;">      29</span> : <span style="color:purple;">  4000e9:</span><span style="color:blue;">       mov    edx,0x4</span>
<span style="color:green;">      28</span> : <span style="color:purple;">  4000ee:</span><span style="color:blue;">       mov    r8d,0x5</span>
<span style="color:green;">      18</span> : <span style="color:purple;">  4000f4:</span><span style="color:blue;">       mov    r9d,0x6</span>
<span style="color:green;">      21</span> : <span style="color:purple;">  4000fa:</span><span style="color:blue;">       mov    r10d,0x7</span>
<span style="color:green;">      19</span> : <span style="color:purple;">  400100:</span><span style="color:blue;">       mov    r11d,0x8</span>
<span style="color:green;">      26</span> : <span style="color:purple;">  400106:</span><span style="color:blue;">       mov    eax,0x1</span>
<span style="color:green;">      18</span> : <span style="color:purple;">  40010b:</span><span style="color:blue;">       mov    ebx,0x2</span>
<span style="color:green;">      29</span> : <span style="color:purple;">  400110:</span><span style="color:blue;">       mov    edi,0x3</span>
<span style="color:green;">      19</span> : <span style="color:purple;">  400115:</span><span style="color:blue;">       mov    edx,0x4</span>
</div>

The first column shows the number of interrupts received for each instruction. Specially, the number of times an instruction would be the next instruction to execute following the interrupt.

Without doing any deep statistical analysis, I don't see any particular pattern here. Every instruction gets its time in the sun. Some columns have somewhat higher values than others, but if you repeat the measurements, the columns with higher values don't necessarily repeat.

We can try the exact same thing, but with `add` instructions [like this](https://github.com/travisdowns/interrupt-test/blob/master/indep-add.asm):

~~~nasm
	add  eax, 1
	add  ebx, 2
	add  edi, 3
	add  edx, 4
	add  r8d, 5
	add  r9d, 6
	add r10d, 7
	add r11d, 8
~~~

We expect the execution behavior to be similar to the `mov` case: we _do_ have dependency chains here but 8 separate ones (for each destination register) for a 1 cycle instruction so there should be little practical impact. Indeed, the results are basically identical to the last experiment so I won't show them here (you can see them yourself with the `indep-add` test).

Let's get moving here and try something more interesting. This time we will again use all `add` instructions, but two of the adds will depend on each other, while the other two will be independent. So the chain shared by those two adds will be twice as long (2 cycles) as the other chains (1 cycle each). [Like this](https://github.com/travisdowns/interrupt-test/blob/master/add-2-1-1.asm):

~~~nasm
    add  rax, 1 ; 2-cycle chain
    add  rax, 2 ; 2-cycle chain
    add  rsi, 3
    add  rdi, 4
~~~

Here the chain through `rax` should limit the throughput of the above repeated block to 1 per 2 cycles, and indeed I measure an IPC of 2 (4 instructions / 2 cycles = 2 IPC).

Here's the interrupt distribution:
<div class="perf-annotate">
       0 : <span style="color:purple;">  4000ae:</span><span style="color:blue;">       add    rax,0x1</span>
<span style="color:green;">      82</span> : <span style="color:purple;">  4000b2:</span><span style="color:blue;">       add    rax,0x2</span>
<span style="color:green;">     112</span> : <span style="color:purple;">  4000b6:</span><span style="color:blue;">       add    rsi,0x3</span>
       0 : <span style="color:purple;">  4000ba:</span><span style="color:blue;">       add    rdi,0x4</span>
       0 : <span style="color:purple;">  4000be:</span><span style="color:blue;">       add    rax,0x1</span>
<span style="color:green;">      45</span> : <span style="color:purple;">  4000c2:</span><span style="color:blue;">       add    rax,0x2</span>
<span style="color:green;">     144</span> : <span style="color:purple;">  4000c6:</span><span style="color:blue;">       add    rsi,0x3</span>
       0 : <span style="color:purple;">  4000ca:</span><span style="color:blue;">       add    rdi,0x4</span>
       0 : <span style="color:purple;">  4000ce:</span><span style="color:blue;">       add    rax,0x1</span>
<span style="color:green;">      44</span> : <span style="color:purple;">  4000d2:</span><span style="color:blue;">       add    rax,0x2</span>
<span style="color:green;">     107</span> : <span style="color:purple;">  4000d6:</span><span style="color:blue;">       add    rsi,0x3</span>

(pattern repeats...)
</div>

This is certainly something new. We see that *all* the interrupts fall on the middle two instructions, one of which is part of the addition chain and one which is not. The second of the two locations also gets about 2-3 times as many interrupts as the first.

### A Hypothesis

Let's make a hypothesis now so we can design more tests.

Let's guess that interrupts _select_ instructions which are the oldest unretired instruction, and that this _selected_ instruction is allowed to complete hence samples fall on the next instruction (let us call this next instruction the _sampled_ instruction). I am making the distinction between _selected_ and _sampled_ instructions rather than just saying "interrupts sample instructions that follow the oldest unretired instruction" because we are going to build our model almost entirely around the _selected_ instructions, so we want to name them. The characteristics of the ultimately sampled instructions (except their positioning after _selected_ instructions) hardly matters[^untrue].

Without a more detailed model of instruction retirement, we can't yet explain everything we see - but the basic idea is instructions that take longer, hence are more likely to be the oldest unretired instruction, are the ones that get sampled. In particular, if there is a critical dependency chain, instructions in that chain are likely[^likely] be sampled at some point[^notonly].

Let's take a look at some more examples. I'm going to switch using `mov rax, [rax]` as my long latency instruction (4 cycles latency) and `nop` as the filler instruction not part of any chain. Don't worry, `nop` has to allocate and retire just like any other instruction: it simply gets to skip execution. You can build all these examples with a real instruction like `add` and they'll work in the same way[^whynop].

Let's [take a look](https://github.com/travisdowns/interrupt-test/blob/master/load-nop10.asm) at a load followed by 10 `nops`:

~~~nasm
.loop:

%rep 10
    mov  rax, [rax]
    times 10 nop
%endrep

    dec rcx
    jne .loop
~~~

The result:

<div class="perf-annotate">
       0 : <span style="color:purple;">  4000ba:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      33</span> : <span style="color:purple;">  4000bd:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000be:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000bf:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c0:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      11</span> : <span style="color:purple;">  4000c1:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c2:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c3:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c4:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      22</span> : <span style="color:purple;">  4000c5:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c6:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c7:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:green;">      15</span> : <span style="color:purple;">  4000ca:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cb:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cc:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cd:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      13</span> : <span style="color:purple;">  4000ce:</span><span style="color:blue;">       nop</span>
       1 : <span style="color:purple;">  4000cf:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d0:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d1:</span><span style="color:blue;">       nop</span>
<span style="color:red;">      35</span> : <span style="color:purple;">  4000d2:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d3:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d4:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:green;">      16</span> : <span style="color:purple;">  4000d7:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d8:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d9:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000da:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      14</span> : <span style="color:purple;">  4000db:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000dc:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000dd:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000de:</span><span style="color:blue;">       nop</span>
<span style="color:red;">      31</span> : <span style="color:purple;">  4000df:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e0:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e1:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:green;">      22</span> : <span style="color:purple;">  4000e4:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e5:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e6:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e7:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      16</span> : <span style="color:purple;">  4000e8:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000e9:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000ea:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000eb:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      24</span> : <span style="color:purple;">  4000ec:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000ed:</span><span style="color:blue;">       nop</span>
</div>

The _selected_ instructions are the long-latency `mov`-chain, but also two specific `nop` instructions out of the 10 that follow: those which fall 4 and 8 instructions after the `mov`. Here we can see the impact of retirement throughput. Although the `mov`-chain is the only thing that contributes to _execution_ latency, this Skylake CPU can [only retire](https://www.realworldtech.com/forum/?threadid=161978&curpostid=162222) up to 4 instructions per cycle (per thread). So when the `mov` finally retires, there will be two cycles of retiring blocks of 4 `nop` instructions before we get to the next `mov`:

~~~nasm
;                            retire cycle
mov    rax,QWORD PTR [rax] ; 0 (execution limited)
nop                        ; 0
nop                        ; 0
nop                        ; 0
nop                        ; 1 <-- selected nop
nop                        ; 1
nop                        ; 1
nop                        ; 1
nop                        ; 2 <-- selected nop
nop                        ; 2
nop                        ; 2
mov    rax,QWORD PTR [rax] ; 4 (execution limited)
nop                        ; 4
nop                        ; 4
~~~

In this example, the retirement of `mov` instructions are "execution limited" - i.e., their retirement cycle is determined by when they are done executing, not by any details of the retirement engine. The retirement of the other instructions, on the other hand, is determined by the retirement behavior: they are "ready" early but cannot retire because the in-order retirement pointer hasn't reached them yet (it is held up waiting for the `mov` to execute).

So those selected `nop` instructions aren't particularly special: they aren't slower than the rest or causing any bottleneck. They are simply selected because the pattern of retirement following the `mov` is predictable. Note also that it is the _first_ `nop` that in the group of 4 that would otherwise retire that is selected[^already].

This means that we can construct [an example](https://github.com/travisdowns/interrupt-test/blob/master/load-add2.asm) where an instruction on the critical path never gets selected:

~~~nasm
%rep 10
    mov  rax, [rax]
    nop
    nop
    nop
    nop
    nop
    add  rax, 0
%endrep
~~~

The results:

<div class="perf-annotate">
       0 : <span style="color:purple;">  4000ba:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      94</span> : <span style="color:purple;">  4000bd:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000be:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000bf:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c0:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      17</span> : <span style="color:purple;">  4000c1:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c2:</span><span style="color:blue;">       add    rax,0x0</span>
       0 : <span style="color:purple;">  4000c6:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      78</span> : <span style="color:purple;">  4000c9:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000ca:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cb:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cc:</span><span style="color:blue;">       nop</span>
<span style="color:green;">      18</span> : <span style="color:purple;">  4000cd:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000ce:</span><span style="color:blue;">       add    rax,0x0</span>
</div>

The `add` instruction is on the critical path: it increases the execution time of the block from 4 cycles to 6 cycles[^4to6], yet it is never selected. The retirement pattern looks like:
<a name="lookhere"></a>
~~~nasm
                        /- scheduled
                       |  /- ready
                       |  |  /- complete
                       |  |  |  /- retired
    mov  rax, [rax]  ; 0  0  5  5 <-- selected
    nop              ; 0  0  0  5 <-- sample
    nop              ; 0  0  0  5
    nop              ; 0  0  0  5
    nop              ; 1  1  1  6 <-- selected
    nop              ; 1  1  1  6 <-- sampled
    add  rax, 0      ; 1  5  6  6
    mov  rax, [rax]  ; 1  6 11 11 <-- selected
    nop              ; 2  2  2 11 <-- sampled
    nop              ; 2  2  2 11
    nop              ; 2  2  2 11
    nop              ; 2  2  2 12 <-- selected
    nop              ; 3  3  3 12 <-- sampled
    add  rax, 0      ; 3 11 12 12
    mov  rax, [rax]  ; 3 12 17 17 <-- selected
    nop              ; 3  3  3 17 <-- sampled
~~~

On the right hand side, I've annotated each instruction with several key cycle values, described below.

The _scheduled_ column indicates when the instruction enters the scheduler and hence could execute if all its dependencies were met. This column is very simple: we assume that there are no front-end bottlenecks and hence we schedule (aka "allocate") 4 instructions every cycle. This part is in-order: instructions enter the scheduler in program order.

The _ready_ column indicates when all dependencies of a scheduled instruction have executed and hence the instruction is ready to execute. In this simple model, an instruction always begins executing when it is ready. A more complicated model would also need to model contention for execution ports, but here we don't have any such contention. Instruction readiness occurs _out of order_: you can see that many instructions become ready before older instructions (e.g., the `nop` instructions are generally ready before the preceding `mov` or `add` instructions). To calculate this column take the maximum of the _ready_ column for this instruction and the _completed_ column for all previous instructions whose outputs are inputs to this instruction.

The _complete_ column indicates when an instruction finishes execution. In this model it simply takes the value of the _ready_ column plus the instruction latency, which is 0 for the `nop` instructions (they don't execute at all, so they have 0 effective latency), 1 for the `add` instruction and 5 for the `mov`. Like the _ready_ column this happens out of order.

Finally, the _retired_ column, what we're really after, shows when the instruction retires.  The rule is fairly simple: an instruction cannot retire until it is complete, and the instruction before it must be retired or retiring on this cycle. No more than 4 instructions can retire in a cycle. As a consequence of the "previous instruction must retired" part, this column is only increasing and so like the first column, retirement is _in order_.

Once we have the _retired_ column filled out, we can identify the `<-- selected` instructions[^possibly]: they are the ones where the retirement cycle increases. In this case, selected instructions are always either the `mov` instruction (because of its long latency, it holds up retirement), or the fourth `nop` after the `mov` (because of the "only retire 4 per cycle" rule, this `nop` is at the head of the group that retires in the cycle after the `mov` retires). Finally, the _sampled_ instructions which are those will actually show up in the interrupt report are simply the instruction following each selected instruction.

Here, the `add` is never selected because it executes in the cycle after the `mov`, so it is eligible for retirement in the next cycle and hence doesn't slow down retirement and so doesn't behave much differently than a `nop` for the purposes of retirement. We can change the position of the `add` slightly, so it falls in the same 4-instruction retirement window as the `mov`, [like this](https://github.com/travisdowns/interrupt-test/blob/master/load-add3.asm):

~~~nasm
%rep 10
    mov  rax, [rax]
    nop
    nop
    add  rax, 0
    nop
    nop
    nop
%endrep
~~~

We've only slid the `add` up a few places. The number of instructions is the same and this block executes in 6 cycles, identical to the last example. However, the `add` instruction now always gets selected:

<div class="perf-annotate">
<span style="color:green;">      21</span> : <span style="color:purple;">  4000ba:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      54</span> : <span style="color:purple;">  4000bd:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000be:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000bf:</span><span style="color:blue;">       add    rax,0x0</span>
<span style="color:green;">      15</span> : <span style="color:purple;">  4000c3:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c4:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c5:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000c6:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      88</span> : <span style="color:purple;">  4000c9:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000ca:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000cb:</span><span style="color:blue;">       add    rax,0x0</span>
<span style="color:green;">      14</span> : <span style="color:purple;">  4000cf:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d0:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d1:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d2:</span><span style="color:blue;">       mov    rax,QWORD PTR [rax]</span>
<span style="color:red;">      91</span> : <span style="color:purple;">  4000d5:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d6:</span><span style="color:blue;">       nop</span>
       0 : <span style="color:purple;">  4000d7:</span><span style="color:blue;">       add    rax,0x0</span>
<span style="color:green;">      13</span> : <span style="color:purple;">  4000db:</span><span style="color:blue;">       nop</span>
</div>

Here's the cycle analysis and retirement pattern for this version:

~~~nasm
                        /- scheduled
                       |  /- ready
                       |  |  /- complete
                       |  |  |  /- retired
    mov  rax, [rax]  ; 0  0  5  5 <-- selected
    nop              ; 0  0  0  5 <-- sample
    nop              ; 0  0  0  5
    add  rax, 0      ; 0  5  6  6 <-- selected
    nop              ; 1  1  1  6 <-- sampled
    nop              ; 1  1  1  6
    nop              ; 1  1  1  6
    mov  rax, [rax]  ; 1  6 11 11 <-- selected
    nop              ; 2  2  2 11 <-- sampled
    nop              ; 2  2  2 11
    add  rax, 0      ; 2 11 12 12 <-- selected
    nop              ; 2  2  2 12 <-- sampled
    nop              ; 3  3  3 12
    nop              ; 3  3  3 12
    mov  rax, [rax]  ; 3 12 17 17 <-- selected
    nop              ; 3  3  3 17 <-- sampled
~~~

Now might be a good time to note that we also care about the actual sample counts, and not just their presence or absence. Here, the samples associated with the `mov` are more frequent than the samples associated with the `add`. In fact, there are about 4.9 samples for `mov` for every sample for `add` (calculated over the full results). That lines up almost exactly with the `mov` having a latency of 5 and the `add` a latency of 1: the `mov` will be the oldest unretired instruction 5 times as often as the `add`. So the sample counts are very meaningful in this case.

Going back to the cycle charts, we know the _selected_ instructions are those where the retirement cycle increases. To that we add that the _size_ of the increase determines their _selection weight_: the `mov` instruction has a weight of 5, since it jumps (for example) from 6 to 11 so it is the oldest unretired instruction for 5 cycles, while the `nop` instructions have a weight of 1.

This lets you measure _in-situ_ the latency of various instructions, as long as you have accounted for the retirement behavior. For example, measuring the following block (`rdx` is zero at runtime):

~~~nasm
    mov  rax, [rax]
    mov  rax, [rax + rdx]
~~~

Results in samples accumulating in a 4:5 ratio for the first and second lines: reflecting the fact that the second load has a latency of 5 due to complex addressing, while the first load takes only 4 cycles.

### Branches

What about branches? I don't find anything special about branches: whether taken or untaken they seem to retire normally and fit the pattern described above. I am not going to show the results but you can play with the [`branches` test](https://github.com/travisdowns/interrupt-test/blob/master/branches.asm) yourself if you want.

### Atomic Operations

What about atomic operations? Here the story does get interesting.

I'm going to use `lock add QWORD [rbx], 1` as my default atomic instruction, but the story seems similar for all of them. Alone, this instruction has a "latency"[^atomiclat] of 18 cycles. Let's put it in parallel with a couple of SIMD instructions that have a total latency of 20 cycles alone:

~~~nasm
    vpmulld xmm0, xmm0, xmm0
    vpmulld xmm0, xmm0, xmm0
    lock add QWORD [rbx], 1
~~~

This loop _still takes 20 cycles_ to execute. That is, the atomic costs nothing in runtime: the performance is the same if you comment it out. The `vpmulld` dependency chain is long enough to hide the cost of the atomic. Let's take a look at the interrupt distribution for this code:

<div class="perf-annotate">
       0 : <span style="color:purple;">  4000c8:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
      12 : <span style="color:purple;">  4000cd:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
      10 : <span style="color:purple;">  4000d2:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     244</span> : <span style="color:purple;">  4000d7:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  4000dc:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      26</span> : <span style="color:purple;">  4000e1:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     299</span> : <span style="color:purple;">  4000e6:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  4000eb:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      35</span> : <span style="color:purple;">  4000f0:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     277</span> : <span style="color:purple;">  4000f5:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  4000fa:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      33</span> : <span style="color:purple;">  4000ff:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     302</span> : <span style="color:purple;">  400104:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400109:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      33</span> : <span style="color:purple;">  40010e:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     272</span> : <span style="color:purple;">  400113:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400118:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      31</span> : <span style="color:purple;">  40011d:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     280</span> : <span style="color:purple;">  400122:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400127:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      40</span> : <span style="color:purple;">  40012c:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     277</span> : <span style="color:purple;">  400131:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400136:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      21</span> : <span style="color:purple;">  40013b:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     282</span> : <span style="color:purple;">  400140:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400145:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      35</span> : <span style="color:purple;">  40014a:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     291</span> : <span style="color:purple;">  40014f:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400154:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      35</span> : <span style="color:purple;">  400159:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:red;">     270</span> : <span style="color:purple;">  40015e:</span><span style="color:blue;">       dec    rcx</span>
       0 : <span style="color:purple;">  400161:</span><span style="color:blue;">       jne    4000c8 &lt;_start.loop&gt;</span>

</div>

The `lock add` instructions are selected by the interrupt close to 90% of the time, despite not contributing to the execution time. Based on our mental model, these instructions should be able to run ahead of the `vpmulld` loop and hence be ready to retire as soon as they are the head of the ROB. The effect that we see here is because `lock`-prefixed instructions are _execute at retire_. This is a special type of instruction that waits until it at the head of the ROB before it executes[^execretire].

So this instruction will _always_ take a certain minimum amount of time as the oldest unretired instruction: it never retires immediately regardless of the surrounding instructions. In this case, it means retirement spends most of its time waiting for the locked instructions, while execution spends most of its time waiting for the `vpmulld`. Note that the retirement time added by the locked instructions wasn't additive with that from `vpmulld`: the time it spends waiting for retirement is subtracted from the time that would otherwise be spent waiting on the multiplication retirement. That's why you end up with a lopsided split, not 50/50. We can see this more clearly if we double the number of multiplications to 4:

~~~nasm
    vpmulld xmm0, xmm0, xmm0
    vpmulld xmm0, xmm0, xmm0
    vpmulld xmm0, xmm0, xmm0
    vpmulld xmm0, xmm0, xmm0
    lock add QWORD [rbx], 1
~~~

This takes 40 cycles to execute, and the interrupt pattern looks like:

<div class="perf-annotate">
       0 : <span style="color:purple;">  4000c8:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
      18 : <span style="color:purple;">  4000cd:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      49</span> : <span style="color:purple;">  4000d2:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     133</span> : <span style="color:purple;">  4000d7:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     152</span> : <span style="color:purple;">  4000dc:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:green;">     263</span> : <span style="color:purple;">  4000e1:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  4000e6:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      61</span> : <span style="color:purple;">  4000eb:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     160</span> : <span style="color:purple;">  4000f0:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     168</span> : <span style="color:purple;">  4000f5:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:green;">     251</span> : <span style="color:purple;">  4000fa:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  4000ff:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      59</span> : <span style="color:purple;">  400104:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     166</span> : <span style="color:purple;">  400109:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     162</span> : <span style="color:purple;">  40010e:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:green;">     267</span> : <span style="color:purple;">  400113:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400118:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      60</span> : <span style="color:purple;">  40011d:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     160</span> : <span style="color:purple;">  400122:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     155</span> : <span style="color:purple;">  400127:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>
<span style="color:green;">     218</span> : <span style="color:purple;">  40012c:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
       0 : <span style="color:purple;">  400131:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">      58</span> : <span style="color:purple;">  400136:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     144</span> : <span style="color:purple;">  40013b:</span><span style="color:blue;">       vpmulld xmm0,xmm0,xmm0</span>
<span style="color:green;">     154</span> : <span style="color:purple;">  400140:</span><span style="color:blue;">       lock add QWORD PTR [rbx],0x1</span>

pattern continues...
</div>

The sample counts are similar for `lock add` but they've now increased to a comparable amount (in total) for the `vmulld` instructions[^uneven]. In fact, we can calculate how long the `lock add` instruction takes to retire, using the ratio of the times it was selected compared to the known block throughput of 40 cycles. I get about a 38%-40% rate over a couple of runs which corresponds to a retire time of 15-16 cycles, only slightly less than then back-to-back latency[^atomiclat] of this instruction.

Can we do anything with this information?

Well one idea is that it lets us fairly precisely map out the retirement timing of instructions. For example, we can set up an instruction to test, and a parallel series of instructions with a known latency. Then we observe what is selected by interrupts: the instruction under test or the end of the known-latency chain. Whichever is selected has longer retirement latency and the known-latency chain can be adjusted to narrow it down exactly.

Of course, this sounds way harder than the usual way of measuring latency: a long series of back-to-back instrucitons, but it does let us measure some things "in situ" without a long chain, and we can measure instructions that don't have an obvious way to chain (e.g,. have no output like stores or different-domain instructions).

### TODO

 - Explain the variable (non-self synchronizing) results in terms of retire window patterns
 - Check interruptible instructions
 - Check `mfence` and friends
 - Check the execution effect of atomic instructions (e.g., blocking load ports)

### Comments

Feedback of any type is welcome. I don't have a comments system[^comments] yet, so as usual I'll outsource discussion to [this HackerNews thread](https://news.ycombinator.com/item?id=20751186).


### Thanks and Attribution

Thanks to HN user rrss for pointing out errors in my cycle chart.

[Intel 8259 image](https://commons.wikimedia.org/wiki/File:Intel_8259.svg) by Wikipedia user German under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0).

{% include other-posts.md %}

---
---
<br>

[^twoc]: The two choices basically correspond to letting the current instruction finish, or aborting it in order to run the interrupt.

[^triggered]: By _externally triggered_ I mean pretty much any interrupt that doesn't result directly from the code currently running on the logical core (such as an `int` instruction or some fault/trap). So it includes includes timer interrupts, cross CPU inter-processor interrupts, etc.

[^srcnotes]: Here I show the full loop, and the `%rep` directive which repeats (unrolls) the contained block the specified number of times, but from this point on I may just show the inner block itself with the understanding that it is unrolled with `%rep` some number of times (to reduce the impact of the loop) and contained with a loop of ~1,000,000 iterations so we get a reasonable number of samples. For the exact code you can always refer to the [repo](https://github.com/travisdowns/interrupt-test).

[^whymov]: I use `mov` here to avoid creating any dependency chains, i.e., the destination of `mov` is _write-only_ unlike most x86 integer instructions which both read and write their first operand.

[^ipc]: In general I'll just say "this code executes like this" or "the bottleneck is this", without futher justification as the examples are usually simple with one obvious bottleneck. Even though I won't always mentioned it, I _have_ checked that the examples perform as expected, usually with a `perf stat` to confirm the IPC or cycles per iteration or whatever.

[^likely]: Originally I thought it was guaranteed that instructions on the critical path would be eligible for sampling, but it is not: later we construct an example where a critical instruction never gets selected.

[^notonly]: Note that I am specifically _not_ saying the only selected instructions will be from the chain. As we will see soon, retirement limits mean that unless the chain instructions are fairly dense (i.e., at least 1 every 4 instructions), other instructions may appear also.

[^whynop]: I use `nop` because it has no inputs or outputs so I don't have to be careful not to create dependency chains (e.g., ensuring each `add` goes to a distinct register), and it doesn't use any execution units, so we won't steal a unit from the chain on the critical path.

[^acommand]: The full command I use is something like `perfc annotate -Mintel --stdio --no-source --stdio-color --show-nr-samples`. For interactive analysis just drop the `--stdio` part to get the tui UI.

[^untrue]: Of course we will see that in some cases the _selected_ and _sampled_ instructions can actually be the same, in the case of interruptible instructions.

[^possibly]: Of course this doesn't mean the instruction _will_ be selected, we only have a few thousand interrupts over one million or more interrupts, so usually nothign happens at all. These are just the locations that are highly likely to be chosen when an interrupt does arrive.

[^already]: We have already seen this effect in all of the earlier examples: it is why the long-latency `add` is selected, even though that in the cycle that it retires the three subsequent instructions also retire. This behavior is nice because it ensures that longer latency instructions are generally selected, rather than some unrelated instruction (i.e., the usual skid is +1 not +4).

[^4to6]: The increase is from 4 to 6, rather than 4 to 5, because of +1 cycle for the `add` itself (obvious) and +1 cycle because any ALU instruction in the address computation path of a pointer chasing loop disables the 4-cycle load fast path (much less obvious).

[^atomiclat]: Latency is in scare quotes here because the apparent latency of atomic operations doesn't behave like most other instructions: if you measure the throughput of back-to-back atomic instructions you get higher performance if the instructions form a dependency chain, rather than if they don't! The latency of atomics doesn't fit neatly into an input-to-output model as their _execute at retirement_ behavior causes other bottlenecks.

[^execretire]: That's the simple way of looking at it: reality is more complex as usual. Locked instructions may execute some of their instructions before they are ready to retire: e.g., loading the the required value and the ALU operation. However, the key "unlock" operation which verifies the result of the earlier operations and commits the results, in an atomic way, happens at retire and this is responsible for the majority of the cost of this instruction.

[^uneven]: The uneven pattern among the `vpmulld` instructions is because the `lock add` instruction eats the retire cycles of the first `vpmulld` that occur after (they can retire quickly because they are already complete), so only the later ones have a full allocation.

[^comments]: If anyone has a recommendation or a if anyone knows of a comments system that works with static sites, and which is not Disqus, has no ads, is free and fast, and lets me own the comment data (or at least export it in a reasonable format), I am all ears.

{% include glossary.md %}
