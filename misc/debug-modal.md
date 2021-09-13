---
layout: default
---

<div class="comments">
<article class="modal mdl-card mdl-shadow--2dp">
  <div>
    <h3 class="modal-title js-modal-title"></h3>
  </div>
  <div class="mdl-card__supporting-text js-modal-text"></div>
  <div class="mdl-card__actions mdl-card--border">
    <button class="button mdl-button--colored mdl-js-button mdl-js-ripple-effect js-close-modal">Close</button>
  </div>
</article>

<script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.4/jquery.min.js"></script>

<script>
(function ($) {
  
  showModal('Comment submitted', 'Thanks! Your comment is <a href="https://github.com/travisdowns/travisdowns.github.io/pulls">pending</a>. It will appear when approved.');

        

  $('.js-close-modal').click(function () {
    $('body').removeClass('show-modal');
  });

  function showModal(title, message) {
    $('.js-modal-title').text(title);
    $('.js-modal-text').html(message);
    $('body').addClass('show-modal');
  }
})(jQuery);

</script>

</div>

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

This is some background text.

