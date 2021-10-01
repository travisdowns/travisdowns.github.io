---
layout: default
title: Settings
permalink: /settings
---


<script>
  var td = {
    DEBUG: false,

    log(what) {
      if (this.DEBUG) {
        console.log(what);
      }
    }
  };
</script>

<label for="theme-select">Theme:</label>
<select name="Theme" id="theme-select" onchange="updateTheme(this)">
    <option value="system">(default)</option>
    <option value="light">Light</option>
    <option value="dark">Dark</option>
</select>

<div id="theme-description"></div>

<script>  
  var updateDesc = function (theme) {
    var desc = {
      system: 'Dark or light theme is chosen based on browser or system preferences.',
      dark: 'Dark theme is enabled for all pages.',
      light: 'Light theme is enabled for all pages.'
    };
    document.getElementById('theme-description').textContent = desc[theme];
  }

  var updateTheme = function (elem) {
    var v = elem.value;
    td.log('update: ' + v);
    DARKMODE.override(v === 'system' ? null : v);
    updateDesc(v);
  };

  var updateSelect = function () {
    var cur = DARKMODE.getOverride() || 'system';
    document.getElementById('theme-select').value = cur;
    updateDesc(cur);
  };

  var refreshDebug = function() {
    if (!DARKMODE.lsOk()) {
      document.getElementById('theme-select').disabled = true;
      document.getElementById('theme-description').textContent = 'Can\'t set theme because localStorage is not working';
    } else {
      updateSelect();
    }
    document.getElementById('ls-check').textContent = DARKMODE.lsOk() ? 'OK' : 'FAILED';
    document.getElementById('dm-closed').textContent = sessionStorage.getItem('dm-closed') || '(unset)';
    document.getElementById('dm-close-count').textContent = DARKMODE.closeCount();
    document.getElementById('bar-used').textContent = localStorage.getItem('bar-used') || '(unset)';
  }

  window.addEventListener('DOMContentLoaded', function(e) {
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

---

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
</div></div>
