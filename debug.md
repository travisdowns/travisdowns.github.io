---
layout: default
---

Last rebuild (`site.time`): {{ site.time }}

| Property | Value |
| -----------------|
| jekyll.environment  | {{ jekyll.environment }} |
| site.url | {{ site.url }} |
| site.baseurl  | {{ site.baseurl }} |

relative foo: {{ '/foo' | relative_url }}

[link](http://www.example.com)


[bad link]({{ 'notexist.html' | relative_url}})  
[self link]({{ 'debug.html' | relative_url}})

| Property | Value |
| -----------------|
| site.markdown  | {{ site.markdown }} |
| site.kramdown  | `{{ site.kramdown }}` |


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

<a href="#pages-table">Jump to PAGES table</a><br>
<a href="#posts-table">Jump to POSTS table</a><br>
<a href="#static-table">Jump to STATIC table</a><br>

<div id="props">

<h2 id="pages-table" >site.pages</h2>
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

<h2 id="posts-table">site.posts</h2>

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

<br /><strong>All posts props:</strong><br />
{{allprops | split: ',' | uniq | join: '<br />'}}

<h2 id="static-table">site.static_files</h2>
    
    {%- for page in site.static_files -%}
    <strong>{{ page.path }}:</strong><br>
    <table>
        <tr><th>Property</th><th>Value</th></tr>

        <tr><td>path         </td><td><span>{{ page.path       }}</span></td></tr>
        <tr><td>collection   </td><td><span>{{ page.collection       }}</span></td></tr>
        <tr><td>modified_time</td><td><span>{{ page.modified_time       }}</span></td></tr>
        <tr><td>basename     </td><td><span>{{ page.basename       }}</span></td></tr>
        <tr><td>name         </td><td><span>{{ page.name       }}</span></td></tr>
        <tr><td>extname      </td><td><span>{{ page.extname       }}</span></td></tr>
    </table>
{%- endfor -%}

</div>