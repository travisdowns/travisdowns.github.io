---
layout: default
---

{% include color-check.html %}

<p>force: <span id="forceout">(unknown)</span></p>

<script>

  var update = function () {
    document.getElementById("forceout").textContent = DARKMODE.getOverride() || '(unset)';
  }

  update();

</script>

<button onclick="DARKMODE.override('light'); update()" > LIGHT </button>
<button onclick="DARKMODE.override('dark' ); update()" > DARK </button>
<button onclick="DARKMODE.override(null   ); update()" > CLEAR </button>

This is a danger callout.
<br><br><br><br>
{: .danger}

This is a warning callout.
<br><br><br><br>
{: .warning}

This is an info callout.
<br><br><br><br>
{: .info}

This is a success callout.
<br><br><br><br>
{: .success}

