
{% assign ai__attributes = "" %}

{% if include.width %}
{% capture ai__attributes %}{{ ai__attributes }}width="{{include.width}}" {% endcapture %}
{% endif %}

{% if ai__attributes != "" %}
{% capture ai__ial %}{:{{ai__attributes}}}{% endcapture %}
{% else %}
{% comment %} needed because otherwise the ai__ial variable leaks into the next include {% endcomment %}
{% assign ai__ial = '' %}
{% endif %}

![{{include.alt | default image }}]({{assetpath}}/{{include.path}}){{ai__ial}}
