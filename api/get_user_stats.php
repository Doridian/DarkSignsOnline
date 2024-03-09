<?php
	include_once "function.php";
	
	$returnwith = preg($_GET['returnwith'], "[^0-9]");

	if ($returnwith == "")
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