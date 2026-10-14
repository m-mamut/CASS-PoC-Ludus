<?php
// parent CSS
add_action('wp_enqueue_scripts', function () {
    wp_enqueue_style('astra-parent', get_template_directory_uri().'/style.css');
}, 5);

// === CTA fixer (robustan slug + wildcard '*') ===
add_action('wp_enqueue_scripts', function () {
    // mapa: slug => (tekst_gumba -> URL)  (ključevi lowercase)
    $map_by_text = [
        'home' => [
            'get started'     => '/services/',
            'find out more'   => '/about/',
            "let's talk now"  => '/contact/',
        ],
        // ako je slug stranice drugačiji (npr. "our-services"), i dalje će raditi jer ispod imamo wildcard '*'
        'services' => [
            'start a project' => '/contact/',
        ],
        '*' => [ // vrijedi za sve stranice
            'start a project' => '/contact/',   // ⬅️ ovo osigurava da radi i ako slug nije točno "services"
        ],
    ];

    wp_register_script('cta-fixer', '', [], null, true);
    wp_enqueue_script('cta-fixer');

    wp_add_inline_script('cta-fixer', '(function(){
      function norm(t){return (t||"").replace(/[\u2019]/g,"\'").trim().toLowerCase();}
      const MAP = '.json_encode($map_by_text).';

      // odredi slug robusno: "/" => "home", inače zadnji dio patha
      let slug = (function(){
        const p = (location.pathname || "/").replace(/\/+$/,"");
        if (p === "" || p === "/") return "home";
        const parts = p.split("/").filter(Boolean);
        return parts[parts.length-1].toLowerCase();
      })();

      // kandidati selektora za CTA linkove (Spectra + Gutenberg)
      const anchors = document.querySelectorAll("a.uagb-infobox-cta-link, .wp-block-button__link, a.button");
      anchors.forEach(a=>{
        const key = norm(a.textContent);
        let target = "";

        // 1) slug-specifično
        if (MAP[slug] && MAP[slug][key]) target = MAP[slug][key];
        // 2) wildcard
        if (!target && MAP["*"] && MAP["*"][key]) target = MAP["*"][key];

        if (target){
          a.setAttribute("href", target);
          a.removeAttribute("onclick");
          a.setAttribute("rel","noopener");
        }
      });
    })();');
});


