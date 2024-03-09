<?php
	include_once 'function.php';
	
	echo $auth;
	if ($auth == '1001')
	{
		$res = $db->query("SELECT ipt.ip FROM iptable ipt, domain d WHERE d.name='$u' AND d.ext='usr' AND d.id=ipt.id") or die($db->error);
		$ip = $res->fetch_row()[0];
		echo $ip;
	}
	echo '<end>';
?>