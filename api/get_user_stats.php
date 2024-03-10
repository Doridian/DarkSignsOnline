<?php
	include_once "function.php";
	
	$returnwith = (string)(int)$_GET['returnwith'];

	if ($returnwith == "0")
	{
		// Default returnwith is 2000
		$returnwith = "2000";
	}
	echo $returnwith;

	if ($auth == '1001')
	{
		echo 'STATS: You have $'.number_format(getCash($user['id'])).'.';
		echo 'newline';
	}
	else
	{
		echo 'Access Denied 1984';
	}
	
	echo '<end>';
?>