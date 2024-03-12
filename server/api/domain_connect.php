<?php

$rewrite_done = true;
require_once 'function.php';
global $auth;

echo '4100';

$port = (int)$_REQUEST['port'];

if ($port < 1 || $port > 65536)
{
	die('not found<end>');
}
$d = $_REQUEST['d'];
$d = strtolower($d); 
$temp = getDomainInfo($d);

if ($temp[0] > 0)
{
	$stmt = $db->prepare("SELECT code FROM domainscripts WHERE domain_id = ? AND port = ?");
	$stmt->bind_param('ii', $temp[0], $port);
	$stmt->execute();
	$exists = $stmt->get_result();
	if ($exists->num_rows == 1)
	{
		$code = $exists->fetch_row();
		echo $d.'_'.$port.'::'.$code[0];
	}
	else
	{
		echo 'not found';
	}
}
else
{
	echo 'not found';
}

echo '<end>';
