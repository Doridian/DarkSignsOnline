<?php
	include_once 'function.php';
	
	echo $auth;
	if ($auth == '1001')
	{
		$ip = $db->result($db->query("SELECT ipt.ip FROM iptable ipt, domain d WHERE d.name='$u' AND d.ext='usr' AND d.id=ipt.id"), 0);
		echo $ip;
	}
	echo '<end>';
?>