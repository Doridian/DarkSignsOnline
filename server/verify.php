<?php
require('_top.php');
require_once('api/function_base.php');

$verify = $_REQUEST['code'];
if (empty($verify)) {
    echo '<font face="Georgia, Times New Roman, Times, serif" size="+3">Empty verification code</font>';
} else {
    $stmt = $db->prepare('UPDATE users SET active = 1, emailverifycode = "" WHERE emailverifycode = ? AND active = 0');
    $stmt->bind_param('s', $verify);
    $stmt->execute();
    echo '<font face="Georgia, Times New Roman, Times, serif" size="+3">Verification done</font>';
}

require('_bottom.php');
