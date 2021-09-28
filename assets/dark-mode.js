---
---
(function(i) {
  
  i.setSheet = function (color) {
    document.getElementById("mainstyle").setAttribute("href",
    "{{ '/assets/css/' | relative_url }}" + color + '.css');
  }
  
  /**
   * Set the correct sheet based on any override and the media query.
   */
  i.updateSheet = function() {
    i.setSheet(i.get());
  }

  /**
   * See if localStorage apears to be working.
   */
  i.lsOk = function() {
    try {
      localStorage.setItem('lsOk', 'x');
      return localStorage.getItem('lsOk') === 'x';
    } catch (e) {
      return false;
    }
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
  
}(DARKMODE));
    
var dmQuery = window.matchMedia('(prefers-color-scheme: dark)');
dmQuery.addEventListener('change', function (e) {
  DARKMODE.updateSheet();
});
