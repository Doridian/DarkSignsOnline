<?php
require('_top.php');
require_once('api/config.php');

$verify = $_REQUEST['verify'];
if (empty($verify)) {
    die("<h1>No verification code provided</h1>");
}

$stmt = $db->prepare("SELECT * FROM users WHERE emailverifycode = ?");
$stmt->bind_param("s", $verify);
$stmt->execute();

?>
<h1>Verification done</h1>
<?php require('_bottom.php');
