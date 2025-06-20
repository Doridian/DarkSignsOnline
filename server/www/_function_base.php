<?php

require_once('api/function_base.php');

function die_frontend_msg($msg, $submsg = '') {
    echo '<center><br><br><font size="4" color="orange" face="arial"><b>';
    echo $msg;
    echo '</b>';
    if (!empty($submsg)) {
        echo '<br>';
        echo $submsg;
    }
    echo '</font></center>';
    require(__DIR__ . '/../_bottom.php');
    exit;
}
