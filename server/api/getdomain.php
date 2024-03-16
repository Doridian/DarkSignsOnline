<?php
	include 'function.php';

	if ($auth == '1001')
	{
		$data = $_REQUEST['data'];
		$domain = getdomain($data);
		
		if ($domain == '0')
		{
			echo 'Invalid lookup.';			
		}
		else if ($domain == '1')
		{
			echo 'Domain not found.';			
		}
		else
		{
			echo $domain;
		}
	}
