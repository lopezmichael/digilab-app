// scroll-indicator.js
// Adds scroll position indicators (fade shadows) to containers with .scroll-fade
// Uses data-scroll-pos attribute: "top" | "middle" | "bottom" | "none"

(function() {
  'use strict';

  var SELECTOR = '.scroll-fade';

  function updateScrollPos(el) {
    var scrollTop = el.scrollTop;
    var scrollHeight = el.scrollHeight;
    var clientHeight = el.clientHeight;
    var threshold = 4; // px tolerance

    var canScroll = scrollHeight > clientHeight + threshold;

    if (!canScroll) {
      el.setAttribute('data-scroll-pos', 'none');
      return;
    }

    var atTop = scrollTop <= threshold;
    var atBottom = scrollTop + clientHeight >= scrollHeight - threshold;

    if (atTop && atBottom) {
      el.setAttribute('data-scroll-pos', 'none');
    } else if (atTop) {
      el.setAttribute('data-scroll-pos', 'top');
    } else if (atBottom) {
      el.setAttribute('data-scroll-pos', 'bottom');
    } else {
      el.setAttribute('data-scroll-pos', 'middle');
    }
  }

  function initElement(el) {
    if (el._scrollFadeInit) return;
    el._scrollFadeInit = true;

    el.addEventListener('scroll', function() {
      updateScrollPos(el);
    }, { passive: true });

    updateScrollPos(el);
  }

  function scanAll() {
    var els = document.querySelectorAll(SELECTOR);
    for (var i = 0; i < els.length; i++) {
      initElement(els[i]);
    }
  }

  // Initial scan once DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scanAll);
  } else {
    scanAll();
  }

  // Re-scan when Shiny renders new content (dynamic UI)
  var observer = new MutationObserver(function() {
    scanAll();
  });

  function startObserver() {
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
    } else {
      document.addEventListener('DOMContentLoaded', function() {
        observer.observe(document.body, { childList: true, subtree: true });
      });
    }
  }
  startObserver();

  // Also re-check positions when Shiny outputs update (content may grow/shrink)
  $(document).on('shiny:value', function() {
    setTimeout(scanAll, 100);
  });
})();
