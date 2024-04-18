<?php

require_once("function.php");

$domain = $_REQUEST['domain'];
$port = (int)$_REQUEST['port'];

$dInfo = getDomainInfo($domain);
if ($dInfo === false) {
	die('0');
}
if($port === 0) {
	die('1');
}

$stmt = $db->prepare('SELECT domain_id FROM domain_scripts WHERE domain_id=? AND port=? AND ver=?;');
$stmt->bind_param('iii', $dInfo['id'], $port, $ver);
$stmt->execute();
$query = $stmt->get_result();
if($query->num_rows > 0)
{
	die('1');
}

die('0');
