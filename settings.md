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

  window.addEventListener('DOMContentLoaded', function() {
    if (!DARKMODE.lsOk()) {
      document.getElementById('theme-select').disabled = true;
      document.getElementById('theme-description').textContent = 'Can\'t set theme because localStorage is not working';
    } else {
      updateSelect();
    }
  });
</script>
