// url-routing.js - Browser history handling for deep linking
// Enables shareable URLs for players, decks, stores, tournaments, and scenes

(function() {
  'use strict';

  // ==========================================================================
  // Parent Frame Communication (for iframe embedding on digilab.cards)
  // ==========================================================================

  var PARENT_ORIGIN = 'https://app.digilab.cards';
  var isInIframe = window.parent !== window;

  // Send URL update to parent frame
  function notifyParentUrl(url, replace) {
    if (isInIframe) {
      try {
        window.parent.postMessage({
          type: 'digilab-url-update',
          url: url,
          replace: replace || false
        }, PARENT_ORIGIN);
      } catch (e) {
        // Parent may not be digilab.cards, ignore
      }
    }
  }

  // Listen for URL updates from parent (browser back/forward in parent)
  window.addEventListener('message', function(event) {
    if (event.origin !== PARENT_ORIGIN) return;
    if (!event.data) return;

    if (event.data.type === 'digilab-url-navigate') {
      // Parent is telling us to navigate to a URL (back/forward button)
      var search = event.data.search || '';
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('url_popstate', {
          state: {},
          search: search,
          timestamp: Date.now()
        }, {priority: 'event'});
      }
    } else if (event.data.type === 'digilab-initial-url') {
      // Parent is sending initial URL params on load
      var search = event.data.search || '';
      if (search && typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('url_initial', {
          search: search,
          timestamp: Date.now()
        }, {priority: 'event'});
      }
    }
  });

  // ==========================================================================
  // Browser History Handling
  // ==========================================================================

  // Listen for back/forward button navigation
  window.addEventListener('popstate', function(event) {
    // Notify Shiny when user navigates with browser buttons
    if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
      Shiny.setInputValue('url_popstate', {
        state: event.state,
        search: window.location.search,
        timestamp: Date.now()
      }, {priority: 'event'});
    }
  });

  // ==========================================================================
  // Shiny Message Handlers
  // ==========================================================================

  // Wait for Shiny to be ready
  $(document).on('shiny:connected', function() {

    // Listen for modal close events to clear URL entity
    // Use small delay to allow cross-modal navigation to update URL first
    $(document).on('hidden.bs.modal', '.modal', function() {
      setTimeout(function() {
        // Only clear URL if no modal is currently visible (not cross-modal nav)
        if ($('.modal:visible').length === 0) {
          if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
            Shiny.setInputValue('modal_closed', Date.now(), {priority: 'event'});
          }
        }
      }, 100);
    });

    // Handler for pushing new URL to history (adds to back button history)
    Shiny.addCustomMessageHandler('pushUrl', function(message) {
      var url = message.url || '';
      var state = message.state || {};

      // Only push if URL is different from current
      if (window.location.search !== url) {
        history.pushState(state, '', url || window.location.pathname);
        // Notify parent frame of URL change
        notifyParentUrl(url, false);
      }
    });

    // Handler for replacing current URL (no history entry)
    Shiny.addCustomMessageHandler('replaceUrl', function(message) {
      var url = message.url || '';
      var state = message.state || {};
      history.replaceState(state, '', url || window.location.pathname);
      // Notify parent frame of URL change (replace mode)
      notifyParentUrl(url, true);
    });

    // Handler for going back in history
    Shiny.addCustomMessageHandler('historyBack', function(message) {
      history.back();
    });

    // Parse initial URL and send to Shiny
    // Only if we're not in an iframe (parent will send initial URL via postMessage)
    if (!isInIframe) {
      var initialSearch = window.location.search;
      if (initialSearch) {
        Shiny.setInputValue('url_initial', {
          search: initialSearch,
          timestamp: Date.now()
        }, {priority: 'event'});
      }
    }

    // If in iframe, tell parent we're ready to receive initial URL
    if (isInIframe) {
      try {
        window.parent.postMessage({
          type: 'digilab-iframe-ready'
        }, PARENT_ORIGIN);
      } catch (e) {
        // Fallback: use own URL if parent doesn't respond
        var initialSearch = window.location.search;
        if (initialSearch) {
          Shiny.setInputValue('url_initial', {
            search: initialSearch,
            timestamp: Date.now()
          }, {priority: 'event'});
        }
      }
    }
  });

  // ==========================================================================
  // Copy URL Functions
  // ==========================================================================

  // Copy current URL to clipboard (uses digilab.cards URL when in iframe)
  window.copyCurrentUrl = function() {
    var urlToCopy;
    if (isInIframe) {
      // Build the digilab.cards URL with current query params
      urlToCopy = PARENT_ORIGIN + '/' + window.location.search;
    } else {
      urlToCopy = window.location.href;
    }
    copyToClipboard(urlToCopy);
  };

  // Copy a specific URL to clipboard
  window.copyUrl = function(url) {
    copyToClipboard(url);
  };

  // Copy community-filtered URL to clipboard
  window.copyCommunityUrl = function(storeSlug) {
    var baseUrl;
    if (isInIframe) {
      baseUrl = PARENT_ORIGIN + '/';
    } else {
      baseUrl = window.location.origin + window.location.pathname;
    }
    var communityUrl = baseUrl + '?community=' + encodeURIComponent(storeSlug);
    copyToClipboard(communityUrl);
  };

  // Shared clipboard helper with textarea fallback for iframe contexts
  function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(function() {
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('link_copied', Date.now(), {priority: 'event'});
      }
    }).catch(function(err) {
      console.error('Failed to copy URL:', err);
      // Fallback: select and copy (needed in iframe contexts)
      var textArea = document.createElement('textarea');
      textArea.value = text;
      document.body.appendChild(textArea);
      textArea.select();
      document.execCommand('copy');
      document.body.removeChild(textArea);

      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('link_copied', Date.now(), {priority: 'event'});
      }
    });
  }

  // ==========================================================================
  // URL Building Helpers
  // ==========================================================================

  // Build a URL with query parameters
  window.buildUrl = function(params) {
    var search = Object.keys(params)
      .filter(function(key) { return params[key] !== null && params[key] !== undefined; })
      .map(function(key) { return encodeURIComponent(key) + '=' + encodeURIComponent(params[key]); })
      .join('&');

    return search ? '?' + search : '';
  };

  // Parse query string into object
  window.parseQueryString = function(search) {
    if (!search) return {};
    search = search.replace(/^\?/, '');

    var params = {};
    search.split('&').forEach(function(pair) {
      var parts = pair.split('=');
      if (parts.length === 2) {
        params[decodeURIComponent(parts[0])] = decodeURIComponent(parts[1]);
      }
    });

    return params;
  };

})();
