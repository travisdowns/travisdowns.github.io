'use strict';

// Static comments
// originally sourced from: https://github.com/eduardoboucas/popcorn/blob/gh-pages/js/main.js
var addComment = function() {

  var select = function(s) {
    return document.querySelector(s);
  };

  var I = function(id) {
    return document.getElementById(id);
  };

  var submitButton = select("#comment-form-submit");

  var form = select('.js-form');
  form.doReset = function() {
    submitButton.innerHTML = "Submit";
    this.classList.remove('disabled');
  };

  // Cloudflare Turnstile (invisible) runs when the form is submitted. If it is
  // blocked, slow or fails, the comment is sent without a token and the server
  // flags it for moderation rather than rejecting it.
  var turnstileWidget = null;
  var turnstileFinish = null;

  var getTurnstileToken = function(callback) {
    var container = I('turnstile-widget');
    if (!container || !window.turnstile) {
      callback('');
      return;
    }

    var done = false;
    turnstileFinish = function(token) {
      if (!done) {
        done = true;
        callback(token || '');
      }
    };
    setTimeout(turnstileFinish, 15000);

    if (turnstileWidget === null) {
      turnstileWidget = turnstile.render(container, {
        sitekey: container.getAttribute('data-sitekey'),
        execution: 'execute',
        callback: function(token) { turnstileFinish(token); },
        'error-callback': function() { turnstileFinish(''); }
      });
    } else {
      turnstile.reset(turnstileWidget);
    }
    turnstile.execute(turnstileWidget);
  };

  form.addEventListener('submit', function (event) {
    event.preventDefault();

    submitButton.innerHTML =
      '<svg class="icon spin"><use xlink:href="#icon-loading"></use></svg> Sending...';

    var errorHandler = function(title, err) {
      console.log(err);
      var ecode = err.errorCode || "unknown";
      showModal(title, 'An error occured.<br>[' + ecode + ']');
      form.doReset();
    }

    form.classList.add('disabled');

    var action = this.getAttribute('action');
    var body = new URLSearchParams(new FormData(this));

    getTurnstileToken(function(token) {
      body.set('cf-turnstile-response', token);

      fetch(action, {
        method: 'POST',
        body: body,
        headers: new Headers({'content-type': 'application/x-www-form-urlencoded'})
      }).then(
        function (data) {
          if (data.ok) {
            showModal('Comment submitted', 'Thanks! Your comment is <a href="https://github.com/travisdowns/travisdowns.github.io/pulls">pending</a>. It will appear when approved.');
            form.reset();
            form.doReset();
          } else {
            data.json().then(function(err) {
              errorHandler('Server Error', err);
            });
          }
        }
      ).catch(function (err) {
        console.error(err);
        errorHandler('Unexpected Error', err);
      });
    });

  });

  select('.js-close-modal').addEventListener('click', function () {
    select('body').classList.remove('show-modal');
  });

  function showModal(title, message) {
    select('.js-modal-title').innerText = title;
    select('.js-modal-text').innerHTML = message;
    select('body').classList.add('show-modal');
  }

  // Staticman comment replies, from https://github.com/mmistakes/made-mistakes-jekyll
  // modified from Wordpress https://core.svn.wordpress.org/trunk/wp-includes/js/comment-reply.js
  // Released under the GNU General Public License - https://wordpress.org/about/gpl/
  // addComment.moveForm is called from comment.html when the reply link is clicked.

  return {

    // commId - the id attribute of the comment replied to (e.g., "comment-10")
    // respondId - the string 'respond', I guess
    // parentUid - the UID of the parent comment
    moveForm: function(commId, respondId, parentUid) {
      var t           = this;
      var comm        = I( commId );                                // whole comment
      var respond     = I( respondId );                             // whole new comment form
      var cancel      = I( 'cancel-comment-reply-link' );           // whole reply cancel link
      var parentuidF  = I( 'comment-replying-to-uid' );             // a hidden element in the comment

      if ( ! comm || ! respond || ! cancel || ! parentuidF ) {
        return;
      }

      t.respondId = respondId;

      if ( ! I( 'sm-temp-form-div' ) ) {
        var div = document.createElement('div');
        div.id = 'sm-temp-form-div';
        div.style.display = 'none';
        respond.parentNode.insertBefore(div, respond); // create and insert a bookmark div right before comment form
      }

      comm.parentNode.insertBefore( respond, comm.nextSibling );  // move the form from the bottom to above the next sibling
      parentuidF.value = parentUid;
      cancel.style.display = '';                        // make the cancel link visible

      cancel.onclick = function() {
        var temp    = I( 'sm-temp-form-div' );            // temp is the original bookmark
        var respond = I( t.respondId );                   // respond is the comment form

        if ( !temp || !respond ) {
          return;
        }

        I('comment-replying-to-uid').value = null;
        temp.parentNode.insertBefore(respond, temp);  // move the comment form to its original location
        temp.parentNode.removeChild(temp);            // remove the bookmark div
        this.style.display = 'none';                  // make the cancel link invisible
        this.onclick = null;                          // retire the onclick handler
        return false;
      };

      I('comment-form-message').focus();

      return false;
    }
  }
}();
