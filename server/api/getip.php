<?php
	include 'function.php';

	if ($auth == '1001')
	{
		$data = $_REQUEST['data'];
		$ip = getip($data);
		
		if ($ip == 0)
		{
			echo 'Invalid lookup.';			
		}
		else if ($ip == 1)
		{
			echo 'IP not found.';			
		}
		else
		{
			echo $ip;
		}
	}
