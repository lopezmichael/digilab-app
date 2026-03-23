// scene-selector.js - Scene selection and localStorage persistence
// Handles first-visit detection, scene preference storage, and geolocation
// Includes postMessage iframe storage bridge for cross-origin iframe contexts
// (Mobile Safari/Chrome block third-party localStorage in cross-origin iframes)

(function() {
  'use strict';

  var STORAGE_KEY = 'digilab_scene_preference';
  var CONTINENT_KEY = 'digilab_continent_preference';
  var ONBOARDING_KEY = 'digilab_onboarding_complete';
  var LAST_SEEN_ANNOUNCEMENT_KEY = 'digilab_last_seen_announcement_id';
  var LAST_SEEN_VERSION_KEY = 'digilab_last_seen_version';
  var PLAYER_ID_KEY = 'digilab_player_id';
  var PLAYER_NAME_KEY = 'digilab_player_name';

  // ==========================================================================
  // PostMessage Storage Bridge
  // ==========================================================================

  var VALID_PARENT_ORIGINS = ['https://app.digilab.cards', 'https://digilab.cards'];
  var isInIframe = window !== window.parent;
  var pendingRequests = {};
  var REQUEST_TIMEOUT = 2000; // 2 seconds

  /**
   * Generate a unique request ID
   * @returns {string}
   */
  function generateRequestId() {
    return Date.now() + '-' + Math.random().toString(36).substr(2, 9);
  }

  /**
   * Listen for storage responses from parent frame
   */
  window.addEventListener('message', function(event) {
    if (VALID_PARENT_ORIGINS.indexOf(event.origin) === -1) return;
    if (event.data && event.data.type === 'digilab-storage-result') {
      var requestId = event.data.requestId;
      if (requestId && pendingRequests[requestId]) {
        clearTimeout(pendingRequests[requestId].timer);
        pendingRequests[requestId].resolve(event.data.value);
        delete pendingRequests[requestId];
      }
    }
  });

  /**
   * Send a storage request to the parent frame and wait for response
   * @param {string} action - 'get', 'set', or 'remove'
   * @param {string} key - Storage key
   * @param {string} [value] - Value for set operations
   * @returns {Promise<string|null>}
   */
  function postMessageStorage(action, key, value) {
    return new Promise(function(resolve) {
      var requestId = generateRequestId();
      var messageType = 'digilab-storage-' + action;

      var message = {
        type: messageType,
        key: key,
        requestId: requestId
      };
      if (value !== undefined) {
        message.value = value;
      }

      // Set up timeout - resolve with null if parent doesn't respond
      var timer = setTimeout(function() {
        if (pendingRequests[requestId]) {
          delete pendingRequests[requestId];
          resolve(null);
        }
      }, REQUEST_TIMEOUT);

      pendingRequests[requestId] = {
        resolve: resolve,
        timer: timer
      };

      VALID_PARENT_ORIGINS.forEach(function(origin) {
        window.parent.postMessage(message, origin);
      });
    });
  }

  // ==========================================================================
  // DigilabStorage - Abstraction over localStorage / postMessage bridge
  // ==========================================================================

  var DigilabStorage = {
    /**
     * Get an item from storage
     * @param {string} key
     * @returns {Promise<string|null>}
     */
    getItem: function(key) {
      if (isInIframe) {
        return postMessageStorage('get', key);
      }
      // Direct mode - wrap in Promise for consistent API
      return new Promise(function(resolve) {
        try {
          resolve(localStorage.getItem(key));
        } catch (e) {
          resolve(null);
        }
      });
    },

    /**
     * Set an item in storage
     * @param {string} key
     * @param {string} value
     * @returns {Promise<void>}
     */
    setItem: function(key, value) {
      if (isInIframe) {
        return postMessageStorage('set', key, value);
      }
      return new Promise(function(resolve) {
        try {
          localStorage.setItem(key, value);
        } catch (e) {
          // localStorage may be unavailable
        }
        resolve();
      });
    },

    /**
     * Remove an item from storage
     * @param {string} key
     * @returns {Promise<void>}
     */
    removeItem: function(key) {
      if (isInIframe) {
        return postMessageStorage('remove', key);
      }
      return new Promise(function(resolve) {
        try {
          localStorage.removeItem(key);
        } catch (e) {
          // localStorage may be unavailable
        }
        resolve();
      });
    }
  };

  // ==========================================================================
  // Storage Helpers (async, using DigilabStorage)
  // ==========================================================================

  /**
   * Get saved scene preference from storage
   * @returns {Promise<string|null>} Scene slug or null if not set
   */
  function getSavedScene() {
    return DigilabStorage.getItem(STORAGE_KEY);
  }

  /**
   * Save scene preference to storage
   * @param {string} sceneSlug Scene slug to save
   * @returns {Promise<void>}
   */
  function saveScene(sceneSlug) {
    return DigilabStorage.setItem(STORAGE_KEY, sceneSlug);
  }

  /**
   * Check if onboarding has been completed
   * @returns {Promise<boolean>}
   */
  function isOnboardingComplete() {
    return DigilabStorage.getItem(ONBOARDING_KEY).then(function(value) {
      return value === 'true';
    });
  }

  /**
   * Mark onboarding as complete
   * @returns {Promise<void>}
   */
  function completeOnboarding() {
    return DigilabStorage.setItem(ONBOARDING_KEY, 'true');
  }

  // ==========================================================================
  // Geolocation
  // ==========================================================================

  /**
   * Get user's current position using browser geolocation
   * @returns {Promise<{lat: number, lng: number}>}
   */
  function getCurrentPosition() {
    return new Promise(function(resolve, reject) {
      if (!navigator.geolocation) {
        reject(new Error('Geolocation not supported'));
        return;
      }

      navigator.geolocation.getCurrentPosition(
        function(position) {
          resolve({
            lat: position.coords.latitude,
            lng: position.coords.longitude
          });
        },
        function(error) {
          reject(error);
        },
        {
          enableHighAccuracy: false,
          timeout: 10000,
          maximumAge: 300000 // 5 minutes
        }
      );
    });
  }

  /**
   * Calculate distance between two coordinates (Haversine formula)
   * @returns {number} Distance in kilometers
   */
  function calculateDistance(lat1, lng1, lat2, lng2) {
    var R = 6371; // Earth's radius in km
    var dLat = (lat2 - lat1) * Math.PI / 180;
    var dLng = (lng2 - lng1) * Math.PI / 180;
    var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLng/2) * Math.sin(dLng/2);
    var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  }

  // ==========================================================================
  // Shiny Integration
  // ==========================================================================

  $(document).on('shiny:connected', function() {

    // Send initial scene + continent + player preference to Shiny (async storage read)
    Promise.all([
      getSavedScene(),
      isOnboardingComplete(),
      DigilabStorage.getItem(LAST_SEEN_ANNOUNCEMENT_KEY),
      DigilabStorage.getItem(LAST_SEEN_VERSION_KEY),
      DigilabStorage.getItem(CONTINENT_KEY),
      DigilabStorage.getItem(PLAYER_ID_KEY),
      DigilabStorage.getItem(PLAYER_NAME_KEY)
    ]).then(function(results) {
      var savedScene = results[0];
      var onboardingDone = results[1];
      var lastSeenAnnouncementId = results[2] ? parseInt(results[2], 10) : null;
      var lastSeenVersion = results[3];
      var savedContinent = results[4];
      var savedPlayerId = results[5] ? parseInt(results[5], 10) : null;
      var savedPlayerName = results[6];

      Shiny.setInputValue('scene_from_storage', {
        scene: savedScene,
        continent: savedContinent,
        needsOnboarding: !onboardingDone,
        lastSeenAnnouncementId: lastSeenAnnouncementId,
        lastSeenVersion: lastSeenVersion,
        playerId: savedPlayerId,
        playerName: savedPlayerName,
        timestamp: Date.now()
      }, {priority: 'event'});
    });

    // Handler for saving scene + continent to storage
    Shiny.addCustomMessageHandler('saveScenePreference', function(message) {
      var sceneSlug = message.scene;
      var continent = message.continent || 'all';
      saveScene(sceneSlug).then(function() {
        return DigilabStorage.setItem(CONTINENT_KEY, continent);
      }).then(function() {
        completeOnboarding();
      });
    });

    // Handler for updating continent icon
    Shiny.addCustomMessageHandler('updateContinentIcon', function(iconClass) {
      var el = document.getElementById('continent_icon');
      if (el) {
        el.className = 'fas fa-' + iconClass + ' continent-icon';
      }
    });

    // Handler for geolocation request
    Shiny.addCustomMessageHandler('requestGeolocation', function(message) {
      getCurrentPosition()
        .then(function(position) {
          // Find nearest scene from provided scenes
          var scenes = message.scenes || [];
          var nearestScene = null;
          var minDistance = Infinity;

          scenes.forEach(function(scene) {
            if (scene.latitude && scene.longitude) {
              var dist = calculateDistance(
                position.lat, position.lng,
                scene.latitude, scene.longitude
              );
              if (dist < minDistance) {
                minDistance = dist;
                nearestScene = scene;
              }
            }
          });

          Shiny.setInputValue('geolocation_result', {
            success: true,
            userLat: position.lat,
            userLng: position.lng,
            nearestScene: nearestScene,
            distance: minDistance,
            timestamp: Date.now()
          }, {priority: 'event'});
        })
        .catch(function(error) {
          var errorMessage = 'Unable to get location';
          if (error.code === 1) {
            errorMessage = 'Location permission denied';
          } else if (error.code === 2) {
            errorMessage = 'Location unavailable';
          } else if (error.code === 3) {
            errorMessage = 'Location request timed out';
          }

          Shiny.setInputValue('geolocation_result', {
            success: false,
            error: errorMessage,
            timestamp: Date.now()
          }, {priority: 'event'});
        });
    });

    // Handler for clearing onboarding (for testing)
    Shiny.addCustomMessageHandler('clearOnboarding', function(message) {
      DigilabStorage.removeItem(STORAGE_KEY).then(function() {
        return DigilabStorage.removeItem(CONTINENT_KEY);
      }).then(function() {
        return DigilabStorage.removeItem(ONBOARDING_KEY);
      }).then(function() {
        return DigilabStorage.removeItem(PLAYER_ID_KEY);
      }).then(function() {
        DigilabStorage.removeItem(PLAYER_NAME_KEY);
      });
    });

    // Handler for saving seen announcement ID to storage
    Shiny.addCustomMessageHandler('saveSeenAnnouncement', function(message) {
      DigilabStorage.setItem(LAST_SEEN_ANNOUNCEMENT_KEY, String(message.id));
    });

    // Handler for saving seen version to storage
    Shiny.addCustomMessageHandler('saveSeenVersion', function(message) {
      DigilabStorage.setItem(LAST_SEEN_VERSION_KEY, message.version);
    });

    // Handler for locale fallback (onboarding skip → continent detection)
    Shiny.addCustomMessageHandler('requestLocaleFallback', function(message) {
      var lang = navigator.language || navigator.userLanguage || 'en-US';
      Shiny.setInputValue('locale_fallback', {
        language: lang,
        timestamp: Date.now()
      }, {priority: 'event'});
    });

    // Handler for saving player identity to storage (onboarding Step 2)
    Shiny.addCustomMessageHandler('savePlayerIdentity', function(message) {
      DigilabStorage.setItem(PLAYER_ID_KEY, String(message.player_id));
      DigilabStorage.setItem(PLAYER_NAME_KEY, message.display_name);
    });

  });

  // Expose for debugging (all functions return Promises)
  window.digilabScene = {
    getSavedScene: getSavedScene,
    saveScene: saveScene,
    isOnboardingComplete: isOnboardingComplete,
    clearOnboarding: function() {
      return DigilabStorage.removeItem(STORAGE_KEY).then(function() {
        return DigilabStorage.removeItem(ONBOARDING_KEY);
      });
    },
    isInIframe: isInIframe,
    storage: DigilabStorage
  };

})();
