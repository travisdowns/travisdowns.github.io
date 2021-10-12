---
layout: post
assets: /assets
notables: true
---

{% include post-boilerplate.liquid %}

{% capture apath %}{{ '/assets' | relative_url }}{% endcapture %}
{% assign fname = 'rabbit3.png' %}
{% assign fpath = '/assets/' | append: fname %}

<!-- ![Fast Rabbit]({% link {{apath}}/rabbit3.png %}){: {% imagesize fpath:props %} } -->

{% include svg-fig.html src='rabbit3.png' %}

<img src="https://dummyimage.com/740x100/000/fff&text=Fallback" srcset="
    https://dummyimage.com/740x100/000/fff&text=740w   740w,
    https://dummyimage.com/1480x200/000/fff&text=1480w 1480w,
    https://dummyimage.com/2220x300/000/fff&text=2220w 2220w,
    https://dummyimage.com/2960x400/000/fff&text=2960w 2960w,
    https://dummyimage.com/3700x500/000/fff&text=3700w 3700w,
    https://dummyimage.com/4440x600/000/fff&text=4440w 4440w,
    "
    sizes="(max-width: 800px) calc(100vw - 30px), 740px"
    alt="dummy">

---

<div style="font-family: monospace; white-space:pre-wrap;">
    Window inner dims : <span id="inner"></span>
    Window client dims: <span id="client"></span>
    Device pixel ratio: <span id="dpr"></span>
    Content width     : <span id="cow"></span>
    Calc'd width      : <span id="caw"></span> 
</div>

<!-- we'll get the width of this div as Content width-->
<div id="test-div"></div>

<style>
#calc-div { width: 740px; }
@media (max-width: 800px) {
    #calc-div { width: calc(100vw - 30px); }
}
</style>

<!-- this div is for our calculated width -->
<div id="calc-div" style=""><p></p></div>

<script>

    function reportWindowSize() {
        document.querySelector('#inner').textContent = window.innerWidth + ' x ' + window.innerHeight;
        document.querySelector('#client').textContent = document.documentElement.clientWidth + ' x ' + document.documentElement.clientHeight;
        document.querySelector('#dpr').textContent = window.devicePixelRatio;
        document.querySelector('#cow').textContent = document.querySelector('#test-div').offsetWidth + 'px';
        document.querySelector('#caw').textContent = document.querySelector('#calc-div').offsetWidth + 'px';
    }
    
    reportWindowSize();
    window.onresize = reportWindowSize;
</script>
