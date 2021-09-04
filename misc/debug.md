---
layout: default
---

Last rebuild (`site.time`): {{ site.time }}

| Property | Value |
| -----------------|
| jekyll.environment  | {{ jekyll.environment }} |
| site.url | {{ site.url }} |
| site.baseurl  | {{ site.baseurl }} |
| site.markdown  | {{ site.markdown }} |
| site.kramdown  | `{{ site.kramdown }}` |
| site.rss | {{ site.rss }} |


relative foo: {{ '/foo' | relative_url }}

[link](http://www.example.com)


[bad link]({{ 'notexist.html' | relative_url}})  
[self link]({{ 'misc/debug.html' | relative_url}})


<style>
.color-check:after   { content: 'unset'; }

@media (prefers-color-scheme: dark) {
  .color-check:after   { content: 'dark mode'; }
}

@media (prefers-color-scheme: light) {
  .color-check:after   { content: 'light mode'; }
}
</style>

<p class="color-check">prefers-color-scheme: </p>

<style>
#props span, .mono {
    font-family: monospace;
    white-space: pre;
}

#props span {
    background-color: lightgrey;
}
</style>

<div class="mono">
<script>
        document.write('location.href    : ' + location.href + '<br>')
        document.write('window.location  : ' + window.location + '<br>')
        document.write('document.referrer: ' + document.referrer + '<br>')
    </script>
</div>
