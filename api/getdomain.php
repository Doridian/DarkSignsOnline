<?php
	include 'function.php';

	if ($auth == '1001')
	{
		$data = $db->real_escape_string($_REQUEST['data']);
		$domain = getdomain($data);
		
		//echo $domain;
		
		//echo $ip;
		
		if ($domain == '0')
		{
			echo 'Invalid lookup.<end>';			
		}
		else if ($domain == '1')
		{
			echo 'Domain not found.';			
		}
		else
		{
			echo $domain;
		}
		
		echo '<end>';
	}
?>