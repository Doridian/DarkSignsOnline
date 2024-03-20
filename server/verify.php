<?php
require('_top.php');
require_once('api/config.php');

$verify = $_REQUEST['code'];
if (empty($verify)) {
    die("<h1>No verification code provided</h1>");
}

$stmt = $db->prepare('UPDATE users SET active = 1, emailverifycode = "" WHERE emailverifycode = ? AND active = 0');
$stmt->bind_param('s', $verify);
$stmt->execute();

?>
<font face="Georgia, Times New Roman, Times, serif" size="+3">Verification done</font>
<?php require('_bottom.php');
