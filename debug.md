---
---

relative foo: {{ '/foo' | relative_url }}

url: {{ site.url }}

baseurl: {{ site.baseurl }}

[bad link]({{ 'notexist.html' | relative_url}})  
[self link]({{ 'debug.html' | relative_url}})

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


<div id="props">

<h2>site.pages</h2>
{%- for page in site.pages -%}
    <strong>{{ page.path }}:</strong><br>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        {% for key_value in page %}
        {% if key_value[0] == "content" %}
        <tr><td>content</td><td>[{{ key_value[1] | size }} characters]</td></tr>
        {% else %}
        <tr><td>{{ key_value[0] }}</td><td><span>{{ key_value[1] }}</span></td></tr>
        {% endif %}
        {% endfor %}
    </table>
{%- endfor -%}

<h2>site.posts</h2>

{% assign liquid_posts = site.posts | map: 'to_liquid' %}

{% assign allprops = "" %}

{%- for page in site.posts -%}
    <strong>{{ page.path }}:</strong><br>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>layout: </td><td><span>{{ page.layout }}</span></td></tr>
        <tr><td>relative_path </td><td><span>{{ page.relative_path }}</span></td></tr>
        <tr><td>collection    </td><td><span>{{ page.collection    }}</span></td></tr>
        <tr><td>id            </td><td><span>{{ page.id            }}</span></td></tr>
        <tr><td>url           </td><td><span>{{ page.url           }}</span></td></tr>
        <tr><td>path          </td><td><span>{{ page.path          }}</span></td></tr>
        <tr><td>draft         </td><td><span>{{ page.draft         }}</span></td></tr>
        <tr><td>categories    </td><td><span>{{ page.categories    }}</span></td></tr>
        <tr><td>comments      </td><td><span>{{ page.comments      }}</span></td></tr>
        <tr><td>layout        </td><td><span>{{ page.layout        }}</span></td></tr>
        <tr><td>title         </td><td><span>{{ page.title         }}</span></td></tr>
        <tr><td>category      </td><td><span>{{ page.category      }}</span></td></tr>
        <tr><td>tags          </td><td><span>{{ page.tags          }}</span></td></tr>
        <tr><td>assets        </td><td><span>{{ page.assets        }}</span></td></tr>
        <tr><td>image         </td><td><span>{{ page.image         }}</span></td></tr>
        <tr><td>twitter       </td><td><span>{{ page.twitter       }}</span></td></tr>
        <tr><td>date          </td><td><span>{{ page.date          }}</span></td></tr>
        <tr><td>slug          </td><td><span>{{ page.slug          }}</span></td></tr>
        <tr><td>ext           </td><td><span>{{ page.ext           }}</span></td></tr>
        <tr><td>assetsmin     </td><td><span>{{ page.assetsmin     }}</span></td></tr>
        <tr><td>description   </td><td><span>{{ page.description   }}</span></td></tr>
        <tr><td>code          </td><td><span>{{ page.code          }}</span></td></tr>
        <tr><td>previous      </td><td><span>{{ page.previous.path }}</span></td></tr>
        <tr><td>next          </td><td><span>{{ page.next.path     }}</span></td></tr>
        <tr><td>excerpt       </td><td><span>{{ page.excerpt       }}</span></td></tr>
        <tr><td>content       </td><td><span>{{ page.content | size}} characters</span></td></tr>
        <tr><td>output        </td><td><span>{{ page.output | size }} characters</span></td></tr>
        {% comment %}
        {% endcomment %}
    </table>

    {% for key_value in page %}
        {% assign allprops = allprops | append: key_value | append: ',' %}
    {% endfor %}
    
{%- endfor -%}

<br /><strong>allprops:</strong><br />
{{allprops | split: ',' | uniq | join: '<br />'}}

</div>