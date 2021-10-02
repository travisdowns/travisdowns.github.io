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
| site.darkmode | {{ site.darkmode }} |

relative foo: {{ '/foo' | relative_url }}

[link](http://www.example.com)


[bad link]({{ 'notexist.html' | relative_url}})  
[self link]({{ 'misc/debug.html' | relative_url}})

---

<script>
    var refreshDebug = function() {
        document.getElementById('ls-check').textContent = DARKMODE.lsOk() ? 'OK' : 'FAILED';
        document.getElementById('dm-closed').textContent = sessionStorage.getItem('dm-closed') || '(unset)';
        document.getElementById('dm-close-count').textContent = DARKMODE.closeCount();
        document.getElementById('bar-used').textContent = localStorage.getItem('bar-used') || '(unset)';
    }

  window.addEventListener('DOMContentLoaded', function() {
    refreshDebug();
    document.getElementById('clear-closed').addEventListener('click',
      function() {
        sessionStorage.removeItem('dm-closed');
        refreshDebug();
      }
    );
    document.getElementById('clear-count').addEventListener('click',
      function() {
        localStorage.removeItem('dm-close-count');
        refreshDebug();
      }
    );
    document.getElementById('clear-bar-used').addEventListener('click',
      function() {
        localStorage.removeItem('bar-used');
        refreshDebug();
      }
    );
  });
</script>

<style>
.dm-debug button, .spacer {
  display: inline-block;
  width: 50px;
  margin-bottom: 5px;
}
</style>

<div style="font-size: 0.75em; font-family: monospace">
    <p><strong>Theme debugging:</strong></p>
    {%- include color-check.html -%}
    <div class="dm-debug" style="white-space: pre-wrap">
<span class="spacer"             > </span> localStorage        : <span id="ls-check"></span>
<button id="clear-closed"  >clear</button> dm-closed (session) : <span id="dm-closed"></span>
<button id="clear-count"   >clear</button> dm-close-count      : <span id="dm-close-count"></span>
<button id="clear-bar-used">clear</button> bar-used            : <span id="bar-used"></span>
    </div>
</div>

---

<div class="mono">
<script>
        document.write('location.href    : ' + location.href + '<br>')
        document.write('window.location  : ' + window.location + '<br>')
        document.write('document.referrer: ' + document.referrer + '<br>')
        document.write('document.location.hostname: ' + document.location.hostname + '<br>')
    </script>
</div>
