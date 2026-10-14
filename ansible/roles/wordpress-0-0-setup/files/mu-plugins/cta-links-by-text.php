<?php
/**
 * Plugin Name: CTA Link Mapper by block_id (MU)
 * Description: Mijenja linkove UAGB (Spectra) info-box CTA gumba pri renderu, po block_id. Ne dira post_content.
 */

add_filter('render_block', function ($block_content, $block) {
    if (!is_array($block) || ($block['blockName'] ?? '') !== 'uagb/info-box') {
        return $block_content;
    }

    // Kontekst: trenutna stranica (slug)
    $post = get_post();
    $slug = $post ? $post->post_name : '';

    // ====== KONFIGURACIJA: mapa po slugu → block_id → URL ======
    $map = [
        // Primjer (dom): na HOME stranici block_id '9a97965e' vodi na /contact/
        'home' => [
            '9a97965e' => '/contact/',
            // 'abc12345' => '/services/',
            // 'def67890' => '/about/',
        ],
        // 'about' => [ 'xxxx' => '/contact/' ],
        // '*' => [ 'blockid-ako-vrijedi-za-sve-stranice' => '/neki/url/' ],
    ];
    // ===========================================================

    $attrs    = $block['attrs'] ?? [];
    $block_id = $attrs['block_id'] ?? '';
    if (!$block_id) return $block_content;

    // Poredak: slug-specifično → wildcard '*'
    $target = '';
    if ($slug && isset($map[$slug][$block_id])) $target = $map[$slug][$block_id];
    if (!$target && isset($map['*'][$block_id])) $target = $map['*'][$block_id];
    if (!$target) return $block_content;

    // Zamijeni href u renderiranom HTML-u i ukloni onclick="return false"
    $out = preg_replace(
        '/(<a\b[^>]*class="[^"]*uagb-infobox-cta-link[^"]*"[^>]*href=")[^"]*(")/i',
        '$1' . esc_url($target) . '$2',
        $block_content
    );
    $out = preg_replace('/\sonclick="return\s+false"\s*/i', ' ', $out);

    return $out ?: $block_content;
}, 10, 2);

