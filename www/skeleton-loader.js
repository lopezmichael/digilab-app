// skeleton-loader.js
// Auto-hide skeleton loaders when Shiny outputs render

$(document).on('shiny:value', function(event) {
  var skeleton = document.getElementById(event.name + '_skeleton');
  if (skeleton) {
    skeleton.style.display = 'none';
  }
});

// Hide map loading placeholders when mapboxgl maps initialize
$(document).on('shiny:value', function(event) {
  var container = document.getElementById(event.name);
  if (container) {
    var placeholder = container.closest('.map-loading-container');
    if (placeholder) {
      var loader = placeholder.querySelector('.map-loading-placeholder');
      if (loader) {
        loader.style.opacity = '0';
        setTimeout(function() { loader.style.display = 'none'; }, 300);
      }
    }
  }
});
