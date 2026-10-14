<?php
/**
 * LAB ONLY — disable KSES (sanitizaciju) za komentare i postove,
 * te ugasi "pametne navodnike" u komentarima.
 */
add_action('init', function () {
    // Komentari — ukloni sanitizaciju pri unosu i pri prikazu
    remove_filter('pre_comment_content', 'wp_filter_kses');
    remove_filter('pre_comment_content', 'wp_kses_data');
    remove_filter('comment_text',        'wp_kses_data');
    remove_filter('comment_text_rss',    'wp_kses_data');
    remove_filter('comment_excerpt',     'wp_kses_data');

    // Ukloni "wptexturize" na komentarima (da ostanu ravni navodnici)
    remove_filter('comment_text', 'wpautop');
    remove_filter('comment_text', 'make_clickable');
    remove_filter('comment_text', 'convert_chars');
    remove_filter('comment_text', 'wptexturize');

    // (opcionalno) isto i za postove — full send u labu
    remove_filter('content_save_pre',          'wp_filter_post_kses');
    remove_filter('excerpt_save_pre',          'wp_filter_post_kses');
    remove_filter('content_filtered_save_pre', 'wp_filter_post_kses');

    error_log('>>> MU disable-kses: removed filters on init <<<');
}, 9999);
