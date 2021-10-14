---
---
'use strict';

(function(i) {
  
  i.setSheet = function (color) {
    var existing = document.getElementById(i.OID);
    var link = i.makeLink(color);
    if (existing) {
      existing.href = link.href;
    } else {
      // element may not exist if there was no existing override when
      // the settings page was loaded so create it now
      document.head.appendChild(link);
    }
  }
  
  /**
   * Set the correct sheet based on any override and the media query.
   */
  i.updateSheet = function() {
    i.setSheet(i.get());
  }

  /**
   * Check if the given storage seems to be working.
   * @param {*} storage storage object to check
   */
  var storageOk = function(storage) {
    try {
      storage.setItem('dm-test', 'x');
      return storage.getItem('dm-test') === 'x';
    } catch (e) {
      return false;
    }
  }

  /**
   * See if localStorage apears to be working.
   */
  i.lsOk = function() {
    return storageOk(localStorage);  
  }

  i.bothOk = function() {
    return storageOk(localStorage) && storageOk(sessionStorage);
  }

  
  /**
   * Override the theme to the given value, or remove any existing
   * override if null.
   * 
   * This saves the override value in localstorage (if possible) and
   * applies the override (or the default if no override) to the
   * current page by swapping the stylesheet.
   * 
   * @param {*} value the override value, null, 'dark' or 'light'
   */
  i.override = function(value) {
    if (value === 'dark' || value == 'light') {
      localStorage.setItem(i.PROP, value);
    } else if (value === null) {
      localStorage.removeItem(i.PROP);
    } else {
      console.error('bad override: ' + value);
    }
    i.updateSheet();
  }
  
  i.closeCount = function() {
    return parseInt(localStorage.getItem('dm-close-count') || '0');
  }

  i.showDmBar = function() {
    // We show the bar if we are in "default" light mode, i.e.,
    // not overrideden. Additionally, we check that session and
    // local storage are working, because if not we aren't 
    // going to be able to hide the bar, so better to now show
    // it at all. We also show the bar if we are overriden to dark
    // mode and this override was set via the bar, since we don't 
    // want the bar to suddenly disapear when the box is checked.
    // Finally, we don't show the bar if the user has
    // closed it this session, or twice ever (saved in localStorage)
    if (i.BANNER === 'true') {
      return false;
    }
    if (!i.bothOk() || sessionStorage.getItem('dm-closed') || i.closeCount() >= 2) {
      return false;
    }
    if (i.get() === 'light') {
      return !i.getOverride();
    } else {
      return localStorage.getItem('bar-used');
    }
  }


  var dmHeader = document.getElementById('dm-header');

  i.closeBar = function() {
    dmHeader.classList.add('hidden');
    sessionStorage.setItem('dm-closed', 'true');
    localStorage.setItem('dm-close-count', i.closeCount() + 1);
  }

  if (i.showDmBar()) {
    dmHeader.classList.remove('hidden');
    var check = document.getElementById('dm-select');
    check.addEventListener('change', function(e) {
      // console.log('box is ' + (this.checked ? 'checked' : 'unchecked'));
      if (this.checked) {
        localStorage.setItem('bar-used', 'true');
        DARKMODE.override('dark');
      } else {
        localStorage.removeItem('bar-used', 'true');
        DARKMODE.override(null);
      }
    });
  }
  
}(DARKMODE));
    
var dmQuery = window.matchMedia('(prefers-color-scheme: dark)');
dmQuery.addEventListener('change', function (e) {
  DARKMODE.updateSheet();
});
