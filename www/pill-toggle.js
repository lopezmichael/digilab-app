// pill-toggle.js - Segmented pill toggle control for Shiny
(function() {
  'use strict';

  // Initialize pill toggle: set Shiny input value on click
  $(document).on('click', '.pill-toggle .pill-option', function() {
    var $el = $(this);
    var $group = $el.closest('.pill-toggle');
    var inputId = $group.data('input-id');
    var value = $el.data('value');

    // Update active state
    $group.find('.pill-option').removeClass('active');
    $el.addClass('active');

    // Send to Shiny
    Shiny.setInputValue(inputId, String(value), {priority: 'event'});
  });

  // On Shiny connect, initialize default values
  $(document).on('shiny:connected', function() {
    $('.pill-toggle').each(function() {
      var $group = $(this);
      var inputId = $group.data('input-id');
      var $active = $group.find('.pill-option.active');
      if ($active.length > 0) {
        Shiny.setInputValue(inputId, String($active.data('value')), {priority: 'event'});
      }
    });

    // Handle reset from server
    Shiny.addCustomMessageHandler('resetPillToggle', function(message) {
      var $group = $('.pill-toggle[data-input-id="' + message.inputId + '"]');
      $group.find('.pill-option').removeClass('active');
      $group.find('.pill-option[data-value="' + message.value + '"]').addClass('active');
      Shiny.setInputValue(message.inputId, String(message.value), {priority: 'event'});
    });

    // Clear color pills from server
    Shiny.addCustomMessageHandler('clearColorPills', function(message) {
      $('.color-filter-pills .color-pill').removeClass('active');
      Shiny.setInputValue('meta_color_pills', null, {priority: 'event'});
    });
  });

  // Toggle advanced filters visibility
  $(document).on('click', '.btn-title-strip-filters', function(e) {
    e.preventDefault();
    var btn = $(this);
    var targetId = btn.data('target');
    var $target = $('#' + targetId);
    if ($target.hasClass('open')) {
      $target.removeClass('open');
      btn.removeClass('active');
    } else {
      $target.addClass('open');
      btn.addClass('active');
    }
  });

  // Color filter pills — multi-select toggle, sends array to Shiny
  $(document).on('click', '.color-pill', function() {
    $(this).toggleClass('active');
    var selected = [];
    $(this).closest('.color-filter-pills').find('.color-pill.active').each(function() {
      selected.push($(this).data('color'));
    });
    Shiny.setInputValue('meta_color_pills', selected.length > 0 ? selected : null, {priority: 'event'});
  });
})();
